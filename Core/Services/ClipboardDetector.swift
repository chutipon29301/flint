// Core/Services/ClipboardDetector.swift
// Monitors NSPasteboard for content matching a registered tool predicate.
// Uses NSPasteboardDidChangeNotification (0% idle CPU) + visibility gate (Pitfall #7).
// Re-checks on popover focus to implement D-05 (always re-show banner on focus).
// Source: RESEARCH.md Pattern 6 [VERIFIED]

import AppKit
import Observation

@Observable
@MainActor
final class ClipboardDetector {
    var detectionResult: DetectionResult? = nil
    var isEnabled: Bool = true

    /// Bound to MenuBarExtraAccess isPresented. Setting true re-triggers detection (D-05).
    var isPopoverPresented: Bool = false {
        didSet {
            if isPopoverPresented {
                checkPasteboard(force: true)   // D-05: re-show banner on every focus
            } else {
                // Clear detection result when popover closes so stale banner doesn't persist
                detectionResult = nil
                // D-04: watchdog on the falling edge, gated on NSColorPanel visibility —
                // re-present if the popover closed while the system color panel is still open.
                if NSColorPanel.shared.isVisible {
                    isPopoverPresented = true
                }
            }
        }
    }

    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private weak var registry: ToolRegistry?
    private var observerToken: NSObjectProtocol?

    /// Call to start listening for pasteboard changes.
    /// Safe to call multiple times — removes any previous observer before registering a new one (CR-02).
    func start(registry: ToolRegistry) {
        // CR-02: remove existing observer before re-registering to prevent multiplied handlers.
        // MenuBarPopoverView.onAppear calls start() on every popover appearance; without this
        // guard, N appearances → N active observers → N redundant handler invocations per change.
        if let token = observerToken {
            NotificationCenter.default.removeObserver(token)
            observerToken = nil
        }
        self.registry = registry
        // NSPasteboardDidChangeNotification: private-but-stable, 0% idle CPU (Pitfall #7)
        // Capture self as MainActor-isolated object; dispatch to main queue in closure.
        let token = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("NSPasteboardDidChangeNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Already on main queue (queue: .main above)
            // Dispatch to main actor to satisfy Swift 6 strict concurrency
            Task { @MainActor [weak self] in
                self?.pasteboardDidChange()
            }
        }
        observerToken = token
    }

    private func pasteboardDidChange() {
        guard isEnabled, isPopoverPresented else { return }
        checkPasteboard(force: false)
    }

    /// Manually trigger clipboard detection — used by the ⌘⇧V paste-and-detect shortcut (INFRA-16).
    /// Reads the current pasteboard contents and fires detection regardless of change-count delta.
    func triggerDetect() {
        checkPasteboard(force: true)
    }

    private func checkPasteboard(force: Bool) {
        let current = NSPasteboard.general.changeCount
        guard force || current != lastChangeCount else { return }
        lastChangeCount = current

        guard isEnabled,
              let string = NSPasteboard.general.string(forType: .string),
              !string.isEmpty else {
            detectionResult = nil
            return
        }
        detectionResult = registry?.detect(from: string)
    }
}
