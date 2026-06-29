// Core/Services/SparkleUpdaterService.swift
// Lazy wrapper around Sparkle's SPUStandardUpdaterController (DIST-04).
//
// Sparkle is initialized OFF the cold-start critical path: start() is invoked from
// the popover .onAppear (MenuBarPopoverView), NOT from FlintApp.init. Constructing
// SPUStandardUpdaterController at app launch would regress the < 500ms cold-start
// budget (RESEARCH Pitfall #6 / A5). Deferring it to the first popover appearance
// keeps launch instant while still arming the background update check.
//
// Sparkle intentionally does NOT check for updates on the very first launch — this is
// correct, expected behavior; do not override it (RESEARCH anti-pattern).
//
// D-08: Sparkle owns the standard update sheet (background auto-check → user prompt with
// release notes → install-and-restart). No custom update UI is added here; we never set
// up silent auto-install.
//
// D-03/D-04: SPUUpdaterDelegate is now wired so that update check results surface as an
// observable UpdateStatus. checkForUpdates() defensively calls start() so that Preferences
// can trigger a check even when the popover has never appeared.
//
// Source: 04-PATTERNS.md § "SparkleUpdaterService.swift — D-03/D-04 delegate + status"
//         04-RESEARCH.md § "Pattern 3: Sparkle Result Reporting (D-03/D-04)"

import Sparkle
import Observation

// MARK: - UpdateStatus

/// Observable update-check result state (D-03/D-04).
/// Mapped from SPUUpdaterDelegate callbacks and surfaced in PreferencesView.
enum UpdateStatus: Equatable {
    case idle
    case checking
    case upToDate
    case updateAvailable(version: String)
    case error(message: String)
}

// MARK: - SparkleUpdaterService

@Observable
@MainActor
final class SparkleUpdaterService: NSObject {
    /// The standard Sparkle controller. Nil until start() is first called from the popover.
    private(set) var controller: SPUStandardUpdaterController?

    /// Observable update-check status. Updated by SPUUpdaterDelegate callbacks (D-03/D-04).
    var updateStatus: UpdateStatus = .idle

    /// Lazily create and start the updater. Called from the popover .onAppear so Sparkle
    /// init stays off the cold-start critical path. Idempotent — guarded so repeated
    /// popover appearances do not re-create the controller.
    ///
    /// D-03 fix: passes `updaterDelegate: self` (was `nil`) so delegate callbacks fire.
    /// The service is held alive by the app environment satisfying Sparkle's weak-delegate
    /// retention requirement (RESEARCH A4).
    func start() {
        guard controller == nil else { return }
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,   // D-03 fix: was nil — delegate callbacks never fired
            userDriverDelegate: nil
        )
    }

    /// Trigger a manual update check (e.g. from "Check for Updates..." in Preferences).
    ///
    /// D-03: Defensively calls start() first (idempotent, guarded) so that the button
    /// works even when Preferences is opened directly via cmd+, without the popover ever
    /// appearing (RESEARCH Pitfall 6). Sets updateStatus to .checking immediately so the
    /// UI reflects progress.
    func checkForUpdates() {
        start()  // idempotent — no-op if controller already exists
        updateStatus = .checking
        controller?.updater.checkForUpdates()
    }
}

// MARK: - SPUUpdaterDelegate

extension SparkleUpdaterService: SPUUpdaterDelegate {

    /// Called when no update is found (user-initiated or background check).
    ///
    /// D-03: Only sets upToDate for user-initiated checks (SPUNoUpdateFoundUserInitiatedKey).
    /// Background auto-checks silently leave status as .idle so the UI is not polluted
    /// with "up to date" notifications the user did not ask for (UI-SPEC Update Checker).
    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        let isUserInitiated = (error as NSError).userInfo[SPUNoUpdateFoundUserInitiatedKey] as? Bool ?? false
        if isUserInitiated {
            updateStatus = .upToDate
        }
        // Background checks: silently ignore — do not change status from .idle
    }

    /// Called when Sparkle finds a valid update.
    ///
    /// D-03: Surfaces the update version string so PreferencesView can display it.
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        updateStatus = .updateAvailable(version: item.displayVersionString)
    }

    /// Called when Sparkle aborts due to a network error, bad feed URL, etc.
    ///
    /// D-04: Passes error.localizedDescription through unmodified. For the placeholder
    /// localhost feed, this produces "The connection was refused." or
    /// "A server with the specified hostname could not be found." — a clear, human-readable
    /// error per D-04 and CF-01 (never a silent failure or indefinite spinner).
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        updateStatus = .error(message: error.localizedDescription)
    }

    /// Catch-all called at the end of every update cycle.
    ///
    /// D-04: If a non-nil error arrives and status is still .checking (meaning neither
    /// didAbortWithError nor didFindValidUpdate fired first), set the error state so
    /// the spinner is never left indefinitely (CF-01).
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        if let error {
            if case .checking = updateStatus {
                updateStatus = .error(message: error.localizedDescription)
            }
        }
    }
}
