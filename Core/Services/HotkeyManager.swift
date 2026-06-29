// Core/Services/HotkeyManager.swift
// Registers the global hotkey ⌘⇧Space using KeyboardShortcuts (Carbon RegisterEventHotKey).
// No Accessibility permission dialog (INFRA-04).
// Source: RESEARCH.md § "HotkeyManager" [VERIFIED]

import KeyboardShortcuts
import Foundation
import Observation
import AppKit

extension KeyboardShortcuts.Name {
    // Default: ⌘⇧Space — user-configurable in preferences (INFRA-04)
    // Note: Using 'initial:' (new API) to avoid deprecation
    static let openFlint = Self("openFlint", initial: .init(.space, modifiers: [.command, .shift]))
}

extension Notification.Name {
    static let showPopover = Notification.Name("com.lathe.showPopover")
    static let openWorkspace = Notification.Name("com.lathe.openWorkspace")
}

@Observable
@MainActor
final class HotkeyManager {
    // D-09: capture the frontmost app BEFORE the popover opens so paste-back targets the
    // user's app, not Flint (Pitfall 2 — capture-before-popover rule).
    // NSRunningApplication cannot be weak-referenced; store as a regular optional.
    private(set) var previousFrontmostApp: NSRunningApplication?

    init() {
        // Register hotkey — fires NotificationCenter so any subscriber can respond
        // KeyboardShortcuts.onKeyDown is @MainActor-isolated in v3.0.1
        KeyboardShortcuts.onKeyDown(for: .openFlint) { [self] in
            // Capture now — NSWorkspace.shared.frontmostApplication still reflects
            // the user's app because the popover hasn't appeared yet (RESEARCH OQ-01(c)).
            // Warning sign: if this ever returns Flint's own bundle ID, the capture is too late.
            previousFrontmostApp = NSWorkspace.shared.frontmostApplication
            NotificationCenter.default.post(name: .showPopover, object: nil)
        }
    }
}
