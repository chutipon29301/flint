---
phase: 01-infrastructure-core-tools
plan: 10
subsystem: keyboard-handling
tags: [esc-handling, appkit-bridge, responder-chain, two-stage-esc, uiat-16]
dependency_graph:
  requires: []
  provides: [reliable-esc-to-launcher]
  affects: [MenuBarPopoverView, SyntaxEditorView, all tool views with NSTextView input]
tech_stack:
  added: []
  patterns: [NSTextViewDelegate.doCommandBy for key interception, NotificationCenter broadcast to SwiftUI]
key_files:
  created: []
  modified:
    - UI/Components/SyntaxEditorView.swift
    - UI/MenuBarPopoverView.swift
decisions:
  - "Use NSTextViewDelegate.textView(_:doCommandBy:) rather than NSTextView subclass — keeps fix scoped to the component, avoids subclassing overhead"
  - "Declare .escapePressed once in SyntaxEditorView.swift (the posting site); MenuBarPopoverView references it as a cross-module extension"
  - "No debounce needed — when editor focused only .escapePressed fires (cancelOperation intercepted, .onKeyPress never reached); when unfocused only .onKeyPress fires. Mutual exclusion is structural, not timed."
metrics:
  duration: "12 minutes"
  completed: "2026-06-26"
  tasks: 3 (2 auto + 1 human-verify, all complete)
  files: 2
uat_outcome: |
  UAT found the original doCommandBy fix was too narrow: it only covered the focused
  NSTextView. Opening a tool from a history row leaves the history List (NSTableView) as
  first responder, which also swallows Esc — so Esc-from-history still failed. Superseded
  the editor-only hack with a popover-wide local NSEvent keyDown monitor (keyCode 53) in
  MenuBarPopoverView, installed on .onAppear / removed on .onDisappear. It catches Esc from
  any first responder (editor, history List, or none) with one mechanism; the .escapePressed
  notification and doCommandBy interception were removed. UAT passed (Esc from editor AND
  from history both return to launcher; two-stage close preserved; editing keys unaffected).
---

# Phase 01 Plan 10: AppKit Esc Interception for SyntaxEditorView Summary

**One-liner:** AppKit-layer `cancelOperation` delegate intercept in SyntaxEditorView posts `.escapePressed` broadcast that routes to the existing two-stage `handleEscape()`, eliminating intermittent UAT Test 16 failure when the NSTextView holds first-responder focus.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Intercept Esc in SyntaxEditorView via doCommandBy delegate | e289813 | UI/Components/SyntaxEditorView.swift |
| 2 | Route broadcast Esc into existing two-stage handler | 8cb8a60 | UI/MenuBarPopoverView.swift |
| 3 | checkpoint:human-verify | — | Manual UAT required |

## What Was Built

### Root Cause (from debug session)
Stage-1 Esc (back-to-launcher) was wired only via SwiftUI `.onKeyPress(.escape)` on `MenuBarPopoverView`. The tool views' primary input is `SyntaxEditorView` — an AppKit `NSTextView` first responder. When that NSTextView held focus (the normal case once the user types/pastes/clicks into the input), AppKit delivered Esc to the text view's built-in `cancelOperation:` handler, which consumed it without propagating it up the responder chain to the SwiftUI `.onKeyPress` host. `handleEscape()` never ran — producing the intermittent failure.

### Task 1 — SyntaxEditorView.swift

- Declared `Notification.Name.escapePressed` ("lathe.escapePressed") in a new `extension Notification.Name` block at the top of `SyntaxEditorView.swift`
- Added `func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool` to the existing `Coordinator` class (which already conforms to `NSTextViewDelegate`)
- When `selector == #selector(NSResponder.cancelOperation(_:))` (the Esc mapping), posts `.escapePressed` and returns `true` — AppKit does NOT run its own cancelOperation
- All other selectors return `false` so normal editing keys (Return, Tab, etc.) are unaffected
- Existing `textDidChange`, guard-loop-break, and accessibility setup are untouched

### Task 2 — MenuBarPopoverView.swift

- Added `.onReceive(NotificationCenter.default.publisher(for: .escapePressed)) { _ in handleEscape() }` alongside the existing `.onReceive(.showPopover)` block
- The original `.onKeyPress(.escape) { handleEscape(); return .handled }` is retained as the fallback for the editor-unfocused case
- `handleEscape()` logic is completely unchanged — two-stage contract (D-03) preserved:
  - Stage 1: `navigationState = .root; searchText = ""`
  - Stage 2: `clipboard.isPopoverPresented = false`
- A code comment documents the mutual-exclusion reasoning (no debounce needed)

## Verification (Source-Level)

| Check | Result |
|-------|--------|
| `doCommandBy` method added to Coordinator | 1 occurrence |
| `#selector(NSResponder.cancelOperation)` reference | 1 occurrence |
| `return true` for cancelOperation only | 1 occurrence |
| `return false` for all other selectors | 1 occurrence |
| `.escapePressed` declared exactly once across all UI files | 1 declaration (SyntaxEditorView.swift:16) |
| `publisher(for: .escapePressed)` in MenuBarPopoverView | 1 occurrence |
| `handleEscape()` call sites | 2 (onKeyPress + onReceive) + 1 definition |
| Original `.onKeyPress(.escape)` retained | 1 occurrence (line 111) |
| Build (xcodebuild) | Pre-existing failures in UUID/Hash unrelated to this plan; see note below |

**xcodebuild note:** The CLI build fails with pre-existing errors in `Tools/UUID/UUIDViewModel.swift` and `Tools/Hash/HashViewModel.swift` (`cannot find type 'ToolShortcutActions' in scope`). These errors are in files entirely outside this plan's scope and existed before this plan executed (GRDB/ToolShortcutActions integration in progress). The files modified by this plan (`UI/Components/SyntaxEditorView.swift`, `UI/MenuBarPopoverView.swift`) compile without errors in isolation. Per the plan note, source-level verification is used in place of a clean build.

## Deviations from Plan

None — plan executed exactly as written. The `textView(_:doCommandBy:)` delegate approach was used as specified (not an NSTextView subclass). The `.escapePressed` notification name is declared in `SyntaxEditorView.swift` (the posting site) and referenced from `MenuBarPopoverView.swift` — exactly one declaration as required.

## Threat Model Review

| Threat ID | Category | Disposition | Implementation |
|-----------|----------|-------------|----------------|
| T-10-01 | Denial of Service (swallowing non-Esc selectors) | mitigated | `doCommandBy` returns `true` only for `cancelOperation`; all other selectors return `false` — editing keys unaffected |
| T-10-02 | Tampering (spurious .escapePressed posts) | accepted | Notification carries no payload; only triggers local navigation state change; no untrusted data crosses the boundary |

## Known Stubs

None — the fix is complete and routes to a fully-implemented handler.

## Awaiting Human Verify (Task 3 Checkpoint)

The fix depends on first-responder focus state at runtime and cannot be verified by automated tools. Manual UAT steps:

1. Build and run Lathe; open the popover (Cmd+Shift+Space) and open a tool with an editor (e.g. JSON Formatter).
2. Click INTO the input editor and type/paste so the NSTextView has focus.
3. Press Esc ONCE — must return to the launcher (previously-failing case).
4. At the launcher with empty search, press Esc again — popover must close (stage 2).
5. Reopen a tool but do NOT click into the editor; press Esc — must return to the launcher (no regression).
6. In the editor, confirm normal editing keys still work (typing, Return inserts newline) — Esc interception must not break other keys.

## Self-Check: PASSED

- [x] UI/Components/SyntaxEditorView.swift modified and committed (e289813)
- [x] UI/MenuBarPopoverView.swift modified and committed (8cb8a60)
- [x] `.escapePressed` declared exactly once
- [x] `doCommandBy` delegate method present and returns `true` only for `cancelOperation`
- [x] Original `.onKeyPress(.escape)` fallback preserved in MenuBarPopoverView
- [x] `handleEscape()` logic unchanged
- [x] Pre-existing build failures documented (out of scope)
