// Tools/Regex/RegexDefinition.swift
// Stub — will be implemented in Task 3.
import SwiftUI

enum RegexDefinition {
    static func make() -> ToolDefinition {
        ToolDefinition(
            id: "regex",
            name: "Regex Tester",
            category: .analysis,
            keywords: ["regex", "regexp", "pattern", "match", "replace", "grep"],
            sfSymbol: "text.magnifyingglass",
            detectionPredicate: nil,
            makeView: { @MainActor in AnyView(RegexView()) }
        )
    }
}
