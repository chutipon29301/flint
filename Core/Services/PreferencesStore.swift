// Core/Services/PreferencesStore.swift
// @Observable UserDefaults wrapper for app preferences.
// SECURITY (T-07-ID): Never store secrets here — UserDefaults may be iCloud-backed.
// Launch-at-login via SMAppService added in plan 01-07 (INFRA-13).

import Foundation
import Observation
import ServiceManagement

@Observable
final class PreferencesStore {

    // MARK: - Pinned Tool IDs (INFRA-11)

    // D-13 default order: JSON, Base64, JWT, URL, Timestamp, UUID
    // Ordered, persisted in UserDefaults, max 6 tools.
    var pinnedToolIds: [String] {
        get { defaults.stringArray(forKey: Keys.pinnedToolIds) ?? Self.defaultPinnedToolIds }
        set { defaults.set(newValue, forKey: Keys.pinnedToolIds) }
    }

    /// Alias with canonical casing (matching PLAN.md interface spec).
    var pinnedToolIDs: [String] {
        get { pinnedToolIds }
        set { pinnedToolIds = newValue }
    }

    /// Move a pinned tool from one position to another and persist. (INFRA-11 drag-to-reorder)
    func movePinnedTool(from source: IndexSet, to destination: Int) {
        var ids = pinnedToolIds
        ids.move(fromOffsets: source, toOffset: destination)
        pinnedToolIds = ids
    }

    /// Add a tool to pinned list (max 6). No-op if already pinned or at cap.
    func pinTool(_ id: String) {
        guard !pinnedToolIds.contains(id), pinnedToolIds.count < 6 else { return }
        pinnedToolIds.append(id)
    }

    /// Remove a tool from pinned list.
    func unpinTool(_ id: String) {
        pinnedToolIds.removeAll { $0 == id }
    }

    // MARK: - Launch at Login (INFRA-13)
    // Uses SMAppService.mainApp — Apple-sanctioned API for macOS 13+.
    // macOS shows a system notification on change (T-07-SC accepted risk).

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // SMAppService errors are non-fatal — user can re-toggle.
                // Errors include: notFound (bundle lacks Login Item target), permissionDenied.
                print("[PreferencesStore] SMAppService error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Onboarding (DIST-03)
    // First-run welcome window gate. False default (missing key) triggers onboarding on the
    // first launch after install/update — no migration needed. A single synchronous
    // UserDefaults bool read so the cold-start critical path is not regressed (Pitfall #6/#7).

    var hasSeenOnboarding: Bool {
        get { defaults.object(forKey: Keys.hasSeenOnboarding) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Keys.hasSeenOnboarding) }
    }

    // MARK: - Show in Dock (INFRA-13)
    // When true, overrides the .accessory policy to keep the Dock icon visible persistently.
    // WindowCoordinator still manages per-window toggles; this is the persistent preference.

    var showInDock: Bool {
        get { defaults.object(forKey: Keys.showInDock) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Keys.showInDock) }
    }

    // MARK: - Default Open Mode (INFRA-13)
    // Whether tools open in the popover or detach to the workspace window by default.

    enum OpenMode: String, CaseIterable, Identifiable {
        case popover = "popover"
        case window = "window"
        var id: String { rawValue }
        var label: String {
            switch self {
            case .popover: return "Popover (default)"
            case .window: return "Workspace Window"
            }
        }
    }

    var defaultOpenMode: OpenMode {
        get {
            guard let raw = defaults.string(forKey: Keys.defaultOpenMode),
                  let mode = OpenMode(rawValue: raw) else { return .popover }
            return mode
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.defaultOpenMode) }
    }

    // MARK: - Clipboard Auto-Detection (INFRA-13)
    // Persisted preference — ClipboardDetector.isEnabled should read this at startup.

    var clipboardAutoDetect: Bool {
        get { defaults.object(forKey: Keys.clipboardAutoDetect) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.clipboardAutoDetect) }
    }

    /// Legacy accessor (01-01 name) — delegates to clipboardAutoDetect.
    var clipboardDetectionEnabled: Bool {
        get { clipboardAutoDetect }
        set { clipboardAutoDetect = newValue }
    }

    // MARK: - Theme (INFRA-14)

    enum AppTheme: String, CaseIterable, Identifiable {
        case system = "system"
        case light = "light"
        case dark = "dark"
        var id: String { rawValue }
        var label: String {
            switch self {
            case .system: return "System"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }
        /// Maps to SwiftUI ColorScheme for the .preferredColorScheme() modifier.
        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
    }

    var theme: AppTheme {
        get {
            guard let raw = defaults.string(forKey: Keys.theme),
                  let t = AppTheme(rawValue: raw) else { return .system }
            return t
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.theme) }
    }

    // MARK: - Code Font (INFRA-14)

    /// Name of the preferred monospaced font for code editors.
    /// Empty string = use system SF Mono (.monospaced design).
    var codeFont: String {
        get { defaults.string(forKey: Keys.codeFont) ?? "" }
        set { defaults.set(newValue, forKey: Keys.codeFont) }
    }

    /// Code editor font size (INFRA-14). Range: 10–20pt.
    var codeFontSize: Int {
        get {
            let stored = defaults.object(forKey: Keys.codeFontSize) as? Int ?? 13
            return max(10, min(20, stored))
        }
        set { defaults.set(max(10, min(20, newValue)), forKey: Keys.codeFontSize) }
    }

    // MARK: - History Limit (INFRA-13)

    /// Maximum number of unpinned history entries to retain. Clamped 10–100.
    var historyLimit: Int {
        get {
            let stored = defaults.object(forKey: Keys.historyLimit) as? Int ?? 100
            return max(10, min(100, stored))
        }
        set { defaults.set(max(10, min(100, newValue)), forKey: Keys.historyLimit) }
    }

    // MARK: - Workspace State (INFRA-02)

    /// Last tool opened in the workspace window — restored on reopen.
    var lastWorkspaceToolId: String? {
        get { defaults.string(forKey: Keys.lastWorkspaceToolId) }
        set {
            if let id = newValue {
                defaults.set(id, forKey: Keys.lastWorkspaceToolId)
            } else {
                defaults.removeObject(forKey: Keys.lastWorkspaceToolId)
            }
        }
    }

    // MARK: - Per-Tool Defaults

    /// JSON Formatter: default indent size (2, 4, or 0 for tab)
    var jsonDefaultIndent: Int {
        get { defaults.object(forKey: Keys.jsonDefaultIndent) as? Int ?? 2 }
        set { defaults.set(newValue, forKey: Keys.jsonDefaultIndent) }
    }

    /// Base64: default URL-safe mode
    var base64UrlSafe: Bool {
        get { defaults.object(forKey: Keys.base64UrlSafe) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Keys.base64UrlSafe) }
    }

    /// Hash Generator: default uppercase output
    var hashUppercase: Bool {
        get { defaults.object(forKey: Keys.hashUppercase) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Keys.hashUppercase) }
    }

    // MARK: - Private

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
        static let clipboardAutoDetect = "lathe.clipboardAutoDetect"
        static let historyLimit = "lathe.historyLimit"
        static let showInDock = "lathe.showInDock"
        static let defaultOpenMode = "lathe.defaultOpenMode"
        static let theme = "lathe.theme"
        static let codeFont = "lathe.codeFont"
        static let codeFontSize = "lathe.codeFontSize"
        static let jsonDefaultIndent = "lathe.jsonDefaultIndent"
        static let base64UrlSafe = "lathe.base64UrlSafe"
        static let hashUppercase = "lathe.hashUppercase"
        static let lastWorkspaceToolId = "lathe.lastWorkspaceToolId"
        static let hasSeenOnboarding = "lathe.hasSeenOnboarding"
    }
}

// MARK: - ColorScheme Import

import SwiftUI
