// Tools/JWT/JWTDefinition.swift
// Real ToolDefinition for JWT Decoder — overwrites the Wave-1 stub.
// Detection chain priority 2: hasPrefix("ey") + exactly 2 "." separators.
// Same make() signature as the stub — ToolRegistry already references it, no registry edit needed.
// Covers: JWT-01..06, INFRA-09 (secret exclusion via JWTView/JWTViewModel architecture)

import SwiftUI

enum JWTDefinition {
    static func make() -> ToolDefinition {
        ToolDefinition(
            id: "jwt-decoder",
            name: "JWT Decoder",
            category: .analysis,
            keywords: ["jwt", "json", "web", "token", "bearer", "hmac", "signature", "claims", "expiry", "decode"],
            sfSymbol: "person.badge.key",
            detectionPredicate: { @Sendable input in
                let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
                // JWT detection: starts with "ey" (base64url of "{") + exactly 2 "." separators
                // Source: RESEARCH.md § "Native API Recipes" → "JWT Tool" (chain priority 2)
                guard trimmed.hasPrefix("ey"),
                      trimmed.components(separatedBy: ".").count == 3 else { return nil }
                return DetectionResult(
                    toolId: "jwt-decoder",
                    toolName: "JWT Decoder",
                    sample: String(trimmed.prefix(40))
                )
            },
            makeView: { @MainActor in
                AnyView(JWTView())
            }
        )
    }
}
