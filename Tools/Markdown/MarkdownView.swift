// Tools/Markdown/MarkdownView.swift
// Markdown Previewer UI — editor + WKWebView preview + toolbar + footer + export.
// D-09: popover shows segmented Editor/Preview toggle; window shows HSplitView.
// D-12: formatting toolbar (B/I/link/image/code/code-block/table) + word-count footer.
// D-11: export Copy HTML / Save as HTML… / Save as PDF…

import SwiftUI
import AppKit

// MARK: - MarkdownView (history-injected entry point)

struct MarkdownView: View {
    let onSaveHistory: (HistoryEntry) -> Void

    @State private var viewModel: MarkdownViewModel?

    var body: some View {
        Group {
            if let vm = viewModel {
                MarkdownContentView(viewModel: vm)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = MarkdownViewModel(onSaveHistory: onSaveHistory)
            }
        }
    }
}

// MARK: - MarkdownContentView

private struct MarkdownContentView: View {
    @Bindable var viewModel: MarkdownViewModel

    /// Detects popover vs. window mode (D-09): narrow = segmented toggle, roomy = HSplitView.
    @State private var containerWidth: CGFloat = 0

    /// Segmented selection: 0 = Editor, 1 = Preview (popover mode only)
    @State private var selectedTab: Int = 0

    /// WebPreviewView coordinator reference for PDF export
    @State private var previewCoordinator: WebPreviewView.Coordinator? = nil

    // Popover threshold ~600pt (UI-SPEC)
    private var isPopover: Bool { containerWidth < 600 && containerWidth > 0 }

    var body: some View {
        VStack(spacing: 0) {
            // Formatting toolbar
            MarkdownToolbar(source: $viewModel.source)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if isPopover {
                // Popover: segmented Editor/Preview toggle
                Picker("", selection: $selectedTab) {
                    Text("Editor").tag(0)
                    Text("Preview").tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .accessibilityLabel("Editor or Preview mode")

                if selectedTab == 0 {
                    editorPanel
                } else {
                    previewPanel
                }
            } else {
                // Window: side-by-side split
                HSplitView {
                    editorPanel
                        .frame(minWidth: 220)
                    previewPanel
                        .frame(minWidth: 220)
                }
            }

            Divider()

            // Footer: word count + reading time + Copy HTML + Save ▾
            footerBar
        }
        .navigationTitle("Markdown Previewer")
        .toolShortcuts(viewModel)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { containerWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, w in containerWidth = w }
            }
        )
    }

    // MARK: - Editor panel

    private var editorPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Editor")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 4)

            SyntaxEditorView(text: $viewModel.source, accessibilityLabel: "Markdown editor", markdownHighlight: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            InlineErrorView(message: viewModel.errorMessage)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
        }
    }

    // MARK: - Preview panel

    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Preview")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 4)

            WebPreviewView(html: viewModel.html)
                .opacity(viewModel.outputDimmed ? 0.4 : 1.0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Markdown preview pane")
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack(spacing: 12) {
            // Word count + reading time
            Text(viewModel.wordCountText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .accessibilityLabel(viewModel.wordCountText)

            Text("•")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Text(viewModel.readingTimeText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .accessibilityLabel(viewModel.readingTimeText)

            Spacer()

            // Copy HTML button
            Button("Copy HTML") {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(viewModel.html, forType: .string)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
            .disabled(viewModel.html.isEmpty)
            .accessibilityLabel("Copy HTML to clipboard")

            // Save ▾ menu
            Menu("Save \u{25BE}") {
                Button("Save as HTML…") {
                    saveAsHTML()
                }
                .accessibilityLabel("Save rendered HTML to a file")

                Button("Save as PDF…") {
                    saveAsPDF()
                }
                .accessibilityLabel("Save preview as PDF")
            }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: 70)
            .disabled(viewModel.html.isEmpty)
            .accessibilityLabel("Export options")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Export actions

    /// Exports default to the Downloads folder, not the app's last/Documents dir.
    private var defaultExportDirectory: URL? {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    }

    /// Light-forced HTML for export — shared docs/PDF should be light regardless of system theme.
    private var exportHTML: String {
        if case .success(let html) = MarkdownTransformer.fullStyledHTML(viewModel.source, forceLight: true) {
            return html
        }
        return viewModel.html  // fall back to the adaptive preview HTML
    }

    private func saveAsHTML() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = "preview.html"
        panel.message = "Save Markdown HTML"
        panel.prompt = "Save"
        panel.directoryURL = defaultExportDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try exportHTML.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            // WR-03: surface write failures instead of swallowing them.
            MarkdownExportError.present("Could not save HTML", error)
        }
    }

    private func saveAsPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "preview.pdf"
        panel.message = "Save Markdown PDF"
        panel.prompt = "Save"
        panel.directoryURL = defaultExportDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // CR-02: the WKWebView's navigationDelegate is weak, so the exporter must own a
        // strong reference to itself until createPDF's completion fires — otherwise the
        // delegate is deallocated when this method returns and didFinish never calls back.
        MarkdownPDFExporter.export(html: exportHTML, to: url)
    }
}

// MARK: - PDF export (self-retaining; see #CR-02)

import WebKit

private final class MarkdownPDFExporter: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private let destination: URL
    private var strongSelf: MarkdownPDFExporter?

    private init(html: String, to url: URL) {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        self.webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 1200), configuration: config)
        self.destination = url
        super.init()
        self.strongSelf = self          // keep alive across the async load + createPDF
        webView.navigationDelegate = self
        webView.loadHTMLString(html, baseURL: nil)
    }

    static func export(html: String, to url: URL) {
        _ = MarkdownPDFExporter(html: html, to: url)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.createPDF(configuration: WKPDFConfiguration()) { [destination] result in
            switch result {
            case .success(let data):
                do { try data.write(to: destination) }
                catch { MarkdownExportError.present("Could not save PDF", error) }
            case .failure(let error):
                MarkdownExportError.present("Could not generate PDF", error)
            }
            self.strongSelf = nil       // release after the write completes
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        MarkdownExportError.present("Could not render Markdown for PDF", error)
        strongSelf = nil
    }
}

private enum MarkdownExportError {
    @MainActor static func present(_ message: String, _ error: Error) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}

// MARK: - Markdown Toolbar (D-12)

private struct MarkdownToolbar: View {
    @Binding var source: String

    var body: some View {
        HStack(spacing: 4) {
            toolbarButton(title: "B", tooltip: "Bold — wraps selection in **…**", action: insertBold)
                .font(.system(size: 13, weight: .bold))
                .accessibilityLabel("Insert bold")

            toolbarButton(title: "I", tooltip: "Italic — wraps selection in *…*", action: insertItalic)
                .font(.system(size: 13, weight: .regular).italic())
                .accessibilityLabel("Insert italic")

            toolbarButton(title: "Link", tooltip: "Insert link [text](url)", action: insertLink)
                .accessibilityLabel("Insert link")

            toolbarButton(title: "Img", tooltip: "Insert image ![alt](url)", action: insertImage)
                .accessibilityLabel("Insert image")

            toolbarButton(title: "`code`", tooltip: "Inline code — wraps in backticks", action: insertInlineCode)
                .font(.system(size: 11, design: .monospaced))
                .accessibilityLabel("Insert inline code")

            toolbarButton(title: "```", tooltip: "Code block — fenced with backticks", action: insertCodeBlock)
                .font(.system(size: 11, design: .monospaced))
                .accessibilityLabel("Insert code block")

            toolbarButton(title: "Table", tooltip: "Insert 2×2 GFM table template", action: insertTable)
                .accessibilityLabel("Insert table")

            Spacer()
        }
    }

    private func toolbarButton(title: String, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
        }
        .buttonStyle(.borderless)
        .help(tooltip)
    }

    // MARK: - Insert actions (pure string operations)

    private func insertBold() {
        insertWrapped("**", "**", placeholder: "bold text")
    }

    private func insertItalic() {
        insertWrapped("*", "*", placeholder: "italic text")
    }

    private func insertLink() {
        insertSnippet("[link text](https://example.com)")
    }

    private func insertImage() {
        insertSnippet("![alt text](https://example.com/image.png)")
    }

    private func insertInlineCode() {
        insertWrapped("`", "`", placeholder: "code")
    }

    private func insertCodeBlock() {
        insertSnippet("```\ncode here\n```")
    }

    private func insertTable() {
        insertSnippet("| Column 1 | Column 2 |\n|----------|----------|\n| Cell 1   | Cell 2   |\n| Cell 3   | Cell 4   |")
    }

    /// Insert a snippet at end (or replace selection if we could access it via AppKit).
    /// For simplicity, appends on a new line if source is not empty.
    private func insertSnippet(_ snippet: String) {
        if source.isEmpty {
            source = snippet
        } else if source.hasSuffix("\n") {
            source += snippet
        } else {
            source += "\n" + snippet
        }
    }

    /// Wraps a placeholder in prefix/suffix and appends.
    private func insertWrapped(_ prefix: String, _ suffix: String, placeholder: String) {
        let snippet = "\(prefix)\(placeholder)\(suffix)"
        insertSnippet(snippet)
    }
}

// MARK: - WKWebView import (needed for saveAsPDF)

import WebKit
