---
phase: 04-ux-improvement
plan: 05
subsystem: paste-back
tags: [keyboard-flow, accessibility, cgevent, D-09]
status: paused-at-checkpoint
dependency_graph:
  requires: [04-02, 04-03, 04-04]
  provides: [paste-back-service, pasteBackEnabled-pref, previousFrontmostApp-capture]
  affects: [PreferencesView, ColorView, HashView, NumberBaseView, ToolShortcutActions]
tech_stack:
  added: [ApplicationServices/AXIsProcessTrusted, CoreGraphics/CGEvent]
  patterns: [D-09-opt-in-toggle, prompt-on-enable, poll-revert-pattern, at-paste-re-verify]
key_files:
  created: [Core/Services/PasteBackService.swift]
  modified:
    - Core/Services/PreferencesStore.swift
    - Core/Services/HotkeyManager.swift
    - App/FlintApp.swift
    - UI/PreferencesView.swift
    - UI/Components/ToolShortcutActions.swift
    - Tools/Color/ColorView.swift
    - Tools/Hash/HashView.swift
    - Tools/NumberBase/NumberBaseView.swift
    - Flint.xcodeproj/project.pbxproj
decisions:
  - D-09 paste-back is default-OFF; AXIsProcessTrustedWithOptions called only in handlePasteBackToggleOn(), never at startup or hotkey
  - Used "AXTrustedCheckOptionPrompt" string literal key (not kAXTrustedCheckOptionPrompt) to satisfy Swift 6 Sendable constraints
  - Used NSRunningApplication.activate() (not deprecated .activateIgnoringOtherApps) for macOS 14 compatibility
  - Injected hotkeyManager + pasteBackService into workspace WindowGroup (Rule 2: missing env injection prevents assertionFailure crash)
metrics:
  completed_date: 2026-06-29
  tasks_completed: 2
  tasks_total: 3
  plan_status: paused_at_task_3_human_verify
---

# Phase 4 Plan 5: Paste-Back (D-09) Summary

**One-liner:** Default-off ⌘V paste-back with AXIsProcessTrusted prompt-on-enable, 30s poll-revert, CGEvent synthesis into previously-focused app.

**Status: PAUSED — awaiting human verification at Task 3.**
Tasks 1 and 2 are complete and committed. Task 3 (human-verify checkpoint) requires live device testing of CGEvent synthesis, Accessibility TCC behavior, and end-to-end keyboard loop. This summary covers Tasks 1–2 only.

---

## Tasks Completed

### Task 1: PasteBackService + pasteBackEnabled pref + previousFrontmostApp capture

**Commit:** `24a302c`

- Created `Core/Services/PasteBackService.swift` as `@Observable @MainActor final class` following the HotkeyManager service triple pattern.
- `synthesizePaste(into: NSRunningApplication)`: guards `AXIsProcessTrusted()` at call time (T-04-12 re-verify), calls `app.activate()`, then after 80ms asyncAfter synthesizes CGEvent keyDown+keyUp for virtual key 9 ('v', RESEARCH A3) with `.maskCommand` flag, posted to `.cgSessionEventTap`.
- Added `pasteBackEnabled: Bool` to `PreferencesStore` (default `false`, key `"lathe.pasteBackEnabled"`, CF-02 compliance).
- Added `import AppKit`, `private(set) var previousFrontmostApp: NSRunningApplication?`, and capture in `HotkeyManager.onKeyDown` BEFORE posting `.showPopover` (Pitfall 2).
- Registered `PasteBackService` in `FlintApp.swift` for MenuBarExtra context. Also injected `hotkeyManager` to MenuBarExtra content (was missing).
- Added `PasteBackService.swift` to Xcode project (pbxproj file reference + Sources build phase).

### Task 2: D-09 toggle + permission flow + paste-back branch in observers

**Commit:** `2077218`

- Added `Section("Keyboard Flow")` to `GeneralPreferencesTab` with:
  - `Toggle("Auto-paste result after copying")` bound via custom Binding setter calling `handlePasteBackToggleOn()` on enable; OFF path clears timer and state.
  - `.accessibilityLabel("Enable automatic paste-back after copying a result")`.
  - `.help("When enabled, pressing ⌘1–⌘9 copies the result AND pastes it into the previously-focused app. Requires Accessibility permission.")`.
  - Confirmation text (shown when `pasteBackEnabled == true`): "Accessibility permission granted. ⌘1–⌘9 will copy and paste the result into the previously-focused app." at 13pt `.secondary`.
  - Denial section (shown on timeout): orange "Accessibility permission was denied..." + `Button("Open System Settings")` opening `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` (Pitfall 3).
- `handlePasteBackToggleOn()`: arms immediately if `AXIsProcessTrusted()` is already true; otherwise calls `AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true])`, polls every 0.5s for up to 30s (60 polls), sets `pasteBackEnabled = true` on grant or reverts + shows denial on timeout (RESEARCH OQ-01(b)).
- Extended `.selectOutputRow` observers in `ToolShortcutActions.swift` (shared index-1 path), `ColorView.swift`, `HashView.swift`, `NumberBaseView.swift` with paste-back branch: `if prefs.pasteBackEnabled, AXIsProcessTrusted(), let app = hotkeyManager.previousFrontmostApp { clipboard.isPopoverPresented = false; pasteBackService.synthesizePaste(into: app) }`.
- Added `@Environment(PreferencesStore.self)`, `@Environment(HotkeyManager.self)`, `@Environment(PasteBackService.self)`, `@Environment(ClipboardDetector.self)` to `ToolShortcutsModifier`, `ColorContentView`, `HashView`, and `NumberBaseContentView`.
- Injected `hotkeyManager` and `pasteBackService` into the workspace `WindowGroup` (Rule 2: tool views using `.toolShortcuts(viewModel)` are rendered in the workspace window — missing env injection would cause assertionFailure crash at runtime).

---

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] activateIgnoringOtherApps deprecated on macOS 14**
- **Found during:** Task 1 — build warning.
- **Issue:** `NSRunningApplication.activate(options: [.activateIgnoringOtherApps])` is deprecated in macOS 14 with "will have no effect" note.
- **Fix:** Replaced with `app.activate()` (the macOS 14+ API).
- **Files modified:** `Core/Services/PasteBackService.swift`
- **Commit:** `24a302c`

**2. [Rule 1 - Bug] Swift 6 Sendable violation for kAXTrustedCheckOptionPrompt**
- **Found during:** Task 2 — build error: "reference to var 'kAXTrustedCheckOptionPrompt' is not concurrency-safe because it involves shared mutable state".
- **Issue:** `kAXTrustedCheckOptionPrompt` is a `CFString` global that is not `Sendable` in Swift 6.
- **Fix:** Used string literal `"AXTrustedCheckOptionPrompt"` directly. This is the stable underlying key value (unchanged since macOS 10.9) and avoids the Sendable boundary crossing.
- **Files modified:** `UI/PreferencesView.swift`
- **Commit:** `2077218`

**3. [Rule 2 - Missing critical functionality] hotkeyManager + pasteBackService not injected into workspace WindowGroup**
- **Found during:** Task 2 — reviewing FlintApp.swift environment chains.
- **Issue:** `MainWindowView` calls `tool.makeView()` which renders tool views using `.toolShortcuts(viewModel)`. The updated `ToolShortcutsModifier` reads `@Environment(HotkeyManager.self)` and `@Environment(PasteBackService.self)`. The workspace WindowGroup was missing both, which would cause an `assertionFailure` crash at runtime when any tool is opened in the workspace window.
- **Fix:** Added `.environment(hotkeyManager)` and `.environment(pasteBackService)` to the workspace `WindowGroup` in `FlintApp.swift`.
- **Files modified:** `App/FlintApp.swift`
- **Commit:** `2077218`

---

## Checkpoint Pending

**Task 3 (checkpoint:human-verify)** has NOT been executed. It requires live device testing:
1. Default-OFF toggle: no Accessibility prompt at launch or on opening Preferences (CF-02).
2. Toggle ON without permission: prompt appears, then reverts + shows orange denial + System Settings button.
3. Toggle ON with permission: toggle stays ON, shows confirmation text.
4. End-to-end: ⌘1 in Color tool copies HEX AND pastes into previously-focused app.
5. Revoke permission while ON: ⌘1 copies only, no crash (T-04-12 re-verification).
6. ⌘7 on NumberBase (4 rows): no-op, no crash.

CGEvent virtual key code 9 (RESEARCH A3) and 80ms activation delay (RESEARCH A2) are ASSUMED values that must be confirmed on real hardware during Task 3.

---

## Known Stubs

None. The paste-back feature is fully wired. The activation delay (80ms) and virtual key code (9) are implementation choices that require live verification (Task 3) rather than stubs.

---

## Threat Flags

No new network endpoints, auth paths, or file access patterns beyond those already documented in the plan's `<threat_model>`. The Accessibility/CGEvent surface is fully covered by T-04-11 through T-04-SC in the threat register.

---

## Self-Check

**Files exist:**
- `Core/Services/PasteBackService.swift`: FOUND
- `UI/PreferencesView.swift` (modified): FOUND
- `UI/Components/ToolShortcutActions.swift` (modified): FOUND

**Commits exist:**
- `24a302c` (Task 1): FOUND
- `2077218` (Task 2): FOUND

## Self-Check: PASSED
