// Tools/TextDiff/TextDiffDefinition.swift
// STUB — placeholder for TDD RED phase
import SwiftUI

enum TextDiffDefinition {
    static func make() -> ToolDefinition {
        ToolDefinition(
            id: "text-diff", name: "Text Diff", category: .analysis,
            keywords: [], sfSymbol: "arrow.left.arrow.right",
            detectionPredicate: nil,
            makeView: { @MainActor in AnyView(TextDiffView()) }
        )
    }
}
