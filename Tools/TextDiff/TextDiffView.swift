// Tools/TextDiff/TextDiffView.swift
// Text Diff tool UI — two stacked editors + unified/side-by-side diff output.
// DIFF-01: Unified default in popover, side-by-side in main window (width ≥ 600pt threshold).
// DIFF-02: Line numbers, +/-/space prefix, color coding, word-level inline highlights.
// DIFF-03: Next/prev navigation, copy unified patch.
// DIFF-04: Ignore-whitespace and ignore-case toggles.

import SwiftUI
import AppKit

// MARK: - Outer wrapper (lazy init, environment injection)

struct TextDiffView: View {
    @Environment(HistoryStore.self) private var historyStore
    @State private var viewModel: TextDiffViewModel?

    var body: some View {
        Group {
            if let vm = viewModel {
                TextDiffContentView(viewModel: vm)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = TextDiffViewModel(
                    onSaveHistory: { [historyStore] entry in
                        historyStore.save(entry)
                    }
                )
            }
        }
    }
}

// MARK: - Content view

private struct TextDiffContentView: View {
    @Bindable var viewModel: TextDiffViewModel
    /// Width-based detection: ≥ 600pt → side-by-side default (D-15).
    @State private var viewWidth: CGFloat = 0

    // TextDiffViewModel has no errorMessage; drop errors surface via this view-local
    // WarningBannerView (the only sanctioned drop-error surface — no new UI introduced).
    @State private var dropError: String?
    @State private var isDragTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            if let dropError {
                WarningBannerView(message: dropError, severity: .warning)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }
            controlBar
            Divider()
            editorsSection
            if viewModel.original.isEmpty && viewModel.changed.isEmpty {
                Divider()
                Text("Paste or type content above")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(16)
            } else if viewModel.result != nil || shouldShowEmptyMessage {
                Divider()
                diffOutputSection
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear.onAppear {
                    viewWidth = geo.size.width
                    // Set default view mode based on available width (D-15)
                    if geo.size.width >= 600 {
                        viewModel.viewMode = .sideBySide
                    } else {
                        viewModel.viewMode = .unified
                    }
                }
                .onChange(of: geo.size.width) { _, newWidth in
                    viewWidth = newWidth
                }
            }
        )
        .navigationTitle("Text Diff")
        .toolShortcuts(viewModel)
        .fileDrop(
            isTargeted: $isDragTargeted,
            onText: { text in
                // TextDiff has two inputs — load into the primary/left (Original) input.
                dropError = nil
                viewModel.original = text
            },
            onError: { dropError = $0 }
        )
        .overlay {
            if isDragTargeted {
                DropOverlayView(label: "Drop to load")
                    .transition(.opacity.animation(.easeOut(duration: 0.15)))
            }
        }
    }

    // MARK: - Control bar

    private var controlBar: some View {
        HStack(spacing: 12) {
            // DIFF-04: Ignore toggles
            Toggle("Ignore Whitespace", isOn: $viewModel.ignoreWhitespace)
                .toggleStyle(.checkbox)
                .accessibilityLabel("Ignore whitespace")

            Toggle("Ignore Case", isOn: $viewModel.ignoreCase)
                .toggleStyle(.checkbox)
                .accessibilityLabel("Ignore case")

            Spacer()

            // DIFF-01: Unified/Side-by-side toggle
            Picker("", selection: $viewModel.viewMode) {
                ForEach(DiffViewMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)
            .accessibilityLabel("Diff view mode")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Editors section

    private var editorsSection: some View {
        Group {
            if viewModel.viewMode == .sideBySide {
                // Side-by-side editors (D-15: main window layout)
                HSplitView {
                    editorPanel(label: "Original", text: $viewModel.original,
                                accessibilityLabel: "Original text input")
                    editorPanel(label: "Changed", text: $viewModel.changed,
                                accessibilityLabel: "Changed text input")
                }
                .frame(minHeight: 120)
            } else {
                // Stacked editors (popover / unified layout)
                VStack(spacing: 0) {
                    editorPanel(label: "Original", text: $viewModel.original,
                                accessibilityLabel: "Original text input")
                    Divider()
                    editorPanel(label: "Changed", text: $viewModel.changed,
                                accessibilityLabel: "Changed text input")
                }
                .frame(minHeight: 120)
            }
        }
    }

    private func editorPanel(label: String, text: Binding<String>, accessibilityLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 8)

            SyntaxEditorView(text: text, accessibilityLabel: accessibilityLabel)
                .frame(maxWidth: .infinity, minHeight: 60, maxHeight: .infinity)
        }
        .frame(minWidth: 160)
    }

    // MARK: - Diff output section

    private var shouldShowEmptyMessage: Bool {
        !viewModel.original.isEmpty && !viewModel.changed.isEmpty
            && viewModel.result == nil
    }

    @ViewBuilder
    private var diffOutputSection: some View {
        // Navigation + copy bar (shown when diff has results)
        if let r = viewModel.result, r.hasDiffs {
            HStack(spacing: 8) {
                // DIFF-03: Prev/Next navigation
                Button("◀ Prev Diff") {
                    viewModel.prevDiff()
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Previous difference")
                .help("Previous difference (⌃↑)")

                Text(viewModel.currentDiffLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(viewModel.currentDiffLabel)

                Button("Next Diff ▶") {
                    viewModel.nextDiff()
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Next difference")
                .help("Next difference (⌃↓)")

                Spacer()

                // DIFF-03: Copy patch button
                CopyButtonView(getText: { r.unifiedPatch })
                Text("Copy Patch")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.accentColor)
                    .onTapGesture {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(r.unifiedPatch, forType: .string)
                    }
                    .accessibilityLabel("Copy as unified patch")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()
        }

        // Diff output rows
        if let r = viewModel.result {
            if r.hasDiffs {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if viewModel.viewMode == .sideBySide {
                            SideBySideDiffRowsView(lines: r.lines, currentHunkIndex: viewModel.currentDiffIndex)
                        } else {
                            UnifiedDiffRowsView(lines: r.lines, currentHunkIndex: viewModel.currentDiffIndex)
                        }
                    }
                }
            } else if let msg = viewModel.statusMessage {
                // "No differences found"
                Text(msg)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(16)
            }
        } else if shouldShowEmptyMessage {
            // "Enter text in both fields to compare"
            Text("Enter text in both fields to compare")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(16)
        }
    }
}

// MARK: - Unified diff rows

private struct UnifiedDiffRowsView: View {
    let lines: [DiffLine]
    let currentHunkIndex: Int

    var body: some View {
        ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
            UnifiedDiffRow(line: line)
        }
    }
}

private struct UnifiedDiffRow: View {
    let line: DiffLine

    private var rowBackground: Color {
        switch line.kind {
        case .added:     return Color.green.opacity(0.18)
        case .removed:   return Color.red.opacity(0.18)
        case .unchanged: return Color.clear
        }
    }

    private var prefix: String {
        switch line.kind {
        case .added:     return "+"
        case .removed:   return "-"
        case .unchanged: return " "
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            // Line number(s)
            lineNumberLabel
                .frame(width: 36, alignment: .trailing)

            // Prefix char (+/-/ )
            Text(prefix)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(prefixColor)
                .frame(width: 12, alignment: .leading)

            // Content
            if let segs = line.wordSegments, !segs.isEmpty {
                WordSegmentsView(segments: segs, kind: line.kind)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(line.displayText.isEmpty ? " " : line.displayText)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 8)
        .background(rowBackground)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var prefixColor: Color {
        switch line.kind {
        case .added:     return .green
        case .removed:   return .red
        case .unchanged: return .secondary
        }
    }

    private var lineNumberLabel: some View {
        Group {
            switch line.kind {
            case .added:
                Text(line.newLineNumber.map(String.init) ?? "")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            case .removed:
                Text(line.originalLineNumber.map(String.init) ?? "")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            case .unchanged:
                Text(line.originalLineNumber.map(String.init) ?? "")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var accessibilityDescription: String {
        let lineNum: String
        switch line.kind {
        case .added:     lineNum = line.newLineNumber.map { "line \($0)" } ?? ""
        case .removed:   lineNum = line.originalLineNumber.map { "line \($0)" } ?? ""
        case .unchanged: lineNum = line.originalLineNumber.map { "line \($0)" } ?? ""
        }
        let kindStr: String
        switch line.kind {
        case .added:     kindStr = "added"
        case .removed:   kindStr = "removed"
        case .unchanged: kindStr = "unchanged"
        }
        return "\(kindStr) \(lineNum): \(line.displayText)"
    }
}

// MARK: - Side-by-side diff rows

private struct SideBySideRowPair {
    let left: DiffLine?
    let right: DiffLine?
}

private struct SideBySideDiffRowsView: View {
    let lines: [DiffLine]
    let currentHunkIndex: Int

    var body: some View {
        // Build paired side-by-side rows:
        // - .unchanged: left = original, right = changed
        // - .removed: left = removed text, right = empty
        // - .added: left = empty, right = added text
        // - Consecutive .removed + .added at same position → paired row
        let pairedRows = buildPairedRows(lines: lines)

        ForEach(Array(pairedRows.enumerated()), id: \.offset) { _, pair in
            SideBySideRow(pair: pair)
        }
    }

    private func buildPairedRows(lines: [DiffLine]) -> [SideBySideRowPair] {
        var result = [SideBySideRowPair]()
        var i = 0
        while i < lines.count {
            let line = lines[i]
            switch line.kind {
            case .unchanged:
                result.append(SideBySideRowPair(left: line, right: line))
                i += 1
            case .removed:
                // Peek: if next is .added, they're a modification pair
                if i + 1 < lines.count, lines[i + 1].kind == .added {
                    result.append(SideBySideRowPair(left: line, right: lines[i + 1]))
                    i += 2
                } else {
                    result.append(SideBySideRowPair(left: line, right: nil))
                    i += 1
                }
            case .added:
                result.append(SideBySideRowPair(left: nil, right: line))
                i += 1
            }
        }
        return result
    }
}

private struct SideBySideRow: View {
    let pair: SideBySideRowPair

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left panel (original / removed)
            sideCell(line: pair.left, side: .left)
            Divider()
            // Right panel (changed / added)
            sideCell(line: pair.right, side: .right)
        }
    }

    enum Side { case left, right }

    private func cellBackground(for line: DiffLine?) -> Color {
        guard let l = line else {
            return Color(NSColor.controlBackgroundColor).opacity(0.3)
        }
        switch l.kind {
        case .added:     return Color.green.opacity(0.18)
        case .removed:   return Color.red.opacity(0.18)
        case .unchanged: return Color.clear
        }
    }

    private func cellPrefix(for line: DiffLine?) -> String {
        guard let l = line else { return " " }
        switch l.kind {
        case .added:     return "+"
        case .removed:   return "-"
        case .unchanged: return " "
        }
    }

    @ViewBuilder
    private func sideCell(line: DiffLine?, side: Side) -> some View {
        HStack(alignment: .top, spacing: 4) {
            // Line number
            Text(lineNum(for: line, side: side))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .trailing)

            // Prefix
            Text(cellPrefix(for: line))
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(prefixColor(for: line))
                .frame(width: 12)

            // Content
            if let segs = line?.wordSegments, !segs.isEmpty, let lineKind = line?.kind {
                WordSegmentsView(segments: segs, kind: lineKind)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(line?.displayText ?? "")
                    .font(.system(size: 13, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .background(cellBackground(for: line))
    }

    private func lineNum(for line: DiffLine?, side: Side) -> String {
        guard let l = line else { return "" }
        switch side {
        case .left:  return l.originalLineNumber.map(String.init) ?? ""
        case .right: return l.newLineNumber.map(String.init) ?? ""
        }
    }

    private func prefixColor(for line: DiffLine?) -> Color {
        guard let l = line else { return .secondary }
        switch l.kind {
        case .added:     return .green
        case .removed:   return .red
        case .unchanged: return .secondary
        }
    }
}

// MARK: - Word-level segment highlight view

/// Renders word-level diff segments as inline text with background highlights.
/// Added words: green.opacity(0.40), Removed words: red.opacity(0.40).
private struct WordSegmentsView: View {
    let segments: [WordSegment]
    let kind: DiffLine.LineKind

    var body: some View {
        // Build an AttributedString from segments
        let attStr = buildAttributedString()
        Text(attStr)
            .font(.system(size: 13, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func buildAttributedString() -> AttributedString {
        var result = AttributedString()
        for seg in segments {
            var part = AttributedString(seg.text)
            switch seg.segmentKind {
            case .inserted:
                // Word-level inserted: green highlight (only show on added lines)
                if kind == .added {
                    part.backgroundColor = Color.green.opacity(0.40)
                }
            case .deleted:
                // Word-level deleted: red highlight (only show on removed lines)
                if kind == .removed {
                    part.backgroundColor = Color.red.opacity(0.40)
                }
            case .equal:
                break
            }
            result.append(part)
        }
        return result
    }
}

#Preview {
    TextDiffView()
        .environment(HistoryStore())
        .frame(width: 700, height: 600)
}
