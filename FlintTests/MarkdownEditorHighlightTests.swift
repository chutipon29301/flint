// FlintTests/MarkdownEditorHighlightTests.swift
// Unit tests for MarkdownEditorHighlight — pure span function for MD-02 editor syntax highlighting.
// TDD: Tests written BEFORE implementation (RED phase).
// Covers: heading markers, bold, italic, inline code, link syntax,
//         empty + huge input (no-crash guarantee, INFRA-17 parity).

import XCTest
import AppKit
@testable import Flint

final class MarkdownEditorHighlightTests: XCTestCase {

    // MARK: - Heading marker (#, ##, etc.)

    func testHeadingH1_markerSpanExists() {
        // "# Hello" — the "# " prefix should produce at least one span
        let text = "# Hello"
        let spans = MarkdownEditorHighlight.spans(in: text)
        XCTAssertFalse(spans.isEmpty,
                       "# heading should produce at least one span, got: \(spans)")
        // The first span must start at position 0 and cover the marker "# "
        let firstRange = spans[0].range
        XCTAssertEqual(firstRange.location, 0,
                       "Heading marker span must start at index 0, got location=\(firstRange.location)")
        XCTAssertGreaterThanOrEqual(firstRange.length, 1,
                       "Heading marker span must cover at least '#', got length=\(firstRange.length)")
    }

    func testHeadingH3_markerCoveredCorrectly() {
        // "### Title" — marker is "### " (4 chars)
        let text = "### Title"
        let spans = MarkdownEditorHighlight.spans(in: text)
        XCTAssertFalse(spans.isEmpty, "### heading should produce a span")
        // Find a span at location 0
        let headingSpan = spans.first { $0.range.location == 0 }
        XCTAssertNotNil(headingSpan, "A span starting at 0 should exist for the heading marker")
        // Span should cover at least "### " (4 chars)
        if let hs = headingSpan {
            XCTAssertGreaterThanOrEqual(hs.range.length, 3,
                           "### marker span should cover at least 3 '#' chars, got \(hs.range.length)")
        }
    }

    func testHeadingH6_accepted() {
        let text = "###### Deep"
        let spans = MarkdownEditorHighlight.spans(in: text)
        XCTAssertFalse(spans.isEmpty, "###### heading (h6) should produce a span")
    }

    func testSevenHashes_notAHeading() {
        // 7 # signs is NOT a valid ATX heading (only 1-6 allowed)
        let text = "####### NotHeading"
        let spans = MarkdownEditorHighlight.spans(in: text)
        // Should NOT produce a heading span at location 0
        let headingSpan = spans.first { $0.range.location == 0 && $0.range.length >= 7 }
        XCTAssertNil(headingSpan,
                     "7 hashes should not produce a heading marker span, got: \(spans)")
    }

    // MARK: - Bold (** and __)

    func testBold_asterisk_spansExist() {
        // "a **b** c" — the **b** range should be highlighted
        let text = "a **b** c"
        let spans = MarkdownEditorHighlight.spans(in: text)
        XCTAssertFalse(spans.isEmpty, "**bold** should produce at least one span, got: \(spans)")
        // Verify a span covers somewhere in the bold marker region (positions 2-6)
        let boldSpan = spans.first { $0.range.location >= 2 && $0.range.location <= 6 }
        XCTAssertNotNil(boldSpan,
                        "A span should exist around the **b** bold region, got: \(spans)")
    }

    func testBold_underscore_spansExist() {
        let text = "a __b__ c"
        let spans = MarkdownEditorHighlight.spans(in: text)
        XCTAssertFalse(spans.isEmpty, "__bold__ should produce at least one span, got: \(spans)")
    }

    // MARK: - Italic (* and _)

    func testItalic_asterisk_spansExist() {
        // "a *b* c" — the *b* range should be highlighted
        let text = "a *b* c"
        let spans = MarkdownEditorHighlight.spans(in: text)
        XCTAssertFalse(spans.isEmpty, "*italic* should produce at least one span, got: \(spans)")
    }

    func testItalic_underscore_spansExist() {
        let text = "a _b_ c"
        let spans = MarkdownEditorHighlight.spans(in: text)
        XCTAssertFalse(spans.isEmpty, "_italic_ should produce at least one span, got: \(spans)")
    }

    // MARK: - Inline code (` ` `)

    func testInlineCode_spansExist() {
        // "`code`" — the full backtick-wrapped range should produce a span
        let text = "`code`"
        let spans = MarkdownEditorHighlight.spans(in: text)
        XCTAssertFalse(spans.isEmpty, "`code` should produce at least one span, got: \(spans)")
        // The span should start at 0 and cover "`code`" (6 chars)
        let codeSpan = spans.first { $0.range.location == 0 }
        XCTAssertNotNil(codeSpan, "A span starting at 0 should exist for inline code")
        if let cs = codeSpan {
            XCTAssertGreaterThanOrEqual(cs.range.length, 6,
                           "Inline code span should cover at least the 6 chars of `code`, got length=\(cs.range.length)")
        }
    }

    func testInlineCode_inSentence() {
        // "Use `fmt.Println` for output" — span in the middle
        let text = "Use `fmt.Println` for output"
        let spans = MarkdownEditorHighlight.spans(in: text)
        XCTAssertFalse(spans.isEmpty, "Inline code in sentence should produce a span, got: \(spans)")
        // There should be a span covering the backtick region starting at index 4
        let codeSpan = spans.first { $0.range.location == 4 }
        XCTAssertNotNil(codeSpan,
                        "A span at position 4 (opening backtick) should exist, got: \(spans)")
    }

    // MARK: - Link syntax ([text](url))

    func testLink_spansExist() {
        // "[Go](https://go.dev)" — the brackets/parens/url should produce spans
        let text = "[Go](https://go.dev)"
        let spans = MarkdownEditorHighlight.spans(in: text)
        XCTAssertFalse(spans.isEmpty, "Link syntax should produce at least one span, got: \(spans)")
    }

    func testLink_bracketSpanAtStart() {
        // "[Go](https://go.dev)" — first char '[' should be in a span
        let text = "[Go](https://go.dev)"
        let spans = MarkdownEditorHighlight.spans(in: text)
        let bracketSpan = spans.first { $0.range.location == 0 }
        XCTAssertNotNil(bracketSpan,
                        "A span at position 0 ('[') should exist for link syntax, got: \(spans)")
    }

    // MARK: - Mixed content (multiple constructs)

    func testMixedContent_multipleSpans() {
        let text = "# Title\n\nHello **world** and `code` here."
        let spans = MarkdownEditorHighlight.spans(in: text)
        // Should have spans for heading, bold, and inline code
        XCTAssertGreaterThanOrEqual(spans.count, 3,
            "Mixed content should produce spans for heading + bold + code, got \(spans.count) spans: \(spans)")
    }

    // MARK: - NSRange validity

    func testAllRangesAreValid() {
        let text = "# Heading\n**bold** _italic_ `code` [link](url)"
        let nsText = text as NSString
        let spans = MarkdownEditorHighlight.spans(in: text)
        for (i, span) in spans.enumerated() {
            XCTAssertGreaterThanOrEqual(span.range.location, 0,
                "Span \(i) location must be >= 0, got \(span.range.location)")
            XCTAssertGreaterThan(span.range.length, 0,
                "Span \(i) must have length > 0, got length=\(span.range.length)")
            let end = span.range.location + span.range.length
            XCTAssertLessThanOrEqual(end, nsText.length,
                "Span \(i) end (\(end)) must not exceed string length (\(nsText.length))")
        }
    }

    // MARK: - No-crash guarantees (INFRA-17 parity)

    func testEmpty_doesNotCrash() {
        // Must return without crashing and produce an empty or small result
        let spans = MarkdownEditorHighlight.spans(in: "")
        XCTAssertEqual(spans.count, 0, "Empty input should produce no spans, got: \(spans)")
    }

    func testSingleChar_doesNotCrash() {
        let spans = MarkdownEditorHighlight.spans(in: "#")
        // May or may not produce a span — must not crash
        XCTAssertTrue(spans.count >= 0)
    }

    func testUnbalancedBold_doesNotCrash() {
        // Unmatched ** — must not crash; returns whatever complete spans it found
        let spans = MarkdownEditorHighlight.spans(in: "**unmatched")
        XCTAssertNotNil(spans, "Must return a value (not crash) for unbalanced markers")
    }

    func testUnbalancedBacktick_doesNotCrash() {
        let spans = MarkdownEditorHighlight.spans(in: "`unclosed code")
        XCTAssertNotNil(spans, "Must return a value (not crash) for unclosed backtick")
    }

    func testLargeInput_hashRepeated_doesNotCrash() {
        // 1 MB of '#' characters — must complete without crash and return bounded output
        let huge = String(repeating: "#", count: 1_000_000)
        let spans = MarkdownEditorHighlight.spans(in: huge)
        // Output must be bounded (not one span per character)
        XCTAssertLessThan(spans.count, 100_000,
            "Should not produce unbounded spans for 1 MB input, got \(spans.count)")
    }

    func testLargeInput_asteriskRepeated_doesNotCrash() {
        // 1 MB of '*' characters — must complete without crash
        let huge = String(repeating: "*", count: 1_000_000)
        let spans = MarkdownEditorHighlight.spans(in: huge)
        XCTAssertLessThan(spans.count, 100_000,
            "Should not produce unbounded spans for 1 MB asterisk input, got \(spans.count)")
    }

    func testGarbageInput_doesNotCrash() {
        // Garbage with special chars — must not crash
        let garbage = String(repeating: "!@#$%^&*()", count: 1000)
        let spans = MarkdownEditorHighlight.spans(in: garbage)
        XCTAssertNotNil(spans, "Must return without crashing on garbage input")
    }

    // MARK: - NSColor non-nil for all spans

    func testAllSpansHaveNonNilColor() {
        let text = "# Heading\n**bold** _italic_ `code` [link](https://example.com)"
        let spans = MarkdownEditorHighlight.spans(in: text)
        for (i, span) in spans.enumerated() {
            // NSColor is always non-nil (value type wrapper); just verify span is well-formed
            XCTAssertGreaterThan(span.range.length, 0,
                "Span \(i) must have non-zero length")
            // Verify color is a real NSColor (not a null/sentinel)
            let cgColor = span.color.cgColor
            XCTAssertNotNil(cgColor, "Span \(i) color must have a valid CGColor")
        }
    }
}
