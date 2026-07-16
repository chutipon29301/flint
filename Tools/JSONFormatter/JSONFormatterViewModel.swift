// Tools/JSONFormatter/JSONFormatterViewModel.swift
// MVVM ViewModel for the JSON Formatter — owns debounce, last-good-output.
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

    // MARK: - Find & Replace (operates on the input text)

    /// Whether the compact find/replace bar is visible.
    var findVisible: Bool = false
    var findQuery: String = ""
    var replaceText: String = ""
    var findCaseSensitive: Bool = false

    /// Number of matches for the current query in the current input.
    var matchCount: Int {
        guard !findQuery.isEmpty else { return 0 }
        let opts: String.CompareOptions = findCaseSensitive ? [] : [.caseInsensitive]
        var count = 0
        var range = input.startIndex..<input.endIndex
        while let found = input.range(of: findQuery, options: opts, range: range) {
            count += 1
            range = found.upperBound..<input.endIndex
        }
        return count
    }

    /// Replace all occurrences of findQuery with replaceText in the input.
    func replaceAll() {
        guard !findQuery.isEmpty else { return }
        let opts: String.CompareOptions = findCaseSensitive ? [] : [.caseInsensitive]
        input = input.replacingOccurrences(of: findQuery, with: replaceText, options: opts)
    }

    // MARK: - Private

    private let debounce = Debounce()

    // MARK: - Init

    init() {}

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
        case .failure(let error):
            // D-11: keep last valid output visible but dimmed — do NOT clear output
            outputDimmed = true
            errorMessage = error.displayMessage
        }
    }
}
