---
phase: 06-remove-the-history-feature
plan: "02"
subsystem: tools/color,tools/regex,tools/json-formatter,tools/number-base
tags: [refactor, history-removal, cleanup]
dependency_graph:
  requires: []
  provides: [color-no-history, regex-no-history, json-formatter-no-history, number-base-no-history]
  affects: [HistoryStore-removal-wave3]
tech_stack:
  added: []
  patterns: [environment-in-view-cleanup, wrapper-pattern-cleanup]
key_files:
  modified:
    - Tools/Color/ColorViewModel.swift
    - Tools/Color/ColorView.swift
    - Tools/Regex/RegexViewModel.swift
    - Tools/Regex/RegexView.swift
    - Tools/JSONFormatter/JSONFormatterViewModel.swift
    - Tools/JSONFormatter/JSONFormatterView.swift
    - Tools/NumberBase/NumberBaseViewModel.swift
    - Tools/NumberBase/NumberBaseView.swift
    - Tools/NumberBase/NumberBaseDefinition.swift
decisions:
  - "NumberBaseView uses @State private var viewModel = NumberBaseViewModel() (stored property default) instead of custom init — cleaner than init(onSaveHistory:) removal with @State workaround"
metrics:
  duration: "~15 minutes"
  completed: "2026-07-01"
  tasks_completed: 3
  files_modified: 9
---

# Phase 06 Plan 02: Remove History from Color, Regex, JSON, and Number Base Tools Summary

Strip all per-tool history capture from Color, Regex, JSON Formatter, and Number Base tools by removing onSaveHistory closures, HistoryEntry calls, HistoryStore environment reads, and stale GRDB comment lines from 8 source files plus the NumberBaseDefinition wrapper.

## Tasks Completed

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | Remove history from Color and Regex tools (Environment-in-View pattern) | ee47b8e | ColorViewModel.swift, ColorView.swift, RegexViewModel.swift, RegexView.swift |
| 2 | Remove history from JSON Formatter tool (Environment-in-View pattern) | c2961e4 | JSONFormatterViewModel.swift, JSONFormatterView.swift |
| 3 | Remove history from Number Base tool (Wrapper pattern) | bd45112 | NumberBaseViewModel.swift, NumberBaseView.swift, NumberBaseDefinition.swift |

## What Was Built

**Color tool (Environment-in-View):**
- `ColorViewModel`: removed `onSaveHistory` stored property, `init(onSaveHistory:)` param, all `saveHistory(input:)` call sites (6 total: hex, RGB, HSL, HSV, OKLCH, eyedropper), `saveHistory()` helper method, and the stale GRDB comment line 5. Changed to `init()`.
- `ColorView`: removed `@Environment(HistoryStore.self) private var historyStore` and the `onSaveHistory: { [historyStore] entry in historyStore.save(entry) }` argument when constructing ColorViewModel.

**Regex tool (Environment-in-View):**
- `RegexViewModel`: removed `onSaveHistory` stored property, `init(onSaveHistory:)` param, the `onSaveHistory(HistoryEntry(...))` call in `runEval`, and the stale GRDB comment line 6. Changed to `init() {}`.
- `RegexView`: removed `@Environment(HistoryStore.self) private var historyStore`, simplified ViewModel init, removed `.environment(HistoryStore())` from `#Preview`.

**JSON Formatter tool (Environment-in-View):**
- `JSONFormatterViewModel`: removed `onSaveHistory` stored property, `init(onSaveHistory:)` param, and the `onSaveHistory(HistoryEntry(...))` call in `runTransform`. Changed to `init() {}`.
- `JSONFormatterView`: removed `@Environment(HistoryStore.self) private var historyStore`, simplified ViewModel init call, removed `.environment(HistoryStore())` from `#Preview`.

**Number Base tool (Wrapper pattern):**
- `NumberBaseViewModel`: removed `onSaveHistory` stored property, `lastEditedBase`/`lastEditedText` tracking fields (only needed for history label), `init(onSaveHistory:)` param, and the `onSaveHistory(HistoryEntry(...))` call in `update(from:text:)`. Also removed stale GRDB comment line 5. Changed to `init()`.
- `NumberBaseView`: changed `init(onSaveHistory:)` to use `@State private var viewModel = NumberBaseViewModel()` stored property default. Updated `#Preview` from `NumberBaseView(onSaveHistory: { _ in })` to `NumberBaseView()`.
- `NumberBaseDefinition`: deleted the `NumberBaseViewWrapper` struct (and its `@Environment(HistoryStore.self)`), changed `makeView` closure to `AnyView(NumberBaseView())` directly.

## Verification Results

Final grep across all four tool directories:
```
grep -rn "onSaveHistory|HistoryEntry|HistoryStore|GRDB" Tools/Color/ Tools/NumberBase/ Tools/Regex/ Tools/JSONFormatter/
```
Returns nothing. All four tools have zero history/GRDB references.

## Deviations from Plan

None — plan executed exactly as written.

The `lastEditedBase` and `lastEditedText` private properties in NumberBaseViewModel were removed as part of removing the `onSaveHistory` closure. These properties existed solely to track the most recently edited base field "for history input label" (as noted in the comment). With history capture gone they became dead code, so they were removed inline (no separate deviation — part of the normal cleanup for this task).

## Known Stubs

None.

## Threat Flags

None — this plan is a pure removal/refactor with no new network endpoints, auth paths, file access, or schema changes.

## Self-Check: PASSED

Files exist:
- Tools/Color/ColorViewModel.swift: FOUND
- Tools/Color/ColorView.swift: FOUND
- Tools/Regex/RegexViewModel.swift: FOUND
- Tools/Regex/RegexView.swift: FOUND
- Tools/JSONFormatter/JSONFormatterViewModel.swift: FOUND
- Tools/JSONFormatter/JSONFormatterView.swift: FOUND
- Tools/NumberBase/NumberBaseViewModel.swift: FOUND
- Tools/NumberBase/NumberBaseView.swift: FOUND
- Tools/NumberBase/NumberBaseDefinition.swift: FOUND

Commits exist:
- ee47b8e: Task 1 (Color + Regex)
- c2961e4: Task 2 (JSON Formatter)
- bd45112: Task 3 (Number Base)
