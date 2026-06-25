// Core/Services/PreferencesStore.swift
// @Observable UserDefaults wrapper for app preferences.
// SECURITY: Never store secrets here (UserDefaults may be iCloud-backed).
// Launch-at-login via SMAppService added in plan 01-07.

import Foundation
import Observation

@Observable
final class PreferencesStore {
    // Pinned tool IDs — D-13 default order: JSON, Base64, JWT, URL, Timestamp, UUID
    var pinnedToolIds: [String] {
        get { defaults.stringArray(forKey: Keys.pinnedToolIds) ?? Self.defaultPinnedToolIds }
        set { defaults.set(newValue, forKey: Keys.pinnedToolIds) }
    }

    // Global hotkey (stored as KeyboardShortcuts name — HotkeyManager owns registration)
    // Stored separately by KeyboardShortcuts library in UserDefaults

    // Whether clipboard auto-detection is enabled
    var clipboardDetectionEnabled: Bool {
        get { defaults.object(forKey: Keys.clipboardDetectionEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.clipboardDetectionEnabled) }
    }

    // History item limit (default 100, max 100)
    var historyLimit: Int {
        get { defaults.object(forKey: Keys.historyLimit) as? Int ?? 100 }
        set { defaults.set(min(newValue, 100), forKey: Keys.historyLimit) }
    }

    // Appearance — follows system by default (managed by SwiftUI environment)
    // Preferences view for theme selection added in 01-07.

    private let defaults = UserDefaults.standard

    // D-13: default pinned order
    static let defaultPinnedToolIds = [
        "json-formatter",
        "base64",
        "jwt-decoder",
        "url-encoder",
        "timestamp",
        "uuid-generator"
    ]

    private enum Keys {
        static let pinnedToolIds = "lathe.pinnedToolIds"
        static let clipboardDetectionEnabled = "lathe.clipboardDetectionEnabled"
        static let historyLimit = "lathe.historyLimit"
    }
}
