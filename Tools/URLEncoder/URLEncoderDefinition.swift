// Tools/URLEncoder/URLEncoderDefinition.swift
// STUB — Wave-2 plan 01-03 overwrites this file with the real URL tool.
// DO NOT add implementation here. This stub allows ToolRegistry to compile.

import SwiftUI

enum URLEncoderDefinition {
    static func make() -> ToolDefinition {
        ToolDefinition(
            id: "url-encoder",
            name: "URL Encoder/Decoder",
            category: .encoding,
            keywords: ["url", "percent", "encode", "decode", "query", "uri"],
            sfSymbol: "link",
            detectionPredicate: { input in
                let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
                // URL-encoded: contains %XX pattern
                let hasPercentEncoding = trimmed.range(
                    of: #"%[0-9A-Fa-f]{2}"#,
                    options: .regularExpression
                ) != nil
                // URL parser: valid http/https URL
                let isURL = URL(string: trimmed)?.scheme.map { ["http", "https"].contains($0) } ?? false
                guard hasPercentEncoding || isURL else { return nil }
                return DetectionResult(
                    toolId: "url-encoder",
                    toolName: "URL Encoder/Decoder",
                    sample: String(trimmed.prefix(40))
                )
            },
            makeView: {
                AnyView(Text("URL Encoder/Decoder — Coming Soon")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity))
            }
        )
    }
}
