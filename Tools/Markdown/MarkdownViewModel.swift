// Tools/Markdown/MarkdownViewModel.swift
// Debounced Markdown ViewModel — owns render scheduling and last-good output.
// Reuses project-wide Debounce actor (defined in JSONFormatterViewModel.swift).

import Foundation
import Observation

@Observable
@MainActor
final class MarkdownViewModel: ToolShortcutActions {

    // MARK: - Observable State

    var source: String = "" {
        didSet { scheduleRender() }
    }

    /// Last successfully rendered HTML. Never cleared on error (CF-02).
    var html: String = ""

    /// True while source is invalid or render pending — dims the preview (CF-02).
    var outputDimmed: Bool = false

    /// Inline error message (nil when no error).
    var errorMessage: String? = nil

    /// Footer: "words: N"
    var wordCountText: String = "words: 0"

    /// Footer: "~N min read"
    var readingTimeText: String = "~1 min read"

    // MARK: - Private

    private let debounce = Debounce()

    // MARK: - Init

    init() {}

    // MARK: - ToolShortcutActions (INFRA-16)

    func primaryOutput() -> String? {
        html.isEmpty ? nil : html
    }

    func clearInput() {
        source = ""
    }

    // MARK: - Render scheduling

    func scheduleRender() {
        guard !source.isEmpty else {
            html = ""
            outputDimmed = false
            errorMessage = nil
            wordCountText = "words: 0"
            readingTimeText = "~1 min read"
            return
        }
        Task {
            await debounce.schedule(delay: .milliseconds(300)) { [weak self] in
                await self?.runRender()
            }
        }
    }

    private func runRender() {
        let result = MarkdownTransformer.fullStyledHTML(source)
        switch result {
        case .success(let rendered):
            html = rendered
            outputDimmed = false
            errorMessage = nil
            // Update word count + reading time
            let wc = MarkdownTransformer.wordCount(source)
            let rt = MarkdownTransformer.readingTimeMinutes(words: wc)
            wordCountText = "words: \(wc)"
            readingTimeText = "~\(rt) min read"
        case .failure(let error):
            // CF-02: keep last-good html visible but dimmed — do NOT clear html
            outputDimmed = true
            errorMessage = error.displayMessage
        }
    }
}
