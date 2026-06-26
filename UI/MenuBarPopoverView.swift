// UI/MenuBarPopoverView.swift
// The main 480×600 popover — search-first launcher (D-01).
// Search bar autofocused, detection banner (D-04), 6 pinned tools (D-13), recent history.
// Global keyboard shortcuts (INFRA-16):
//   ⌘K / ⌘F — focus search bar
//   ⌘H — toggle history panel (D-07)
//   ⌘N — open workspace window (INFRA-02)
//   ⌘, — preferences (INFRA-12)
//   ⌘] — next tool in registry
//   ⌘[ — previous tool in registry
//   ⌘Delete — clear input (broadcast via .clearInput notification)
//   ⌘⇧V — paste-and-detect (reads clipboard, triggers detection banner)
//   Esc — two-stage: back to launcher / close popover (D-03)
//   ⌘⇧Space — open/focus popover (KeyboardShortcuts, wired in HotkeyManager)
// Source: RESEARCH.md Pattern 1 + UI-SPEC.md § "Popover Layout"

import SwiftUI
import AppKit

// MARK: - Notification Names (INFRA-16)

extension Notification.Name {
    /// Broadcast by MenuBarPopoverView when the user presses ⌘Delete (clear input).
    /// Tool views observe this to clear their input field.
    static let clearInput = Notification.Name("lathe.clearInput")
    /// Broadcast by MenuBarPopoverView when the user presses ⌘C (copy output).
    /// Tool views observe this to copy their primary output to the clipboard.
    static let copyOutput = Notification.Name("lathe.copyOutput")
    /// Broadcast by HotkeyManager when ⌘⇧Space fires (open/focus popover).
    /// Already defined in HotkeyManager.swift — re-exported here for documentation.
    // static let showPopover = Notification.Name("lathe.showPopover") // defined in HotkeyManager
    /// Broadcast by MenuBarPopoverView when the user presses ⌘⇧V (paste-and-detect).
    /// Triggers immediate clipboard detection and shows the DetectionBannerView (INFRA-16).
    static let pasteAndDetect = Notification.Name("lathe.pasteAndDetect")
}

/// Navigation state for the popover.
enum PopoverNavigationState: Equatable {
    case root                        // launcher: search + pinned + recent history
    case tool(toolId: String)        // inside a tool view
    case searchResults(query: String) // showing search results
    case history                     // D-07: first-class history view
}

struct MenuBarPopoverView: View {
    @Environment(HistoryStore.self) private var historyStore
    @Environment(ToolRegistry.self) private var toolRegistry
    @Environment(ClipboardDetector.self) private var clipboard
    @Environment(PreferencesStore.self) private var prefs
    @Environment(ToolSeed.self) private var toolSeed
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    @State private var searchText: String = ""
    @State private var navigationState: PopoverNavigationState = .root
    @State private var dismissedDetection: Bool = false
    @FocusState private var searchFocused: Bool
    /// Local keyDown monitor for Esc. Installed while the popover is on screen so Esc is caught
    /// regardless of which AppKit first responder holds focus — the SyntaxEditorView NSTextView,
    /// the history List's NSTableView, or none. SwiftUI's `.onKeyPress(.escape)` only fires when
    /// the popover subtree itself holds key focus, so it silently fails whenever a descendant
    /// responder (text view / table) swallows Esc first (UAT Test 16). A local monitor sees the
    /// event before responder dispatch and covers every focus state with one mechanism.
    @State private var escMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            // Zone 1: Search bar (D-01) — always visible at top
            searchBar

            // Zone 2: Detection banner (D-04) — slides in when there's a detection
            if let result = clipboard.detectionResult, !dismissedDetection, searchText.isEmpty {
                DetectionBannerView(
                    result: result,
                    onAccept: {
                        dismissedDetection = true
                        // Seed the tool with the detected clipboard value so accepting the
                        // banner pre-fills it (e.g. #3366FF lands in Color Converter).
                        // makeView() is frozen and takes no arg, so we hand off via ToolSeed.
                        if let clip = NSPasteboard.general.string(forType: .string) {
                            toolSeed.set(toolId: result.toolId, value: clip)
                        }
                        navigationState = .tool(toolId: result.toolId)
                    },
                    onDismiss: {
                        dismissedDetection = true
                    }
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeOut(duration: 0.15), value: clipboard.detectionResult != nil)
            }

            Divider()

            // Zone 3: Pinned tools row (D-13) — visible at root
            if navigationState == .root && searchText.isEmpty {
                PinnedToolBarView(onSelectTool: { toolId in
                    navigationState = .tool(toolId: toolId)
                })
                Divider()
            }

            // Zone 4: Body — recent history, search results, or active tool
            bodyContent
        }
        .frame(width: 480, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .onChange(of: clipboard.detectionResult) { _, _ in
            // D-05: re-show banner on any new detection (reset dismissal)
            dismissedDetection = false
        }
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty {
                if case .searchResults = navigationState {
                    navigationState = .root
                }
            } else if newValue.trimmingCharacters(in: .whitespaces).lowercased() == "history" {
                // D-07: "history" query opens the first-class history view
                navigationState = .history
            } else {
                navigationState = .searchResults(query: newValue)
            }
        }
        .onAppear {
            searchFocused = true
            // Start clipboard detection with the registry (called here so toolRegistry is ready)
            clipboard.start(registry: toolRegistry)
            installEscMonitor()
        }
        .onDisappear {
            removeEscMonitor()
        }
        // Handle hotkey notification (show popover)
        .onReceive(NotificationCenter.default.publisher(for: .showPopover)) { _ in
            clipboard.isPopoverPresented = true
        }
        // DIST-01 (D-02): Services match → navigate to the matched tool. The tool view consumes
        // the staged ToolSeed on its .onAppear, exactly like the clipboard-accept path above.
        .onReceive(NotificationCenter.default.publisher(for: .routeServiceMatch)) { notification in
            guard let toolId = notification.userInfo?["toolId"] as? String else { return }
            dismissedDetection = true
            searchText = ""
            navigationState = .tool(toolId: toolId)
        }
        // DIST-01 (D-03): Services no-match → stage the text in the search field so the user
        // picks a tool manually. Never a dead end.
        .onReceive(NotificationCenter.default.publisher(for: .routeServiceNoMatch)) { notification in
            guard let text = notification.userInfo?["text"] as? String else { return }
            searchText = text
            navigationState = .searchResults(query: text)
        }
        // INFRA-16: Global keyboard shortcuts — wired via hidden overlay buttons in .background()
        // ⌘H — toggle history panel (D-07)
        .background(
            Group {
                // ⌘K — focus search
                Button("Focus Search") { focusSearch() }
                    .keyboardShortcut("k", modifiers: .command)
                    .accessibilityHidden(true)
                    .hidden()

                // ⌘F — focus search (alternative)
                Button("Find") { focusSearch() }
                    .keyboardShortcut("f", modifiers: .command)
                    .accessibilityHidden(true)
                    .hidden()

                // ⌘H — toggle history panel
                Button("Toggle History") { toggleHistory() }
                    .keyboardShortcut("h", modifiers: .command)
                    .accessibilityHidden(true)
                    .hidden()

                // ⌘N — open workspace window (INFRA-02)
                // WindowCoordinator.openWorkspace() handles the activation-policy dance (Pitfall #2).
                // openWindow(id:) only works if the WindowGroup has already been loaded;
                // WindowCoordinator posts .openWorkspace which the window listens to.
                Button("New Window") {
                    WindowCoordinator.shared.openWorkspace()
                    openWindow(id: "workspace")
                    clipboard.isPopoverPresented = false
                }
                .keyboardShortcut("n", modifiers: .command)
                .accessibilityHidden(true)
                .hidden()

                // ⌘] — next tool
                Button("Next Tool") { navigateTool(direction: .next) }
                    .keyboardShortcut("]", modifiers: .command)
                    .accessibilityHidden(true)
                    .hidden()

                // ⌘[ — previous tool
                Button("Previous Tool") { navigateTool(direction: .previous) }
                    .keyboardShortcut("[", modifiers: .command)
                    .accessibilityHidden(true)
                    .hidden()

                // ⌘Delete — clear input (broadcast to active tool)
                Button("Clear Input") {
                    NotificationCenter.default.post(name: .clearInput, object: nil)
                    searchText = ""
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .accessibilityHidden(true)
                .hidden()

                // ⌘, — preferences (INFRA-12)
                // pitfall #2: openSettings() is broken on macOS 14 with .accessory.
                // Use WindowCoordinator activation dance instead.
                Button("Preferences") {
                    WindowCoordinator.shared.openPreferences()
                    clipboard.isPopoverPresented = false
                }
                .keyboardShortcut(",", modifiers: .command)
                .accessibilityHidden(true)
                .hidden()

                // ⌘⇧C — copy output (broadcast; system ⌘C handles text fields)
                Button("Copy Output") {
                    NotificationCenter.default.post(name: .copyOutput, object: nil)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .accessibilityHidden(true)
                .hidden()

                // ⌘⇧V — paste-and-detect (INFRA-16)
                // Reads the current clipboard and triggers detection regardless of change-count.
                // Resets dismissedDetection so the banner re-appears even if the user had closed it.
                // Works while the popover is open (isPopoverPresented is true at this point).
                Button("Paste and Detect") {
                    dismissedDetection = false
                    clipboard.triggerDetect()
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
                .accessibilityHidden(true)
                .hidden()
            }
        )
    }

    // MARK: - Keyboard Action Helpers (INFRA-16)

    private func focusSearch() {
        searchFocused = true
        // If inside a tool, come back to root first so search is visible
        if case .tool = navigationState {
            navigationState = .root
            searchText = ""
        }
    }

    private func toggleHistory() {
        if navigationState == .history {
            navigationState = .root
            searchText = ""
        } else {
            navigationState = .history
        }
    }

    private enum ToolDirection { case next, previous }

    private func navigateTool(direction: ToolDirection) {
        let tools = toolRegistry.tools
        guard !tools.isEmpty else { return }

        if case .tool(let currentId) = navigationState {
            guard let idx = tools.firstIndex(where: { $0.id == currentId }) else { return }
            let newIdx: Int
            switch direction {
            case .next: newIdx = (idx + 1) % tools.count
            case .previous: newIdx = (idx - 1 + tools.count) % tools.count
            }
            navigationState = .tool(toolId: tools[newIdx].id)
        } else {
            // Not in a tool yet — open first/last
            let tool = direction == .next ? tools.first : tools.last
            if let t = tool { navigationState = .tool(toolId: t.id) }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .accessibilityHidden(true)

            TextField("Search tools or history…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($searchFocused)
                .accessibilityLabel("Search tools or history")
                .onSubmit {
                    // Enter selects first search result
                    if case .searchResults(let q) = navigationState {
                        let results = toolRegistry.search(q)
                        if let first = results.first {
                            navigationState = .tool(toolId: first.id)
                            searchText = ""
                        }
                    }
                }

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Body Content

    @ViewBuilder
    private var bodyContent: some View {
        switch navigationState {
        case .root:
            // Recent history (last 5 entries)
            recentHistoryView

        case .searchResults(let query):
            SearchView(
                query: query,
                onSelectTool: { toolId in
                    navigationState = .tool(toolId: toolId)
                    searchText = ""
                },
                onSelectHistoryEntry: { entry in
                    navigationState = .tool(toolId: entry.tool)
                    searchText = ""
                },
                onShowHistory: {
                    navigationState = .history
                }
            )

        case .history:
            // D-07: First-class history view
            HistoryPanelView(onRestoreEntry: { entry in
                // D-08: restore input into matched tool; output always recomputed live
                navigationState = .tool(toolId: entry.tool)
                searchText = ""
            })

        case .tool(let toolId):
            if let tool = toolRegistry.tools.first(where: { $0.id == toolId }) {
                tool.makeView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("Tool Not Found", systemImage: "questionmark")
            }
        }
    }

    // MARK: - Recent History

    private var recentHistoryView: some View {
        let recent = Array(historyStore.entries.prefix(5))
        return Group {
            if recent.isEmpty {
                // Empty state (D-01)
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("Welcome to Flint")
                        .font(.headline)
                    Text("Paste content or press ⌘⇧Space from any app to get started.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(recent, id: \.id) { entry in
                    HistoryRowView(
                        entry: entry,
                        onOpen: {
                            navigationState = .tool(toolId: entry.tool)
                        },
                        onPin: { historyStore.togglePin(entry: entry) },
                        onDelete: { historyStore.delete(entry: entry) }
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                }
                .listStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Esc Handler (Two-Stage, D-03)

    private func handleEscape() {
        if case .root = navigationState, searchText.isEmpty {
            // Stage 2: close popover
            clipboard.isPopoverPresented = false
        } else {
            // Stage 1: return to launcher
            navigationState = .root
            searchText = ""
        }
    }

    /// Install a local keyDown monitor that runs the two-stage Esc handler for any Esc press
    /// while the popover is on screen, no matter which first responder is focused. Returning nil
    /// consumes the event (so the focused text view / table never sees its own cancelOperation);
    /// any other key is returned untouched. keyCode 53 is Esc. Idempotent.
    private func installEscMonitor() {
        guard escMonitor == nil else { return }
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                handleEscape()
                return nil
            }
            return event
        }
    }

    private func removeEscMonitor() {
        if let monitor = escMonitor {
            NSEvent.removeMonitor(monitor)
            escMonitor = nil
        }
    }
}

// HistoryRowView is defined in UI/Components/HistoryRowView.swift
