// UI/MainWindowView.swift
// Detachable workspace window (INFRA-02) — NavigationSplitView with all seven tools.
// Min 800×600; remembers last-open tool per tool (last mode persisted in PreferencesStore).
// Opens via NotificationCenter + WindowCoordinator activation-policy dance (Pattern 1/7).
// Source: RESEARCH.md Pattern 1, Pattern 7, § "Phase Requirements" INFRA-02

import SwiftUI

struct MainWindowView: View {
    @Environment(ToolRegistry.self) private var toolRegistry
    @Environment(PreferencesStore.self) private var prefs
    @Environment(ClipboardDetector.self) private var clipboard
    @Environment(ToolSeed.self) private var toolSeed

    // Persisted last-selected tool ID — restored on reopen (INFRA-02)
    @State private var selectedToolId: String? = nil

    // DIST-02: launcher-style drop on the workspace chrome (mirrors MenuBarPopoverView.fileDrop).
    @State private var isDragTargeted = false
    @State private var dropError: String?

    var body: some View {
        NavigationSplitView {
            // Sidebar: list of all registered tools
            List(toolRegistry.tools, selection: $selectedToolId) { tool in
                Label(tool.name, systemImage: tool.sfSymbol)
                    .tag(tool.id)
                    .accessibilityLabel(tool.name)
                    .help(tool.name)
            }
            .navigationTitle("Flint")
            .listStyle(.sidebar)
            .accessibilityLabel("Tool list")
        } detail: {
            // Detail pane hosts the post-drop banner so it lands BELOW the window toolbar
            // and does not overlap the sidebar (a window-wide overlay floats over both panes).
            VStack(spacing: 0) {
                // DIST-02 (D-06): post-drop rejection surface — binary/oversized/no-match dropped
                // on the chrome is reported here AFTER the drop, never during drag. Tap to dismiss.
                if let dropError {
                    HStack(spacing: 8) {
                        WarningBannerView(message: dropError, severity: .warning)
                        Button(action: { self.dropError = nil }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dismiss notice")
                        .help("Dismiss")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if let toolId = selectedToolId,
                   let tool = toolRegistry.tools.first(where: { $0.id == toolId }) {
                    tool.makeView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView(
                        "Select a Tool",
                        systemImage: "wrench.and.screwdriver",
                        description: Text("Choose a tool from the sidebar to get started.")
                    )
                    .accessibilityLabel("No tool selected. Choose a tool from the sidebar.")
                }
            }
            .animation(.easeOut(duration: 0.15), value: dropError)
        }
        // INFRA-02: cannot shrink below 800×600
        .frame(minWidth: 800, minHeight: 600)
        // DIST-02 (D-04): launcher drop on the workspace — read file text, run detect(),
        // select + pre-fill the best tool. Per-tool drops in the detail pane are handled by
        // each tool's own .fileDrop (innermost target wins). Binary/oversized → onError banner.
        .fileDrop(
            isTargeted: $isDragTargeted,
            onText: { text in
                dropError = nil
                if let result = toolRegistry.detect(from: text) {
                    toolSeed.set(toolId: result.toolId, value: text)
                    selectedToolId = result.toolId
                } else {
                    // No search field in the workspace chrome (D-03 analog): a non-destructive
                    // post-drop notice instead of staging — never a dead end, never a crash.
                    dropError = "No matching tool for that text — pick a tool from the sidebar and drop again, or paste it in."
                }
            },
            onError: { message in
                dropError = message
            }
        )
        .overlay {
            if isDragTargeted {
                DropOverlayView(label: "Drop to open in best tool")
                    .transition(.opacity.animation(.easeOut(duration: 0.15)))
            }
        }
        .onAppear {
            // Restore last-open tool from PreferencesStore (INFRA-02)
            let lastTool = prefs.lastWorkspaceToolId
            if let id = lastTool, toolRegistry.tools.contains(where: { $0.id == id }) {
                selectedToolId = id
            } else if selectedToolId == nil {
                // Default: JSON Formatter
                selectedToolId = "json-formatter"
            }
        }
        .onChange(of: selectedToolId) { _, newId in
            // Persist last-open tool for next reopen (INFRA-02)
            if let id = newId {
                prefs.lastWorkspaceToolId = id
            }
        }
        .onDisappear {
            // Restore .accessory policy when workspace closes (Pattern 7)
            WindowCoordinator.shared.windowWillClose()
        }
        // Handle .openWorkspace notification (Pattern 1 — NotificationCenter bridge)
        .onReceive(NotificationCenter.default.publisher(for: .openWorkspace)) { _ in
            // Window is already open when this fires (WindowCoordinator sends after activation)
            // No additional action needed — WindowCoordinator.openWorkspace() handles activation
        }
        // INFRA-16: ⌘, opens Preferences from workspace too
        .background(
            Button("Preferences") {
                WindowCoordinator.shared.openPreferences()
            }
            .keyboardShortcut(",", modifiers: .command)
            .accessibilityHidden(true)
            .hidden()
        )
    }
}
