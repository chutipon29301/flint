// Tools/Base64/Base64ViewModel.swift
// MVVM ViewModel for the Base64 Encoder/Decoder — owns debounce, auto-detect, history write.
// File I/O (B64-04) is button-triggered per D-10; runs off main thread via Task.detached.
// SECURITY: Never imports GRDB. History write via injected onSaveHistory closure (INFRA-09).

import Foundation
import Observation
import AppKit

@Observable
@MainActor
final class Base64ViewModel: ToolShortcutActions {

    // MARK: - Observable State

    /// Input text (encode or decode depending on mode).
    var input: String = "" {
        didSet { scheduleTransform() }
    }

    /// Last successfully transformed output (never cleared on error — D-11).
    var output: String = ""

    /// True while input is currently invalid — dims the output view (D-11).
    var outputDimmed: Bool = false

    /// Inline error message (INFRA-17).
    var errorMessage: String? = nil

    /// URL-safe variant toggle (B64-02).
    var urlSafe: Bool = false {
        didSet { scheduleTransform() }
    }

    /// Auto-detected mode: if input looks like base64, decode; otherwise encode.
    var isDecodeMode: Bool = false

    /// Byte count of decoded output (B64-05).
    var decodedByteCount: Int? = nil

    /// Character count of decoded output (B64-05).
    var decodedCharCount: Int? = nil

    /// File encoding progress (B64-04).
    var isProcessingFile: Bool = false

    /// File operation error message.
    var fileErrorMessage: String? = nil

    // MARK: - Private

    private let onSaveHistory: (HistoryEntry) -> Void
    private let debounce = Debounce()

    // MARK: - Init

    init(onSaveHistory: @escaping (HistoryEntry) -> Void) {
        self.onSaveHistory = onSaveHistory
    }

    // MARK: - ToolShortcutActions (INFRA-16)

    /// Returns the transformed output, or nil when there is nothing to copy.
    func primaryOutput() -> String? {
        output.isEmpty ? nil : output
    }

    /// Clears the input field (triggers scheduleTransform via didSet).
    func clearInput() {
        input = ""
    }

    // MARK: - Transform (D-10: 150ms debounce for text)

    private func scheduleTransform() {
        guard !input.isEmpty else {
            output = ""
            outputDimmed = false
            errorMessage = nil
            decodedByteCount = nil
            decodedCharCount = nil
            isDecodeMode = false
            return
        }
        Task {
            await debounce.schedule(delay: .milliseconds(150)) { [weak self] in
                await self?.runTransform()
            }
        }
    }

    private func runTransform() {
        // B64-03: auto-detect decode vs encode direction
        let likelyBase64 = Base64Transformer.isLikelyBase64(input)
        isDecodeMode = likelyBase64

        if likelyBase64 {
            // Attempt decode
            switch Base64Transformer.decode(input) {
            case .success(let text):
                output = text
                outputDimmed = false
                errorMessage = nil
                // B64-05: compute byte/char counts
                decodedByteCount = Base64Transformer.byteCount(for: Data(text.utf8))
                decodedCharCount = Base64Transformer.charCount(for: text)
                saveHistory(input: input, output: text)
            case .failure:
                // Not valid base64 despite looking like it — encode instead
                encodeInput()
            }
        } else {
            encodeInput()
        }
    }

    private func encodeInput() {
        isDecodeMode = false
        let encoded = Base64Transformer.encode(input, urlSafe: urlSafe)
        if encoded.isEmpty && !input.isEmpty {
            outputDimmed = true
            errorMessage = "Could not encode input"
        } else {
            output = encoded
            outputDimmed = false
            errorMessage = nil
            decodedByteCount = nil
            decodedCharCount = nil
            saveHistory(input: input, output: encoded)
        }
    }

    private func saveHistory(input: String, output: String) {
        onSaveHistory(HistoryEntry(
            tool: "base64",
            input: input,
            output: output,
            timestamp: Date(),
            pinned: false
        ))
    }

    // MARK: - Manual mode (user can override auto-detect)

    func forceEncode() {
        isDecodeMode = false
        let encoded = Base64Transformer.encode(input, urlSafe: urlSafe)
        output = encoded
        outputDimmed = false
        errorMessage = nil
        decodedByteCount = nil
        decodedCharCount = nil
        if !encoded.isEmpty {
            saveHistory(input: input, output: encoded)
        }
    }

    func forceDecode() {
        isDecodeMode = true
        switch Base64Transformer.decode(input) {
        case .success(let text):
            output = text
            outputDimmed = false
            errorMessage = nil
            decodedByteCount = Base64Transformer.byteCount(for: Data(text.utf8))
            decodedCharCount = Base64Transformer.charCount(for: text)
            saveHistory(input: input, output: text)
        case .failure:
            outputDimmed = true
            errorMessage = "Not valid Base64"
        }
    }

    // MARK: - File Encode (B64-04, D-10: button-triggered, T-02-DOS: chunked read)

    func encodeFile() {
        let panel = NSOpenPanel()
        panel.title = "Select File to Encode"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        isProcessingFile = true
        fileErrorMessage = nil

        // T-02-DOS: chunked read in Task.detached to avoid blocking main thread and loading large files at once
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let encoded = try await Self.encodeFileChunked(url: url, urlSafe: false)
                await MainActor.run { [weak self] in
                    self?.isProcessingFile = false
                    self?.output = encoded
                    self?.outputDimmed = false
                    self?.errorMessage = nil
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.isProcessingFile = false
                    self?.fileErrorMessage = "Could not read file"
                }
            }
        }
    }

    /// Chunked Base64 encoding of a file (T-02-DOS: 1MB chunks, never loads entire file).
    static func encodeFileChunked(url: URL, urlSafe: Bool) async throws -> String {
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }

        var chunks: [String] = []
        let chunkSize = 1_024 * 1_024  // 1MB chunks (T-02-DOS)

        // Each chunk must be a multiple of 3 bytes for clean base64 encoding (no padding between chunks)
        // Use 3 * 341 * 1024 = 1,047,552 bytes per chunk (multiple of 3)
        let alignedChunkSize = (chunkSize / 3) * 3  // 1_048_575 or nearest multiple of 3

        while true {
            let data = fileHandle.readData(ofLength: alignedChunkSize)
            if data.isEmpty { break }
            var encoded = data.base64EncodedString()
            if urlSafe {
                encoded = encoded
                    .replacingOccurrences(of: "+", with: "-")
                    .replacingOccurrences(of: "/", with: "_")
                    .replacingOccurrences(of: "=", with: "")
            }
            chunks.append(encoded)
        }

        return chunks.joined()
    }

    // MARK: - File Decode (B64-04, D-10: button-triggered)

    func decodeToFile() {
        guard !input.isEmpty else {
            fileErrorMessage = "No Base64 input to decode"
            return
        }

        let savePanel = NSSavePanel()
        savePanel.title = "Save Decoded File"
        savePanel.nameFieldStringValue = "decoded_file"

        guard savePanel.runModal() == .OK, let url = savePanel.url else { return }

        isProcessingFile = true
        fileErrorMessage = nil

        let inputSnapshot = input
        Task.detached(priority: .userInitiated) { [weak self] in
            switch Base64Transformer.decodeToData(inputSnapshot) {
            case .success(let data):
                do {
                    try data.write(to: url, options: .atomic)
                    await MainActor.run { [weak self] in
                        self?.isProcessingFile = false
                        self?.fileErrorMessage = nil
                    }
                } catch {
                    await MainActor.run { [weak self] in
                        self?.isProcessingFile = false
                        self?.fileErrorMessage = "Could not write file"
                    }
                }
            case .failure:
                await MainActor.run { [weak self] in
                    self?.isProcessingFile = false
                    self?.fileErrorMessage = "Not valid Base64"
                }
            }
        }
    }
}
