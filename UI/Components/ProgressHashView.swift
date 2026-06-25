// UI/Components/ProgressHashView.swift
// Displays file hashing progress + per-hash copy rows once complete.
// HASH-02 (progress), HASH-04 (per-hash copy, uppercase toggle), D-12.

import SwiftUI

struct ProgressHashView: View {
    let result: HashTransformer.HashResult?
    let progress: Double          // 0.0 – 1.0; nil when not hashing
    let isHashing: Bool
    let uppercase: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isHashing {
                ProgressView(value: progress, total: 1.0) {
                    Text("Hashing file…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .progressViewStyle(.linear)
                .accessibilityLabel("File hashing progress")
            }

            if let result {
                hashRows(result)
            }
        }
    }

    @ViewBuilder
    private func hashRows(_ result: HashTransformer.HashResult) -> some View {
        VStack(spacing: 6) {
            hashRow(algorithm: "MD5",    value: result.md5)
            hashRow(algorithm: "SHA-1",  value: result.sha1)
            hashRow(algorithm: "SHA-256",value: result.sha256)
            hashRow(algorithm: "SHA-384",value: result.sha384)
            hashRow(algorithm: "SHA-512",value: result.sha512)
            hashRow(algorithm: "CRC32",  value: result.crc32)
        }
    }

    private func hashRow(algorithm: String, value: String) -> some View {
        let displayValue = uppercase ? value.uppercased() : value
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(algorithm)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .leading)
                Text(displayValue)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(2)
            }
            Spacer()
            CopyButtonView(text: displayValue)
                .accessibilityLabel("Copy \(algorithm) hash")
        }
        .padding(8)
        .background(.quaternary.opacity(0.5))
        .cornerRadius(6)
    }
}
