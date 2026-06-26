// App/AppDelegate.swift
// NSApplicationDelegate target for @NSApplicationDelegateAdaptor (DIST-01).
// Registers the single Services provider and forces a Services-cache refresh so the
// "Open in Flint" entry appears during development without a logout/login cycle.
// Source: RESEARCH.md Pattern 1 [VERIFIED] + 03-PATTERNS.md "App/AppDelegate.swift"

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register the single Services provider (only one per app).
        // FlintServiceProvider reads the pasteboard text and posts a notification;
        // routing into detect()/ToolSeed happens on @MainActor in FlintApp.
        NSApp.servicesProvider = FlintServiceProvider.shared
        // Force the Services cache to refresh (Pitfall #2). Apps in /Applications
        // refresh at login; during development this avoids a logout/login cycle.
        // Harmless in production.
        NSUpdateDynamicServices()
    }
}
