// Tools/URLEncoder/URLViewModel.swift
// MVVM ViewModel for the URL Encoder/Decoder — owns debounce, parse state, history write.
// SECURITY: Never imports GRDB. History write via injected onSaveHistory closure (INFRA-09).

import Foundation
import Observation

/// Operating mode for the URL tool.
enum URLToolMode: CaseIterable, Identifiable {
    case encode
    case decode
    case parse

    var id: Self { self }
    var label: String {
        switch self {
        case .encode: return "Encode"
        case .decode: return "Decode"
        case .parse:  return "Parse URL"
        }
    }
}

@Observable
@MainActor
final class URLViewModel: ToolShortcutActions {

    // MARK: - Observable State

    /// The raw input text.
    var input: String = "" {
        didSet { scheduleTransform() }
    }

    /// Output for encode/decode mode.
    var encodedOutput: String = ""

    /// True while input produces an error — dims last-good output (D-11).
    var outputDimmed: Bool = false

    /// Inline error message (INFRA-17).
    var errorMessage: String? = nil

    /// Active mode (encode / decode / parse).
    var mode: URLToolMode = .encode {
        didSet { scheduleTransform() }
    }

    // MARK: - Parse Mode State (URL-02, URL-03)

    /// Parsed URL components (non-nil when parse mode succeeds).
    var parsedURL: URLTransformer.ParsedURL? = nil

    /// Editable query items for the add/delete table (URL-03).
    var editableQueryItems: [URLTransformer.QueryItem] = []

    /// The rebuilt URL after editing query params (URL-03).
    var rebuiltURL: String = ""

    // MARK: - Private

    private let onSaveHistory: (HistoryEntry) -> Void
    private let debounce = Debounce()

    // MARK: - Init

    init(onSaveHistory: @escaping (HistoryEntry) -> Void) {
        self.onSaveHistory = onSaveHistory
    }

    // MARK: - ToolShortcutActions (INFRA-16)

    /// Returns the primary output for the active mode, or nil when there is nothing to copy.
    /// In .parse mode, the rebuilt URL is the primary output; in .encode/.decode, encodedOutput.
    func primaryOutput() -> String? {
        switch mode {
        case .parse:
            return rebuiltURL.isEmpty ? nil : rebuiltURL
        case .encode, .decode:
            return encodedOutput.isEmpty ? nil : encodedOutput
        }
    }

    /// Clears the input field (triggers scheduleTransform via didSet).
    func clearInput() {
        input = ""
    }

    // MARK: - Transform (D-10: 150ms debounce)

    private func scheduleTransform() {
        guard !input.isEmpty else {
            encodedOutput = ""
            outputDimmed = false
            errorMessage = nil
            parsedURL = nil
            editableQueryItems = []
            rebuiltURL = ""
            return
        }
        Task {
            await debounce.schedule(delay: .milliseconds(150)) { [weak self] in
                await self?.runTransform()
            }
        }
    }

    private func runTransform() {
        switch mode {
        case .encode:
            runEncode()
        case .decode:
            runDecode()
        case .parse:
            runParse()
        }
    }

    private func runEncode() {
        switch URLTransformer.percentEncode(input) {
        case .success(let encoded):
            encodedOutput = encoded
            outputDimmed = false
            errorMessage = nil
            saveHistory(input: input, output: encoded)
        case .failure(let error):
            outputDimmed = true
            errorMessage = error.localizedDescription
        }
    }

    private func runDecode() {
        switch URLTransformer.percentDecode(input) {
        case .success(let decoded):
            encodedOutput = decoded
            outputDimmed = false
            errorMessage = nil
            saveHistory(input: input, output: decoded)
        case .failure(let error):
            outputDimmed = true
            errorMessage = error.localizedDescription
        }
    }

    private func runParse() {
        switch URLTransformer.parse(input) {
        case .success(let parsed):
            parsedURL = parsed
            editableQueryItems = parsed.queryItems
            outputDimmed = false
            errorMessage = nil
            rebuildURL()
            saveHistory(input: input, output: rebuiltURL)
        case .failure(let error):
            // D-11: keep last parsed components visible but dimmed
            outputDimmed = true
            errorMessage = error.localizedDescription
        }
    }

    private func saveHistory(input: String, output: String) {
        onSaveHistory(HistoryEntry(
            tool: "url-encoder",
            input: input,
            output: output,
            timestamp: Date(),
            pinned: false
        ))
    }

    // MARK: - Query Param Table Operations (URL-03)

    /// Rebuild the URL from the current editable query items.
    func rebuildURL() {
        guard var parsed = parsedURL else { return }
        parsed.queryItems = editableQueryItems
        switch URLTransformer.rebuild(parsed) {
        case .success(let url):
            rebuiltURL = url
            errorMessage = nil
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    /// Add a new blank query parameter to the editable table.
    func addQueryItem() {
        editableQueryItems.append(URLTransformer.QueryItem(name: "", value: ""))
        rebuildURL()
    }

    /// Delete a query parameter at the given offset set.
    func deleteQueryItems(at offsets: IndexSet) {
        editableQueryItems.remove(atOffsets: offsets)
        rebuildURL()
    }

    /// Called when the user edits a query item key or value in the table.
    func queryItemDidChange() {
        rebuildURL()
    }
}
