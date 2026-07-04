// UI/MenuBarPopoverView.swift
// The main 480×600 popover — search-first launcher (D-01).
// Search bar autofocused, detection banner (D-04), all-tools grid.
// Global keyboard shortcuts (INFRA-16):
//   ⌘K / ⌘F — focus search bar
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
    case root                        // launcher: search + pinned tools
    case tool(toolId: String)        // inside a tool view
    case searchResults(query: String) // showing search results
}

struct MenuBarPopoverView: View {
    @Environment(ToolRegistry.self) private var toolRegistry
    @Environment(ClipboardDetector.self) private var clipboard
    @Environment(PreferencesStore.self) private var prefs
    @Environment(ToolSeed.self) private var toolSeed
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    @State private var searchText: String = ""
    @State private var navigationState: PopoverNavigationState = .root
    /// Index of the keyboard-selected tile in the filtered grid (↑/↓ navigation). Resets to 0
    /// whenever the query changes. Used only in the .searchResults state.
    @State private var selectedToolIndex: Int = 0
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

            // Zone 3: Body — tool grid (filtered live while typing) or active tool.
            // The old pinned-tool icon strip (D-13) was removed: it duplicated the grid below it.
            bodyContent
        }
        .frame(width: 480, height: 600, alignment: .top)
        .background(Color.graphite950)
        // Task 5 (260704-mgn follow-up): tint ONCE at the popover root so every inherited-accent
        // control (Toggle, Picker, ProgressView, text selection, .bordered buttons) reads ember
        // instead of stock system blue. Applied at the scene root, never per-control.
        .tint(Color.spark)
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
        .onChange(of: clipboard.detectionResult) { _, newResult in
            // D-05: re-show banner on any new detection (reset dismissal)
            dismissedDetection = false
            // Auto-open the detected tool (pre-filled) when we're sitting on the launcher with
            // an empty search — copying #FF5733 + ⌘⇧Space lands you straight in Color Converter.
            autoOpenDetectedTool(newResult)
        }
        .onChange(of: searchText) { _, newValue in
            selectedToolIndex = 0 // reset highlight whenever the filter changes
            if newValue.isEmpty {
                if case .searchResults = navigationState {
                    navigationState = .root
                }
            } else {
                navigationState = .searchResults(query: newValue)
            }
        }
        .onAppear {
            searchFocused = true
            // Start clipboard detection with the registry (called here so toolRegistry is ready)
            clipboard.start(registry: toolRegistry)
            // Sparkle not armed: the unsigned/ad-hoc build cannot install updates, so starting
            // the updater would only fire a background check that errors. Re-enable
            // `sparkle.start()` here when shipping the signed+notarized (release.sh) build.
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

    // MARK: - Detection Auto-Open

    /// Auto-open the detected tool (pre-filled with the clipboard value) when the user is on the
    /// launcher with an empty search. This is the "copy something + ⌘⇧Space → land in the right
    /// tool" flow. Guarded so it never yanks the user out of a tool they're already using or out
    /// of an active search.
    private func autoOpenDetectedTool(_ result: DetectionResult?) {
        guard let result else { return }
        guard case .root = navigationState, searchText.isEmpty, !dismissedDetection else { return }
        dismissedDetection = true // consume this detection so it doesn't re-trigger
        if let clip = NSPasteboard.general.string(forType: .string) {
            toolSeed.set(toolId: result.toolId, value: clip)
        }
        navigationState = .tool(toolId: result.toolId)
    }

    /// Open a tool chosen from the launcher search (type-to-filter → Enter, or click a filtered
    /// tile), pre-filled with the current clipboard value so it's ready to use immediately.
    /// Seeding an empty clipboard is a harmless no-op (the tool just opens blank).
    private func openToolFromLauncher(_ toolId: String) {
        if let clip = NSPasteboard.general.string(forType: .string), !clip.isEmpty {
            toolSeed.set(toolId: toolId, value: clip)
        }
        navigationState = .tool(toolId: toolId)
        searchText = ""
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
                .foregroundColor(.ash)
                .accessibilityHidden(true)

            TextField("Search tools…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.monoSearch)
                .foregroundColor(.chalk)
                .focused($searchFocused)
                .accessibilityLabel("Search tools")
                .onSubmit {
                    // Enter opens the SELECTED filtered tool (↑/↓ moves the selection; defaults to
                    // the first match), pre-filled with the clipboard value:
                    // copy → ⌘⇧Space → type → (↑/↓) → Enter → tool is ready to use.
                    if case .searchResults(let q) = navigationState {
                        let results = toolRegistry.search(q)
                        let idx = min(max(selectedToolIndex, 0), results.count - 1)
                        if results.indices.contains(idx) {
                            openToolFromLauncher(results[idx].id)
                        }
                    }
                }

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.ash)
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
                    .foregroundColor(.ash)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Flint in a resizable window to drag and drop files")
            .help("Open in a window to drag and drop files")

            // Preferences (gear) — was only reachable via ⌘, before; now always visible (UX).
            Button {
                openPreferences()
            } label: {
                Image(systemName: "gearshape")
                    .foregroundColor(.ash)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Preferences")
            .help("Preferences (⌘,)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: Radius.control)
                .fill(Color.graphite950)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.control)
                        .strokeBorder(searchFocused ? Color.spark : Color.graphite800, lineWidth: searchFocused ? 2 : 1)
                )
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Body Content

    @ViewBuilder
    private var bodyContent: some View {
        switch navigationState {
        case .root:
            // D-01: All-tools grid — the sole launcher surface.
            AllToolsGridView(onSelect: { toolId in
                navigationState = .tool(toolId: toolId)
            })

        case .searchResults(let query):
            // Typing filters the SAME grid in-place (no separate results page). Content hugs
            // the top; remaining space stays empty (no stretching the grid to fill the popover).
            VStack(spacing: 0) {
                AllToolsGridView(filter: query, selectedIndex: selectedToolIndex, onSelect: { toolId in
                    // Clicking a filtered tile mirrors the Enter path: open pre-filled with the
                    // clipboard value, ready to use.
                    openToolFromLauncher(toolId)
                })
                Spacer(minLength: 0)
            }

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
            // Only intercept ↑/↓ while filtering — move the grid's tile selection. The search
            // TextField holds focus, so this NSEvent monitor (runs before responder dispatch) is
            // how the arrows reach our selection state at all (Pitfall 7).
            guard case .searchResults(let query) = navigationState else { return event }
            let count = toolRegistry.search(query).count
            guard count > 0 else { return event }
            switch event.keyCode {
            case 125: // ↓ — next tile
                selectedToolIndex = min(selectedToolIndex + 1, count - 1)
                return nil // consume (prevents the NSTextField "ding")
            case 126: // ↑ — previous tile
                selectedToolIndex = max(selectedToolIndex - 1, 0)
                return nil
            default:
                return event
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
