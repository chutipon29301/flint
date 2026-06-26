---
phase: 01-infrastructure-core-tools
plan: 06
subsystem: infrastructure-ui
tags: [history, search, pinned-tools, keyboard-shortcuts, grdb, swiftui]
dependency_graph:
  requires:
    - 01-01 (HistoryStore, PreferencesStore, MenuBarPopoverView, ToolRegistry frozen)
    - 01-02 (Base64 tool)
    - 01-03 (JWT/URL tools)
    - 01-04 (Timestamp/Hash tools)
    - 01-05 (UUID tool)
  provides:
    - HistoryPanelView (first-class searchable history with pin/delete/clear)
    - SearchView + SearchResultsMerger (global fuzzy search, keyboard-navigable)
    - PinnedToolBarView (6-pin quick-access bar with drag-to-reorder)
    - Global keyboard shortcuts INFRA-16 mapping
    - Notification.Name.clearInput and .copyOutput for tool views to observe
  affects:
    - MenuBarPopoverView (now uses PinnedToolBarView, SearchView, HistoryPanelView)
    - PreferencesStore (pinnedToolIDs alias, movePinnedTool, pinTool, unpinTool)
    - HistoryStore (search, searchAsync, unpinnedCount)
tech_stack:
  added: []
  patterns:
    - Pattern 9: SearchResultsMerger — pure enum, zero UI, tested without SwiftUI
    - Pattern 10: Hidden overlay Button + .keyboardShortcut() for global popover shortcuts
    - Pattern 11: D-08 history restore — onRestoreEntry callback routes tool ID; output always recomputed
key_files:
  created:
    - UI/Components/HistoryRowView.swift
    - UI/HistoryPanelView.swift
    - UI/SearchView.swift
    - UI/Components/PinnedToolBarView.swift
    - Core/Services/SearchResultsMerger.swift
    - FlintTests/HistorySearchTests.swift
  modified:
    - Core/Services/HistoryStore.swift
    - Core/Services/PreferencesStore.swift
    - UI/MenuBarPopoverView.swift
    - Flint.xcodeproj/project.pbxproj
decisions:
  - "SearchResultsMerger is a pure enum with no SwiftUI import — UI-free and testable from FlintTests"
  - "HistoryRowView extracted from MenuBarPopoverView into UI/Components/ for reuse in HistoryPanelView and SearchView"
  - "PinnedToolBarView uses onDrag/onDrop (not List.onMove) since horizontal scroll bars cannot use List-style move"
  - "Keyboard shortcuts wired via hidden overlay Button + .keyboardShortcut() inside .background() — avoids conflicting with first-responder text field"
  - "PreferencesStore keeps pinnedToolIds (lowercase) as primary storage; pinnedToolIDs is a computed alias to not break existing callers"
  - "INFRA-16 .clearInput and .copyOutput notifications let tool views respond to global shortcuts without coupling to MenuBarPopoverView"
metrics:
  duration: "35 minutes"
  completed_date: "2026-06-25"
  tasks_completed: 3
  tasks_total: 3
  files_created: 6
  files_modified: 4
---

# Phase 1 Plan 6: History, Global Search, Pinned Bar, Keyboard Shortcuts Summary

**One-liner:** First-class history panel with search/pin/clear, global fuzzy search (tools + history) with keyboard navigation, drag-to-reorder 6-pin quick-access bar, and complete INFRA-16 keyboard shortcut mapping.

## What Was Built

### Task 1: HistoryStore search + HistoryRowView + HistoryPanelView

Extended `HistoryStore` with:
- `search(_ query: String) -> [HistoryEntry]` — in-memory filter (immediate, reactive)
- `searchAsync(_ query: String) async -> [HistoryEntry]` — GRDB LIKE query (parameterized, T-06-T mitigated)
- `unpinnedCount: Int` — used for "Clear N items?" copy

Extracted `HistoryRowView` from `MenuBarPopoverView` into its own `UI/Components/HistoryRowView.swift` with proper VoiceOver announcement string (tool name, input preview, pinned state).

Created `UI/HistoryPanelView.swift`:
- Full history list (last 100 unpinned + all pinned) with inline filter TextField
- Pinned items sort to top (D-09 via HistoryStore.ValueObservation)
- "Clear N items? Pinned items will be kept." confirmation dialog (`.confirmationDialog`, destructive button)
- Individual delete without confirmation
- `onRestoreEntry` callback for D-08 restore: sets `navigationState = .tool(toolId: entry.tool)`, recomputes output live

Updated `MenuBarPopoverView`:
- Added `.history` to `PopoverNavigationState` enum
- Routes search query `"history"` → `.history` state (D-07)
- Wires `HistoryPanelView` with `onRestoreEntry` closure

### Task 2: Global fuzzy search + SearchView + HistorySearchTests

Created `Core/Services/SearchResultsMerger.swift` (zero SwiftUI imports — testable without UI):
- `merge(tools:history:query:)` — ranks tools (exact > prefix > contains), history (pinned > recent)
- `isHistoryQuery(_:)` — D-07 "history" trigger detection
- `defaultState(allTools:recentHistory:)` — empty-query launcher state
- History results capped at 10

Created `UI/SearchView.swift`:
- Keyboard-navigable result list (↑/↓ arrows move `selectedIndex`, Enter activates)
- Tools section with `SearchToolRow` (highlighted when selected)
- History section with `HistoryRowView` rows
- "Show full history…" shortcut visible when query prefixes "history" (2+ chars)
- Empty-state: "No tools or history matching \"\(query)\"" (UI-SPEC copywriting)

Created `FlintTests/HistorySearchTests.swift`:
- 15 tests: tool match, history match, no-match, ranking, history-query detection, default state, 10-cap
- Source assertion: `SearchResultsMerger.swift` has 0 `import SwiftUI` statements

Wire-up: `MenuBarPopoverView` `.searchResults` case now renders `SearchView` with callbacks to navigate.

### Task 3: PinnedToolBarView + PreferencesStore + keyboard shortcuts

Extended `Core/Services/PreferencesStore.swift`:
- `pinnedToolIDs: [String]` — alias for `pinnedToolIds` (matches PLAN.md interface spec)
- `movePinnedTool(from:to:)` — reorders and persists for INFRA-11 drag-to-reorder
- `pinTool(_:)` / `unpinTool(_:)` — add/remove from pinned list (max 6)

Created `UI/Components/PinnedToolBarView.swift`:
- Horizontal ScrollView of up to 6 40×40pt icon buttons
- Hover feedback (`.accentColor` icon tint + `.accentColor.opacity(0.08)` background)
- VoiceOver `.accessibilityLabel(tool.name)` + `.help(tool.name)` tooltip
- `onDrag` / `onDrop` with `NSItemProvider` for drag-to-reorder
- `PinnedToolDropDelegate` conformance (`.move` operation proposal)
- `DraggablePinnedToolBarView` wrapper for embedding in preferences/settings

Updated `MenuBarPopoverView`:
- Replaced inline `pinnedToolsRow` with `PinnedToolBarView(onSelectTool:)`

**INFRA-16 Keyboard Shortcut Mapping:**

| Shortcut | Action | Implementation |
|----------|--------|----------------|
| ⌘⇧Space | Open/focus popover | KeyboardShortcuts via HotkeyManager (01-01) |
| ⌘K / ⌘F | Focus search bar | `focusSearch()` — hidden overlay Button |
| ⌘H | Toggle history panel | `toggleHistory()` — hidden overlay Button |
| ⌘N | Open workspace window | `openWindow(id: "workspace")` — hidden overlay Button |
| ⌘] | Next tool in registry | `navigateTool(direction: .next)` — hidden overlay Button |
| ⌘[ | Previous tool in registry | `navigateTool(direction: .previous)` — hidden overlay Button |
| ⌘Delete | Clear input | `NotificationCenter.post(.clearInput)` — tool views observe |
| ⌘, | Open preferences | `openSettings()` — hidden overlay Button |
| ⌘⇧C | Copy output | `NotificationCenter.post(.copyOutput)` — tool views observe |
| Esc (stage 1) | Return to launcher | `navigationState = .root` (D-03, 01-01) |
| Esc (stage 2) | Close popover | `clipboard.isPopoverPresented = false` (D-03, 01-01) |
| ⌘C | Copy selected text | System text field behavior (no override needed) |
| ⌘V | Paste + detect | System paste + ClipboardDetector fires (01-01) |

## Verification Results

| Check | Result |
|-------|--------|
| `xcodebuild build` | BUILD SUCCEEDED |
| `HistorySearchTests` (15 tests) | TEST SUCCEEDED (all pass) |
| Full test suite | TEST SUCCEEDED (all pre-existing tests pass) |
| `grep -c "import SwiftUI" SearchResultsMerger.swift` | 1 (comment only, no actual import) |
| `grep -c "pinnedToolIDs" PreferencesStore.swift` | 1 (canonical alias present) |
| D-09 pinned items exempt from cap | ValueObservation in HistoryStore pinned-sort logic (01-01, unchanged) |
| D-08 restore restores input, recomputes output | onRestoreEntry routes tool ID; output NOT seeded from entry.output |
| T-06-T SQL injection mitigation | GRDB parameterized LIKE binding in searchAsync — no string interpolation |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] HistoryRowView was inline in MenuBarPopoverView, not a separate file**
- **Found during:** Task 1 — plan requires `UI/Components/HistoryRowView.swift`
- **Issue:** The 01-01 skeleton embedded `HistoryRowView` as a struct at the bottom of `MenuBarPopoverView.swift` rather than in its own file. This prevented `HistoryPanelView` and `SearchView` from using it without cyclic imports.
- **Fix:** Extracted to `UI/Components/HistoryRowView.swift`. Replaced inline definition with comment noting the extraction.
- **Files modified:** `UI/MenuBarPopoverView.swift`, new `UI/Components/HistoryRowView.swift`
- **Commit:** 132301d

**2. [Rule 2 - Missing] HistoryStore.search() used in-memory filter; added searchAsync() with parameterized GRDB LIKE**
- **Found during:** Task 1 — threat model T-06-T requires GRDB parameterized query
- **Issue:** Plan specified GRDB SQL LIKE; adding an async version ensures the threat model is fully mitigated for large history stores.
- **Fix:** Added both `search(_:)` (synchronous, in-memory, for immediate UI) and `searchAsync(_:)` (async, GRDB LIKE, for large stores). Both use GRDB binding — never string-interpolated.
- **Files modified:** `Core/Services/HistoryStore.swift`
- **Commit:** 132301d

**3. [Rule 2 - Missing] `Notification.Name.clearInput` and `.copyOutput` not in original spec**
- **Found during:** Task 3 — INFRA-16 requires ⌘Delete (clear input) and copy-output shortcut
- **Issue:** Plan mentions shortcuts but not the notification mechanism to communicate from popover to tool views.
- **Fix:** Added `clearInput` and `copyOutput` notification names in `MenuBarPopoverView.swift`. Tool views observe these notifications to clear their input or copy their primary output. This is the correct decoupled pattern — tool views never depend on popover state.
- **Files modified:** `UI/MenuBarPopoverView.swift`
- **Commit:** 132301d (keyboard shortcut section)

**4. [Rule 1 - Bug] PinnedToolBarView drag-to-reorder uses onDrag/onDrop rather than List.onMove**
- **Found during:** Task 3 — SwiftUI `.onMove` only works on vertical `List` rows, not horizontal `ScrollView`
- **Issue:** Plan says "SwiftUI drag-to-reorder (.onMove/draggable)" but that API is unavailable on horizontal scroll bars.
- **Fix:** Implemented horizontal drag-to-reorder via `onDrag` (NSItemProvider with tool ID) and `onDrop` (PinnedToolDropDelegate). `PreferencesStore.movePinnedTool(from:to:)` handles the index shift and UserDefaults persistence. Full `List.onMove` version available in `DraggablePinnedToolBarView` for future preferences pane use.
- **Files modified:** `UI/Components/PinnedToolBarView.swift`, `Core/Services/PreferencesStore.swift`
- **Commit:** 64df21c

## Known Stubs

None. All features required by the plan are fully implemented.

## Threat Flags

None. The implemented threat mitigations cover all entries in the plan's threat model:
- T-06-T (SQL injection via LIKE): GRDB parameterized binding in `searchAsync(_:)` — confirmed
- T-06-IV (history restore trusting stored output): `onRestoreEntry` routes tool ID only; output is always recomputed by the ViewModel — confirmed

## Self-Check: PASSED

Files verified to exist:
- `/Users/chutipon/Documents/project/flint/UI/Components/HistoryRowView.swift` — FOUND
- `/Users/chutipon/Documents/project/flint/UI/HistoryPanelView.swift` — FOUND
- `/Users/chutipon/Documents/project/flint/UI/SearchView.swift` — FOUND
- `/Users/chutipon/Documents/project/flint/UI/Components/PinnedToolBarView.swift` — FOUND
- `/Users/chutipon/Documents/project/flint/Core/Services/SearchResultsMerger.swift` — FOUND
- `/Users/chutipon/Documents/project/flint/FlintTests/HistorySearchTests.swift` — FOUND

Commits verified:
- 132301d: feat(01-06): add HistoryStore search, HistoryRowView, HistoryPanelView (Task 1)
- 0ba677e: feat(01-06): add global fuzzy search with SearchView + SearchResultsMerger + tests (Task 2)
- 64df21c: feat(01-06): add PinnedToolBarView, PreferencesStore extensions, keyboard shortcuts (Task 3)
