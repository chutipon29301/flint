// Tools/UUID/UUIDDefinition.swift
// STUB — Wave-2 plan 01-05 overwrites this file with the real UUID tool.
// DO NOT add implementation here. This stub allows ToolRegistry to compile.

import SwiftUI

enum UUIDDefinition {
    static func make() -> ToolDefinition {
        ToolDefinition(
            id: "uuid-generator",
            name: "UUID Generator",
            category: .generation,
            keywords: ["uuid", "guid", "v4", "v1", "v5", "generate", "unique"],
            sfSymbol: "rectangle.and.hand.point.up.left.filled",
            detectionPredicate: { input in
                let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
                guard UUID(uuidString: trimmed) != nil else { return nil }
                return DetectionResult(
                    toolId: "uuid-generator",
                    toolName: "UUID Generator",
                    sample: String(trimmed.prefix(40))
                )
            },
            makeView: {
                AnyView(Text("UUID Generator — Coming Soon")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity))
            }
        )
    }
}
