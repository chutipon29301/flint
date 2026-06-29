// UI/AllToolsGridView.swift
// All-Tools Grid (D-01) — shows all registered tools in a fixed 4-column grid.
// Stateless: navigation state lives in MenuBarPopoverView. Caller provides onSelect callback.
// When `filter` is non-empty, the grid shows only tools matching the query (in-place search).
//
// Design: 04-UI-SPEC.md § "All-Tools Grid — D-01"
// Pattern: UI/Components/PinnedToolBarView.swift (registry iteration + hover tile pattern)
// Accessibility: .accessibilityLabel(tool.name) + .accessibilityHint("Open \(tool.name)")
// Colors: semantic only (INFRA-14) — .accentColor, .quaternary, .primary

import SwiftUI

struct AllToolsGridView: View {
    @Environment(ToolRegistry.self) private var toolRegistry

    /// Optional search query. Empty = show all tools; non-empty = filter the grid in-place.
    var filter: String = ""

    /// Callback invoked with the selected tool's id. Caller sets `navigationState = .tool(toolId:)`.
    let onSelect: (String) -> Void

    // Fixed 4-column grid so every tile is the same width regardless of how many tools exist.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    private var tools: [ToolDefinition] {
        let q = filter.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? toolRegistry.tools : toolRegistry.search(q)
    }

    var body: some View {
        Group {
            if tools.isEmpty {
                // In-place "no match" state (only reachable while filtering).
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text("No tools matching \"\(filter)\"")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(tools) { tool in
                        ToolGridTile(tool: tool, onSelect: onSelect)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Grid Tile

/// Single tile in the all-tools grid. Owns hover state so AllToolsGridView stays state-free.
/// Fixed height so tiles with one-line and two-line labels render at identical size.
private struct ToolGridTile: View {
    let tool: ToolDefinition
    let onSelect: (String) -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: { onSelect(tool.id) }) {
            VStack(spacing: 6) {
                Image(systemName: tool.sfSymbol)
                    .font(.system(size: 20))
                    .foregroundColor(.accentColor)

                Text(tool.name)
                    .font(.system(size: 11))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity) // ponytail: width fills column; height fixed by tile frame below
            }
            .frame(maxWidth: .infinity)
            .frame(height: 72) // equal-size tiles regardless of label length
            .padding(.horizontal, 4)
            .background(
                Color(NSColor.quaternaryLabelColor).opacity(isHovered ? 1.0 : 0.6)
            )
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tool.name)
        .accessibilityHint("Open \(tool.name)")
        .onHover { hovered in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovered
            }
        }
    }
}
