// App/LatheApp.swift
// @main app entry point — service ownership, MenuBarExtra + MenuBarExtraAccess wiring.
// Services are @State (only lifecycle-stable ownership point — Pattern 1).
// Source: RESEARCH.md Pattern 1 [VERIFIED]
//
// NOTE: MenuBarExtraAccess.menuBarExtraAccess() is an extension on MenuBarExtra, not Scene.
// It must be applied BEFORE .menuBarExtraStyle() — the order matters.

import SwiftUI
import MenuBarExtraAccess

@main
struct LatheApp: App {
    // MARK: - Service Ownership (Pattern 1)
    // All shared services live here — the only lifecycle-stable ownership point.
    // Tool ViewModels are created on-demand per navigation destination.

    @State private var historyStore = HistoryStore()
    @State private var prefs = PreferencesStore()
    @State private var clipboard = ClipboardDetector()
    @State private var hotkeyManager = HotkeyManager()
    @State private var toolRegistry = ToolRegistry()

    var body: some Scene {
        // MARK: - MenuBar Popover
        // MenuBarExtraAccess must be applied before .menuBarExtraStyle (extension on MenuBarExtra)
        MenuBarExtra("Lathe", systemImage: "wrench.and.screwdriver") {
            MenuBarPopoverView()
                .environment(historyStore)
                .environment(prefs)
                .environment(clipboard)
                .environment(toolRegistry)
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
        }
        .defaultSize(width: 900, height: 650)
        .commandsRemoved()

        // MARK: - Preferences (INFRA-12)
        // openSettings() is broken on macOS 14 with .accessory — use WindowCoordinator dance.
        Settings {
            PreferencesView()
                .environment(prefs)
                .environment(hotkeyManager)
        }
    }
}

// MARK: - Preferences View (Placeholder — fleshed out in 01-07)

struct PreferencesView: View {
    @Environment(PreferencesStore.self) private var prefs

    var body: some View {
        Form {
            Section("General") {
                Text("Preferences — more options coming soon.")
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 400, minHeight: 300)
        .padding()
        .navigationTitle("Preferences")
    }
}
