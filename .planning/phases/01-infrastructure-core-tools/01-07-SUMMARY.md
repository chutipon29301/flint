---
phase: 01-infrastructure-core-tools
plan: 07
subsystem: infra
tags: [swiftui, preferences, SMAppService, accessibility, performance, GRDB, menubar, workspace]

requires:
  - phase: 01-infrastructure-core-tools/01-01
    provides: walking skeleton — MenuBarExtra + WindowCoordinator + ToolRegistry + frozen ToolDefinition
  - phase: 01-infrastructure-core-tools/01-06
    provides: HistoryStore, SearchView, PinnedToolBarView, PreferencesStore extensions (pinnedToolIDs)

provides:
  - PreferencesView with General/Appearance/History/per-tool tabs, all settings wired
  - PreferencesStore extended with launchAtLogin (SMAppService), showInDock, theme, codeFont, fontSize, historyLimit
  - Detachable MainWindowView workspace (min 800x600, NavigationSplitView, last-mode persistence)
  - WindowCoordinator activation dance for both Preferences and Workspace windows
  - Full accessibility audit (automated source checks) — labels on all interactive elements + NSTextView wrappers
  - Release build verified — no get-task-allow in entitlements, off-main GRDB open, notification-driven clipboard
  - Performance checkpoint accepted on source-level architecture checks; on-hardware measurements deferred (see Task 4 notes)

affects: [phase-02, distribution, phase-03-polish]

tech-stack:
  added: [ServiceManagement (SMAppService), KeyboardShortcuts.Recorder (in PreferencesView)]
  patterns:
    - WindowCoordinator activation dance — setActivationPolicy(.regular) + makeKeyAndOrderFront for prefs/workspace in front
    - SMAppService.mainApp.register()/unregister() triggered live from PreferencesStore.launchAtLogin setter
    - lazy makeView factory in ToolDefinition — ViewModel constructed only on navigation, not at app launch
    - Task.detached(priority:.utility) for GRDB open and all DB writes — main thread never blocked
    - NSPasteboardDidChangeNotification + isPopoverPresented visibility gate — 0% idle CPU (pitfall #7)

key-files:
  created:
    - UI/PreferencesView.swift (General/Appearance/History/per-tool tabs, SMAppService wired)
    - .planning/phases/01-infrastructure-core-tools/01-07-a11y-audit.md (Task 3 audit record)
  modified:
    - Core/Services/PreferencesStore.swift (launchAtLogin, showInDock, theme, codeFont, fontSize, historyLimit)
    - UI/MainWindowView.swift (NavigationSplitView workspace, min 800x600, last-mode persistence)
    - App/LatheApp.swift (.preferredColorScheme on all 3 scenes, Settings scene declaration)
    - App/WindowCoordinator.swift (openPreferences + openWorkspace + activation dance)

key-decisions:
  - "WindowCoordinator activation dance (not openSettings()) for macOS 14 .accessory compatibility (pitfall #2)"
  - "SMAppService.mainApp register/unregister on launchAtLogin setter — Apple-sanctioned, no prompt"
  - "Task 3 checkpoint accepted on automated source checks; live VoiceOver/Light-Dark pass deferred to pre-release"
  - "Task 4 (performance audit) checkpoint accepted on source-level architecture checks only; on-hardware measurements (cold start <500ms, hotkey-to-popover <200ms, peak RAM <100MB, idle CPU <0.5%) were NOT taken and are deferred — recommend an Instruments pass before release. The architecture structurally supports the budget but the numbers are unmeasured."

patterns-established:
  - "WindowCoordinator: all window-open paths go through it to ensure correct activation policy dance"
  - "PreferencesStore: computed properties backed by UserDefaults with type-safe keys enum; never stores secrets"
  - "ToolDefinition.makeView: lazy factory pattern — no ViewModel allocated until tool is navigated to"

requirements-completed: [INFRA-02, INFRA-12, INFRA-13, INFRA-14, INFRA-15, INFRA-18]

duration: ~90min (all 4 tasks; Task 4 accepted on source-level architecture checks)
completed: 2026-06-25
---

# Phase 01 Plan 07: Preferences + Workspace + Accessibility + Performance Audit Summary

**Preferences window (4 tabs, SMAppService launch-at-login, live theme/font/history settings), detachable 800x600 workspace, full automated accessibility source audit — performance running-app measurement at checkpoint awaiting Instruments**

## Performance

- **Duration:** ~90 min
- **Started:** 2026-06-25T15:30:00Z
- **Completed:** 2026-06-25 (all 4 tasks complete; Task 4 accepted on source-level checks)
- **Tasks completed:** 4 of 4 (Task 4 checkpoint accepted on source-level checks; on-hardware measurements deferred)
- **Files modified:** 6 source files + 1 planning/audit file

## Accomplishments

- Preferences window with General / Appearance / History / per-tool tabs; all settings wired (INFRA-12, INFRA-13)
- SMAppService.mainApp register/unregister live-wired in PreferencesStore.launchAtLogin — no Accessibility prompt
- Detachable MainWindowView workspace (NavigationSplitView, min 800x600, last-mode persisted in PreferencesStore) (INFRA-02)
- WindowCoordinator activation dance fixes macOS 14 bug where openSettings() is hidden behind frontmost app (pitfall #2)
- Automated accessibility source check PASSED: zero hardcoded hex colors, .accessibilityLabel on all interactive elements + NSTextView wrappers with .textArea role (INFRA-14, INFRA-15)
- Release build succeeded; entitlements verified (no get-task-allow); GRDB off-main-thread open confirmed (pitfall #6); clipboard notification-driven with visibility gate (pitfall #7) confirmed

## Task Commits

Each task was committed atomically:

1. **Task 1: Preferences window (4 tabs) + all settings wired** - `ec35fc9` (feat)
2. **Task 2: Detachable resizable workspace window** - `2bbe4ca` (feat)
3. **Task 3: Light/Dark + VoiceOver + Dynamic Type audit** - `1f5e2ff` (docs/audit)
4. **Task 4: Performance audit** - ACCEPTED on source-level architecture checks; on-hardware Instruments measurements NOT taken and deferred to pre-release

## Files Created/Modified

- `Core/Services/PreferencesStore.swift` - Extended: launchAtLogin (SMAppService), showInDock, defaultOpenMode, clipboardAutoDetect, theme, codeFont, codeFontSize, historyLimit, lastWorkspaceToolId
- `UI/PreferencesView.swift` - New: 4-tab preferences (General/Appearance/History/per-tool)
- `UI/MainWindowView.swift` - Fleshed out: NavigationSplitView with ToolRegistry sidebar, content area, min 800x600
- `App/LatheApp.swift` - Updated: .preferredColorScheme on all 3 scenes (INFRA-14)
- `App/WindowCoordinator.swift` - Updated: openPreferences() + openWorkspace() activation dance
- `.planning/phases/01-infrastructure-core-tools/01-07-a11y-audit.md` - Task 3 audit record (accepted on automated checks)

## Decisions Made

- Used WindowCoordinator activation dance instead of openSettings() — macOS 14 with .accessory policy silently hides the settings window behind the frontmost app (pitfall #2 documented in RESEARCH.md)
- SMAppService.mainApp is the Apple-sanctioned API since macOS 13+; used in PreferencesStore.launchAtLogin computed property setter
- Task 3 checkpoint accepted on automated source-level checks only — live VoiceOver/Light-Dark/Dynamic-Type observation was NOT run and is deferred to pre-release manual validation
- Task 4 source-level performance checks verified (GRDB off-main, lazy factory, notification-driven clipboard); running-app Instruments measurement not automatable and requires human checkpoint

## Deviations from Plan

None - plan executed exactly as specified. Task 3 checkpoint was resolved as per explicit checkpoint_resolution instructions: accepted on automated source checks, honest audit record committed noting that live manual pass was deferred.

## Accessibility Audit Results (Task 3)

**Method:** Automated source-level checks only.

| Check | Result | Details |
|-------|--------|---------|
| Hardcoded hex colors | CLEAN | `grep -rl "Color(red:\|Color(hex:\|\.init(red:" UI Tools` → no matches |
| Interactive element labels | PRESENT | All Button/Toggle/Picker/TextField/DatePicker in all 7 tools carry `.accessibilityLabel()` |
| NSTextView wrapper | PRESENT | `SyntaxEditorView.makeNSView` calls `setAccessibilityLabel()` + `setAccessibilityRole(.textArea)` |
| .preferredColorScheme | PRESENT | Applied to MenuBarPopoverView, MainWindowView, PreferencesView scenes |
| PreferencesView labels | PRESENT | Every control in all 4 tabs has `.accessibilityLabel()` |

**IMPORTANT:** Live VoiceOver walkthrough, Light/Dark toggle, accent color change, and Dynamic Type max were NOT run. Manual confirmation recommended before public v1.0 release.

## Performance Audit Results (Task 4 — checkpoint accepted)

**IMPORTANT:** Performance checkpoint was accepted on source-level architecture checks only. On-hardware measurements (cold start <500ms, hotkey-to-popover <200ms, peak RAM <100MB, idle CPU <0.5%) were NOT taken and are deferred. The architecture structurally supports the budget but the numbers are unmeasured. An Instruments pass is recommended before public v1.0 release.

**What was verified automatically:**

| Check | Pattern | Status |
|-------|---------|--------|
| GRDB off-main open (pitfall #6) | `Task.detached(priority: .utility) { try HistoryStore.openDatabase() }` in HistoryStore.initializeDatabase() | VERIFIED |
| Lazy ViewModel init | `makeView: { @MainActor in … }` factory in all 7 tool Definition files — only called on navigation | VERIFIED |
| GRDB writes off-main | All save/delete/pin operations use `Task.detached(priority: .utility)` | VERIFIED |
| Clipboard idle CPU (pitfall #7) | `NSPasteboardDidChangeNotification` (not polling timer) + `guard isEnabled, isPopoverPresented else { return }` gate | VERIFIED |
| PreferencesStore startup cost | Pure UserDefaults computed properties — no I/O at init | VERIFIED |
| HotkeyManager startup cost | `KeyboardShortcuts.onKeyDown` registration only — no I/O, no permissions dialog | VERIFIED |
| Release build | `xcodebuild -scheme Lathe -configuration Release build` → `BUILD SUCCEEDED` | VERIFIED |
| Entitlements security gate | No `get-task-allow` key in `Lathe-release.entitlements` (only in XML comments) | VERIFIED |
| No-crash on malformed input | All tools have INFRA-17 tests — 1MB garbage JSON, non-existent file hash, garbage URL, empty inputs — all pass | VERIFIED (TEST SUCCEEDED) |

**What requires human measurement (Instruments) — DEFERRED to pre-release:**

These measurements were NOT taken. The checkpoint was accepted on source-level architecture checks. Actual numbers are unknown.

| Target | Method Required | Budget | Status |
|--------|----------------|--------|--------|
| Cold start < 500ms | Instruments "App Launch" template on Release build | < 500ms | UNMEASURED — deferred |
| Hotkey-to-popover < 200ms | Stopwatch or Instruments, press ⌘⇧Space on Release build | < 200ms | UNMEASURED — deferred |
| Steady-state RAM < 100MB | Activity Monitor / Instruments Allocations, open several tools + history | < 100MB | UNMEASURED — deferred |
| Idle CPU < 0.5% | Activity Monitor, popover closed, 60-second observation | < 0.5% | UNMEASURED — deferred |

## Issues Encountered

None. The macOS 14 openSettings() pitfall was already anticipated and addressed in Task 1 using WindowCoordinator.

## User Setup Required

None - no external service configuration required beyond standard macOS developer setup.

## Next Phase Readiness

- All Phase 1 infrastructure requirements INFRA-02, INFRA-12, INFRA-13, INFRA-14 (partial — source-verified; live VoiceOver/Light-Dark pass deferred), INFRA-15 (partial — source-verified; live pass deferred), INFRA-18 (source-verified; on-hardware measurement deferred) are structurally complete
- Phase 2 extended tools (Regex, Color, Markdown, Number Base, Text Diff) can begin — ToolRegistry + ToolDefinition contract frozen since 01-01
- Before public v1.0 release: (1) run manual VoiceOver/Light-Dark/Dynamic-Type pass (Task 3 deferred items), (2) run Instruments performance measurement pass (Task 4 — cold start, hotkey latency, RAM, idle CPU are all unmeasured)

## Known Stubs

None — all tool views are fully wired to their ViewModels and live data.

---
*Phase: 01-infrastructure-core-tools*
*Completed: 2026-06-25*
