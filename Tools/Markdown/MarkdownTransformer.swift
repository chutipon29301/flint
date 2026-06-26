// Tools/Markdown/MarkdownTransformer.swift
// Pure Markdown → HTML transformer using swift-markdown AST walking.
// NO SwiftUI/AppKit imports — pure Foundation + Markdown (testable without UI).
// Security: all text nodes HTML-escaped (XSS hardening, T-02-MD-XSS).
// INFRA-17: size guard + no crash on empty/huge/garbage input.

import Foundation
import Markdown

// MARK: - MarkdownTransformer

enum MarkdownTransformer {

    struct TransformError: Error {
        let message: String
        var displayMessage: String { message }
    }

    // MARK: - Size limit (INFRA-17)

    private static let maxInputBytes = 10_000_000  // 10 MB

    // MARK: - Public API

    /// MD-01: Parse Markdown source → escaped GFM HTML body fragment.
    /// Returns .failure if input exceeds size limit; otherwise always .success (bad MD = treated as text).
    static func renderHTML(_ source: String) -> Result<String, TransformError> {
        guard source.utf8.count <= maxInputBytes else {
            return .failure(TransformError(message: "Input too large (>10 MB)"))
        }
        let document = Document(parsing: source)
        var visitor = HTMLVisitor()
        let html = visitor.visit(document)
        return .success(html)
    }

    /// MD-03: Full self-contained HTML with inlined github-markdown.css.
    /// CSS is inlined from bundle (no external resource loads — fully offline).
    static func fullStyledHTML(_ source: String) -> Result<String, TransformError> {
        switch renderHTML(source) {
        case .failure(let err):
            return .failure(err)
        case .success(let body):
            let css = loadBundledCSS()
            let html = """
            <!DOCTYPE html>
            <html>
            <head>
            <meta charset="utf-8">
            <meta name="color-scheme" content="light dark">
            <style>
            \(css)
            body { box-sizing: border-box; max-width: 860px; margin: 0 auto; padding: 16px 24px; }
            </style>
            </head>
            <body class="markdown-body">
            \(body)
            </body>
            </html>
            """
            return .success(html)
        }
    }

    /// MD-04: Pure word-count (whitespace-split token count).
    static func wordCount(_ s: String) -> Int {
        guard !s.isEmpty else { return 0 }
        return s.components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .count
    }

    /// MD-04: Reading time in minutes (ceil(words/200), minimum 1).
    static func readingTimeMinutes(words: Int) -> Int {
        guard words > 0 else { return 1 }
        return Int(ceil(Double(words) / 200.0))
    }

    // MARK: - Private helpers

    private static func loadBundledCSS() -> String {
        guard let url = Bundle.main.url(forResource: "github-markdown", withExtension: "css"),
              let css = try? String(contentsOf: url, encoding: .utf8) else {
            // Fallback minimal CSS so preview is never completely unstyled
            return "body { font-family: -apple-system, sans-serif; line-height: 1.6; color: #333; }"
        }
        return css
    }
}

// MARK: - HTML Visitor

/// Walks the swift-markdown AST and emits controlled, HTML-escaped HTML.
/// Security invariant: every text node passes through htmlEscape() before emission.
private struct HTMLVisitor: MarkupVisitor {
    typealias Result = String

    // MARK: - Block elements

    mutating func visitDocument(_ document: Document) -> String {
        document.children.map { visit($0) }.joined()
    }

    mutating func visitHeading(_ heading: Heading) -> String {
        let level = heading.level
        let inner = visitChildren(heading)
        return "<h\(level)>\(inner)</h\(level)>\n"
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> String {
        let inner = visitChildren(paragraph)
        return "<p>\(inner)</p>\n"
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> String {
        let inner = visitChildren(blockQuote)
        return "<blockquote>\n\(inner)</blockquote>\n"
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> String {
        let escaped = htmlEscape(codeBlock.code)
        if let lang = codeBlock.language, !lang.isEmpty {
            return "<pre><code class=\"language-\(htmlEscape(lang))\">\(escaped)</code></pre>\n"
        }
        return "<pre><code>\(escaped)</code></pre>\n"
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> String {
        return "<hr />\n"
    }

    // MARK: - List elements

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> String {
        let inner = visitChildren(unorderedList)
        return "<ul>\n\(inner)</ul>\n"
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) -> String {
        let inner = visitChildren(orderedList)
        return "<ol>\n\(inner)</ol>\n"
    }

    mutating func visitListItem(_ listItem: ListItem) -> String {
        // Task-list checkbox (GFM extension)
        if let checkbox = listItem.checkbox {
            let checkedAttr = checkbox == .checked ? " checked" : ""
            let inner = visitChildren(listItem)
            return "<li><input type=\"checkbox\"\(checkedAttr) disabled> \(inner)</li>\n"
        }
        let inner = visitChildren(listItem)
        return "<li>\(inner)</li>\n"
    }

    // MARK: - Table elements

    mutating func visitTable(_ table: Table) -> String {
        let inner = visitChildren(table)
        return "<table>\n\(inner)</table>\n"
    }

    mutating func visitTableHead(_ tableHead: Table.Head) -> String {
        let inner = visitChildren(tableHead)
        return "<thead>\n<tr>\n\(inner)</tr>\n</thead>\n"
    }

    mutating func visitTableBody(_ tableBody: Table.Body) -> String {
        let inner = visitChildren(tableBody)
        return "<tbody>\n\(inner)</tbody>\n"
    }

    mutating func visitTableRow(_ tableRow: Table.Row) -> String {
        let inner = visitChildren(tableRow)
        return "<tr>\n\(inner)</tr>\n"
    }

    mutating func visitTableCell(_ tableCell: Table.Cell) -> String {
        let inner = visitChildren(tableCell)
        // Determine if this is a header cell (parent is Table.Head or its row)
        let isHeader = tableCell.parent is Table.Row && tableCell.parent?.parent is Table.Head
        let tag = isHeader ? "th" : "td"

        // Column alignment from the table's column definitions
        if let row = tableCell.parent as? Table.Row,
           let table = row.parent?.parent as? Table {
            let colIndex = tableCell.indexInParent
            let columns = table.columnAlignments
            if colIndex < columns.count {
                let alignAttr: String
                switch columns[colIndex] {
                case .left:   alignAttr = " align=\"left\""
                case .center: alignAttr = " align=\"center\""
                case .right:  alignAttr = " align=\"right\""
                case .none:   alignAttr = ""
                }
                return "<\(tag)\(alignAttr)>\(inner)</\(tag)>\n"
            }
        }
        return "<\(tag)>\(inner)</\(tag)>\n"
    }

    // MARK: - Inline elements

    mutating func visitText(_ text: Text) -> String {
        return htmlEscape(text.string)
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> String {
        let inner = visitChildren(emphasis)
        return "<em>\(inner)</em>"
    }

    mutating func visitStrong(_ strong: Strong) -> String {
        let inner = visitChildren(strong)
        return "<strong>\(inner)</strong>"
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> String {
        let inner = visitChildren(strikethrough)
        return "<del>\(inner)</del>"
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> String {
        return "<code>\(htmlEscape(inlineCode.code))</code>"
    }

    mutating func visitLink(_ link: Link) -> String {
        let inner = visitChildren(link)
        let dest = htmlEscape(link.destination ?? "")
        return "<a href=\"\(dest)\">\(inner)</a>"
    }

    mutating func visitImage(_ image: Image) -> String {
        let src = htmlEscape(image.source ?? "")
        let alt = image.plainText
        return "<img src=\"\(src)\" alt=\"\(htmlEscape(alt))\">"
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> String {
        return "\n"
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> String {
        return "<br>\n"
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> String {
        // Raw HTML blocks from user input: escape them (XSS hardening — never emit raw HTML)
        return "<pre><code>\(htmlEscape(html.rawHTML))</code></pre>\n"
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> String {
        // Raw inline HTML from user input: escape it (XSS hardening)
        return htmlEscape(inlineHTML.rawHTML)
    }

    mutating func visitSymbolLink(_ symbolLink: SymbolLink) -> String {
        return htmlEscape(symbolLink.destination ?? "")
    }

    mutating func visitCustomBlock(_ customBlock: CustomBlock) -> String {
        return visitChildren(customBlock)
    }

    mutating func visitCustomInline(_ customInline: CustomInline) -> String {
        return htmlEscape(customInline.text)
    }

    // MARK: - Helpers

    mutating func visitChildren(_ markup: some Markup) -> String {
        markup.children.map { visit($0) }.joined()
    }

    mutating func defaultVisit(_ markup: any Markup) -> String {
        visitChildren(markup)
    }

    // MARK: - HTML escaping (XSS hardening — T-02-MD-XSS)

    /// Escapes &, <, >, " in text nodes so user content cannot inject HTML/JS.
    private func htmlEscape(_ s: String) -> String {
        var result = s
        result = result.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        result = result.replacingOccurrences(of: "\"", with: "&quot;")
        return result
    }
}
