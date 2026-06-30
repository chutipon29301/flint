// Core/Services/PasteBackService.swift
// D-09: Synthetic ⌘V paste-back into the previously-focused app.
// Permission is re-verified at call time (AXIsProcessTrusted) — stored pasteBackEnabled
// bool is NOT the sole gate. Permission may be revoked after toggle-on (T-04-12).
//
// Security Domain:
//   T-04-11: AXIsProcessTrustedWithOptions is NEVER called here — only in PreferencesView
//            handlePasteBackToggleOn(). This service only synthesizes events when the
//            permission is already confirmed.
//   T-04-12: AXIsProcessTrusted() is re-verified at call time, before synthesizing any event.
//   T-04-13: Caller provides the specific NSRunningApplication captured before the popover opened.
//
// RESEARCH OQ-01(c): synthesize ⌘V using CGEvent after activating the target app.
// Virtual key code 9 = 'v' on US keyboard (RESEARCH A3/Pitfall 8 — verify with IOHIDUsageTables).

import AppKit
import CoreGraphics
import ApplicationServices
import Observation

@Observable
@MainActor
final class PasteBackService {

    // MARK: - Paste Synthesis

    /// Synthesizes a ⌘V key event into the specified app.
    ///
    /// Re-verifies `AXIsProcessTrusted()` at call time — if Accessibility permission was revoked
    /// since the toggle was enabled, the action is silently a no-op (copy-only fallback, CF-01).
    ///
    /// Sequence (RESEARCH OQ-01(c)):
    ///  1. Guard `AXIsProcessTrusted()` — bail if permission revoked (T-04-12).
    ///  2. Activate the target app with `.activateIgnoringOtherApps`.
    ///  3. After 80ms delay (RESEARCH A2 — activation is async; tune if paste fires too early),
    ///     synthesize a CGEvent keyDown+keyUp for virtual key 9 ('v' on US keyboard, RESEARCH A3)
    ///     with `.maskCommand` flag, posted to `.cgSessionEventTap`.
    ///
    /// - Parameter app: The `NSRunningApplication` to receive the paste event. Captured in
    ///   `HotkeyManager` before the Flint popover opens (Pitfall 2 — capture-before-popover).
    func synthesizePaste(into app: NSRunningApplication) {
        // Re-verify at call time — permission may be revoked after toggle-on (T-04-12, Security Domain).
        guard AXIsProcessTrusted() else {
            // Copy-only fallback: clipboard already has the value; user can ⌘V manually.
            return
        }

        // Activate the target app so it becomes the frontmost process before the ⌘V arrives.
        // NOTE: `.activateIgnoringOtherApps` is deprecated on macOS 14; `activate()` is the
        // replacement. On macOS 14+ activate() has the same effect for our use case.
        app.activate()

        // 80ms delay — NSRunningApplication.activate() is asynchronous; the CGEvent must not
        // arrive before the app has become frontmost (RESEARCH A2/Pitfall 8).
        // If paste fires in the wrong app, increase this delay or switch to
        // NSWorkspace.didActivateApplicationNotification observation (RESEARCH OQ-01(c) note).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            // Virtual key code 9 = 'v' on standard US ANSI keyboard layout.
            // RESEARCH A3 / Pitfall 8: verify against IOHIDUsageTables.h or test empirically.
            // If the wrong character is typed, adjust this value.
            let vKeyCode: CGKeyCode = 9

            guard
                let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: true),
                let keyUp   = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: false)
            else { return }

            keyDown.flags = .maskCommand
            keyUp.flags   = .maskCommand

            // Post to the session event tap — requires Accessibility (kTCCServicePostEvent).
            // We already verified AXIsProcessTrusted() above. If permission was revoked in
            // the 80ms window, the CGEvent post is a no-op on macOS 14 (TCC gate at post time).
            keyDown.post(tap: .cgSessionEventTap)
            keyUp.post(tap: .cgSessionEventTap)
        }
    }
}
