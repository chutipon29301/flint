// Tools/Timestamp/TimestampDefinition.swift
// Real Timestamp tool definition — overwrites stub from 01-01.
// Detection predicate: chain priority 6 (pure numeric, 10 or 13 digits).
// ToolRegistry.swift is FROZEN — not edited here.

import SwiftUI

enum TimestampDefinition {
    static func make() -> ToolDefinition {
        ToolDefinition(
            id: "timestamp",
            name: "Unix Timestamp Converter",
            category: .conversion,
            keywords: ["timestamp", "unix", "date", "time", "epoch", "iso", "utc", "convert", "now"],
            sfSymbol: "clock",
            detectionPredicate: { input in
                let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
                // Priority 6: pure numeric, 10 or 13 digits (seconds or milliseconds)
                // 11/12-digit ambiguous inputs DO match (we show the toggle in the View)
                let digits = trimmed.hasPrefix("-") ? String(trimmed.dropFirst()) : trimmed
                guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return nil }
                let count = digits.count
                guard count == 10 || count == 13 else { return nil }
                return DetectionResult(
                    toolId: "timestamp",
                    toolName: "Unix Timestamp Converter",
                    sample: String(trimmed.prefix(40))
                )
            },
            makeView: { @MainActor in
                AnyView(TimestampViewWrapper())
            }
        )
    }
}

// MARK: - Wrapper for environment-injected history store

private struct TimestampViewWrapper: View {
    @Environment(HistoryStore.self) private var historyStore

    var body: some View {
        TimestampView { entry in
            historyStore.save(entry)
        }
    }
}
