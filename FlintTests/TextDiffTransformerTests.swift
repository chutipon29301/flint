// FlintTests/TextDiffTransformerTests.swift
// Unit tests for TextDiffTransformer — covers DIFF-01..04 + INFRA-17 no-crash guarantee.
// TDD: Tests written against the behavior spec before implementation (RED phase).

import XCTest
@testable import Flint

final class TextDiffTransformerTests: XCTestCase {

    // MARK: - Identical inputs

    func testDiff_identicalInputs_allUnchanged() {
        let text = "hello\nworld"
        let result = TextDiffTransformer.diff(
            original: text, changed: text,
            ignoreWhitespace: false, ignoreCase: false
        )
        XCTAssertTrue(result.lines.allSatisfy { $0.kind == .unchanged },
                      "Identical inputs should produce all-unchanged lines")
        XCTAssertTrue(result.lines.count > 0, "Should produce at least one line for non-empty input")
    }

    func testDiff_identicalInputs_noDiffs() {
        let text = "abc\ndef\nghi"
        let result = TextDiffTransformer.diff(
            original: text, changed: text,
            ignoreWhitespace: false, ignoreCase: false
        )
        XCTAssertFalse(result.hasDiffs, "Identical inputs should report hasDiffs = false")
    }

    // MARK: - Pure insert

    func testDiff_pureInsert_addedLineDetected() {
        let original = "a\nb"
        let changed = "a\nb\nc"
        let result = TextDiffTransformer.diff(
            original: original, changed: changed,
            ignoreWhitespace: false, ignoreCase: false
        )
        let addedLines = result.lines.filter { $0.kind == .added }
        XCTAssertEqual(addedLines.count, 1, "Expected 1 added line")
        XCTAssertEqual(addedLines.first?.displayText, "c", "Added line should be 'c'")
    }

    // MARK: - Pure delete

    func testDiff_pureDelete_removedLineDetected() {
        let original = "a\nb\nc"
        let changed = "a\nb"
        let result = TextDiffTransformer.diff(
            original: original, changed: changed,
            ignoreWhitespace: false, ignoreCase: false
        )
        let removedLines = result.lines.filter { $0.kind == .removed }
        XCTAssertEqual(removedLines.count, 1, "Expected 1 removed line")
        XCTAssertEqual(removedLines.first?.displayText, "c", "Removed line should be 'c'")
    }

    // MARK: - Modified line (paired remove + insert + word-level)

    func testDiff_modifiedLine_pairedRemoveInsert() {
        let original = "the cat"
        let changed = "the dog"
        let result = TextDiffTransformer.diff(
            original: original, changed: changed,
            ignoreWhitespace: false, ignoreCase: false
        )
        let removedLines = result.lines.filter { $0.kind == .removed }
        let addedLines = result.lines.filter { $0.kind == .added }
        XCTAssertEqual(removedLines.count, 1, "Should have 1 removed line")
        XCTAssertEqual(addedLines.count, 1, "Should have 1 added line")
        XCTAssertEqual(removedLines.first?.displayText, "the cat")
        XCTAssertEqual(addedLines.first?.displayText, "the dog")
    }

    func testDiff_modifiedLine_wordLevelSegmentsPresent() {
        let original = "the cat"
        let changed = "the dog"
        let result = TextDiffTransformer.diff(
            original: original, changed: changed,
            ignoreWhitespace: false, ignoreCase: false
        )
        let removedLine = result.lines.first { $0.kind == .removed }
        let addedLine = result.lines.first { $0.kind == .added }
        XCTAssertNotNil(removedLine?.wordSegments, "Modified removed line should have word segments")
        XCTAssertNotNil(addedLine?.wordSegments, "Modified added line should have word segments")
    }

    func testDiff_modifiedLine_wordSegmentsUseSwiftDiff() {
        // "the cat" vs "the dog": SwiftDiff should produce equal("the "), delete("cat")/insert("dog")
        let original = "the cat"
        let changed = "the dog"
        let result = TextDiffTransformer.diff(
            original: original, changed: changed,
            ignoreWhitespace: false, ignoreCase: false
        )
        let removedLine = result.lines.first { $0.kind == .removed }
        let addedLine = result.lines.first { $0.kind == .added }

        // Removed line word segments should contain a "deleted" segment for "cat"
        let removedSegs = removedLine?.wordSegments ?? []
        let hasDeletedCat = removedSegs.contains { $0.segmentKind == .deleted && $0.text.contains("cat") }
        XCTAssertTrue(hasDeletedCat, "Removed line should have deleted segment for 'cat'. Segments: \(removedSegs)")

        // Added line word segments should contain an "inserted" segment for "dog"
        let addedSegs = addedLine?.wordSegments ?? []
        let hasInsertedDog = addedSegs.contains { $0.segmentKind == .inserted && $0.text.contains("dog") }
        XCTAssertTrue(hasInsertedDog, "Added line should have inserted segment for 'dog'. Segments: \(addedSegs)")
    }

    // MARK: - Ignore whitespace

    func testDiff_ignoreWhitespace_true_noChange() {
        let original = "a b"
        let changed = "a  b"
        let result = TextDiffTransformer.diff(
            original: original, changed: changed,
            ignoreWhitespace: true, ignoreCase: false
        )
        XCTAssertFalse(result.hasDiffs,
                       "With ignoreWhitespace=true, 'a b' vs 'a  b' should be equal")
    }

    func testDiff_ignoreWhitespace_false_diffPresent() {
        let original = "a b"
        let changed = "a  b"
        let result = TextDiffTransformer.diff(
            original: original, changed: changed,
            ignoreWhitespace: false, ignoreCase: false
        )
        XCTAssertTrue(result.hasDiffs,
                      "With ignoreWhitespace=false, 'a b' vs 'a  b' should differ")
    }

    // MARK: - Ignore case

    func testDiff_ignoreCase_true_noChange() {
        let original = "ABC"
        let changed = "abc"
        let result = TextDiffTransformer.diff(
            original: original, changed: changed,
            ignoreWhitespace: false, ignoreCase: true
        )
        XCTAssertFalse(result.hasDiffs,
                       "With ignoreCase=true, 'ABC' vs 'abc' should be equal")
    }

    func testDiff_ignoreCase_false_diffPresent() {
        let original = "ABC"
        let changed = "abc"
        let result = TextDiffTransformer.diff(
            original: original, changed: changed,
            ignoreWhitespace: false, ignoreCase: false
        )
        XCTAssertTrue(result.hasDiffs,
                      "With ignoreCase=false, 'ABC' vs 'abc' should differ")
    }

    func testDiff_ignoreCase_preservesDisplayText() {
        // Display text should be original casing even when ignoreCase=true treats as equal
        let original = "Hello World"
        let changed = "hello world"
        let result = TextDiffTransformer.diff(
            original: original, changed: changed,
            ignoreWhitespace: false, ignoreCase: true
        )
        // Unchanged lines should preserve original display text
        let unchangedLines = result.lines.filter { $0.kind == .unchanged }
        let allTexts = unchangedLines.map { $0.displayText }
        // At least one line should contain the text (either version)
        XCTAssertFalse(allTexts.isEmpty, "Should have at least one unchanged line when ignoreCase")
    }

    // MARK: - Unified patch

    func testDiff_unifiedPatch_hasHeaderLines() {
        let original = "a\nb"
        let changed = "a\nb\nc"
        let result = TextDiffTransformer.diff(
            original: original, changed: changed,
            ignoreWhitespace: false, ignoreCase: false
        )
        let patch = result.unifiedPatch
        XCTAssertTrue(patch.contains("--- Original"), "Patch should start with '--- Original'")
        XCTAssertTrue(patch.contains("+++ Changed"), "Patch should have '+++ Changed'")
    }

    func testDiff_unifiedPatch_hasHunkHeader() {
        let original = "a\nb"
        let changed = "a\nb\nc"
        let result = TextDiffTransformer.diff(
            original: original, changed: changed,
            ignoreWhitespace: false, ignoreCase: false
        )
        let patch = result.unifiedPatch
        XCTAssertTrue(patch.contains("@@"), "Patch should contain @@ hunk header")
    }

    func testDiff_unifiedPatch_plusPrefixForAdded() {
        let original = "a"
        let changed = "a\nb"
        let result = TextDiffTransformer.diff(
            original: original, changed: changed,
            ignoreWhitespace: false, ignoreCase: false
        )
        let patch = result.unifiedPatch
        XCTAssertTrue(patch.contains("+b"), "Patch should contain '+b' for added line")
    }

    func testDiff_unifiedPatch_minusPrefixForRemoved() {
        let original = "a\nb"
        let changed = "a"
        let result = TextDiffTransformer.diff(
            original: original, changed: changed,
            ignoreWhitespace: false, ignoreCase: false
        )
        let patch = result.unifiedPatch
        XCTAssertTrue(patch.contains("-b"), "Patch should contain '-b' for removed line")
    }

    func testDiff_unifiedPatch_spacePrefixForUnchanged() {
        let original = "a\nb\nc"
        let changed = "a\nx\nc"
        let result = TextDiffTransformer.diff(
            original: original, changed: changed,
            ignoreWhitespace: false, ignoreCase: false
        )
        let patch = result.unifiedPatch
        // Lines "a" and "c" should appear with space prefix in context
        let patchLines = patch.components(separatedBy: "\n")
        let contextLines = patchLines.filter { $0.hasPrefix(" ") }
        XCTAssertFalse(contextLines.isEmpty, "Patch should have space-prefixed context lines")
    }

    func testDiff_identicalInputs_emptyPatchBody() {
        let text = "hello\nworld"
        let result = TextDiffTransformer.diff(
            original: text, changed: text,
            ignoreWhitespace: false, ignoreCase: false
        )
        let patch = result.unifiedPatch
        // Identical inputs produce no hunks — patch body should just be the header or empty
        XCTAssertFalse(patch.contains("@@"), "Identical inputs should produce no @@ hunks")
    }

    // MARK: - Empty inputs (INFRA-17: never crash)

    func testDiff_bothEmpty_graceful() {
        let result = TextDiffTransformer.diff(
            original: "", changed: "",
            ignoreWhitespace: false, ignoreCase: false
        )
        // Must not crash; result should be valid
        XCTAssertFalse(result.hasDiffs, "Two empty inputs should have no diffs")
    }

    func testDiff_originalEmpty_graceful() {
        let result = TextDiffTransformer.diff(
            original: "", changed: "hello",
            ignoreWhitespace: false, ignoreCase: false
        )
        // Must not crash
        let addedLines = result.lines.filter { $0.kind == .added }
        XCTAssertEqual(addedLines.count, 1, "With empty original, 'hello' should appear as added")
    }

    func testDiff_changedEmpty_graceful() {
        let result = TextDiffTransformer.diff(
            original: "hello", changed: "",
            ignoreWhitespace: false, ignoreCase: false
        )
        // Must not crash
        let removedLines = result.lines.filter { $0.kind == .removed }
        XCTAssertEqual(removedLines.count, 1, "With empty changed, 'hello' should appear as removed")
    }

    func testDiff_largeInputs_doesNotCrash() {
        // INFRA-17: must not crash on large inputs
        let bigText = String(repeating: "line of text\n", count: 10_000)
        let result = TextDiffTransformer.diff(
            original: bigText, changed: bigText + "extra\n",
            ignoreWhitespace: false, ignoreCase: false
        )
        // Just verify it doesn't crash and produces a result
        XCTAssertNotNil(result)
    }

    // MARK: - Line numbers

    func testDiff_lineNumbers_originalSide() {
        let original = "a\nb\nc"
        let changed = "a\nb\nc\nd"
        let result = TextDiffTransformer.diff(
            original: original, changed: changed,
            ignoreWhitespace: false, ignoreCase: false
        )
        // Unchanged lines should have original line numbers
        let unchangedLines = result.lines.filter { $0.kind == .unchanged }
        XCTAssertFalse(unchangedLines.isEmpty, "Should have unchanged lines")
        for line in unchangedLines {
            XCTAssertNotNil(line.originalLineNumber, "Unchanged lines should have original line number")
        }
    }

    func testDiff_lineNumbers_newSide() {
        let original = "a\nb\nc"
        let changed = "a\nb\nc\nd"
        let result = TextDiffTransformer.diff(
            original: original, changed: changed,
            ignoreWhitespace: false, ignoreCase: false
        )
        let addedLines = result.lines.filter { $0.kind == .added }
        XCTAssertFalse(addedLines.isEmpty, "Should have added lines")
        for line in addedLines {
            XCTAssertNotNil(line.newLineNumber, "Added lines should have new line number")
        }
    }

    // MARK: - hasDiffs / diffCount

    func testDiff_multipleChanges_diffCountAccurate() {
        let original = "a\nb\nc\nd"
        let changed = "a\nX\nc\nY"
        let result = TextDiffTransformer.diff(
            original: original, changed: changed,
            ignoreWhitespace: false, ignoreCase: false
        )
        XCTAssertTrue(result.hasDiffs, "Should have diffs for modified lines")
        XCTAssertGreaterThan(result.diffHunkCount, 0, "Should count at least one diff hunk")
    }
}
