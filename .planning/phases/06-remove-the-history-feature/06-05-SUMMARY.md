---
phase: 06-remove-the-history-feature
plan: 05
subsystem: app-shell-popover-preferences
tags: [history-removal, swiftui, preferences, menubar-popover]
requires:
  - 06-01 (Hash/JWT/Base64/URL history removal groundwork)
  - 06-02 (NumberBase history cleanup)
  - 06-03 (prior wave history removal)
provides:
  - "App shell (FlintApp, MainWindowView) with no HistoryStore injection anywhere"
  - "Popover (MenuBarPopoverView) with no history nav state, no recent/filtered history UI, no ⌘H shortcut"
  - "Preferences with no History tab and PreferencesStore with no historyLimit"
affects:
  - App/FlintApp.swift
  - UI/MenuBarPopoverView.swift
  - UI/MainWindowView.swift
  - Core/Services/PreferencesStore.swift
  - UI/PreferencesView.swift
tech-stack:
  added: []
  patterns:
    - "Popover launcher (.root state) now renders AllToolsGridView directly with no wrapper VStack — the grid never renders empty (12 registered tools), so no separate welcome/empty-state view is needed"
key-files:
  created: []
  modified:
    - App/FlintApp.swift
    - UI/MainWindowView.swift
    - UI/MenuBarPopoverView.swift
    - Core/Services/PreferencesStore.swift
    - UI/PreferencesView.swift
decisions:
  - "Dropped the 'Welcome to Flint' empty-state view (previously only shown when recentHistoryView's history list was empty) rather than re-homing it, since AllToolsGridView always renders a populated 4-column grid (12 tools) and is never empty on its own — per the plan's explicit fallback option to drop the welcome view if the grid renders acceptably alone."
metrics:
  duration: "~15 minutes"
  completed: 2026-07-02
  tasks_completed: 3
  files_changed: 5
---

# Phase 06 Plan 05: Strip App-Level History Wiring, Popover History Nav/⌘H, and History Preference Summary

Removed all app-level HistoryStore wiring, the history navigation state and ⌘H shortcut in the popover, the unused HistoryStore reference in the workspace window, and the entire History preference (limit property, key, and Preferences tab) — leaving the app shell, popover, workspace, and preferences fully functional with zero reachable history surface.

## What Was Built

### Task 1: Strip history from FlintApp and MainWindowView
- Removed `@State private var historyStore = HistoryStore()` from `FlintApp`.
- Removed every `.environment(historyStore)` injection: on `MenuBarPopoverView`, `MainWindowView`, and the `Settings`/`PreferencesView` scene (including its "CR-01" comment).
- Removed the `.onChange(of: prefs.historyLimit, initial: true) { ... historyStore.historyLimit = newLimit }` modifier and its "WR-04" comment.
- Removed the unused `@Environment(HistoryStore.self) private var historyStore` from `MainWindowView`.

### Task 2: Strip history navigation, recent-history, and ⌘H from MenuBarPopoverView
- Removed `@Environment(HistoryStore.self) private var historyStore`.
- Removed `case history` from `PopoverNavigationState`; updated its doc comment.
- Removed the hidden ⌘H "Toggle History" button and the `toggleHistory()` function; updated the header doc block (removed the ⌘H line and stale D-13/"recent history" mentions).
- Removed the `"history"` search-query branch in `.onChange(of: searchText)` that opened the history nav state.
- In `bodyContent`: `.root` now renders only `AllToolsGridView`; `.searchResults` renders only the filtered grid + `Spacer`; the `.history` case was deleted entirely.
- Removed `recentHistoryView` and `filteredHistoryList(_:)`. The "Welcome to Flint" empty state (previously nested inside `recentHistoryView` and only shown when history was empty) was dropped rather than re-homed, per the plan's explicit fallback — `AllToolsGridView` always renders a non-empty 4-column grid of the 12 registered tools, so the launcher is never visually empty.
- Changed the search field placeholder from "Search tools or history…" to "Search tools…" and its accessibility label from "Search tools or history" to "Search tools".
- Removed the trailing `// HistoryRowView is defined in ...` comment.

### Task 3: Remove the History preference (limit + tab)
- Deleted the `historyLimit` computed property and its "History Limit (INFRA-13)" MARK section from `PreferencesStore`.
- Deleted `Keys.historyLimit` from the `Keys` enum.
- Deleted `@Environment(HistoryStore.self) private var historyStore` and its `.environment(historyStore)` propagation from `PreferencesView`.
- Removed the `HistoryPreferencesTab()` entry and its `.tabItem` from the `TabView` — General, Appearance, and Tools (Per-Tool) tabs remain.
- Deleted the entire `HistoryPreferencesTab` struct (history-limit stepper + "Clear All History" button/confirmation dialog).
- Updated the file header comment to drop "History" from the tab list.

## Verification

- `grep -n "HistoryStore\|historyStore\|historyLimit" App/FlintApp.swift UI/MainWindowView.swift` → no matches.
- `grep -n "HistoryStore\|HistoryEntry\|HistoryRowView\|HistoryPanelView\|\.history\b\|toggleHistory\|Toggle History\|or history" UI/MenuBarPopoverView.swift` → no matches.
- `grep -n 'keyboardShortcut("h"' UI/MenuBarPopoverView.swift` → no matches.
- `grep -n "historyLimit\|Keys.historyLimit" Core/Services/PreferencesStore.swift` → no matches.
- `grep -n "HistoryStore\|historyLimit\|HistoryPreferencesTab\|clearUnpinned" UI/PreferencesView.swift` → no matches.
- `grep -n "GeneralPreferencesTab\|AppearancePreferencesTab\|PerToolPreferencesTab" UI/PreferencesView.swift` → 6 matches (all three tabs present, both declaration and TabView usage).
- Full-tree verification grep across all five files for `HistoryStore|HistoryEntry|historyLimit|HistoryPreferencesTab|toggleHistory|\.history\b` → no matches.
- `xcodebuild -project Flint.xcodeproj -scheme Flint -configuration Debug -destination 'platform=macOS' build` → **BUILD SUCCEEDED**. `HistoryStore.swift` and other history model/view files still exist in the target (their deletion is deferred to Wave 3) and compiled cleanly; nothing in the five modified files references them.

## Deviations from Plan

None — plan executed exactly as written. The plan explicitly offered two options for the launcher's empty/welcome affordance (preserve it or drop it if the grid renders acceptably alone); this executor chose to drop it since `AllToolsGridView` always shows a populated 4-column grid of all 12 registered tools and never renders as visually empty on its own.

## Known Stubs

None.

## Threat Flags

None — this plan only removes surface area (history UI, history preference, HistoryStore injection); it introduces no new network endpoints, auth paths, file access patterns, or schema changes.

## Self-Check: PASSED

- FOUND: App/FlintApp.swift
- FOUND: UI/MainWindowView.swift
- FOUND: UI/MenuBarPopoverView.swift
- FOUND: Core/Services/PreferencesStore.swift
- FOUND: UI/PreferencesView.swift
- FOUND: c26f53b (Task 1 commit)
- FOUND: 00430b7 (Task 2 commit)
- FOUND: 86f3388 (Task 3 commit)
