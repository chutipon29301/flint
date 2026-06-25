// Tools/Hash/HashViewModel.swift
// @Observable ViewModel for the Hash Generator tool.
// SECURITY (INFRA-09, pitfall #3): HMAC key is a View-local @State.
// It is NEVER a ViewModel property and NEVER passed to onSaveHistory.
// NEVER imports GRDB.

import SwiftUI
import Foundation

@Observable
@MainActor
final class HashViewModel {

    // MARK: - Text input

    var textInput: String = "" {
        didSet { scheduleTextHash() }
    }

    // MARK: - Text hash output

    var textHashResult: HashTransformer.HashResult? = nil
    var uppercase: Bool = false

    // MARK: - HMAC output
    // Note: HMAC key is NOT stored here — it lives in HashView as @State.

    var hmacResult: String = ""
    var hmacAlgorithm: HashTransformer.HMACAlgorithm = .sha256
    var hmacEnabled: Bool = false

    // MARK: - File hashing

    var fileURL: URL? = nil
    var fileHashResult: HashTransformer.HashResult? = nil
    var fileHashProgress: Double = 0.0
    var isHashing: Bool = false
    var fileHashTask: Task<Void, Never>? = nil

    // MARK: - Error

    var errorMessage: String? = nil

    // MARK: - Private

    private let onSaveHistory: (HistoryEntry) -> Void
    private let debounce = Debounce()

    init(onSaveHistory: @escaping (HistoryEntry) -> Void) {
        self.onSaveHistory = onSaveHistory
    }

    // MARK: - Text hashing

    private func scheduleTextHash() {
        Task {
            await debounce.schedule(delay: .milliseconds(150)) { [weak self] in
                await self?.runTextHash()
            }
        }
    }

    private func runTextHash() {
        guard !textInput.isEmpty else {
            textHashResult = nil
            hmacResult = ""
            errorMessage = nil
            return
        }

        textHashResult = HashTransformer.hashText(textInput)
        errorMessage = nil

        // Write to history: input text + all hash outputs.
        // SECURITY: HMAC key is NOT included — it never reaches this method (INFRA-09, pitfall #3).
        if let result = textHashResult {
            let outputLines = formatHashResult(result)
            // SECURITY: HMAC key not included in history — INFRA-09 / pitfall #3
            onSaveHistory(HistoryEntry(
                tool: "hash",
                input: textInput,  // input text only — HMAC key excluded by design
                output: outputLines,
                timestamp: Date(),
                pinned: false
            ))
        }
    }

    // MARK: - HMAC (key passed in from View-local @State — never stored here)

    /// Computes HMAC for the current text input using a key provided by the View.
    /// The key parameter is transient — never stored on the ViewModel.
    func computeHMAC(key: String) {
        guard !textInput.isEmpty, !key.isEmpty else {
            hmacResult = ""
            return
        }
        hmacResult = HashTransformer.hmacText(textInput, key: key, algorithm: hmacAlgorithm)
        // SECURITY: history is written in runTextHash() without the key.
        // HMAC result is NOT re-written to history here to avoid leaking patterns.
    }

    // MARK: - File hashing (button-triggered per D-10)

    func startFileHash(url: URL) {
        fileHashTask?.cancel()
        fileURL = url
        fileHashResult = nil
        fileHashProgress = 0.0
        isHashing = true
        errorMessage = nil

        let capturedOnSave = onSaveHistory
        fileHashTask = Task {
            let result = await HashTransformer.hashFile(url: url) { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.fileHashProgress = progress
                }
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.fileHashResult = result
                self.isHashing = false
                // Write history for file hash: filename + hashes.
                // SECURITY: no HMAC key involved in file hashing (INFRA-09, pitfall #3).
                let outputLines = self.formatHashResult(result)
                capturedOnSave(HistoryEntry(
                    tool: "hash",
                    input: url.lastPathComponent,  // filename only — no key
                    output: outputLines,
                    timestamp: Date(),
                    pinned: false
                ))
            }
        }
    }

    func cancelFileHash() {
        fileHashTask?.cancel()
        fileHashTask = nil
        isHashing = false
    }

    // MARK: - Copy all hashes

    func allHashesText(from result: HashTransformer.HashResult) -> String {
        // WR-06: removed dead `prefix` variable (both ternary branches were identical empty strings)
        let lines = [
            "MD5:    \(uppercase ? result.md5.uppercased() : result.md5)",
            "SHA-1:  \(uppercase ? result.sha1.uppercased() : result.sha1)",
            "SHA-256:\(uppercase ? result.sha256.uppercased() : result.sha256)",
            "SHA-384:\(uppercase ? result.sha384.uppercased() : result.sha384)",
            "SHA-512:\(uppercase ? result.sha512.uppercased() : result.sha512)",
            "CRC32:  \(uppercase ? result.crc32.uppercased() : result.crc32)",
        ]
        return lines.joined(separator: "\n")
    }

    // MARK: - Private helpers

    private func formatHashResult(_ result: HashTransformer.HashResult) -> String {
        "MD5: \(result.md5)\nSHA-1: \(result.sha1)\nSHA-256: \(result.sha256)\nSHA-384: \(result.sha384)\nSHA-512: \(result.sha512)\nCRC32: \(result.crc32)"
    }
}
