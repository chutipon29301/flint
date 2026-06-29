// UI/AllToolsGridView.swift
// All-Tools Grid (D-01) — shows all 12 registered tools in a 3-column adaptive grid.
// Stateless: navigation state lives in MenuBarPopoverView. Caller provides onSelect callback.
//
// Design: 04-UI-SPEC.md § "All-Tools Grid — D-01"
// Pattern: UI/Components/PinnedToolBarView.swift (registry iteration + hover tile pattern)
// Accessibility: .accessibilityLabel(tool.name) + .accessibilityHint("Open \(tool.name)")
// Colors: semantic only (INFRA-14) — .accentColor, .quaternary, .primary

import SwiftUI

struct AllToolsGridView: View {
    @Environment(ToolRegistry.self) private var toolRegistry

    /// Callback invoked with the selected tool's id. Caller sets `navigationState = .tool(toolId:)`.
    let onSelect: (String) -> Void

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 100, maximum: 140), spacing: 8)],
            spacing: 8
        ) {
            ForEach(toolRegistry.tools) { tool in
                ToolGridTile(tool: tool, onSelect: onSelect)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Grid Tile

/// Single tile in the all-tools grid. Owns hover state so AllToolsGridView stays state-free.
private struct ToolGridTile: View {
    let tool: ToolDefinition
    let onSelect: (String) -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: { onSelect(tool.id) }) {
            VStack(spacing: 8) {
                Image(systemName: tool.sfSymbol)
                    .font(.system(size: 22))
                    .foregroundColor(.accentColor)

                Text(tool.name)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
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
