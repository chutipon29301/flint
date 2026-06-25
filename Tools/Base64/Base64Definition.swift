// Tools/Base64/Base64Definition.swift
// STUB — Wave-2 plan 01-02 overwrites this file with the real Base64 tool.
// DO NOT add implementation here. This stub allows ToolRegistry to compile.

import SwiftUI

enum Base64Definition {
    static func make() -> ToolDefinition {
        ToolDefinition(
            id: "base64",
            name: "Base64 Encoder/Decoder",
            category: .encoding,
            keywords: ["base64", "encode", "decode", "b64"],
            sfSymbol: "lock.doc",
            detectionPredicate: { input in
                // Base64 detection: all chars in alphabet, ≥12 chars, multiple of 4
                let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.count >= 12 else { return nil }
                let base64Chars = CharacterSet(
                    charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=-_"
                )
                let allBase64 = trimmed.unicodeScalars.allSatisfy { base64Chars.contains($0) }
                guard allBase64 else { return nil }
                return DetectionResult(
                    toolId: "base64",
                    toolName: "Base64 Encoder/Decoder",
                    sample: String(trimmed.prefix(40))
                )
            },
            makeView: {
                AnyView(Text("Base64 — Coming Soon")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity))
            }
        )
    }
}
