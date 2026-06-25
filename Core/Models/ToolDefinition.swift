// Core/Models/ToolDefinition.swift
// The frozen tool abstraction — every tool in the registry is described by this struct.
// FREEZE: shape must NOT change after Phase 1 (all Wave-2 tool plans build against it).
// Source: RESEARCH.md Architecture Patterns — Pattern 3 [VERIFIED]

import SwiftUI

struct ToolDefinition: Identifiable, Sendable {
    let id: String
    let name: String
    let category: ToolCategory
    let keywords: [String]
    let sfSymbol: String
    /// First-match-wins predicate chain. Return nil if input doesn't match this tool.
    /// Must complete in < 2ms to satisfy INFRA-06 (<100ms detection).
    let detectionPredicate: (@Sendable (String) -> DetectionResult?)?
    /// Factory that constructs the tool's SwiftUI view. Called lazily on navigation.
    let makeView: @MainActor () -> AnyView
}
