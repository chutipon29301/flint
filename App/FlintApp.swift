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

    // DIST-03: open the onboarding WindowGroup by id when WindowCoordinator posts .openOnboarding.
    @Environment(\.openWindow) private var openWindow

    @State private var prefs = PreferencesStore()
    @State private var clipboard = ClipboardDetector()
    @State private var hotkeyManager = HotkeyManager()
    @State private var toolRegistry = ToolRegistry()
    @State private var toolSeed = ToolSeed()
    // DIST-04: Sparkle auto-update wrapper. Owned + injected here but currently DORMANT —
    // the unsigned/ad-hoc build cannot install updates, so it is neither started (popover
    // .onAppear) nor exposed in Preferences. Kept wired so the signed+notarized build
    // (release.sh) can re-enable it by un-commenting the two call sites.
    @State private var sparkle = SparkleUpdaterService()
    // D-09: paste-back service — isolates CGEvent ⌘V synthesis, gated on AXIsProcessTrusted.
    @State private var pasteBackService = PasteBackService()

    var body: some Scene {
        // MARK: - MenuBar Popover
        // MenuBarExtraAccess must be applied before .menuBarExtraStyle (extension on MenuBarExtra)
        MenuBarExtra("Flint", systemImage: "wrench.and.screwdriver") {
            MenuBarPopoverView()
                .environment(prefs)
                .environment(clipboard)
                .environment(toolRegistry)
                .environment(toolSeed)
                .environment(sparkle)  // DIST-04: lazy-started from popover .onAppear
                .environment(hotkeyManager)  // D-09: tool observers read previousFrontmostApp
                .environment(pasteBackService)  // D-09: synthesizes ⌘V into previously-focused app
                .preferredColorScheme(prefs.theme.colorScheme)  // INFRA-14 live theme
                // DIST-03: WindowCoordinator.openOnboarding() posts .openOnboarding after the
                // activation-policy dance; open the onboarding WindowGroup here (mirrors the
                // workspace open-by-id path). The MenuBarExtra content is created at launch, so
                // this subscription is in place before the first-run gate fires.
                .onReceive(NotificationCenter.default.publisher(for: .openOnboarding)) { _ in
                    openWindow(id: "onboarding")
                }
        }
        .menuBarExtraAccess(isPresented: $clipboard.isPopoverPresented)
        .menuBarExtraStyle(.window)

        // MARK: - Detachable Workspace Window (INFRA-02)
        WindowGroup(id: "workspace") {
            MainWindowView()
                .environment(prefs)
                .environment(clipboard)
                .environment(toolRegistry)
                .environment(toolSeed)
                .environment(hotkeyManager)     // D-09: tool views read previousFrontmostApp
                .environment(pasteBackService)  // D-09: tool views call synthesizePaste
                .preferredColorScheme(prefs.theme.colorScheme)  // INFRA-14
        }
        .defaultSize(width: 900, height: 650)
        .commandsRemoved()

        // MARK: - Onboarding Window (DIST-03, D-07)
        // First-run welcome window. Opened by id from the .openOnboarding receiver above, after
        // WindowCoordinator's activation dance so it surfaces above the frontmost app. Fixed
        // 480×360 and not resizable (.windowResizability(.contentSize)).
        WindowGroup(id: "onboarding") {
            OnboardingWindowView()
                .environment(prefs)
                .preferredColorScheme(prefs.theme.colorScheme)  // INFRA-14
        }
        .defaultSize(width: 480, height: 360)
        .windowResizability(.contentSize)
        .commandsRemoved()

        // MARK: - Preferences Window (INFRA-12)
        // openSettings() is broken on macOS 14 with .accessory — WindowCoordinator opens it.
        // The Settings scene still must be declared for SettingsLink to resolve.
        Settings {
            PreferencesView()
                .environment(prefs)
                .environment(hotkeyManager)
                .environment(sparkle)        // 04-02: PreferencesView's Updates section reads SparkleUpdaterService
                .preferredColorScheme(prefs.theme.colorScheme)  // INFRA-14
        }
    }
}
