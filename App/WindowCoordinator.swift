// App/WindowCoordinator.swift
// Activation-policy dance to show workspace/preferences windows above other apps.
// The .accessory policy hides the Dock icon but also hides windows behind frontmost app.
// Fix: setActivationPolicy(.regular) → activate → show window → restore .accessory on close.
// Source: RESEARCH.md Pattern 7 [VERIFIED] + Peter Steinberger "Showing Settings from macOS Menu Bar Items"

import AppKit
import Foundation

@MainActor
final class WindowCoordinator {
    static let shared = WindowCoordinator()
    private var windowCount = 0

    private init() {}

    /// Call to open the detachable workspace window (INFRA-02).
    func openWorkspace() {
        windowCount += 1
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // Short delay before posting notification so window can become key
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: .openWorkspace, object: nil)
        }
    }

    /// Open the first-run onboarding window (DIST-03, D-07).
    /// Copies openWorkspace()'s activation-policy dance verbatim so the welcome window appears
    /// ABOVE the frontmost app (the "where did it go?" problem for a no-Dock menubar app).
    /// `.openOnboarding` is declared in this file's Notification.Name extension below.
    func openOnboarding() {
        windowCount += 1
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: .openOnboarding, object: nil)
        }
    }

    /// Call to open the Preferences window (INFRA-12).
    /// openSettings() is broken on macOS 14 with .accessory policy (Pitfall #2).
    /// Instead: setActivationPolicy(.regular) → activate → sendAction(showPreferences) → window appears in front.
    func openPreferences() {
        windowCount += 1
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // showPreferencesWindow: is the action that SwiftUI's Settings scene responds to
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    /// Open the menubar popover positioned on the matched tool (DIST-01, retained per user decision).
    /// Copies openWorkspace()'s activation-policy dance so the popover appears above the source app
    /// (Pitfall #3). The popover is presented via the existing MenuBarExtraAccess isPopoverPresented
    /// binding driven by .showPopover.
    func openToolViaService(toolId: String) {
        windowCount += 1
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: .showPopover, object: nil)
        }
    }

    /// Open the search-first launcher with text staged in the search field (DIST-01, D-03, retained per user decision).
    /// Same activation-policy dance as openToolViaService; the no-match case is never a dead end.
    func openLauncherWithStagedText(_ text: String) {
        windowCount += 1
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: .showPopover, object: nil)
        }
    }

    /// Called when any workspace/preferences window closes.
    func windowWillClose() {
        windowCount = max(0, windowCount - 1)
        if windowCount == 0 {
            // Restore .accessory so Dock icon disappears again
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}

// MARK: - Notification Names (plan 03-03, relocated here plan 260627-lef)
extension Notification.Name {
    /// Posted by WindowCoordinator.openOnboarding() after the activation-policy dance.
    /// FlintApp receives this and opens the onboarding WindowGroup by id (DIST-03).
    static let openOnboarding = Notification.Name("com.lathe.openOnboarding")
}
