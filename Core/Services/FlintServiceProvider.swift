// Core/Services/FlintServiceProvider.swift
// macOS Services handler for the single "Open in Flint" entry (DIST-01, D-01).
// The @objc selector base name `openInFlint` MUST equal the Info.plist NSServices
// NSMessage value (asserted in Task 1).
//
// The handler is invoked by AppKit on an arbitrary (non-main) thread. It only reads
// the pasteboard text, caps its size (T-03-02 DoS mitigation), and posts a notification.
// All routing (detect → seed → window open) is performed by the @MainActor receiver
// in FlintApp — this provider never performs any seed or window-open call directly.
// Source: RESEARCH.md Pattern 1 [VERIFIED] + 03-PATTERNS.md "FlintServiceProvider.swift"

import AppKit

final class FlintServiceProvider: NSObject, @unchecked Sendable {
    static let shared = FlintServiceProvider()
    private override init() {}

    /// Maximum accepted Services text. Mirrors the clipboard oversized guard.
    /// Oversized selections are dropped silently (STRIDE DoS mitigation T-03-02).
    private static let maxTextBytes = 1_000_000  // 1 MB

    /// Services entry point. The selector base name must match Info.plist NSMessage ("openInFlint").
    @objc func openInFlint(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString>?
    ) {
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return }
        // T-03-02: cap incoming text at 1 MB; return silently if exceeded.
        guard text.utf8.count <= Self.maxTextBytes else { return }

        // Decouple to FlintApp via a single notification; the @MainActor receiver routes it.
        NotificationCenter.default.post(
            name: .serviceDidReceiveText,
            object: nil,
            userInfo: ["text": text]
        )
    }
}

// MARK: - Notification Names (Phase 3)
// Follow the existing "com.lathe." prefix used by HotkeyManager's extension.
// Names are distinct from showPopover/openWorkspace to avoid collisions.
extension Notification.Name {
    /// Posted by FlintServiceProvider (off-main) carrying userInfo["text"].
    /// FlintApp receives this on @MainActor and performs detect → seed → open.
    static let serviceDidReceiveText = Notification.Name("com.lathe.serviceDidReceiveText")
    /// Reserved for plan 03-03 onboarding; declared here to fix the name once.
    static let openOnboarding = Notification.Name("com.lathe.openOnboarding")
    /// Posted by FlintApp after a Services match: navigate the popover to the matched tool.
    static let routeServiceMatch = Notification.Name("com.lathe.routeServiceMatch")
    /// Posted by FlintApp on no-match: stage the text in the launcher search field (D-03).
    static let routeServiceNoMatch = Notification.Name("com.lathe.routeServiceNoMatch")
}
