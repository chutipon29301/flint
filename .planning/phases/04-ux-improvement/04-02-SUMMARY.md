---
phase: 04-ux-improvement
plan: "02"
subsystem: update-checker
tags: [sparkle, preferences, observable, delegate, d-03, d-04, dist-04]
dependency_graph:
  requires:
    - "03-polish-distribution: Sparkle 2.9.3 integrated (Phase 3)"
    - "04-01: wave-1 peer plan (no runtime dependency)"
  provides:
    - "SparkleUpdaterService.UpdateStatus: observable update-check state"
    - "SparkleUpdaterService: SPUUpdaterDelegate conformance"
    - "PreferencesView: Check for Updates button + live status display"
  affects:
    - "04-05: D-09 paste-back plan (reads SparkleUpdaterService pattern)"
tech_stack:
  added: []
  patterns:
    - "@Observable + NSObject inheritance for Objective-C delegate bridging"
    - "SPUUpdaterDelegate 4-callback status mapping to Swift enum"
    - "@Environment forwarding chain: PreferencesView → GeneralPreferencesTab"
    - "Defensive start() in checkForUpdates() for Preferences-first access"
key_files:
  created: []
  modified:
    - Core/Services/SparkleUpdaterService.swift
    - UI/PreferencesView.swift
decisions:
  - "SparkleUpdaterService inherits NSObject: SPUUpdaterDelegate extends <NSObject> protocol, so the Swift class must inherit NSObject to conform — without this, the compiler cannot bridge to NSObjectProtocol (Rule 1 auto-fix)"
  - "D-03 delegate-nil bug: changed updaterDelegate: nil to updaterDelegate: self — the root cause why no update check result was ever observable"
  - "UpdateStatus as top-level enum (not nested): avoids access-path verbosity in PreferencesView switch branches and matches the codebase pattern of module-level type declarations"
  - "User-initiated-only upToDate: SPUNoUpdateFoundUserInitiatedKey guards the .upToDate state so background checks do not pollute the UI"
  - "Color.accentColor (not .accentColor): foregroundStyle requires an explicit Color type for .accentColor in this context, unlike foregroundColor"
metrics:
  duration: "~15 minutes"
  completed: "2026-06-29"
  tasks: 2
  files: 2
---

# Phase 04 Plan 02: Update Checker Wire-up (D-03/D-04) Summary

Wire the already-implemented Sparkle update checker into Preferences with observable status reporting: SPUUpdaterDelegate conformance translates network callbacks into an UpdateStatus enum surfaced via a "Check for Updates..." button and live status label.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Add UpdateStatus + SPUUpdaterDelegate to SparkleUpdaterService | d2aa450 | Core/Services/SparkleUpdaterService.swift |
| 2 | Add Updates section (button + status display) to PreferencesView | 10177ac | UI/PreferencesView.swift, Core/Services/SparkleUpdaterService.swift |

## What Was Built

**Task 1 — SparkleUpdaterService overhaul:**

- Added `enum UpdateStatus: Equatable` with five cases: `idle`, `checking`, `upToDate`, `updateAvailable(version: String)`, `error(message: String)`
- Added `var updateStatus: UpdateStatus = .idle` as an observable property
- Fixed the delegate-nil bug: `updaterDelegate: nil` → `updaterDelegate: self`
- `checkForUpdates()` now: calls `start()` defensively (idempotent), sets `.checking`, then calls the Sparkle API
- `extension SparkleUpdaterService: SPUUpdaterDelegate` with four callbacks:
  - `updaterDidNotFindUpdate`: sets `.upToDate` for user-initiated checks only (SPUNoUpdateFoundUserInitiatedKey)
  - `updater(_:didFindValidUpdate:)`: sets `.updateAvailable(version: item.displayVersionString)`
  - `updater(_:didAbortWithError:)`: sets `.error(message: error.localizedDescription)` — pass-through for D-04 clear error
  - `updater(_:didFinishUpdateCycleFor:error:)`: catch-all; sets `.error` if still `.checking`

**Task 2 — PreferencesView Updates section:**

- Added `@Environment(SparkleUpdaterService.self)` to both `PreferencesView` and `GeneralPreferencesTab`
- Added `.environment(sparkle)` forwarding in `PreferencesView.body`
- New `Section("Updates")` in `GeneralPreferencesTab` with:
  - `Button("Check for Updates...")` calling `sparkle.checkForUpdates()`, `.disabled` while `.checking`
  - Five-branch `switch sparkle.updateStatus` rendering exact UI-SPEC copy + SF Symbols + colors

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] SparkleUpdaterService must inherit NSObject for SPUUpdaterDelegate conformance**

- **Found during:** Task 2 xcodebuild verification
- **Issue:** `SPUUpdaterDelegate` is declared as `@protocol SPUUpdaterDelegate <NSObject>` in Objective-C, requiring conforming Swift classes to inherit `NSObject`. Without this, the compiler emits: "cannot declare conformance to 'NSObjectProtocol' in Swift; should inherit 'NSObject' instead."
- **Fix:** Changed `final class SparkleUpdaterService` to `final class SparkleUpdaterService: NSObject`. This is compatible with `@Observable` and `@MainActor`.
- **Files modified:** `Core/Services/SparkleUpdaterService.swift`
- **Commit:** 10177ac (included in Task 2 commit as part of the fix)

**2. [Rule 1 - Bug] `.accentColor` not valid as ShapeStyle in foregroundStyle**

- **Found during:** Task 2 xcodebuild verification
- **Issue:** `.accentColor` cannot be used as a `ShapeStyle` in `.foregroundStyle()` without an explicit type. The compiler reported: "type 'ShapeStyle' has no member 'accentColor'".
- **Fix:** Changed `.foregroundStyle(.accentColor)` to `.foregroundStyle(Color.accentColor)` for the `.updateAvailable` case.
- **Files modified:** `UI/PreferencesView.swift`
- **Commit:** 10177ac

## Known Stubs

None — all five UpdateStatus branches are fully wired. The "placeholder" localhost SUFeedURL in Info.plist is a pre-existing item from Phase 3 integration, not introduced by this plan. It correctly triggers `didAbortWithError` → `.error(message:)` which satisfies D-04.

## Threat Flags

No new threat surface introduced. The plan's threat register was fully mitigated:

- **T-04-03 (Tampering/appcast integrity):** Not weakened — this plan only reads Sparkle delegate result callbacks; EdDSA verification remains entirely Sparkle's responsibility.
- **T-04-04 (DoS/unreachable feed):** Mitigated — `didAbortWithError` → `.error(message: error.localizedDescription)` produces a clear error and clears the `.checking` state (never hangs indefinitely, CF-01).
- **T-04-05 (Information disclosure):** `updateStatus` is transient in-memory state; nothing written to disk.

## Self-Check

**Checking created/modified files exist:**
- `Core/Services/SparkleUpdaterService.swift` — FOUND (modified)
- `UI/PreferencesView.swift` — FOUND (modified)

**Checking commits exist:**
- d2aa450 — FOUND (Task 1)
- 10177ac — FOUND (Task 2)

## Self-Check: PASSED
