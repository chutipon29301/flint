// UI/Components/CodeDisplayView.swift
// Read-only code display using HighlightSwift for syntax highlighting.
// Used for JSON output, not for the editable input (that's SyntaxEditorView).
// Source: RESEARCH.md § "Architecture Responsibility Map" (display-only = HighlightSwift)

import SwiftUI
import HighlightSwift

struct CodeDisplayView: View {
    let code: String
    let language: String

    var body: some View {
        ScrollView {
            if code.isEmpty {
                Text("Output will appear here")
                    .font(.monoBody)
                    .foregroundColor(.ashDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            } else {
                HighlightedCodeBlock(
                    code: code,
                    language: language
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
        }
        .background(Color.graphite950)
        .accessibilityLabel("Formatted output")
        .accessibilityValue(code)
    }
}

/// Wrapper for HighlightSwift 1.1.0 that renders attributed string output.
///
/// HighlightSwift renders via highlight.js CSS classes into an AttributedString. Rather than
/// picking one of the bundled `.dark(theme:)` presets (which don't match the site palette), we
/// pass a `.custom` CSS mapping so JSON/JWT keys, strings, numbers, and punctuation land on the
/// exact DesignSystem tokens (codeKey amber / codeString jade / codeNumber purple / codePunct
/// ash-dim) — matching the landing page's code blocks exactly.
private struct HighlightedCodeBlock: View {
    let code: String
    let language: String

    @State private var attributedCode: AttributedString = AttributedString()
    private let highlight = Highlight()

    /// Maps highlight.js token classes to the DesignSystem syntax palette.
    /// hljs-attr = JSON/JWT keys (codeKey amber), hljs-string = string values (codeString jade),
    /// hljs-number/-literal = numbers/booleans/timestamps (codeNumber purple), base text and
    /// punctuation fall back to chalk / codePunct.
    private static let colors = HighlightColors.custom(
        css: """
        pre code.hljs{display:block;overflow-x:auto;padding:0}
        code.hljs{padding:0}
        .hljs{color:#e8ebef;background:#14171c}
        .hljs-attr{color:#ffb347}
        .hljs-string{color:#6fd3b8}
        .hljs-number,.hljs-literal{color:#c9a8ff}
        .hljs-punctuation{color:#626b78}
        .hljs-comment{color:#626b78}
        """,
        background: "#14171c"
    )

    var body: some View {
        Text(attributedCode.characters.isEmpty
             ? AttributedString(code)
             : attributedCode)
            .font(.monoBody)
            .foregroundColor(.chalk)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .task(id: code) {
                do {
                    // HighlightSwift 1.1.0 API: attributedText(_:language:colors:)
                    let result = try await highlight.attributedText(code, language: language, colors: Self.colors)
                    attributedCode = result
                } catch {
                    // Fallback to plain text if highlighting fails
                    attributedCode = AttributedString(code)
                }
            }
    }
}

#Preview {
    CodeDisplayView(code: #"{"name": "Alice", "age": 30}"#, language: "json")
        .frame(width: 400, height: 200)
}
