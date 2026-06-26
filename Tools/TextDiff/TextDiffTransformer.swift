// Tools/TextDiff/TextDiffTransformer.swift
// STUB — TDD RED phase placeholder. Real implementation in GREEN phase.
import Foundation

// Stub types so tests compile
enum TextDiffTransformer {
    static func diff(original: String, changed: String, ignoreWhitespace: Bool, ignoreCase: Bool) -> DiffResult {
        fatalError("Not implemented — TDD RED phase")
    }
}

struct DiffResult {
    let lines: [DiffLine]
    var hasDiffs: Bool { fatalError("stub") }
    var diffHunkCount: Int { fatalError("stub") }
    var unifiedPatch: String { fatalError("stub") }
}

struct DiffLine {
    enum LineKind { case added, removed, unchanged }
    enum WordSegmentKind { case equal, inserted, deleted }
    struct WordSegment {
        let text: String
        let segmentKind: WordSegmentKind
    }
    let kind: LineKind
    let displayText: String
    let originalLineNumber: Int?
    let newLineNumber: Int?
    let wordSegments: [WordSegment]?
}
