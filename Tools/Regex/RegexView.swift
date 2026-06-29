// Tools/Regex/RegexView.swift
// Regex Tester UI — vertical stack: pattern+flags → test editor (live highlight) →
// collapsible match results → collapsible replace section.
// Convention A: lazy @State viewModel built on .onAppear (matches JSONFormatterView pattern).
// Capture-group highlighting: attribute-only NSTextStorage background pass — never resets .string (Pitfall #5).
// Source: UI-SPEC.md "Tool 1: Regex Tester" + PATTERNS.md All five *View.swift

import SwiftUI
import AppKit

// MARK: - RegexView (Convention A wrapper)

struct RegexView: View {
    @Environment(HistoryStore.self) private var historyStore
    @State private var viewModel: RegexViewModel?

    var body: some View {
        Group {
            if let vm = viewModel {
                RegexContentView(viewModel: vm)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = RegexViewModel(
                    onSaveHistory: { [historyStore] entry in historyStore.save(entry) }
                )
            }
        }
    }
}

// MARK: - Pattern Presets (RGX-04)

private enum PatternPresets {
    static let presets: [(name: String, pattern: String)] = [
        ("Email", #"[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}"#),
        ("URL (HTTP/HTTPS)", #"https?://[^\s/$.?#].[^\s]*"#),
        ("Phone (US)", #"\(?\d{3}\)?[\s\-.]?\d{3}[\s\-.]?\d{4}"#),
        ("Date (ISO 8601)", #"\d{4}-(?:0[1-9]|1[0-2])-(?:0[1-9]|[12]\d|3[01])"#),
        ("IPv4 Address", #"\b(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\b"#)
    ]
}

// MARK: - Capture-group color palette (D-03, UI-SPEC)

private enum GroupColorPalette {
    /// Returns NSColor for a given capture group index (0-based, 0 = full match).
    static func color(for groupIndex: Int) -> NSColor {
        let palette: [NSColor] = [
            // Group 0 (full match): accent at 0.25 opacity
            NSColor.controlAccentColor.withAlphaComponent(0.25),
            // Group 1: yellow
            NSColor.systemYellow.withAlphaComponent(0.30),
            // Group 2: green
            NSColor.systemGreen.withAlphaComponent(0.25),
            // Group 3: purple
            NSColor.systemPurple.withAlphaComponent(0.25),
            // Group 4: orange
            NSColor.systemOrange.withAlphaComponent(0.25)
        ]
        return palette[groupIndex % palette.count]
    }
}

// MARK: - RegexHighlightedEditorView

/// NSViewRepresentable wrapping SyntaxEditorView that also applies
/// attribute-only NSTextStorage background color passes for match highlighting.
/// CRITICAL: Never resets .string on the NSTextView — attribute-only passes only (Pitfall #5).
/// Re-entrancy guarded via isApplyingAttributes flag.
private struct RegexHighlightedEditorView: NSViewRepresentable {
    @Binding var text: String
    let matches: [RegexMatch]
    let outputDimmed: Bool
    let groupCount: Int

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isRichText = true  // needed for attribute-based highlighting
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.usesFontPanel = false
        textView.usesRuler = false

        // Accessibility (INFRA-15)
        textView.setAccessibilityLabel("Test string")
        textView.setAccessibilityRole(.textArea)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // CRITICAL: guard prevents infinite re-render loop (Pitfall #5)
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            // Restore cursor position after programmatic text update
            if selectedRanges.allSatisfy({ $0.rangeValue.location + $0.rangeValue.length <= textView.string.count }) {
                textView.selectedRanges = selectedRanges
            }
        }

        // Apply match highlights via attribute-only pass (never touches .string again).
        applyHighlights(to: textView, context: context)
    }

    private func applyHighlights(to textView: NSTextView, context: Context) {
        // Re-entrancy guard: skip if we're already inside an attribute update.
        guard !context.coordinator.isApplyingAttributes else { return }
        context.coordinator.isApplyingAttributes = true
        defer { context.coordinator.isApplyingAttributes = false }

        guard let storage = textView.textStorage else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        guard fullRange.length > 0 else { return }

        let dimAlpha: CGFloat = outputDimmed ? 0.4 : 1.0

        storage.beginEditing()
        // Clear all background color attributes first.
        storage.removeAttribute(.backgroundColor, range: fullRange)

        // Apply per-capture-group background colors.
        for match in matches {
            // Full match background (group index 0).
            if match.range.location != NSNotFound &&
               match.range.location + match.range.length <= fullRange.length {
                let color = GroupColorPalette.color(for: 0).withAlphaComponent(
                    GroupColorPalette.color(for: 0).alphaComponent * dimAlpha
                )
                storage.addAttribute(.backgroundColor, value: color, range: match.range)
            }

            // Per numbered capture group backgrounds (1-indexed in display, 0-indexed in array).
            for (groupIdx, _) in match.numberedGroups.enumerated() {
                let groupRange = (textView.string as NSString).range(
                    of: match.numberedGroups[groupIdx],
                    range: match.range
                )
                if groupRange.location != NSNotFound &&
                   groupRange.location + groupRange.length <= fullRange.length &&
                   !match.numberedGroups[groupIdx].isEmpty {
                    let color = GroupColorPalette.color(for: groupIdx + 1).withAlphaComponent(
                        GroupColorPalette.color(for: groupIdx + 1).alphaComponent * dimAlpha
                    )
                    storage.addAttribute(.backgroundColor, value: color, range: groupRange)
                }
            }
        }
        storage.endEditing()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        /// Re-entrancy guard — prevents infinite loop in the attribute-only highlight pass (Pitfall #5).
        var isApplyingAttributes: Bool = false

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            DispatchQueue.main.async { [weak self] in
                self?.text.wrappedValue = textView.string
            }
        }
    }
}

// MARK: - RegexContentView (main layout)

private struct RegexContentView: View {
    @Bindable var viewModel: RegexViewModel
    @State private var showMatchResults: Bool = true
    @State private var showReplace: Bool = false
    @State private var isDragTargeted = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // ─── Pattern row + Patterns menu ───────────────────────────────
                HStack(spacing: 8) {
                    TextField("Regular expression", text: $viewModel.pattern)
                        .font(.system(size: 13, design: .monospaced))
                        .textFieldStyle(.plain)
                        .accessibilityLabel("Regex pattern")

                    // Patterns ▾ menu (RGX-04, D-04)
                    Menu {
                        ForEach(PatternPresets.presets, id: \.name) { preset in
                            Button(preset.name) {
                                viewModel.pattern = preset.pattern
                            }
                        }
                    } label: {
                        Label("Patterns", systemImage: "chevron.down")
                            .font(.system(size: 13))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .accessibilityLabel("Pattern presets menu")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))

                // ─── Flag toggles row ───────────────────────────────────────────
                HStack(spacing: 8) {
                    Toggle("g (global)", isOn: Binding(
                        get: { viewModel.flags.contains(.g) },
                        set: { isOn in
                            if isOn { viewModel.flags.insert(.g) }
                            else { viewModel.flags.remove(.g) }
                        }
                    ))
                    .toggleStyle(.checkbox)
                    .accessibilityLabel("Global flag — enumerate all matches")

                    Toggle("i (case)", isOn: Binding(
                        get: { viewModel.flags.contains(.i) },
                        set: { isOn in
                            if isOn { viewModel.flags.insert(.i) }
                            else { viewModel.flags.remove(.i) }
                        }
                    ))
                    .toggleStyle(.checkbox)
                    .accessibilityLabel("Case insensitive flag")

                    Toggle("m (multiline)", isOn: Binding(
                        get: { viewModel.flags.contains(.m) },
                        set: { isOn in
                            if isOn { viewModel.flags.insert(.m) }
                            else { viewModel.flags.remove(.m) }
                        }
                    ))
                    .toggleStyle(.checkbox)
                    .accessibilityLabel("Multiline flag — anchors match line start/end")

                    Toggle("s (dot=nl)", isOn: Binding(
                        get: { viewModel.flags.contains(.s) },
                        set: { isOn in
                            if isOn { viewModel.flags.insert(.s) }
                            else { viewModel.flags.remove(.s) }
                        }
                    ))
                    .toggleStyle(.checkbox)
                    .accessibilityLabel("Dot matches newline flag")

                    Toggle("x (verbose)", isOn: Binding(
                        get: { viewModel.flags.contains(.x) },
                        set: { isOn in
                            if isOn { viewModel.flags.insert(.x) }
                            else { viewModel.flags.remove(.x) }
                        }
                    ))
                    .toggleStyle(.checkbox)
                    .accessibilityLabel("Verbose flag — allows comments and whitespace in pattern")

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))

                // ─── Timeout / error banners ────────────────────────────────────
                if viewModel.timedOut {
                    WarningBannerView(
                        message: viewModel.errorMessage ?? "Pattern too slow — possible catastrophic backtracking",
                        severity: .warning
                    )
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                } else if let err = viewModel.errorMessage, !err.isEmpty {
                    InlineErrorView(message: err)
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                }

                Divider()

                // ─── Test string editor with match-count badge ─────────────────
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Test String")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                        // Match-count badge (live, trailing caption)
                        if !viewModel.matchCountText.isEmpty {
                            Text(viewModel.matchCountText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .accessibilityLabel("Match count: \(viewModel.matchCountText)")
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                    // Highlighted test-string editor (attribute-only, re-entrancy guarded).
                    ZStack(alignment: .center) {
                        RegexHighlightedEditorView(
                            text: $viewModel.testString,
                            matches: viewModel.matches,
                            outputDimmed: viewModel.outputDimmed,
                            groupCount: viewModel.matches.first?.numberedGroups.count ?? 0
                        )
                        .opacity(viewModel.outputDimmed ? 0.4 : 1.0)
                        .accessibilityLabel("Test string editor with match highlights")

                        // D-05: empty state when no test string entered
                        if viewModel.testString.isEmpty {
                            Text("Paste or type content above")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(minHeight: 120, maxHeight: 240)
                }

                Divider()

                // ─── Match Results (collapsible) ────────────────────────────────
                DisclosureGroup(
                    isExpanded: $showMatchResults,
                    content: {
                        if viewModel.matches.isEmpty {
                            Text("No matches")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                        } else {
                            MatchResultsTable(matches: viewModel.matches)
                                .padding(.horizontal, 4)
                        }
                    },
                    label: {
                        HStack {
                            Text("Match Results")
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                )
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

                Divider()

                // ─── Replace Mode (collapsible) ─────────────────────────────────
                DisclosureGroup(
                    isExpanded: $showReplace,
                    content: {
                        VStack(alignment: .leading, spacing: 8) {
                            // Toggle replace mode
                            Toggle("Enable Replace Mode", isOn: $viewModel.replaceMode)
                                .toggleStyle(.checkbox)
                                .accessibilityLabel("Enable replace mode")
                                .padding(.horizontal, 12)

                            if viewModel.replaceMode {
                                // Template field
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Template")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.secondary)
                                    TextField("Replacement template (e.g. $1, $2, ${name})", text: $viewModel.template)
                                        .font(.system(size: 13, design: .monospaced))
                                        .textFieldStyle(.roundedBorder)
                                        .accessibilityLabel("Replacement template")
                                }
                                .padding(.horizontal, 12)

                                // Substitution preview (read-only)
                                if !viewModel.substitutionPreview.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text("Substitution Preview")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundColor(.secondary)
                                            Spacer()
                                            CopyButtonView(getText: { viewModel.substitutionPreview })
                                                .accessibilityLabel("Copy substitution preview")
                                        }
                                        .padding(.horizontal, 12)

                                        CodeDisplayView(code: viewModel.substitutionPreview, language: "text")
                                            .frame(minHeight: 80, maxHeight: 160)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    },
                    label: {
                        HStack {
                            Text("Replace")
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                )
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

                Spacer(minLength: 0)
            }
        }
        .navigationTitle("Regex Tester")
        .toolShortcuts(viewModel)
        .fileDrop(
            isTargeted: $isDragTargeted,
            onText: { viewModel.testString = $0 },
            onError: { viewModel.errorMessage = $0 }
        )
        .overlay {
            if isDragTargeted {
                DropOverlayView(label: "Drop to load")
                    .transition(.opacity.animation(.easeOut(duration: 0.15)))
            }
        }
    }
}

// MARK: - Match Results Table

private struct MatchResultsTable: View {
    let matches: [RegexMatch]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                Text("#")
                    .frame(width: 36, alignment: .trailing)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                Text("Pos")
                    .frame(width: 48, alignment: .trailing)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                Text("Full Match")
                    .frame(minWidth: 80, maxWidth: .infinity, alignment: .leading)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                Text("Groups")
                    .frame(minWidth: 60, maxWidth: 160, alignment: .leading)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
            }
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Data rows
            ForEach(Array(matches.enumerated()), id: \.offset) { idx, match in
                MatchRow(match: match, rowIndex: idx)
                if idx < matches.count - 1 { Divider() }
            }
        }
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
    }
}

// MARK: - Match Row

private struct MatchRow: View {
    let match: RegexMatch
    let rowIndex: Int

    var body: some View {
        HStack(spacing: 0) {
            // Match index (1-based for display)
            Text("\(match.index + 1)")
                .frame(width: 36, alignment: .trailing)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            // Character position
            Text("\(match.position)")
                .frame(width: 48, alignment: .trailing)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            // Full match text (truncated at 60 chars per UI-SPEC)
            let truncated = match.matchedString.count > 60
                ? String(match.matchedString.prefix(60)) + "…"
                : match.matchedString
            Text(truncated)
                .frame(minWidth: 80, maxWidth: .infinity, alignment: .leading)
                .font(.system(size: 13, design: .monospaced))
                .textSelection(.enabled)
                .padding(.horizontal, 4)
                .accessibilityLabel("Full match: \(match.matchedString)")

            // Capture groups summary
            let groupsSummary: String = {
                var parts: [String] = []
                for (i, g) in match.numberedGroups.enumerated() {
                    parts.append("$\(i+1):\(g.prefix(20))")
                }
                for (name, val) in match.namedGroups {
                    parts.append("\(name):\(val.prefix(20))")
                }
                return parts.joined(separator: " ")
            }()
            Text(groupsSummary.isEmpty ? "—" : groupsSummary)
                .frame(minWidth: 60, maxWidth: 160, alignment: .leading)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 4)
                .accessibilityLabel("Capture groups: \(groupsSummary)")
        }
        .padding(.vertical, 4)
        .background(rowIndex % 2 == 0 ? Color.clear : Color(NSColor.controlBackgroundColor).opacity(0.3))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Match \(match.index + 1) at position \(match.position): \(match.matchedString)")
    }
}

#Preview {
    RegexView()
        .environment(HistoryStore())
        .frame(width: 600, height: 700)
}
