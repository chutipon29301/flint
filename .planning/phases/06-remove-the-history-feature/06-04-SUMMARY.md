---
phase: 06-remove-the-history-feature
plan: 04
subsystem: ui
tags: [swiftui, search, refactor]

# Dependency graph
requires:
  - phase: 06-01
    provides: HistoryStore/HistoryEntry/HistoryRowView removal groundwork (Hash/JWT/Base64/URL history call-site cleanup)
  - phase: 06-02
    provides: NumberBase history cleanup
  - phase: 06-03
    provides: Additional tool history cleanup (parallel wave)
provides:
  - Tools-only SearchResultsMerger (pure merge/rank function, no HistoryEntry reference)
  - Tools-only SearchView (no HistoryStore environment dependency, no History section/button)
affects: [06-05, history-store-deletion-wave]

# Tech tracking
tech-stack:
  added: []
  patterns: []

key-files:
  created: []
  modified:
    - Core/Services/SearchResultsMerger.swift
    - UI/SearchView.swift

key-decisions:
  - "Kept SearchResult as single-case enum (.tool) rather than collapsing to a plain struct, to minimize caller-side diff and preserve the flatResults/activateSelected navigation shape for a later editor pass."

patterns-established: []

requirements-completed: [INFRA-10]

# Metrics
duration: 12min
completed: 2026-07-02
---

# Phase 06 Plan 04: Tools-only Global Search Summary

**Reduced SearchResultsMerger and SearchView to a pure tools-only search path — dropped the history merge branch, History section, "Show full history…" button, and HistoryStore environment dependency, while preserving tool ranking and ↑↓/Enter keyboard navigation.**

## Performance

- **Duration:** ~12 min
- **Started:** 2026-07-02T09:10:00Z
- **Completed:** 2026-07-02T09:22:00Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- `SearchResultsMerger` is now a pure tools-only merge/rank function: `SearchResult` has only `.tool`, `MergedSearchResults` has only `toolResults`, `merge(tools:query:)` drops the history param, `isHistoryQuery` deleted, `defaultState(allTools:)` drops `recentHistory`.
- `SearchView` no longer references `HistoryStore`, `HistoryEntry`, `HistoryRowView`, `onSelectHistoryEntry`, or `onShowHistory`. History section and "Show full history…" button removed. Empty-state copy updated to "No tools matching...".
- Full project build (`xcodebuild -project Flint.xcodeproj -scheme Flint -destination 'platform=macOS' build`) succeeds after both changes — no new compiler errors introduced.

## Task Commits

Each task was committed atomically:

1. **Task 1: Reduce SearchResultsMerger to tools-only** - `17d51f6` (refactor)
2. **Task 2: Make SearchView tools-only** - `5b1f3b1` (refactor)

**Plan metadata:** committed alongside SUMMARY.md by orchestrator after wave merge (worktree mode — this executor does not write STATE.md/ROADMAP.md).

## Files Created/Modified
- `Core/Services/SearchResultsMerger.swift` - Tools-only merge/rank; removed `.historyEntry` case, `historyResults`, `isHistoryQuery`, `history`/`recentHistory` params.
- `UI/SearchView.swift` - Tools-only view; removed `@Environment(HistoryStore.self)`, history closures, History section, "Show full history…" button, and the `.historyEntry` switch case in `activateSelected()`.

## Decisions Made
- Kept `SearchResult` as a single-case enum (`.tool`) instead of collapsing directly to `ToolDefinition`, minimizing the diff to `flatResults`/`activateSelected` so future editors touching this file see a stable shape. No history references remain either way.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None. As anticipated by the plan's own verification note, `FlintTests/HistorySearchTests.swift` still references the pre-change `SearchResultsMerger` API (old `merge(tools:history:query:)` signature) — this is explicitly out of scope for 06-04 and is deleted in Wave 3 per the plan text. No test changes were made in this plan.

Per the plan's file-ownership boundary, `MenuBarPopoverView` was not touched — it currently instantiates its own grid/history list rather than `SearchView`, and no caller in the codebase currently instantiates `SearchView` at all; caller-side wiring is scoped to plan 06-05.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- `SearchResultsMerger` and `SearchView` are fully history-free and ready for `HistoryStore`/`HistoryEntry`/`HistoryRowView` deletion in the Wave 3 cleanup plan.
- `FlintTests/HistorySearchTests.swift` remains referencing the old signature and must be deleted (not updated) when the history store is removed in Wave 3 — flagging this explicitly so the Wave 3 executor does not attempt to "fix" it instead of deleting it.

---
*Phase: 06-remove-the-history-feature*
*Completed: 2026-07-02*
