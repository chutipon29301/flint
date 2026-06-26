// FlintTests/RegexTransformerTests.swift
// Unit tests for RegexTransformer — covers RGX-01..04 + INFRA-17 no-crash guarantee.
// TDD: Tests written against the behavior spec before implementation.

import XCTest
@testable import Flint

final class RegexTransformerTests: XCTestCase {

    // MARK: - RGX-01: Numbered capture groups

    func testMatches_numberedGroups_returnsGroupStrings() throws {
        // pattern (\d+)-(\d+) on "12-34" → one match, groups "12" and "34"
        let result = RegexTransformer.matches(pattern: #"(\d+)-(\d+)"#, flags: [], in: "12-34")
        guard case .success(let matches) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(matches.count, 1, "Expected 1 match")
        let m = matches[0]
        XCTAssertEqual(m.numberedGroups.count, 2, "Expected 2 numbered capture groups")
        XCTAssertEqual(m.numberedGroups[0], "12", "Group 1 should be '12'")
        XCTAssertEqual(m.numberedGroups[1], "34", "Group 2 should be '34'")
    }

    // MARK: - RGX-01: Named capture groups

    func testMatches_namedGroup_exposesGroupByName() throws {
        // pattern (?<year>\d{4}) on "2026" → group "year" = "2026"
        let result = RegexTransformer.matches(pattern: #"(?<year>\d{4})"#, flags: [], in: "2026")
        guard case .success(let matches) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(matches.count, 1, "Expected 1 match")
        let m = matches[0]
        XCTAssertEqual(m.namedGroups["year"], "2026", "Named group 'year' should be '2026'")
    }

    // MARK: - RGX-01: Flag i (case insensitive)

    func testMatches_flagI_matchesCaseInsensitive() throws {
        // pattern `abc` with caseInsensitive should match "ABC"
        let result = RegexTransformer.matches(pattern: "abc", flags: [.i], in: "ABC")
        guard case .success(let matches) = result else {
            XCTFail("Expected success with flag i, got \(result)")
            return
        }
        XCTAssertEqual(matches.count, 1, "Flag i should match 'abc' against 'ABC'")
        XCTAssertEqual(matches[0].matchedString, "ABC")
    }

    // MARK: - RGX-01: Flag m (multiline)

    func testMatches_flagM_anchoredPerLine() throws {
        // ^ anchor with multiline should match beginning of each line;
        // use .g to enumerate all matches across lines
        let result = RegexTransformer.matches(pattern: "^line", flags: [.m, .g], in: "line1\nline2\nnope")
        guard case .success(let matches) = result else {
            XCTFail("Expected success with flag m, got \(result)")
            return
        }
        XCTAssertEqual(matches.count, 2, "Flags m+g should match '^line' at start of each line")
    }

    // MARK: - RGX-01: Flag s (dot matches newline)

    func testMatches_flagS_dotMatchesNewline() throws {
        // . should match newline when s flag set
        let result = RegexTransformer.matches(pattern: "a.b", flags: [.s], in: "a\nb")
        guard case .success(let matches) = result else {
            XCTFail("Expected success with flag s, got \(result)")
            return
        }
        XCTAssertEqual(matches.count, 1, "Flag s: dot should match newline")
    }

    func testMatches_noFlagS_dotDoesNotMatchNewline() throws {
        // Without s flag, . should NOT match newline
        let result = RegexTransformer.matches(pattern: "a.b", flags: [], in: "a\nb")
        guard case .success(let matches) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(matches.count, 0, "Without flag s, dot should not match newline")
    }

    // MARK: - RGX-01: Flag x (verbose / comments)

    func testMatches_flagX_ignoresWhitespaceAndComments() throws {
        // verbose pattern with spaces and comment
        let pattern = #"(\d+)  # captures digits"#
        let result = RegexTransformer.matches(pattern: pattern, flags: [.x], in: "123 abc")
        guard case .success(let matches) = result else {
            XCTFail("Expected success with flag x, got \(result)")
            return
        }
        XCTAssertGreaterThan(matches.count, 0, "Flag x should allow comments and extra whitespace in pattern")
    }

    // MARK: - RGX-01: Flag g (global — enumerate all vs first only)

    func testMatches_withFlagG_returnsAllMatches() throws {
        // global flag: all matches
        let result = RegexTransformer.matches(pattern: #"\d+"#, flags: [.g], in: "1 22 333")
        guard case .success(let matches) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(matches.count, 3, "Flag g should enumerate all matches")
    }

    func testMatches_withoutFlagG_returnsFirstMatchOnly() throws {
        // no global flag: only first match
        let result = RegexTransformer.matches(pattern: #"\d+"#, flags: [], in: "1 22 333")
        guard case .success(let matches) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(matches.count, 1, "Without flag g, should return only the first match")
        XCTAssertEqual(matches[0].matchedString, "1")
    }

    // MARK: - RGX-03: Match index and position

    func testMatches_exposesIndexAndPosition() throws {
        let result = RegexTransformer.matches(pattern: #"\d+"#, flags: [.g], in: "abc 123 xyz 456")
        guard case .success(let matches) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(matches.count, 2)
        XCTAssertEqual(matches[0].index, 0, "First match should have index 0")
        XCTAssertEqual(matches[0].position, 4, "First match '123' starts at char offset 4")
        XCTAssertEqual(matches[1].index, 1, "Second match should have index 1")
        XCTAssertEqual(matches[1].position, 12, "Second match '456' starts at char offset 12")
    }

    // MARK: - RGX-04: Substitute

    func testSubstitute_basic_replacesMatch() throws {
        // pattern (\w+) template $1! on "hi" → "hi!"
        let result = RegexTransformer.substitute(pattern: #"(\w+)"#, flags: [], in: "hi", template: "$1!")
        guard case .success(let output) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(output, "hi!")
    }

    func testSubstitute_globalFlag_replacesAllMatches() throws {
        let result = RegexTransformer.substitute(pattern: #"\d+"#, flags: [.g], in: "a1b2c3", template: "#")
        guard case .success(let output) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(output, "a#b#c#")
    }

    // MARK: - INFRA-17: Invalid pattern returns .failure (no crash)

    func testMatches_invalidPattern_returnsFailure() {
        // Unmatched ( is an invalid regex pattern
        let result = RegexTransformer.matches(pattern: "(", flags: [], in: "some text")
        guard case .failure = result else {
            XCTFail("Expected failure for invalid pattern '(', got \(result)")
            return
        }
        // Reaching here without crashing satisfies INFRA-17
    }

    func testSubstitute_invalidPattern_returnsFailure() {
        let result = RegexTransformer.substitute(pattern: "(", flags: [], in: "text", template: "$1")
        guard case .failure = result else {
            XCTFail("Expected failure for invalid pattern in substitute, got \(result)")
            return
        }
    }

    // MARK: - INFRA-17: Empty input returns success with zero matches (no crash)

    func testMatches_emptyInput_returnsSuccessWithZeroMatches() {
        let result = RegexTransformer.matches(pattern: #"\d+"#, flags: [], in: "")
        guard case .success(let matches) = result else {
            XCTFail("Expected success for empty input, got \(result)")
            return
        }
        XCTAssertEqual(matches.count, 0, "Empty input should yield zero matches, not crash")
    }

    func testSubstitute_emptyInput_returnsSuccessWithEmptyString() {
        let result = RegexTransformer.substitute(pattern: #"\d+"#, flags: [], in: "", template: "#")
        guard case .success(let output) = result else {
            XCTFail("Expected success for empty input in substitute, got \(result)")
            return
        }
        XCTAssertEqual(output, "", "Empty input substitute should yield empty string")
    }

    // MARK: - INFRA-17: Empty pattern

    func testMatches_emptyPattern_returnsFailureOrEmptyMatches() {
        // Empty regex is technically valid but may match every character —
        // we only require it does not crash
        let result = RegexTransformer.matches(pattern: "", flags: [], in: "hello")
        // Success or failure is acceptable; crash is not
        switch result {
        case .success: break  // No crash — acceptable
        case .failure: break  // Also acceptable
        }
    }

    // MARK: - INFRA-17: Garbage (non-regex) pattern does not crash

    func testMatches_garbagePattern_doesNotCrash() {
        let garbage = String(repeating: ")(][", count: 100)
        let result = RegexTransformer.matches(pattern: garbage, flags: [], in: "hello world")
        // Must not crash — either failure or success is OK
        switch result {
        case .success: break
        case .failure: break
        }
    }

    // MARK: - Input size guard (INFRA-17)

    func testMatches_oversizedInput_returnsFailure() {
        // 51MB input — should trigger size guard
        let oversized = String(repeating: "a", count: 51_000_000)
        let result = RegexTransformer.matches(pattern: "a", flags: [], in: oversized)
        guard case .failure = result else {
            XCTFail("Expected failure for oversized input (>50 MB), got success")
            return
        }
    }

    // MARK: - Match full range

    func testMatches_fullMatchRange_isCorrect() throws {
        let text = "hello world"
        let result = RegexTransformer.matches(pattern: "world", flags: [], in: text)
        guard case .success(let matches) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].matchedString, "world")
        // Full match range in NSRange should start at offset 6
        XCTAssertEqual(matches[0].range.location, 6)
        XCTAssertEqual(matches[0].range.length, 5)
    }

    // MARK: - Multiple named groups

    func testMatches_multipleNamedGroups() throws {
        let result = RegexTransformer.matches(
            pattern: #"(?<first>\w+)\s+(?<second>\w+)"#,
            flags: [],
            in: "hello world"
        )
        guard case .success(let matches) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].namedGroups["first"], "hello")
        XCTAssertEqual(matches[0].namedGroups["second"], "world")
    }
}
