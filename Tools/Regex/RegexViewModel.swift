// Tools/Regex/RegexViewModel.swift
// @Observable ViewModel for the Regex Tester.
// NEVER-FREEZE CONTRACT (D-02, T-02-RGX-DoS): evaluation runs off the MainActor via Task,
// with 300ms debounce and a 2s withThrowingTaskGroup timeout. The last-good highlight is
// kept visible (dimmed at opacity 0.4) when a timeout or error occurs (CF-02).
// SECURITY (INFRA-09): never imports GRDB; history written via injected onSaveHistory only.

import Foundation
import Observation

@Observable
@MainActor
final class RegexViewModel: ToolShortcutActions {

    // MARK: - Observable State

    var pattern: String = "" {
        didSet { scheduleEval() }
    }

    var testString: String = "" {
        didSet { scheduleEval() }
    }

    var flags: Set<RegexFlag> = [] {
        didSet { scheduleEval() }
    }

    var template: String = "" {
        didSet {
            if replaceMode { scheduleEval() }
        }
    }

    var replaceMode: Bool = false {
        didSet { scheduleEval() }
    }

    /// Current match results (last successful evaluation).
    var matches: [RegexMatch] = []

    /// Badge text, e.g. "3 matches", "1 match", "No matches".
    var matchCountText: String = ""

    /// Substitution preview output (when replaceMode is on and last eval succeeded).
    var substitutionPreview: String = ""

    /// CF-02: true while current input is invalid/timed-out — dims last-good highlight.
    var outputDimmed: Bool = false

    /// Inline error message for invalid pattern.
    var errorMessage: String? = nil

    /// True when the 2-second eval timeout fires (D-02).
    var timedOut: Bool = false

    // MARK: - Private

    /// Injected history write closure. ViewModel NEVER imports GRDB (INFRA-09).
    private let onSaveHistory: (HistoryEntry) -> Void

    /// Project-wide Debounce actor (defined once in JSONFormatterViewModel.swift — import, NOT redefine).
    private let debounce = Debounce()

    /// Cancel-in-flight: stored Task for the current eval; cancelled on every new keystroke.
    private var evalTask: Task<Void, Never>?

    // MARK: - Init

    init(onSaveHistory: @escaping (HistoryEntry) -> Void) {
        self.onSaveHistory = onSaveHistory
    }

    // MARK: - ToolShortcutActions (INFRA-16)

    /// Returns match-count text plus substitution preview when replaceMode.
    func primaryOutput() -> String? {
        var parts: [String] = []
        if !matchCountText.isEmpty { parts.append(matchCountText) }
        if replaceMode && !substitutionPreview.isEmpty {
            parts.append("Substitution:\n\(substitutionPreview)")
        }
        let output = parts.joined(separator: "\n")
        return output.isEmpty ? nil : output
    }

    /// Clears both pattern and test string (triggers scheduleEval via didSet).
    func clearInput() {
        pattern = ""
        testString = ""
    }

    // MARK: - Scheduling

    /// Schedules a debounced evaluation. Cancels any in-flight task immediately.
    private func scheduleEval() {
        // Cancel the previously in-flight eval task on every keystroke (D-02).
        evalTask?.cancel()
        evalTask = nil

        // Empty pattern → clear results immediately without debounce.
        guard !pattern.isEmpty else {
            matches = []
            matchCountText = ""
            substitutionPreview = ""
            outputDimmed = false
            errorMessage = nil
            timedOut = false
            return
        }

        // Snapshot current input values (captured for the off-main eval closure).
        let capturedPattern = pattern
        let capturedText = testString
        let capturedFlags = flags
        let capturedTemplate = template
        let capturedReplaceMode = replaceMode

        // Launch a debounced task: wait 300ms then run the actual eval.
        evalTask = Task { [weak self] in
            guard let self else { return }
            await self.debounce.schedule(delay: .milliseconds(300)) { [weak self] in
                await self?.runEval(
                    pattern: capturedPattern,
                    text: capturedText,
                    flags: capturedFlags,
                    template: capturedTemplate,
                    replaceMode: capturedReplaceMode
                )
            }
        }
    }

    // MARK: - Evaluation (off MainActor + 2s timeout race)

    /// Runs regex evaluation off the MainActor, racing against a 2-second timeout.
    /// On success: publishes matches + history. On timeout/failure: keeps last-good dimmed.
    /// T-02-RGX-DoS mitigation: withThrowingTaskGroup races eval vs sleep(2s); cancelAll on winner.
    private func runEval(
        pattern: String,
        text: String,
        flags: Set<RegexFlag>,
        template: String,
        replaceMode: Bool
    ) async {
        // Check if the task was cancelled before we even start.
        guard !Task.isCancelled else { return }

        // Off-MainActor evaluation with 2-second timeout.
        // The transformer is pure + synchronous; running it inside a Task keeps the UI thread free.
        let evalResult: EvalResult = await withThrowingTaskGroup(
            of: EvalResult.self
        ) { group in
            // Worker: run the transformer off the main actor.
            group.addTask {
                // Run entirely non-isolated (off MainActor).
                let matchResult = RegexTransformer.matches(
                    pattern: pattern,
                    flags: flags,
                    in: text
                )

                var substitution: Result<String, RegexTransformer.TransformError>? = nil
                if replaceMode && !template.isEmpty {
                    substitution = RegexTransformer.substitute(
                        pattern: pattern,
                        flags: flags,
                        in: text,
                        template: template
                    )
                }
                return EvalResult.completed(matchResult: matchResult, substitutionResult: substitution)
            }

            // Timeout sentinel: sleep 2 seconds then declare timeout.
            group.addTask {
                try await Task.sleep(for: .seconds(2))
                return EvalResult.timedOut
            }

            // Whichever finishes first wins; cancel the other.
            let first = (try? await group.next()) ?? .timedOut
            group.cancelAll()
            return first
        }

        // Publish results on the MainActor (we're already here via @MainActor class).
        guard !Task.isCancelled else { return }

        switch evalResult {
        case .timedOut:
            // D-02 / CF-02: keep last-good highlight dimmed; show timeout warning.
            timedOut = true
            outputDimmed = true
            errorMessage = "Pattern too slow — possible catastrophic backtracking"

        case .completed(let matchResult, let substitutionResult):
            timedOut = false
            switch matchResult {
            case .success(let newMatches):
                matches = newMatches
                outputDimmed = false
                errorMessage = nil

                // Build match-count badge text.
                switch newMatches.count {
                case 0: matchCountText = "No matches"
                case 1: matchCountText = "1 match"
                default: matchCountText = "\(newMatches.count) matches"
                }

                // Update substitution preview.
                if let subResult = substitutionResult {
                    switch subResult {
                    case .success(let preview):
                        substitutionPreview = preview
                    case .failure(let err):
                        substitutionPreview = ""
                        errorMessage = err.localizedDescription
                    }
                } else {
                    substitutionPreview = ""
                }

                // Write to history on successful match evaluation.
                let histInput = pattern + "\n" + text
                let histOutput = matchCountText
                onSaveHistory(HistoryEntry(
                    tool: "regex",
                    input: histInput,
                    output: histOutput,
                    timestamp: Date(),
                    pinned: false
                ))

            case .failure(let err):
                // Invalid pattern: dim last-good, show inline error.
                outputDimmed = true
                errorMessage = err.localizedDescription
                matchCountText = ""
                substitutionPreview = ""
            }
        }
    }

    // MARK: - Private Types

    private enum EvalResult: Sendable {
        case timedOut
        case completed(
            matchResult: Result<[RegexMatch], RegexTransformer.TransformError>,
            substitutionResult: Result<String, RegexTransformer.TransformError>?
        )
    }
}
