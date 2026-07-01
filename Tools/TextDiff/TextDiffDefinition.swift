// Tools/TextDiff/TextDiffDefinition.swift
// Text Diff tool definition — search-only (nil predicate), category .analysis.
// DIFF-01..04: Part of the Wave-7 registration group; do NOT add to ToolRegistry here.

import SwiftUI

enum TextDiffDefinition {
    static func make() -> ToolDefinition {
        ToolDefinition(
            id: "text-diff",
            name: "Text Diff",
            category: .analysis,
            keywords: ["diff", "compare", "text", "patch", "difference", "merge", "changes"],
            sfSymbol: "arrow.left.arrow.right",
            detectionPredicate: nil,   // search-only (UI-SPEC § Detection predicate)
            makeView: { @MainActor in
                AnyView(TextDiffView())
            }
        )
    }
}
