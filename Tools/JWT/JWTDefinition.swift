// Tools/JWT/JWTDefinition.swift
// STUB — Wave-2 plan 01-03 overwrites this file with the real JWT tool.
// DO NOT add implementation here. This stub allows ToolRegistry to compile.

import SwiftUI

enum JWTDefinition {
    static func make() -> ToolDefinition {
        ToolDefinition(
            id: "jwt-decoder",
            name: "JWT Decoder",
            category: .analysis,
            keywords: ["jwt", "json", "web", "token", "bearer", "hmac", "signature"],
            sfSymbol: "person.badge.key",
            detectionPredicate: { input in
                let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
                // JWT: starts with "ey" and has exactly 2 "." separators
                guard trimmed.hasPrefix("ey"),
                      trimmed.components(separatedBy: ".").count == 3 else { return nil }
                return DetectionResult(
                    toolId: "jwt-decoder",
                    toolName: "JWT Decoder",
                    sample: String(trimmed.prefix(40))
                )
            },
            makeView: {
                AnyView(Text("JWT Decoder — Coming Soon")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity))
            }
        )
    }
}
