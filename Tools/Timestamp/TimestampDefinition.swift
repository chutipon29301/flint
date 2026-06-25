// Tools/Timestamp/TimestampDefinition.swift
// STUB — Wave-2 plan 01-04 overwrites this file with the real Timestamp tool.
// DO NOT add implementation here. This stub allows ToolRegistry to compile.

import SwiftUI

enum TimestampDefinition {
    static func make() -> ToolDefinition {
        ToolDefinition(
            id: "timestamp",
            name: "Unix Timestamp Converter",
            category: .conversion,
            keywords: ["timestamp", "unix", "date", "time", "epoch", "iso", "utc"],
            sfSymbol: "clock",
            detectionPredicate: { input in
                let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
                // Timestamp: pure numeric, 10 or 13 digits
                guard trimmed.allSatisfy(\.isNumber),
                      trimmed.count == 10 || trimmed.count == 13 else { return nil }
                return DetectionResult(
                    toolId: "timestamp",
                    toolName: "Unix Timestamp Converter",
                    sample: String(trimmed.prefix(40))
                )
            },
            makeView: {
                AnyView(Text("Timestamp Converter — Coming Soon")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity))
            }
        )
    }
}
