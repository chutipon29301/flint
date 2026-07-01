// Tools/UUID/UUIDDefinition.swift
// Real UUID tool definition — overwrites the Wave-1 stub created by plan 01-01.
// UUID-01..04 delivered: generation, inspection, export, case toggle.
// Detection predicate: UUID(uuidString:) != nil (priority 8 in detection chain — D-06).
// Pinned by default (D-13).

import SwiftUI

enum UUIDDefinition {
    static func make() -> ToolDefinition {
        ToolDefinition(
            id: "uuid-generator",
            name: "UUID Generator",
            category: .generation,
            keywords: ["uuid", "guid", "v1", "v4", "v5", "v7", "generate", "unique",
                       "identifier", "inspect", "parse", "bulk", "export"],
            sfSymbol: "rectangle.and.hand.point.up.left.filled",
            detectionPredicate: { input in
                // Detection chain priority 8 (D-06): UUID(uuidString:) != nil
                // Pre-check: must be ~36 chars with hyphens to avoid excessive parsing
                let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.count == 36 else { return nil }
                guard UUID(uuidString: trimmed) != nil else { return nil }
                return DetectionResult(
                    toolId: "uuid-generator",
                    toolName: "UUID Generator",
                    sample: String(trimmed.prefix(36))
                )
            },
            makeView: { @MainActor in
                AnyView(UUIDView())
            }
        )
    }
}
