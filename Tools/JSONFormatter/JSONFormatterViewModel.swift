// Tools/JSONFormatter/JSONFormatterViewModel.swift
// MVVM ViewModel for the JSON Formatter — owns debounce, last-good-output, history write.
// SECURITY: Never imports GRDB. History write via injected onSaveHistory closure (INFRA-09).
// Source: RESEARCH.md Pattern 5 [VERIFIED]

import Foundation
import Observation

// MARK: - Debounce Actor

/// Swift Concurrency actor-based debounce. Cancels in-flight task on each new schedule call.
/// Source: RESEARCH.md debounce pattern [MEDIUM confidence]
actor Debounce: Sendable {
    private var task: Task<Void, Never>?

    func schedule(delay: Duration, action: @Sendable @escaping () async -> Void) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await action()
        }
    }
}

// MARK: - JSON Formatter ViewModel

@Observable
@MainActor
final class JSONFormatterViewModel: ToolShortcutActions {
    // MARK: - Observable State

    var input: String = "" {
        didSet { scheduleTransform() }
    }
    /// Last successfully formatted output. Never cleared on error (D-11).
    var output: String = ""
    /// True while input is currently invalid — dims the output view (D-11).
    var outputDimmed: Bool = false
    /// Inline error message (JSON-03).
    var errorMessage: String? = nil

    // Transform options
    var indentSize: Int = 2 {     // 2 = two spaces, 4 = four spaces, 0 = tab
        didSet { scheduleTransform() }
    }
    var sortKeys: Bool = false {
        didSet { scheduleTransform() }
    }
    var minifyOutput: Bool = false {
        didSet { scheduleTransform() }
    }

    // MARK: - Private

    /// Injected history write closure. ViewModel NEVER imports GRDB directly (INFRA-09).
    private let onSaveHistory: (HistoryEntry) -> Void
    private let debounce = Debounce()

    // MARK: - Init

    init(onSaveHistory: @escaping (HistoryEntry) -> Void) {
        self.onSaveHistory = onSaveHistory
    }

    // MARK: - Transform

    private func scheduleTransform() {
        guard !input.isEmpty else {
            output = ""
            outputDimmed = false
            errorMessage = nil
            return
        }
        Task {
            await debounce.schedule(delay: .milliseconds(150)) { [weak self] in
                await self?.runTransform()
            }
        }
    }

    // MARK: - ToolShortcutActions (INFRA-16)

    /// Returns the formatted output, or nil when there is nothing to copy.
    func primaryOutput() -> String? {
        output.isEmpty ? nil : output
    }

    /// Clears the input field (triggers scheduleTransform via didSet).
    func clearInput() {
        input = ""
    }

    private func runTransform() {
        let result: Result<String, JSONTransformer.JSONError>
        if minifyOutput {
            result = JSONTransformer.minify(input)
        } else if sortKeys {
            result = JSONTransformer.prettyPrintSorted(input, indent: indentSize)
        } else {
            result = JSONTransformer.prettyPrint(input, indent: indentSize)
        }

        switch result {
        case .success(let formatted):
            output = formatted
            outputDimmed = false
            errorMessage = nil
            // Write to history on successful transform (INFRA-07)
            onSaveHistory(HistoryEntry(
                tool: "json-formatter",
                input: input,
                output: formatted,
                timestamp: Date(),
                pinned: false
            ))
        case .failure(let error):
            // D-11: keep last valid output visible but dimmed — do NOT clear output
            outputDimmed = true
            errorMessage = error.displayMessage
        }
    }
}
