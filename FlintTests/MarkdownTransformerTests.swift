// FlintTests/MarkdownTransformerTests.swift
// Unit tests for MarkdownTransformer — covers MD-01..04 + INFRA-17 no-crash guarantee.
// TDD: Tests written against the behavior spec BEFORE implementation (RED phase).
// Covers: headings, GFM tables, task lists, strikethrough, fenced code, XSS escaping,
//         word count, reading time, empty/huge input.

import XCTest
@testable import Flint

final class MarkdownTransformerTests: XCTestCase {

    // MARK: - MD-01: Heading renders to <h1>

    func testHeading_h1() throws {
        let result = MarkdownTransformer.renderHTML("# Hi")
        guard case .success(let html) = result else {
            XCTFail("Expected success, got \(result)"); return
        }
        XCTAssertTrue(html.contains("<h1>") && html.contains("Hi"),
                      "# Hi should produce <h1>Hi</h1>, got: \(html)")
    }

    func testHeading_h2() throws {
        let result = MarkdownTransformer.renderHTML("## Section")
        guard case .success(let html) = result else {
            XCTFail("Expected success, got \(result)"); return
        }
        XCTAssertTrue(html.contains("<h2>"), "## Section should produce <h2>, got: \(html)")
    }

    // MARK: - MD-01: GFM table renders <table> with <th> and <td>

    func testTable_basicStructure() throws {
        let md = "| a | b |\n|---|---|\n| 1 | 2 |"
        let result = MarkdownTransformer.renderHTML(md)
        guard case .success(let html) = result else {
            XCTFail("Expected success, got \(result)"); return
        }
        XCTAssertTrue(html.contains("<table"), "Table markdown should produce <table>, got: \(html)")
        XCTAssertTrue(html.contains("<th"), "Table header should produce <th>, got: \(html)")
        XCTAssertTrue(html.contains("<td"), "Table cells should produce <td>, got: \(html)")
        XCTAssertTrue(html.contains("a") && html.contains("b"), "Table headers a and b should appear")
        XCTAssertTrue(html.contains("1") && html.contains("2"), "Table cells 1 and 2 should appear")
    }

    // MARK: - MD-01: Task list renders checkboxes

    func testTaskList_checkedItem() throws {
        let md = "- [x] done\n- [ ] todo"
        let result = MarkdownTransformer.renderHTML(md)
        guard case .success(let html) = result else {
            XCTFail("Expected success, got \(result)"); return
        }
        XCTAssertTrue(html.contains("checkbox"), "Task list should produce checkbox inputs, got: \(html)")
        XCTAssertTrue(html.contains("checked"), "Checked item should have checked attribute, got: \(html)")
    }

    func testTaskList_uncheckedItem() throws {
        let md = "- [ ] todo"
        let result = MarkdownTransformer.renderHTML(md)
        guard case .success(let html) = result else {
            XCTFail("Expected success, got \(result)"); return
        }
        XCTAssertTrue(html.contains("checkbox"), "Task list item should produce checkbox, got: \(html)")
        // Should NOT have checked on the unchecked item
        XCTAssertFalse(html.contains("checked=\"checked\"") || html.contains(" checked>"),
                       "Unchecked item should not have checked attribute, got: \(html)")
    }

    // MARK: - MD-01: Strikethrough renders <del>

    func testStrikethrough() throws {
        let result = MarkdownTransformer.renderHTML("~~x~~")
        guard case .success(let html) = result else {
            XCTFail("Expected success, got \(result)"); return
        }
        XCTAssertTrue(html.contains("<del>") || html.contains("<s>"),
                      "~~x~~ should produce <del>x</del> or <s>x</s>, got: \(html)")
        XCTAssertTrue(html.contains("x"), "Text content 'x' should appear")
    }

    // MARK: - MD-01: Fenced code renders <pre><code>

    func testFencedCode_swiftBlock() throws {
        let md = "```swift\nlet x = 1\n```"
        let result = MarkdownTransformer.renderHTML(md)
        guard case .success(let html) = result else {
            XCTFail("Expected success, got \(result)"); return
        }
        XCTAssertTrue(html.contains("<pre>") || html.contains("<pre "),
                      "Fenced code should produce <pre>, got: \(html)")
        XCTAssertTrue(html.contains("<code") || html.contains("<code>"),
                      "Fenced code should produce <code>, got: \(html)")
        XCTAssertTrue(html.contains("let x = 1"), "Code content should appear, got: \(html)")
    }

    // MARK: - MD-01: XSS escaping — text node <script> must be escaped, NOT raw

    func testXSSEscaping_scriptTag() throws {
        let malicious = "<script>alert(1)</script>"
        let result = MarkdownTransformer.renderHTML(malicious)
        guard case .success(let html) = result else {
            XCTFail("Expected success, got \(result)"); return
        }
        // Must NOT contain raw <script> tag
        XCTAssertFalse(html.contains("<script>"),
                       "Raw <script> must be HTML-escaped, got: \(html)")
        // Must contain the escaped form
        XCTAssertTrue(html.contains("&lt;script&gt;") || html.contains("&lt;script"),
                      "Script tag should appear as escaped HTML entities, got: \(html)")
    }

    func testXSSEscaping_htmlInText() throws {
        let result = MarkdownTransformer.renderHTML("<b>bold attempt</b>")
        guard case .success(let html) = result else {
            XCTFail("Expected success, got \(result)"); return
        }
        // The raw HTML tag should be escaped — we should NOT see raw <b> passed through
        // (swift-markdown itself may handle this; the test verifies end result is safe)
        XCTAssertFalse(html.contains("<b>bold attempt</b>"),
                       "Raw HTML injection should be escaped, got: \(html)")
    }

    // MARK: - MD-01: XSS via dangerous URL schemes in links/images must be neutralized

    func testXSSLink_javascriptScheme_neutralized() throws {
        let result = MarkdownTransformer.renderHTML("[click](javascript:alert(1))")
        guard case .success(let html) = result else {
            XCTFail("Expected success, got \(result)"); return
        }
        XCTAssertFalse(html.lowercased().contains("javascript:"),
                       "javascript: scheme must be stripped from href, got: \(html)")
        XCTAssertTrue(html.contains("href=\"#\""),
                      "Dangerous link should be rewritten to #, got: \(html)")
    }

    func testXSSImage_dataScheme_neutralized() throws {
        let result = MarkdownTransformer.renderHTML("![x](data:text/html,<script>alert(1)</script>)")
        guard case .success(let html) = result else {
            XCTFail("Expected success, got \(result)"); return
        }
        XCTAssertFalse(html.lowercased().contains("data:"),
                       "data: scheme must be stripped from img src, got: \(html)")
    }

    func testSafeLink_httpsPreserved() throws {
        let result = MarkdownTransformer.renderHTML("[ok](https://example.com/a?b=1#c)")
        guard case .success(let html) = result else {
            XCTFail("Expected success, got \(result)"); return
        }
        XCTAssertTrue(html.contains("href=\"https://example.com/a?b=1#c\""),
                      "Safe https URL must be preserved, got: \(html)")
    }

    // MARK: - MD-04: wordCount pure function

    func testWordCount_threeWords() {
        XCTAssertEqual(MarkdownTransformer.wordCount("one two three"), 3)
    }

    func testWordCount_empty() {
        XCTAssertEqual(MarkdownTransformer.wordCount(""), 0)
    }

    func testWordCount_singleWord() {
        XCTAssertEqual(MarkdownTransformer.wordCount("hello"), 1)
    }

    func testWordCount_extraWhitespace() {
        XCTAssertEqual(MarkdownTransformer.wordCount("  one   two  "), 2)
    }

    // MARK: - MD-04: readingTimeMinutes pure function

    func testReadingTime_400words_is2mins() {
        XCTAssertEqual(MarkdownTransformer.readingTimeMinutes(words: 400), 2,
                       "400 words / 200 wpm = 2 minutes")
    }

    func testReadingTime_0words_is1min() {
        XCTAssertEqual(MarkdownTransformer.readingTimeMinutes(words: 0), 1,
                       "0 words should return minimum 1 minute")
    }

    func testReadingTime_1word_is1min() {
        XCTAssertEqual(MarkdownTransformer.readingTimeMinutes(words: 1), 1,
                       "1 word should return 1 minute (ceil)")
    }

    func testReadingTime_201words_is2mins() {
        XCTAssertEqual(MarkdownTransformer.readingTimeMinutes(words: 201), 2,
                       "201 words / 200 wpm = ceil(1.005) = 2 minutes")
    }

    func testReadingTime_200words_is1min() {
        XCTAssertEqual(MarkdownTransformer.readingTimeMinutes(words: 200), 1,
                       "200 words / 200 wpm = 1 minute")
    }

    // MARK: - INFRA-17: No crash on empty / huge input

    func testRenderHTML_empty_doesNotCrash() {
        let result = MarkdownTransformer.renderHTML("")
        // Should succeed with empty HTML, or fail gracefully — never crash
        switch result {
        case .success(let html):
            XCTAssertTrue(html.count >= 0, "Empty input: got HTML of length \(html.count)")
        case .failure(let err):
            XCTAssertFalse(err.displayMessage.isEmpty, "Failure should have a message")
        }
    }

    func testRenderHTML_hugeInput_doesNotCrash() {
        let huge = String(repeating: "word ", count: 200_000) // 200K words ~ 1 MB
        let result = MarkdownTransformer.renderHTML(huge)
        // Should return failure for input over size limit, not crash
        switch result {
        case .success:
            break // acceptable if size guard is not triggered
        case .failure(let err):
            XCTAssertFalse(err.displayMessage.isEmpty, "Failure should have a message")
        }
        // Reaching here without crashing satisfies INFRA-17
    }

    func testRenderHTML_garbageInput_doesNotCrash() {
        let garbage = String(repeating: "!@#$%^&*()", count: 1000)
        let result = MarkdownTransformer.renderHTML(garbage)
        // Garbage is still valid Markdown (treated as text) — should succeed
        switch result {
        case .success(let html):
            XCTAssertTrue(html.count > 0, "Garbage input should produce some HTML output")
        case .failure:
            break // acceptable
        }
    }

    // MARK: - MD-03: fullStyledHTML inlines CSS (no external link)

    func testFullStyledHTML_containsStyleTag() throws {
        let result = MarkdownTransformer.fullStyledHTML("# Test")
        guard case .success(let html) = result else {
            XCTFail("Expected success, got \(result)"); return
        }
        XCTAssertTrue(html.contains("<html"),  "fullStyledHTML should produce full HTML doc, got: \(html)")
        XCTAssertTrue(html.contains("<style"),  "fullStyledHTML should inline CSS in <style>, got: \(html)")
        XCTAssertTrue(html.contains("<body"),   "fullStyledHTML should include <body>, got: \(html)")
        // Must NOT contain a remote CSS <link>
        XCTAssertFalse(html.contains("<link rel=\"stylesheet\" href=\"http"),
                       "fullStyledHTML must not have external CSS link, got: \(html)")
    }

    func testFullStyledHTML_containsGitHubCSS() throws {
        let result = MarkdownTransformer.fullStyledHTML("# Test")
        guard case .success(let html) = result else {
            XCTFail("Expected success, got \(result)"); return
        }
        // The bundled CSS contains known tokens — verify it's inlined
        XCTAssertTrue(html.contains("markdown-body") || html.contains("--color-canvas"),
                      "fullStyledHTML should inline github-markdown.css content, got prefix: \(html.prefix(500))")
    }

    // MARK: - MD-03: export forces light theme (shared/printed docs must be light)

    func testFullStyledHTML_default_isAdaptive() throws {
        let result = MarkdownTransformer.fullStyledHTML("# Test")
        guard case .success(let html) = result else { XCTFail("Expected success"); return }
        XCTAssertTrue(html.contains("content=\"light dark\""),
                      "Default (preview) HTML should declare adaptive color-scheme, got: \(html.prefix(400))")
        // Assert on the <html> open tag specifically — the CSS selector :root:not([data-theme="light"])
        // legitimately contains the substring, so check the tag, not the whole document.
        XCTAssertTrue(html.contains("<html>"),
                      "Default HTML root tag must be unadorned <html> (no data-theme), got: \(html.prefix(120))")
    }

    func testFullStyledHTML_forceLight_pinsLightTheme() throws {
        let result = MarkdownTransformer.fullStyledHTML("# Test", forceLight: true)
        guard case .success(let html) = result else { XCTFail("Expected success"); return }
        XCTAssertTrue(html.contains("<html data-theme=\"light\">"),
                      "Export HTML should pin <html data-theme=\"light\">, got: \(html.prefix(120))")
        XCTAssertTrue(html.contains("content=\"light\""),
                      "Export HTML should declare light-only color-scheme")
    }

    // MARK: - Paragraph

    func testParagraph_basicText() throws {
        let result = MarkdownTransformer.renderHTML("Hello world")
        guard case .success(let html) = result else {
            XCTFail("Expected success, got \(result)"); return
        }
        XCTAssertTrue(html.contains("Hello world"), "Paragraph text should appear in output")
    }

    // MARK: - Emphasis / Strong / InlineCode

    func testEmphasis() throws {
        let result = MarkdownTransformer.renderHTML("*italic*")
        guard case .success(let html) = result else {
            XCTFail("Expected success, got \(result)"); return
        }
        XCTAssertTrue(html.contains("<em>") || html.contains("<i>"),
                      "*italic* should produce <em>, got: \(html)")
    }

    func testStrong() throws {
        let result = MarkdownTransformer.renderHTML("**bold**")
        guard case .success(let html) = result else {
            XCTFail("Expected success, got \(result)"); return
        }
        XCTAssertTrue(html.contains("<strong>") || html.contains("<b>"),
                      "**bold** should produce <strong>, got: \(html)")
    }

    func testInlineCode() throws {
        let result = MarkdownTransformer.renderHTML("`code`")
        guard case .success(let html) = result else {
            XCTFail("Expected success, got \(result)"); return
        }
        XCTAssertTrue(html.contains("<code>") || html.contains("<code "),
                      "`code` should produce <code>, got: \(html)")
    }
}
