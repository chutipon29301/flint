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
