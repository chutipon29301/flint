// UI/SearchView.swift
// Global fuzzy search view — tools + history, keyboard navigable ↑↓ Enter (INFRA-10).
// Uses SearchResultsMerger (UI-free) for merge/rank logic.
// D-01: search-first launcher; D-02: typing replaces body with results.

import SwiftUI

struct SearchView: View {
    @Environment(HistoryStore.self) private var historyStore
    @Environment(ToolRegistry.self) private var toolRegistry

    let query: String
    let onSelectTool: (String) -> Void         // toolId
    let onSelectHistoryEntry: (HistoryEntry) -> Void
    let onShowHistory: () -> Void

    @State private var selectedIndex: Int = 0

    // MARK: - Merged Results

    private var merged: MergedSearchResults {
        SearchResultsMerger.merge(
            tools: toolRegistry.search(query),
            history: historyStore.search(query),
            query: query
        )
    }

    /// Flat ordered list: tools first, then history entries (for keyboard navigation).
    private var flatResults: [SearchResult] {
        merged.toolResults.map { SearchResult.tool($0) } +
        merged.historyResults.map { SearchResult.historyEntry($0) }
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
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            // UI-SPEC Copywriting: "No tools or history matching '[query]'"
            Text("No tools or history matching \"\(query)\"")
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

            // History results section
            if !merged.historyResults.isEmpty {
                Section("History") {
                    ForEach(Array(merged.historyResults.enumerated()), id: \.element.id) { idx, entry in
                        let flatIdx = merged.toolResults.count + idx
                        HistoryRowView(
                            entry: entry,
                            onOpen: { onSelectHistoryEntry(entry) },
                            onPin: { historyStore.togglePin(entry: entry) },
                            onDelete: { historyStore.delete(entry: entry) }
                        )
                        .background(selectedIndex == flatIdx ? Color.accentColor.opacity(0.1) : .clear)
                        .cornerRadius(4)
                        .accessibilityAddTraits(selectedIndex == flatIdx ? .isSelected : [])
                    }
                }
            }

            // "Show all history" shortcut when query is partial match for "history"
            if "history".hasPrefix(query.lowercased()) && query.count >= 2 {
                Button(action: onShowHistory) {
                    HStack(spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundColor(.accentColor)
                            .frame(width: 24)
                        Text("Show full history…")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
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
        case .historyEntry(let entry):
            onSelectHistoryEntry(entry)
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
        .background(isSelected ? Color.accentColor.opacity(0.1) : .clear)
        .cornerRadius(4)
        .accessibilityLabel(tool.name)
    }
}
