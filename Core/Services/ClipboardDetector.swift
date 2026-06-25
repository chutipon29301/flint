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
            }
        }
    }

    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private weak var registry: ToolRegistry?
    private var observerToken: NSObjectProtocol?

    /// Call once at app startup (from LatheApp or onAppear) to start listening.
    func start(registry: ToolRegistry) {
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
