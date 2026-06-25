// Core/Models/ToolCategory.swift
// Tool categories for grouping and filtering tools in the registry and UI.

enum ToolCategory: String, CaseIterable, Sendable {
    case encoding = "Encoding"
    case formatting = "Formatting"
    case conversion = "Conversion"
    case generation = "Generation"
    case analysis = "Analysis"

    var displayName: String { rawValue }
}
