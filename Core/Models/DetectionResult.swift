// Core/Models/DetectionResult.swift
// Result from the ClipboardDetector predicate chain.
// Carries enough information to show the detection banner.

struct DetectionResult: Sendable, Equatable {
    let toolId: String
    let toolName: String
    let sample: String   // truncated clipboard preview for display in banner
}
