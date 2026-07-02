// UI/SearchView.swift
// Global fuzzy search view — tools-only, keyboard navigable ↑↓ Enter (INFRA-10).
// Uses SearchResultsMerger (UI-free) for merge/rank logic.
// D-01: search-first launcher; D-02: typing replaces body with results.
// D-07: arrow-key navigation with TextField-focused fallback via .searchNavigate notification
//       (MenuBarPopoverView NSEvent monitor — Pitfall 7 / RESEARCH Open Question 1).

import SwiftUI
import AppKit

struct SearchView: View {
    @Environment(ToolRegistry.self) private var toolRegistry

    let query: String
    let onSelectTool: (String) -> Void         // toolId

    @State private var selectedIndex: Int = 0

    // MARK: - Merged Results

    private var merged: MergedSearchResults {
        SearchResultsMerger.merge(
            tools: toolRegistry.search(query),
            query: query
        )
    }

    /// Flat ordered list of tool results (for keyboard navigation).
    private var flatResults: [SearchResult] {
        merged.toolResults.map { SearchResult.tool($0) }
    }

    var body: some View {
        Group {
            if merged.isEmpty {
                emptyState
            } else {
                resultsList
            }
        }
        .onChange(of: query) { _, _ in
            selectedIndex = 0
        }
        // Primary: SwiftUI .onKeyPress handlers — work when this view or a descendant holds focus.
        .onKeyPress(.upArrow) {
            if selectedIndex > 0 { selectedIndex -= 1 }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if selectedIndex < flatResults.count - 1 { selectedIndex += 1 }
            return .handled
        }
        .onKeyPress(.return) {
            activateSelected()
            return .handled
        }
        // D-07 fallback: observe .searchNavigate posted by the NSEvent arrow monitor in
        // MenuBarPopoverView. This fires when the search TextField (a sibling view) holds AppKit
        // first responder focus and SwiftUI's .onKeyPress above is unreliable (Pitfall 7).
        // Direction: -1 = ↑ (move up, clamped at 0), +1 = ↓ (move down, clamped at count-1).
        .onReceive(NotificationCenter.default.publisher(for: .searchNavigate)) { note in
            guard let direction = note.userInfo?["direction"] as? Int else { return }
            if direction < 0 {
                if selectedIndex > 0 { selectedIndex -= 1 }
            } else {
                if selectedIndex < flatResults.count - 1 { selectedIndex += 1 }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            // UI-SPEC Copywriting: "No tools matching '[query]'"
            Text("No tools matching \"\(query)\"")
                .font(.headline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Results List

    private var resultsList: some View {
        List {
            // Tool results section
            if !merged.toolResults.isEmpty {
                Section("Tools") {
                    ForEach(Array(merged.toolResults.enumerated()), id: \.element.id) { idx, tool in
                        SearchToolRow(
                            tool: tool,
                            isSelected: selectedIndex == idx
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { onSelectTool(tool.id) }
                        .accessibilityAddTraits(selectedIndex == idx ? .isSelected : [])
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Keyboard Activation

    private func activateSelected() {
        guard !flatResults.isEmpty else { return }
        let idx = min(selectedIndex, flatResults.count - 1)
        switch flatResults[idx] {
        case .tool(let tool):
            onSelectTool(tool.id)
        }
    }
}

// MARK: - Search Tool Row

/// Tool result row with SF Symbol, name, category, and highlight support.
private struct SearchToolRow: View {
    let tool: ToolDefinition
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: tool.sfSymbol)
                .foregroundColor(.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.name)
                    .font(.system(size: 13, weight: .semibold))
                Text(tool.category.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.12) : .clear)
        .cornerRadius(4)
        .accessibilityLabel(tool.name)
    }
}
