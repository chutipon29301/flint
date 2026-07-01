---
phase: 06-remove-the-history-feature
plan: "03"
subsystem: tools
tags: [history-removal, uuid, timestamp, textdiff, markdown, imagecompress, refactor]
dependency_graph:
  requires: []
  provides: [uuid-no-history, timestamp-no-history, textdiff-no-history, markdown-no-history, imagecompress-no-history]
  affects: [FlintTests/ImageCompressViewModelTests]
tech_stack:
  added: []
  patterns: [no-closure-vm-init, direct-makeView]
key_files:
  created: []
  modified:
    - Tools/UUID/UUIDViewModel.swift
    - Tools/UUID/UUIDView.swift
    - Tools/UUID/UUIDDefinition.swift
    - Tools/Timestamp/TimestampViewModel.swift
    - Tools/Timestamp/TimestampView.swift
    - Tools/Timestamp/TimestampDefinition.swift
    - Tools/TextDiff/TextDiffViewModel.swift
    - Tools/TextDiff/TextDiffView.swift
    - Tools/TextDiff/TextDiffDefinition.swift
    - Tools/Markdown/MarkdownViewModel.swift
    - Tools/Markdown/MarkdownView.swift
    - Tools/Markdown/MarkdownDefinition.swift
    - Tools/ImageCompress/ImageCompressViewModel.swift
    - Tools/ImageCompress/ImageCompressView.swift
    - Tools/ImageCompress/ImageCompressDefinition.swift
    - FlintTests/ImageCompressViewModelTests.swift
decisions:
  - "All five Wrapper-pattern tools converted to no-closure VM inits; makeView builds view directly"
  - "testHistoryFiresOnce and its local HistoryStore shim deleted from ImageCompressViewModelTests"
  - "wasCancelled variable removed from ImageCompressViewModel drain loop — no longer needed without history write"
metrics:
  duration: "~12 minutes"
  completed: "2026-07-01"
  tasks_completed: 3
  files_modified: 16
---

# Phase 06 Plan 03: Strip History from UUID, Timestamp, TextDiff, Markdown, ImageCompress — Summary

Strip all per-tool history capture from the UUID, Timestamp, Text Diff, Markdown, and Image Compress tools (Wrapper-pattern) and clean the ImageCompressViewModelTests test file.

## What Was Built

Removed the history subsystem integration from five tools (all using the Wrapper-pattern) and their associated test file. Each tool's ViewModel, View, and Definition file was updated to eliminate all `onSaveHistory`, `HistoryEntry`, and `HistoryStore` references.

## Tasks Completed

| Task | Description | Commit | Files |
|------|-------------|--------|-------|
| 1 | Remove history from UUID and Timestamp tools | 80078a0 | UUIDViewModel, UUIDView, UUIDDefinition, TimestampViewModel, TimestampView, TimestampDefinition |
| 2 | Remove history from TextDiff and Markdown tools | f2fa993 | TextDiffViewModel, TextDiffView, TextDiffDefinition, MarkdownViewModel, MarkdownView, MarkdownDefinition |
| 3 | Remove history from ImageCompress and its test file | b8bb325 | ImageCompressViewModel, ImageCompressView, ImageCompressDefinition, ImageCompressViewModelTests |

## Changes Made

### Pattern Applied (All Five Tools)

**ViewModel:** Deleted `private let onSaveHistory: (HistoryEntry) -> Void` stored property, removed the `onSaveHistory:` init parameter (replaced with `init() {}`), and removed every `onSaveHistory(HistoryEntry(...))` call site.

**View:** Changed `init(onSaveHistory:)` to a plain no-arg `init()` that builds `SomeViewModel()` directly. Removed any `@Environment(HistoryStore.self)` properties from views that had them (UUIDView, TextDiffView).

**Definition:** Deleted the `_SomeViewWrapper` / `SomeViewWrapper` private struct and its `@Environment(HistoryStore.self)` property. Changed `makeView` closure from `AnyView(SomeViewWrapper())` to `AnyView(SomeView())` directly.

### Tool-Specific Notes

- **TextDiffView**: Had a lazy-init pattern that passed a closure capturing `historyStore`. Replaced with `TextDiffViewModel()` in `.onAppear`. Also removed `.environment(HistoryStore())` from the `#Preview`.
- **MarkdownView**: Had a stored `let onSaveHistory: (HistoryEntry) -> Void` property (not an init param) at line 13. Removed that property and updated the VM build at line 28.
- **ImageCompressViewModel**: Had a more complex drain loop that captured `capturedOnSave = onSaveHistory` and fired one aggregate HistoryEntry per successful batch. Removed the capture, the HistoryEntry construction, and the now-unused `let wasCancelled = Task.isCancelled` variable.

### Test File (ImageCompressViewModelTests.swift)

- Replaced all 11 `ImageCompressViewModel(onSaveHistory: { _ in })` call sites with `ImageCompressViewModel()`
- Deleted the entire `testHistoryFiresOnce` test function (lines 256–297) which tested that `onSaveHistory` fires exactly once per batch — this behavior no longer exists
- Deleted the local `final class HistoryStore` shim defined inside that test function

## Verification

```
grep -rn "onSaveHistory\|HistoryEntry\|HistoryStore" \
  Tools/UUID/ Tools/Timestamp/ Tools/TextDiff/ Tools/Markdown/ Tools/ImageCompress/ \
  FlintTests/ImageCompressViewModelTests.swift
```
Returns nothing — all five tools and the test file are clean.

All five `makeView` closures now build their views directly:
- `AnyView(UUIDView())`
- `AnyView(TimestampView())`
- `AnyView(TextDiffView())`
- `AnyView(MarkdownView())`
- `AnyView(ImageCompressView())`

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None. All tools retain their full non-history functionality (generation, conversion, diff computation, markdown rendering, image compression).

## Threat Flags

None. No new network endpoints, auth paths, file access patterns, or schema changes introduced.

## Self-Check: PASSED

- `Tools/UUID/UUIDDefinition.swift` — exists, contains `AnyView(UUIDView())`
- `Tools/Timestamp/TimestampDefinition.swift` — exists, contains `AnyView(TimestampView())`
- `Tools/TextDiff/TextDiffDefinition.swift` — exists, contains `AnyView(TextDiffView())`
- `Tools/Markdown/MarkdownDefinition.swift` — exists, contains `AnyView(MarkdownView())`
- `Tools/ImageCompress/ImageCompressDefinition.swift` — exists, contains `AnyView(ImageCompressView())`
- `FlintTests/ImageCompressViewModelTests.swift` — exists, `testHistoryFiresOnce` absent, no `HistoryStore` shim
- Commits 80078a0, f2fa993, b8bb325 — all present in git log
