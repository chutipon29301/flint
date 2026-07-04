---
phase: 06-remove-the-history-feature
verified: 2026-07-04T16:00:00Z
status: passed
score: 8/8 must-haves verified
overrides_applied: 0
---

# Phase 6: Remove the History Feature Verification Report

**Phase Goal:** The per-tool history feature is gone from Flint — no history panel, no per-tool history capture, no history entries in global search, no history-limit preference. Global search still works (tools only). The app builds clean, the full test suite is green, and no dead history/GRDB code or unused dependency remains. Nothing a user could reach is broken by the removal.
**Verified:** 2026-07-04T16:00:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | No history panel/nav/⌘H reachable anywhere in the app | ✓ VERIFIED | `PopoverNavigationState` has no `.history` case; no `keyboardShortcut("h"`; `toggleHistory()` deleted (grep confirmed clean in `UI/MenuBarPopoverView.swift`) |
| 2 | No per-tool history capture in any of the 13 tools | ✓ VERIFIED | Repo-wide grep for `onSaveHistory\|HistoryEntry\|HistoryStore` across all `*.swift` returns zero matches outside `.planning/` |
| 3 | Global search has no history entries; tools-only search still works | ✓ VERIFIED | `SearchResultsMerger.swift` is tools-only (`SearchResult.tool` single case, `toolResults` only); live search path in `MenuBarPopoverView` filters `AllToolsGridView` via `toolRegistry.search(q)` with no history branch; typing "history" does not open any panel |
| 4 | No history-limit preference remains | ✓ VERIFIED | `grep -n "historyLimit" Core/Services/PreferencesStore.swift` returns nothing; `PreferencesView` TabView shows only General/Appearance/Tools |
| 5 | No HistoryStore injected into any app scene | ✓ VERIFIED | `App/FlintApp.swift` `.environment(...)` list has 8 injections, none is `historyStore`; `MainWindowView.swift` has no `@Environment(HistoryStore.self)` |
| 6 | The 5 history source files are deleted; pbxproj and GRDB are fully clean | ✓ VERIFIED | `HistoryStore.swift`, `HistoryEntry.swift`, `HistoryPanelView.swift`, `HistoryRowView.swift`, `HistorySearchTests.swift` confirmed absent on disk; `grep -c GRDB Flint.xcodeproj/project.pbxproj` = 0; `Package.resolved` pins list has no `grdb` entry |
| 7 | App builds clean from fresh DerivedData; full test suite is green | ✓ VERIFIED | Independently re-ran `xcodebuild build` (fresh derivedData) → BUILD SUCCEEDED, no GRDB artifacts produced. Independently re-ran `xcodebuild test` → xcresult summary confirms `passedTests: 394, failedTests: 0, skippedTests: 0` |
| 8 | Nothing a user could reach is broken; tools still work | ✓ VERIFIED (human-approved) | Human UAT (06-07 Task 3) approved after a popover-centering layout bug was found and fixed (commit 40bccc8) — tools-only launcher, tools-only search, ⌘H inert, no History pref tab, tools work |

**Score:** 8/8 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Tools/Hash/HashDefinition.swift` | `makeView` builds `HashView()` directly, no wrapper | ✓ VERIFIED | `AnyView(HashView())` at line 18, no `HistoryStore` |
| `Tools/NumberBase/NumberBaseDefinition.swift` | `makeView` builds `NumberBaseView()` directly | ✓ VERIFIED | `AnyView(NumberBaseView())` at line 21 |
| `Tools/UUID/UUIDDefinition.swift`, `Timestamp/TimestampDefinition.swift`, `TextDiff/TextDiffDefinition.swift`, `Markdown/MarkdownDefinition.swift`, `ImageCompress/ImageCompressDefinition.swift` | Direct `AnyView(SomeView())`, no wrapper | ✓ VERIFIED | All confirmed building views directly with no closures |
| `Core/Services/SearchResultsMerger.swift` | Tools-only merge, no `HistoryEntry` | ✓ VERIFIED | Single `.tool` case enum, `toolResults`-only struct, `merge(tools:query:)` signature — matches plan's target shape exactly |
| `UI/SearchView.swift` | No `HistoryStore`, tools-only empty copy | ✓ VERIFIED (see note) | No history references; however this view has zero live callers — see Warnings |
| `App/FlintApp.swift` | No `HistoryStore` @State or `.environment` injection | ✓ VERIFIED | 8 `.environment(...)` calls, none for historyStore; no `onChange(of: prefs.historyLimit...)` |
| `Core/Services/PreferencesStore.swift` | No `historyLimit` property/key | ✓ VERIFIED | grep returns nothing |
| `UI/MenuBarPopoverView.swift` | No history nav state, no ⌘H | ✓ VERIFIED | No `.history` case, no `keyboardShortcut("h"...)`, no `toggleHistory` |
| Five history files (`HistoryStore.swift`, `HistoryEntry.swift`, `HistoryPanelView.swift`, `HistoryRowView.swift`, `HistorySearchTests.swift`) | Deleted from disk | ✓ VERIFIED | All 5 confirmed absent |
| `Flint.xcodeproj/project.pbxproj` | No history file refs, no GRDB entries | ✓ VERIFIED | `grep -c GRDB` = 0; deleted-file basenames all return 0 matches |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `App/FlintApp.swift` | `MenuBarPopoverView` / `MainWindowView` / `PreferencesView` scenes | `.environment(...)` injections | ✓ WIRED | No `historyStore` injected on any scene; all other environment objects (prefs, clipboard, toolRegistry, etc.) intact |
| `Tools/*/*Definition.swift` (7 Wrapper-pattern tools) | `SomeView()` | `makeView: { AnyView(SomeView()) }` | ✓ WIRED | Hash, NumberBase, UUID, Timestamp, TextDiff, Markdown, ImageCompress all confirmed building views with zero-arg init, no wrapper struct |
| `UI/MenuBarPopoverView.swift` search bar | `ToolRegistry.search` | `toolRegistry.search(q)` in `.searchResults` case, `AllToolsGridView(filter:)` | ✓ WIRED | Live search path confirmed functional and history-free; `SearchView`/`SearchResultsMerger` are NOT in this call path (see Warnings) |
| `Flint.xcodeproj/project.pbxproj` | source files on disk | `PBXFileReference` paths | ✓ WIRED | Package graph resolves without GRDB; independent clean build produced no GRDB build artifacts |

### Data-Flow Trace (Level 4)

Not applicable in the traditional sense (no dynamic data-fetching UI added by this phase) — the relevant Level 4 check here is "does search actually return real tool matches from the registry," which is confirmed: `toolRegistry.search(q)` is called live in `MenuBarPopoverView` and drives `AllToolsGridView`'s `filter` parameter, not a static/hardcoded list.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Clean build compiles with GRDB out of the package graph | `xcodebuild build -project Flint.xcodeproj -scheme Flint -destination 'platform=macOS' -derivedDataPath <fresh>` | BUILD SUCCEEDED; no `*grdb*` files found under fresh derivedData | ✓ PASS |
| Full test suite green | `xcodebuild test ... -derivedDataPath <fresh>` + `xcrun xcresulttool get test-results summary` | `"passedTests": 394, "failedTests": 0, "skippedTests": 0, "result": "Passed"` | ✓ PASS |
| No history/GRDB symbol in source | `grep -rn "HistoryStore\|HistoryEntry\|HistoryPanelView\|HistoryRowView\|onSaveHistory\|historyLimit\|historyResults\|onSelectHistoryEntry\|onShowHistory\|HistoryPreferencesTab\|toggleHistory\|GRDB" --include="*.swift" .` (excl. build/dist/.planning) | zero lines returned | ✓ PASS |
| No history/GRDB token in pbxproj | `grep -n "GRDB\|HistoryStore\|HistoryEntry\|HistoryPanelView\|HistoryRowView" Flint.xcodeproj/project.pbxproj` | zero lines returned | ✓ PASS |
| FlintTests scheme wired | Read `Flint.xcodeproj/xcshareddata/xcschemes/Flint.xcscheme` TestAction | `TestableReference` present, `BuildableName = "FlintTests.xctest"`, not skipped | ✓ PASS |

### Probe Execution

No dedicated `scripts/*/tests/probe-*.sh` files exist for this project; the phase's own gate (grep + clean build + test) was executed directly above and independently re-verified rather than trusting SUMMARY.md narration. No separate probe scripts found via `find scripts -path '*/tests/probe-*.sh'`.

### Requirements Coverage

This phase is explicitly a **removal phase** — per the task framing it supersedes INFRA-13 (history-limit pref) and the history portions of INFRA-09/INFRA-10, rather than satisfying them. `.planning/REQUIREMENTS.md` still lists INFRA-08, INFRA-09, INFRA-10, INFRA-12, INFRA-13, INFRA-16, JWT-04, and HASH-03 as "Complete" under Phase 1 — this is a pre-existing artifact from Phase 1 and was **not** in any Phase 6 plan's `files_modified` list, so this is expected staleness, not a phase deliverable gap. No plan in this phase claims to update REQUIREMENTS.md.

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|--------------|--------|----------|
| INFRA-08 (superseded) | 06-01…06-07 | History searchable/re-openable/pin/delete/clear | ✓ SATISFIED (by removal) | Entire history subsystem deleted; requirement is moot post-removal |
| INFRA-09 (history portion superseded) | 06-01 | Secrets never persist to history | ✓ SATISFIED (by removal) | No history exists to leak into; HMAC key/JWT secret confirmed still View-local |
| INFRA-10 (history portion superseded) | 06-04, 06-07 | Global search spans tools + history | ✓ SATISFIED (tools-only) | Search is now tools-only per plan intent; still keyboard-navigable |
| INFRA-13 (superseded) | 06-05 | History-limit preference | ✓ SATISFIED (by removal) | `historyLimit` and its Preferences control are gone |
| INFRA-12, INFRA-16, INFRA-17 | 06-05, 06-07 | Preferences window covers History tab / toggle-history shortcut / no crashes | ✓ SATISFIED (by removal / unaffected) | History tab and ⌘H removed; INFRA-17 unaffected by this phase (no new input-handling code) |
| JWT-04, HASH-03 | 06-01 | Secret never written to history | ✓ SATISFIED (by removal) | Verified unchanged verification/HMAC behavior, no history sink remains |

No orphaned requirements found mapped to Phase 6 beyond what the plans already claim.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `Tools/JWT/JWTView.swift` | 395 | `.accessibilityLabel("HMAC secret key — never saved to history")` | ⚠️ Warning | User-facing VoiceOver label still describes deleted history machinery — misleading but not functionally broken |
| `Tools/Hash/HashView.swift` | 112 | `.accessibilityLabel("HMAC secret key — never written to history")` | ⚠️ Warning | Same as above |
| `Tools/Timestamp/TimestampViewModel.swift` | 93 | Doc comment "same string saved to history" | ℹ️ Info | Stale comment only, no user impact |
| `Tools/Regex/RegexViewModel.swift` | 131 | Doc comment "publishes matches + history" | ℹ️ Info | Stale comment only |
| `UI/MenuBarPopoverView.swift` | 74 | Comment "the history List's NSTableView" | ℹ️ Info | Stale comment only |
| `UI/Components/SyntaxEditorView.swift` | 251 | Comment "text view, history List, or none" | ℹ️ Info | Stale comment, file outside phase's edited set |
| `Tools/Markdown/MarkdownDefinition.swift` | 3 | Comment "no predicate + history-wrapper" | ℹ️ Info | Stale comment only |
| `UI/SearchView.swift`, `Core/Services/SearchResultsMerger.swift` | whole file | Unreachable dead code — `SearchView` never instantiated anywhere; `SearchResultsMerger` has no consumer besides `SearchView` | ⚠️ Warning | Not a history remnant (fully history-free per plan 06-04's own scope) but is dead code the phase touched instead of deleting; no test coverage remains since `HistorySearchTests.swift` (its only test) was deleted this phase |
| `Tools/UUID/UUIDViewModel.swift` | 133-139 | `inspectSummary(_:)` orphaned by removed `onSaveHistory` call site | ℹ️ Info | Dead private method, no external impact |

No `TBD`/`FIXME`/`XXX` debt markers found in any phase-modified file.

None of the above are BLOCKERs: they do not reintroduce history functionality, do not break any tool, and do not fail the grep/build/test gates the phase explicitly defined. They are pre-existing-code-quality warnings the phase's own code review (06-REVIEW.md) already surfaced with 0 critical / 5 warning / 3 info findings.

### Human Verification Required

None outstanding — Task 3 of plan 06-07 was a blocking `checkpoint:human-verify` gate that was already run and approved by the user during phase execution (per 06-07-SUMMARY.md), covering: tools-only launcher, tools-only search, ⌘H inert, no History pref tab, and tools still work. One layout regression (popover content no longer filling the 600pt frame) was found and fixed (commit 40bccc8) before approval was granted.

### Gaps Summary

No blocking gaps. All 8 derived observable truths for the phase goal are VERIFIED against the actual codebase (not just SUMMARY.md claims) via independent re-execution of the grep gate, a fresh `xcodebuild build`, a fresh `xcodebuild test` with xcresult summary confirming 394/394 passed, and direct source inspection of every tool's Definition/ViewModel/View wiring.

Two minor warnings carried over from the phase's own code review (06-REVIEW.md) are noted for awareness but do not block phase completion: (1) two user-facing accessibility labels still say "history" in JWTView.swift and HashView.swift — a VoiceOver-only cosmetic inconsistency, not a functional break; (2) `SearchView.swift`/`SearchResultsMerger.swift` are fully history-free but unreachable dead code (zero callers) — pre-existing to this phase's approach (plan 06-04 edited rather than deleted them) and does not affect the live, working search path in `MenuBarPopoverView`. Both are candidates for a follow-up cleanup phase/task but do not represent a failure of THIS phase's stated goal.

---

_Verified: 2026-07-04T16:00:00Z_
_Verifier: Claude (gsd-verifier)_
