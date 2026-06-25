// Tools/URLEncoder/URLEncoderDefinition.swift
// Real ToolDefinition for URL Encoder/Decoder — overwrites the Wave-1 stub.
// Registers BOTH detection predicates from the chain:
//   priority 4: percent-encoded pattern (%XX)
//   priority 5: URL scheme (http/https/ftp/etc.)
// Same make() signature as the stub — ToolRegistry already references it, no registry edit needed.
// Covers: URL-01..04, D-12

import SwiftUI

enum URLEncoderDefinition {
    static func make() -> ToolDefinition {
        ToolDefinition(
            id: "url-encoder",
            name: "URL Encoder/Decoder",
            category: .encoding,
            keywords: ["url", "percent", "encode", "decode", "query", "uri", "parse", "component", "scheme"],
            sfSymbol: "link",
            detectionPredicate: { @Sendable input in
                let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }

                // Priority 4: percent-encoded content — contains %XX pattern
                let hasPercentEncoding = trimmed.range(
                    of: #"%[0-9A-Fa-f]{2}"#,
                    options: .regularExpression
                ) != nil

                if hasPercentEncoding {
                    return DetectionResult(
                        toolId: "url-encoder",
                        toolName: "URL Encoder/Decoder",
                        sample: String(trimmed.prefix(40))
                    )
                }

                // Priority 5: full URL with recognized scheme
                if let components = URLComponents(string: trimmed),
                   let scheme = components.scheme,
                   !scheme.isEmpty {
                    // Accept any schemed URL: http, https, ftp, mailto, custom, etc.
                    return DetectionResult(
                        toolId: "url-encoder",
                        toolName: "URL Encoder/Decoder",
                        sample: String(trimmed.prefix(40))
                    )
                }

                return nil
            },
            makeView: { @MainActor in
                AnyView(URLView())
            }
        )
    }
}
