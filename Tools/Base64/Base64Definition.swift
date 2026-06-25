// Tools/Base64/Base64Definition.swift
// Real ToolDefinition for Base64 — overwrites the Wave-1 stub.
// Detection chain priority 3: B64-03 isLikelyBase64 heuristic (≥12 chars + alphabet guard).
// Same make() signature as the stub — ToolRegistry already references it, no registry edit needed.
// Covers: B64-01..05, T-02-SP

import SwiftUI

enum Base64Definition {
    static func make() -> ToolDefinition {
        ToolDefinition(
            id: "base64",
            name: "Base64 Encoder/Decoder",
            category: .encoding,
            keywords: ["base64", "encode", "decode", "b64", "url-safe", "binary", "file"],
            sfSymbol: "lock.doc",
            detectionPredicate: { @Sendable input in
                // B64-03: auto-detect using isLikelyBase64 heuristic
                // T-02-SP: ≥12 chars + full base64 alphabet required to avoid false-positives
                let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
                guard Base64Transformer.isLikelyBase64(trimmed) else { return nil }
                return DetectionResult(
                    toolId: "base64",
                    toolName: "Base64 Encoder/Decoder",
                    sample: String(trimmed.prefix(40))
                )
            },
            makeView: { @MainActor in
                AnyView(Base64View())
            }
        )
    }
}
