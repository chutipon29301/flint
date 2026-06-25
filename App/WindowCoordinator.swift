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

    /// Call to open the Preferences window (INFRA-12).
    /// openSettings() is broken on macOS 14 with .accessory policy — use this instead.
    func openPreferences() {
        windowCount += 1
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(
                name: Notification.Name("com.lathe.openPreferences"),
                object: nil
            )
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
