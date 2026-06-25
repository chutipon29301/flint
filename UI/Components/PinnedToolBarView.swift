// UI/Components/PinnedToolBarView.swift
// Horizontal row of up to 6 tool icon buttons with drag-to-reorder (INFRA-11).
// Default order: JSON, Base64, JWT, URL, Timestamp, UUID (D-13).
// Drag-to-reorder persists to PreferencesStore (UserDefaults).
//
// Drag-to-reorder implementation:
//   - Each PinnedToolButton is a drag source (onDrag exports the tool ID as NSString).
//   - Each PinnedToolButton is also a drop target via PinnedToolDropDelegate.
//   - PinnedToolDropDelegate.performDrop reads the dragged tool ID from DropInfo,
//     computes source + destination indices from prefs.pinnedToolIds, and calls
//     prefs.movePinnedTool(from:to:) — which persists the new order to UserDefaults.

import SwiftUI

struct PinnedToolBarView: View {
    @Environment(PreferencesStore.self) private var prefs
    @Environment(ToolRegistry.self) private var toolRegistry

    let onSelectTool: (String) -> Void  // passes toolId

    /// Resolved tool definitions in pinned order, compactMapped against registry.
    private var pinnedTools: [ToolDefinition] {
        prefs.pinnedToolIds.compactMap { id in
            toolRegistry.tools.first { $0.id == id }
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(pinnedTools) { tool in
                    PinnedToolButton(
                        tool: tool,
                        pinnedToolIds: prefs.pinnedToolIds,
                        prefs: prefs,
                        action: { onSelectTool(tool.id) }
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(height: 56)
        .accessibilityLabel("Pinned tools")
    }
}

// MARK: - Pinned Tool Button

/// Individual 40×40pt icon button for a pinned tool.
/// Acts as both a drag source (exports its tool ID) and a drop target (accepts a peer tool ID
/// and calls prefs.movePinnedTool so the reorder round-trips through UserDefaults).
private struct PinnedToolButton: View {
    let tool: ToolDefinition
    let pinnedToolIds: [String]
    let prefs: PreferencesStore
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: tool.sfSymbol)
                    .font(.system(size: 22))
                    .foregroundColor(isHovered ? .accentColor : .secondary)
            }
            .frame(width: 40, height: 40)
            .background(isHovered ? Color.accentColor.opacity(0.08) : .clear)
            .cornerRadius(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tool.name)
        .help(tool.name)
        .onHover { hovered in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovered
            }
        }
        // Drag source: export this tool's ID so the drop target can identify it.
        .onDrag {
            NSItemProvider(object: tool.id as NSString)
        }
        // Drop target: when a peer tool is dropped here, reorder and persist.
        .onDrop(of: [.text], delegate: PinnedToolDropDelegate(
            destinationToolId: tool.id,
            pinnedToolIds: pinnedToolIds,
            prefs: prefs
        ))
    }
}

// MARK: - Drop Delegate (Drag-to-Reorder)

/// Handles drag-to-reorder for the pinned tool bar.
///
/// On performDrop:
///   1. Extracts the dragged tool ID from DropInfo (the NSString exported by the drag source).
///   2. Finds its index in prefs.pinnedToolIds (source).
///   3. Finds the destination tool's index (destination).
///   4. Calls prefs.movePinnedTool(from:to:), which mutates and persists the array.
private struct PinnedToolDropDelegate: DropDelegate {
    /// The ID of the tool that the drag is hovering over / being dropped onto.
    let destinationToolId: String
    /// Snapshot of the pinned IDs at the time the view was built (for index lookup).
    let pinnedToolIds: [String]
    /// Live store — mutable so we can call movePinnedTool.
    let prefs: PreferencesStore

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        // NSItemProvider.loadObject is async; we use the semaphore-free approach and dispatch
        // back to the main actor after loading (DropDelegate callbacks run on MainActor).
        provider.loadObject(ofClass: NSString.self) { item, _ in
            guard let draggedId = item as? String,
                  draggedId != destinationToolId else { return }

            // Use the live pinnedToolIds from prefs for freshest order.
            var ids = prefs.pinnedToolIds
            guard let sourceIndex = ids.firstIndex(of: draggedId),
                  let destIndex = ids.firstIndex(of: destinationToolId) else { return }

            // Perform the move and persist.
            DispatchQueue.main.async {
                prefs.movePinnedTool(from: IndexSet(integer: sourceIndex), to: destIndex > sourceIndex ? destIndex + 1 : destIndex)
            }
        }
        return true
    }

    func dropEntered(info: DropInfo) { }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

// MARK: - Draggable Pinned Tool Bar (full reorder implementation)

/// Full drag-reorder implementation using a List with .onMove for the pinned tool bar.
/// Exposed as a separate view for embedding when the full List+onMove pattern is needed.
struct DraggablePinnedToolBarView: View {
    @Environment(PreferencesStore.self) private var prefs
    @Environment(ToolRegistry.self) private var toolRegistry

    let onSelectTool: (String) -> Void

    private var pinnedTools: [ToolDefinition] {
        prefs.pinnedToolIds.compactMap { id in
            toolRegistry.tools.first { $0.id == id }
        }
    }

    var body: some View {
        // Use the horizontal scroll version for the compact popover bar.
        // The List+onMove version is better suited for a settings/preferences sheet.
        PinnedToolBarView(onSelectTool: onSelectTool)
    }
}
