// App/FlintApp.swift
// @main app entry point — service ownership, MenuBarExtra + MenuBarExtraAccess wiring.
// Services are @State (only lifecycle-stable ownership point — Pattern 1).
// Source: RESEARCH.md Pattern 1 [VERIFIED]
//
// NOTE: MenuBarExtraAccess.menuBarExtraAccess() is an extension on MenuBarExtra, not Scene.
// It must be applied BEFORE .menuBarExtraStyle() — the order matters.
//
// NOTE: openSettings() is broken on macOS 14 with .accessory policy (Pitfall #2).
// MenuBarPopoverView handles ⌘, via WindowCoordinator.openPreferences() instead.

import SwiftUI
import MenuBarExtraAccess

@main
struct FlintApp: App {
    // MARK: - Service Ownership (Pattern 1)
    // All shared services live here — the only lifecycle-stable ownership point.
    // Tool ViewModels are created on-demand per navigation destination.

    // DIST-01: AppDelegate registers the Services provider + refreshes the Services cache.
    // Declared before the @State block (NSApplicationDelegateAdaptor placement convention).
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State private var historyStore = HistoryStore()
    @State private var prefs = PreferencesStore()
    @State private var clipboard = ClipboardDetector()
    @State private var hotkeyManager = HotkeyManager()
    @State private var toolRegistry = ToolRegistry()
    @State private var toolSeed = ToolSeed()

    var body: some Scene {
        // MARK: - MenuBar Popover
        // MenuBarExtraAccess must be applied before .menuBarExtraStyle (extension on MenuBarExtra)
        MenuBarExtra("Flint", systemImage: "wrench.and.screwdriver") {
            MenuBarPopoverView()
                .environment(historyStore)
                .environment(prefs)
                .environment(clipboard)
                .environment(toolRegistry)
                .environment(toolSeed)
                .preferredColorScheme(prefs.theme.colorScheme)  // INFRA-14 live theme
                // WR-04: sync historyLimit from PreferencesStore into HistoryStore whenever it changes
                .onChange(of: prefs.historyLimit, initial: true) { _, newLimit in
                    historyStore.historyLimit = newLimit
                }
                // DIST-01: receive Services text on @MainActor, route via FROZEN detect() + ToolSeed.
                // The MenuBarExtra content is created at launch, so this subscription is in place
                // before any user-triggered service invocation can arrive.
                .onReceive(NotificationCenter.default.publisher(for: .serviceDidReceiveText)) { notification in
                    guard let text = notification.userInfo?["text"] as? String else { return }
                    if let result = toolRegistry.detect(from: text) {
                        // D-02: auto-open the matched tool pre-filled, skipping the detection banner.
                        toolSeed.set(toolId: result.toolId, value: text)
                        WindowCoordinator.shared.openToolViaService(toolId: result.toolId)
                        NotificationCenter.default.post(
                            name: .routeServiceMatch,
                            object: nil,
                            userInfo: ["toolId": result.toolId]
                        )
                    } else {
                        // D-03: no match → open launcher with text staged in the search field.
                        WindowCoordinator.shared.openLauncherWithStagedText(text)
                        NotificationCenter.default.post(
                            name: .routeServiceNoMatch,
                            object: nil,
                            userInfo: ["text": text]
                        )
                    }
                }
        }
        .menuBarExtraAccess(isPresented: $clipboard.isPopoverPresented)
        .menuBarExtraStyle(.window)

        // MARK: - Detachable Workspace Window (INFRA-02)
        WindowGroup(id: "workspace") {
            MainWindowView()
                .environment(historyStore)
                .environment(prefs)
                .environment(clipboard)
                .environment(toolRegistry)
                .environment(toolSeed)
                .preferredColorScheme(prefs.theme.colorScheme)  // INFRA-14
        }
        .defaultSize(width: 900, height: 650)
        .commandsRemoved()

        // MARK: - Preferences Window (INFRA-12)
        // openSettings() is broken on macOS 14 with .accessory — WindowCoordinator opens it.
        // The Settings scene still must be declared for SettingsLink to resolve.
        Settings {
            PreferencesView()
                .environment(prefs)
                .environment(hotkeyManager)
                .environment(historyStore)  // CR-01: needed by HistoryPreferencesTab.clearUnpinned()
                .preferredColorScheme(prefs.theme.colorScheme)  // INFRA-14
        }
    }
}
