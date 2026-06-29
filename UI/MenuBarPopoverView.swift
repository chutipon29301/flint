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
    /// Broadcast by MenuBarPopoverView when the user presses ⌘1–⌘9 (row copy D-08).
    /// userInfo["index"]: Int — the 1-based row number to copy. Tool views observe this to copy
    /// the output at that row index. Out-of-range indices are a silent no-op (CF-01, T-04-06).
    static let selectOutputRow = Notification.Name("lathe.selectOutputRow")
    /// Broadcast by the D-07 arrow-key NSEvent monitor in MenuBarPopoverView when ↑/↓ is pressed
    /// while the search TextField has focus and .onKeyPress is unreliable (Pitfall 7).
    /// userInfo["direction"]: Int — (-1) for ↑ (keyCode 126), (+1) for ↓ (keyCode 125).
    /// SearchView observes this to move selectedIndex; fires ONLY in the .searchResults state.
    static let searchNavigate = Notification.Name("lathe.searchNavigate")
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
    // DIST-04: Sparkle updater — started lazily from .onAppear (off cold-start path).
    @Environment(SparkleUpdaterService.self) private var sparkle
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    @State private var searchText: String = ""
    @State private var navigationState: PopoverNavigationState = .root
    @State private var dismissedDetection: Bool = false
    @FocusState private var searchFocused: Bool
    // DIST-02 (D-04 / D-06): launcher file drop. A dropped text file is decoded off-main, run
    // through detect(), and routed to the best tool (or staged in search on no match). Binary /
    // oversized files surface POST-DROP via `dropError` → WarningBannerView (never during drag).
    @State private var isDragTargeted = false
    @State private var dropError: String?
    /// Local keyDown monitor for Esc. Installed while the popover is on screen so Esc is caught
    /// regardless of which AppKit first responder holds focus — the SyntaxEditorView NSTextView,
    /// the history List's NSTableView, or none. SwiftUI's `.onKeyPress(.escape)` only fires when
    /// the popover subtree itself holds key focus, so it silently fails whenever a descendant
    /// responder (text view / table) swallows Esc first (UAT Test 16). A local monitor sees the
    /// event before responder dispatch and covers every focus state with one mechanism.
    @State private var escMonitor: Any?
    /// D-07 fallback: local keyDown monitor for ↑/↓ arrow keys (keyCodes 126/125) when the search
    /// TextField holds focus and SwiftUI's `.onKeyPress(.upArrow/.downArrow)` in SearchView is
    /// unreliable (Pitfall 7 / RESEARCH Open Question 1 — TextField may swallow arrow events before
    /// they reach sibling views). The monitor fires only while in the .searchResults navigation state;
    /// all other keys and all other states are passed through unchanged. Posting .searchNavigate
    /// updates SearchView's selectedIndex without needing to move @State up to this view.
    @State private var arrowMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            // Zone 1: Search bar (D-01) — always visible at top
            searchBar

            // DIST-02 (D-06): post-drop rejection surface — a binary/oversized file dropped on the
            // launcher (text path) is reported here AFTER the drop, never during drag.
            if let dropError {
                WarningBannerView(message: dropError, severity: .warning)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

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

            // Zone 3: Body — tool grid (filtered live while typing), history, or active tool.
            // The old pinned-tool icon strip (D-13) was removed: it duplicated the grid below it.
            bodyContent
        }
        .frame(width: 480, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
        // DIST-02 (D-04): launcher drop — read file text, run detect(), route to best tool;
        // no-match stages the text in the search field (mirrors Services D-03). Binary/oversized
        // is rejected post-drop via WarningBannerView (D-06).
        .fileDrop(
            isTargeted: $isDragTargeted,
            onText: { text in
                dropError = nil
                if let result = toolRegistry.detect(from: text) {
                    toolSeed.set(toolId: result.toolId, value: text)
                    searchText = ""
                    navigationState = .tool(toolId: result.toolId)
                } else {
                    searchText = text
                    navigationState = .searchResults(query: text)
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
            // DIST-04: lazily arm Sparkle here (NOT at app init) so SPUStandardUpdaterController
            // construction stays off the cold-start critical path (RESEARCH Pitfall #6).
            // Idempotent — guarded internally so repeated popover appearances are no-ops.
            sparkle.start()
            installEscMonitor()
            installArrowMonitor()
            // DIST-03: first-run onboarding gate. A single synchronous UserDefaults bool read —
            // no async/database work, so the cold-start critical path is not regressed (Pitfall
            // #6/#7). Runs only once: the onboarding window's dismiss sets hasSeenOnboarding=true.
            if !prefs.hasSeenOnboarding {
                WindowCoordinator.shared.openOnboarding()
            }
        }
        .onDisappear {
            removeEscMonitor()
            removeArrowMonitor()
        }
        // Handle hotkey notification (show popover)
        .onReceive(NotificationCenter.default.publisher(for: .showPopover)) { _ in
            clipboard.isPopoverPresented = true
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
                Button("Preferences") { openPreferences() }
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

                // ⌘1–⌘9 — row copy (D-08, INFRA-16). Uses digit key characters, NOT the letter N.
                // The existing ⌘N (letter) "Open workspace window" shortcut is unaffected (Pitfall 4).
                // Out-of-range indices (e.g. ⌘7 on a 4-row tool) are a silent no-op in each
                // tool's .selectOutputRow observer — never crashes (CF-01, T-04-06).
                ForEach(1...9, id: \.self) { index in
                    Button("Copy Output \(index)") {
                        NotificationCenter.default.post(
                            name: .selectOutputRow,
                            object: nil,
                            userInfo: ["index": index]
                        )
                    }
                    .keyboardShortcut(KeyEquivalent(Character(String(index))), modifiers: .command)
                    .accessibilityHidden(true)
                    .hidden()
                }
            }
        )
    }

    // MARK: - Keyboard Action Helpers (INFRA-16)

    /// Open the Settings window. The app runs as `.accessory` (no Dock icon), so a settings
    /// window opens *behind* the frontmost app unless we first switch to `.regular` and activate.
    /// After the activation dance we call SwiftUI's supported `openSettings()` action (the raw
    /// `showPreferencesWindow:`/`showSettingsWindow:` selectors do not resolve on macOS 14+).
    private func openPreferences() {
        clipboard.isPopoverPresented = false
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            openSettings()
        }
        WindowCoordinator.shared.notePreferencesOpened() // tracks windowCount for .accessory restore
    }

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

            // DIST-02: always-visible path to the drag-and-drop workspace. The popover NSPanel
            // dismisses on the Finder click needed to grab a file, so file drops live in the
            // resizable workspace window. Mirrors the hidden ⌘N handler.
            Button {
                WindowCoordinator.shared.openWorkspace()
                openWindow(id: "workspace")
                clipboard.isPopoverPresented = false
            } label: {
                Image(systemName: "macwindow")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Flint in a resizable window to drag and drop files")
            .help("Open in a window to drag and drop files")

            // Preferences (gear) — was only reachable via ⌘, before; now always visible (UX).
            Button {
                openPreferences()
            } label: {
                Image(systemName: "gearshape")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Preferences")
            .help("Preferences (⌘,)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Body Content

    @ViewBuilder
    private var bodyContent: some View {
        switch navigationState {
        case .root:
            // D-01: All-tools grid above recent history.
            VStack(spacing: 0) {
                AllToolsGridView(onSelect: { toolId in
                    navigationState = .tool(toolId: toolId)
                })
                Divider()
                recentHistoryView
            }

        case .searchResults(let query):
            // Typing filters the SAME grid in-place (no separate results page) and filters
            // the history list below it. Content hugs the top; remaining space stays empty
            // (no stretching the grid/history to fill the popover).
            let historyMatches = historyStore.search(query)
            VStack(spacing: 0) {
                AllToolsGridView(filter: query, onSelect: { toolId in
                    navigationState = .tool(toolId: toolId)
                    searchText = ""
                })
                if !historyMatches.isEmpty {
                    Divider()
                    filteredHistoryList(historyMatches)
                }
                Spacer(minLength: 0)
            }

        case .history:
            // D-07: First-class history view
            HistoryPanelView(onRestoreEntry: { entry in
                // D-08: restore input into matched tool; output always recomputed live
                navigationState = .tool(toolId: entry.tool)
                searchText = ""
            })

        case .tool(let toolId):
            // D-02: ToolHeaderView wraps every tool uniformly — added here at the switch site
            // so individual tool views stay unchanged. Back button sets navigationState = .root,
            // the same target as Esc stage-1 (both affordances coexist, no change to escMonitor).
            if let tool = toolRegistry.tools.first(where: { $0.id == toolId }) {
                VStack(spacing: 0) {
                    ToolHeaderView(toolName: tool.name, onBack: { navigationState = .root })
                    tool.makeView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
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

    /// History list filtered by the search query (shown below the filtered grid while typing).
    /// Bounded height so it wraps its content instead of stretching to fill the popover.
    private func filteredHistoryList(_ matches: [HistoryEntry]) -> some View {
        List(matches, id: \.id) { entry in
            HistoryRowView(
                entry: entry,
                onOpen: {
                    navigationState = .tool(toolId: entry.tool)
                    searchText = ""
                },
                onPin: { historyStore.togglePin(entry: entry) },
                onDelete: { historyStore.delete(entry: entry) }
            )
            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
        }
        .listStyle(.plain)
        .frame(maxWidth: .infinity)
        .frame(maxHeight: 240) // ponytail: cap; longer history scrolls inside the List
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

    // MARK: - D-07 Arrow Key Monitor (fallback for TextField-focused search nav)

    /// Install a local keyDown monitor that intercepts ↑/↓ (keyCodes 126/125) ONLY when the
    /// popover is in the .searchResults navigation state. In all other states or for all other
    /// keys, events are returned untouched. Coexists with the Esc monitor: the Esc monitor handles
    /// keyCode 53 and passes everything else through; this monitor intercepts only 125/126 in the
    /// search-results state. There is no overlap. Idempotent.
    ///
    /// This is the D-07 fallback for Pitfall 7: SwiftUI `.onKeyPress(.upArrow/.downArrow)` on
    /// SearchView may not fire when the search TextField (in MenuBarPopoverView.searchBar, a sibling
    /// view) holds AppKit first responder focus and swallows arrow-key events before they propagate
    /// to sibling SwiftUI views. The NSEvent local monitor runs before AppKit responder dispatch,
    /// guaranteeing the arrows reach SearchView regardless of focus state.
    private func installArrowMonitor() {
        guard arrowMonitor == nil else { return }
        // NOTE: MenuBarPopoverView is a SwiftUI struct. The closure captures `self` by value.
        // @State variables in Swift are backed by heap storage; reading `navigationState` in this
        // closure always returns the current live value (same underlying StateStorage box).
        // This is the same mechanism used by the existing Esc monitor (installEscMonitor) which
        // reads state indirectly via handleEscape(). Capturing without [weak self] is correct for
        // struct types — there is no retain cycle because structs cannot be captured weakly.
        arrowMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            // Only intercept in search-results state (D-07 spec: "fires ONLY in .searchResults")
            guard case .searchResults = navigationState else { return event }
            switch event.keyCode {
            case 125: // ↓ — move selection down
                NotificationCenter.default.post(
                    name: .searchNavigate,
                    object: nil,
                    userInfo: ["direction": 1]
                )
                return nil // consume the event (prevents system "ding" from NSTextField)
            case 126: // ↑ — move selection up
                NotificationCenter.default.post(
                    name: .searchNavigate,
                    object: nil,
                    userInfo: ["direction": -1]
                )
                return nil // consume the event
            default:
                return event // pass all other keys through unchanged
            }
        }
    }

    private func removeArrowMonitor() {
        if let monitor = arrowMonitor {
            NSEvent.removeMonitor(monitor)
            arrowMonitor = nil
        }
    }
}

// HistoryRowView is defined in UI/Components/HistoryRowView.swift
