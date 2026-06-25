// Core/Services/HotkeyManager.swift
// Registers the global hotkey ⌘⇧Space using KeyboardShortcuts (Carbon RegisterEventHotKey).
// No Accessibility permission dialog (INFRA-04).
// Source: RESEARCH.md § "HotkeyManager" [VERIFIED]

import KeyboardShortcuts
import Foundation
import Observation

extension KeyboardShortcuts.Name {
    // Default: ⌘⇧Space — user-configurable in preferences (INFRA-04)
    // Note: Using 'initial:' (new API) to avoid deprecation
    static let openLathe = Self("openLathe", initial: .init(.space, modifiers: [.command, .shift]))
}

extension Notification.Name {
    static let showPopover = Notification.Name("com.lathe.showPopover")
    static let openWorkspace = Notification.Name("com.lathe.openWorkspace")
}

@Observable
@MainActor
final class HotkeyManager {
    init() {
        // Register hotkey — fires NotificationCenter so any subscriber can respond
        // KeyboardShortcuts.onKeyDown is @MainActor-isolated in v3.0.1
        KeyboardShortcuts.onKeyDown(for: .openLathe) {
            NotificationCenter.default.post(name: .showPopover, object: nil)
        }
    }
}
