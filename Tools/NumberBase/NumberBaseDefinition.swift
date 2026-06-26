// Tools/NumberBase/NumberBaseDefinition.swift
// STUB — will be fully implemented in Task 2.
import SwiftUI

enum NumberBaseDefinition {
    static func make() -> ToolDefinition {
        ToolDefinition(
            id: "number-base",
            name: "Number Base Converter",
            category: .conversion,
            keywords: ["number", "base", "binary", "octal", "decimal", "hex"],
            sfSymbol: "number",
            detectionPredicate: nil,
            makeView: { @MainActor in AnyView(NumberBaseView()) }
        )
    }
}
