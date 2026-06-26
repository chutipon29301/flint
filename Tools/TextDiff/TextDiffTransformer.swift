// Tools/TextDiff/TextDiffTransformer.swift
// Pure diff transformer — NO SwiftUI/AppKit imports (unit-testable without UI).
// INFRA-17: Never force-unwraps, never crashes on malformed / empty / large inputs.
// Line-level diff: native CollectionDifference (Myers). Word-level: vendored SwiftDiff.

import Foundation

// MARK: - Public Types

/// A single word-level segment within a modified line.
struct WordSegment {
    enum SegmentKind { case equal, inserted, deleted }
    let text: String
    let segmentKind: SegmentKind
}

/// Represents a single row in the diff output.
struct DiffLine {
    enum LineKind { case added, removed, unchanged }

    let kind: LineKind
    /// The original display text (casing + spacing preserved regardless of ignore flags).
    let displayText: String
    /// 1-based line number in the original text (nil for pure-added lines).
    let originalLineNumber: Int?
    /// 1-based line number in the changed text (nil for pure-removed lines).
    let newLineNumber: Int?
    /// Word-level segments from SwiftDiff; only present on modified (paired remove/insert) lines.
    let wordSegments: [WordSegment]?
}

/// The complete result of a diff operation.
struct DiffResult {
    let lines: [DiffLine]

    /// True when at least one line is added or removed.
    var hasDiffs: Bool {
        lines.contains { $0.kind != .unchanged }
    }

    /// Number of contiguous diff "hunks" (groups of changed lines).
    var diffHunkCount: Int {
        var count = 0
        var inHunk = false
        for line in lines {
            if line.kind != .unchanged {
                if !inHunk { count += 1; inHunk = true }
            } else {
                inHunk = false
            }
        }
        return count
    }

    /// Unified-diff patch string in standard format:
    ///   --- Original\n+++ Changed\n@@ -l,s +l,s @@\n …
    var unifiedPatch: String {
        var result = "--- Original\n+++ Changed\n"
        if !hasDiffs { return result }

        // Build hunks with ±3 context lines
        let contextRadius = 3
        var hunks: [(origStart: Int, origCount: Int, newStart: Int, newCount: Int, body: [String])] = []

        // Build index list of all diff-line positions
        var changeIndices = [Int]()
        for (idx, line) in lines.enumerated() where line.kind != .unchanged {
            changeIndices.append(idx)
        }

        // Group consecutive and near-consecutive change indices into windows
        var windows: [[Int]] = []
        if !changeIndices.isEmpty {
            var current = [changeIndices[0]]
            for i in 1..<changeIndices.count {
                if changeIndices[i] - changeIndices[i - 1] <= contextRadius * 2 + 1 {
                    current.append(changeIndices[i])
                } else {
                    windows.append(current)
                    current = [changeIndices[i]]
                }
            }
            windows.append(current)
        }

        for window in windows {
            guard let firstIdx = window.first, let lastIdx = window.last else { continue }
            let rangeStart = max(0, firstIdx - contextRadius)
            let rangeEnd = min(lines.count - 1, lastIdx + contextRadius)

            var body = [String]()
            var origCount = 0
            var newCount = 0
            var origLineStart: Int? = nil
            var newLineStart: Int? = nil

            for idx in rangeStart...rangeEnd {
                let line = lines[idx]
                switch line.kind {
                case .unchanged:
                    body.append(" " + line.displayText)
                    origCount += 1
                    newCount += 1
                    if origLineStart == nil { origLineStart = line.originalLineNumber ?? (idx + 1) }
                    if newLineStart == nil { newLineStart = line.newLineNumber ?? (idx + 1) }
                case .removed:
                    body.append("-" + line.displayText)
                    origCount += 1
                    if origLineStart == nil { origLineStart = line.originalLineNumber ?? (idx + 1) }
                    if newLineStart == nil { newLineStart = (line.newLineNumber ?? (idx + 1)) }
                case .added:
                    body.append("+" + line.displayText)
                    newCount += 1
                    if origLineStart == nil { origLineStart = (line.originalLineNumber ?? (idx + 1)) }
                    if newLineStart == nil { newLineStart = line.newLineNumber ?? (idx + 1) }
                }
            }

            let os = origLineStart ?? 1
            let ns = newLineStart ?? 1
            hunks.append((os, origCount, ns, newCount, body))
        }

        for hunk in hunks {
            result += "@@ -\(hunk.origStart),\(hunk.origCount) +\(hunk.newStart),\(hunk.newCount) @@\n"
            result += hunk.body.joined(separator: "\n") + "\n"
        }

        return result
    }
}

// MARK: - Transformer

enum TextDiffTransformer {

    /// Compute a line+word diff between two texts.
    ///
    /// - Parameters:
    ///   - original: The "before" text.
    ///   - changed:  The "after" text.
    ///   - ignoreWhitespace: Collapse runs of whitespace before comparison (preserves display text).
    ///   - ignoreCase: Compare lowercased forms (preserves display text).
    /// - Returns: A `DiffResult` with ordered `DiffLine` rows.
    static func diff(
        original: String,
        changed: String,
        ignoreWhitespace: Bool,
        ignoreCase: Bool
    ) -> DiffResult {
        // INFRA-17: guard very large inputs
        let sizeLimit = 10_000_000  // 10 MB
        guard original.utf8.count <= sizeLimit, changed.utf8.count <= sizeLimit else {
            return DiffResult(lines: [])
        }

        // Split into lines, preserving trailing newlines as empty lines
        let origLines = splitLines(original)
        let changedLines = splitLines(changed)

        // Build normalized forms for comparison only
        func normalize(_ line: String) -> String {
            var s = line
            if ignoreCase { s = s.lowercased() }
            if ignoreWhitespace {
                // Collapse all whitespace runs to a single space, then trim
                s = s.components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }
            return s
        }

        let origNorm = origLines.map(normalize)
        let changedNorm = changedLines.map(normalize)

        // CollectionDifference on normalized strings
        let collDiff = changedNorm.difference(from: origNorm)

        // Build a move table: map each (offset, element) pair from remove/insert at same norm
        // to detect modifications (paired remove+insert on same logical position)
        // We use the standard approach: replay the diff into a sequence of DiffLine values.

        // Reconstruct the final line list by applying the diff
        // Strategy: produce an interleaved list of .unchanged / .removed / .added lines
        // by walking CollectionDifference operations in order of their offset.

        let resultLines = buildLines(
            origLines: origLines, changedLines: changedLines,
            origNorm: origNorm, changedNorm: changedNorm,
            collDiff: collDiff
        )

        return DiffResult(lines: resultLines)
    }

    // MARK: - Internal helpers

    private static func splitLines(_ text: String) -> [String] {
        if text.isEmpty { return [] }
        var lines = text.components(separatedBy: "\n")
        // components(separatedBy:) produces a trailing empty element for texts ending in \n
        // Remove it to avoid phantom empty lines, but only if it's a true artifact
        if lines.last == "" && text.hasSuffix("\n") {
            lines.removeLast()
        }
        return lines
    }

    private static func buildLines(
        origLines: [String],
        changedLines: [String],
        origNorm: [String],
        changedNorm: [String],
        collDiff: CollectionDifference<String>
    ) -> [DiffLine] {
        // Build remove and insert maps keyed by offset in the target (changedNorm) or source (origNorm)
        // removals: offset in origNorm → original line index
        // insertions: offset in changedNorm → changed line index

        // Decompose CollectionDifference into ordered remove/insert operations
        var removals: [Int: Int] = [:]  // origNorm offset → origLines index
        var insertions: [Int: Int] = [:]  // changedNorm offset → changedLines index

        for change in collDiff {
            switch change {
            case .remove(let offset, _, _):
                removals[offset] = offset
            case .insert(let offset, _, _):
                insertions[offset] = offset
            }
        }

        // Produce a merged diff sequence by replaying the edit script.
        // We simulate applying removals to origLines and insertions to changedLines.
        //
        // The standard algorithm: walk both sides simultaneously.
        // For each position in origLines: if it was removed → .removed line.
        //                                 otherwise → advance changedLines position.
        //   At each position in changedLines: if it was inserted here → .added line first.
        //   Then the unchanged line from origLines.

        var lines: [DiffLine] = []
        var origIdx = 0
        var changedIdx = 0
        var origLineNum = 1
        var newLineNum = 1

        // Build sets for O(1) lookup
        let removedOrigOffsets = Set(removals.keys)
        let insertedChangedOffsets = Set(insertions.keys)

        // We need a sorted list of insertions that occur before each origIdx advance
        // Use the standard "replay" approach:

        while origIdx < origLines.count || changedIdx < changedLines.count {
            // First, emit all insertions that happen at the current changedIdx position
            // An insertion at changedOffset N means: "before the Nth unchanged element,
            // insert this". But since we interleave, let's use the standard approach below.

            // Check if origIdx is about to be removed
            let origRemoved = origIdx < origLines.count && removedOrigOffsets.contains(origIdx)
            let changedInserted = changedIdx < changedLines.count && insertedChangedOffsets.contains(changedIdx)

            if origRemoved && changedInserted {
                // Both: this is a modification — pair the remove and insert
                // Emit removed first, then added (with word-level segments for both)
                let origText = origLines[origIdx]
                let changedText = changedLines[changedIdx]
                let (removedSegs, addedSegs) = wordLevelSegments(original: origText, changed: changedText)

                lines.append(DiffLine(
                    kind: .removed, displayText: origText,
                    originalLineNumber: origLineNum, newLineNumber: nil,
                    wordSegments: removedSegs
                ))
                lines.append(DiffLine(
                    kind: .added, displayText: changedText,
                    originalLineNumber: nil, newLineNumber: newLineNum,
                    wordSegments: addedSegs
                ))
                origIdx += 1
                changedIdx += 1
                origLineNum += 1
                newLineNum += 1
            } else if origRemoved {
                // Pure deletion
                lines.append(DiffLine(
                    kind: .removed, displayText: origLines[origIdx],
                    originalLineNumber: origLineNum, newLineNumber: nil,
                    wordSegments: nil
                ))
                origIdx += 1
                origLineNum += 1
            } else if changedInserted {
                // Pure insertion
                lines.append(DiffLine(
                    kind: .added, displayText: changedLines[changedIdx],
                    originalLineNumber: nil, newLineNumber: newLineNum,
                    wordSegments: nil
                ))
                changedIdx += 1
                newLineNum += 1
            } else {
                // Unchanged — consume both sides
                if origIdx < origLines.count && changedIdx < changedLines.count {
                    lines.append(DiffLine(
                        kind: .unchanged, displayText: origLines[origIdx],
                        originalLineNumber: origLineNum, newLineNumber: newLineNum,
                        wordSegments: nil
                    ))
                    origIdx += 1
                    changedIdx += 1
                    origLineNum += 1
                    newLineNum += 1
                } else if origIdx < origLines.count {
                    // Trailing original lines (shouldn't happen with correct diff)
                    lines.append(DiffLine(
                        kind: .removed, displayText: origLines[origIdx],
                        originalLineNumber: origLineNum, newLineNumber: nil,
                        wordSegments: nil
                    ))
                    origIdx += 1
                    origLineNum += 1
                } else {
                    // Trailing changed lines
                    lines.append(DiffLine(
                        kind: .added, displayText: changedLines[changedIdx],
                        originalLineNumber: nil, newLineNumber: newLineNum,
                        wordSegments: nil
                    ))
                    changedIdx += 1
                    newLineNum += 1
                }
            }
        }

        return lines
    }

    /// Compute word-level segments for a paired remove+insert using vendored SwiftDiff.
    /// Returns (removedSegments, addedSegments) as parallel views of the edit.
    private static func wordLevelSegments(
        original: String, changed: String
    ) -> ([WordSegment], [WordSegment]) {
        // Call the module-level global function from vendored SwiftDiff (diff.swift)
        let diffs: [Diff] = Flint.diff(text1: original, text2: changed)

        var removedSegs = [WordSegment]()
        var addedSegs = [WordSegment]()

        for d in diffs {
            switch d {
            case .equal(let t):
                removedSegs.append(WordSegment(text: t, segmentKind: .equal))
                addedSegs.append(WordSegment(text: t, segmentKind: .equal))
            case .delete(let t):
                removedSegs.append(WordSegment(text: t, segmentKind: .deleted))
            case .insert(let t):
                addedSegs.append(WordSegment(text: t, segmentKind: .inserted))
            }
        }

        return (removedSegs, addedSegs)
    }
}
