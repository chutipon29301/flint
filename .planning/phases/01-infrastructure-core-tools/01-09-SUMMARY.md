---
phase: 01-infrastructure-core-tools
plan: 09
subsystem: keyboard-shortcuts
tags: [infra, keyboard-shortcuts, gap-closure, notifications, pasteboard, security]
dependency_graph:
  requires: [01-01, 01-02, 01-03, 01-04, 01-05, 01-06, 01-07]
  provides: [INFRA-16-complete]
  affects: [all-tool-views]
tech_stack:
  added: []
  patterns:
    - ToolShortcutActions protocol for uniform keyboard-shortcut wiring across tools
    - ViewModifier capturing reference-type @Observable viewmodel via protocol constraint
    - NotificationCenter publisher subscription in SwiftUI modifier for broadcast shortcuts
key_files:
  created:
    - UI/Components/ToolShortcutActions.swift
  modified:
    - Tools/JSONFormatter/JSONFormatterViewModel.swift
    - Tools/JSONFormatter/JSONFormatterView.swift
    - Tools/Base64/Base64ViewModel.swift
    - Tools/Base64/Base64View.swift
    - Tools/URLEncoder/URLViewModel.swift
    - Tools/URLEncoder/URLView.swift
    - Tools/Timestamp/TimestampViewModel.swift
    - Tools/Timestamp/TimestampView.swift
    - Tools/JWT/JWTViewModel.swift
    - Tools/JWT/JWTView.swift
    - Tools/Hash/HashViewModel.swift
    - Tools/Hash/HashView.swift
    - Tools/UUID/UUIDViewModel.swift
    - Tools/UUID/UUIDView.swift
decisions:
  - "ToolShortcutActions protocol with AnyObject constraint lets @Observable reference-type VMs conform without Equatable"
  - "ViewModifier captures actions by reference (not copied) so live VM state is always read on notification"
  - "TimestampViewModel.buildOutputString() extracted as private helper shared by primaryOutput() and runTransform() to avoid string duplication"
  - "UUIDViewModel.clearInput() resets inspectInput + generatedUUIDs + v5Name; leaves selectedVersion and uppercase as user preferences per plan spec"
metrics:
  duration: "~4 minutes"
  completed_date: "2026-06-26"
  tasks: 3
  files: 15
---

# Phase 01 Plan 09: INFRA-16 Keyboard Shortcut Gap-Closure Summary

**One-liner:** Shared ToolShortcutActions protocol + view modifier wires Cmd+Shift+C / Cmd+Delete across all 7 tools via NotificationCenter, closing the INFRA-16 observer gap.

## What Was Built

The producer side (MenuBarPopoverView) was already posting `.copyOutput` and `.clearInput` notifications correctly on Cmd+Shift+C and Cmd+Delete. Zero of the 7 tool views had observers — the notifications fired into the void. This plan built the entire observer side.

### Task 1 — ToolShortcutActions protocol + view modifier (a2cb4b3)

Created `UI/Components/ToolShortcutActions.swift`:

- `ToolShortcutActions` protocol: `primaryOutput() -> String?` and `clearInput()`, both `@MainActor`
- `ToolShortcutsModifier<Actions>`: private `@MainActor ViewModifier` with `.onReceive` for both notification names
- `.toolShortcuts(_ actions:)` `View` extension for ergonomic call-site
- Notification names referenced from `MenuBarPopoverView.swift` — not redeclared
- T-09-02 mitigated: nil or empty `primaryOutput()` is a harmless no-op (never writes to pasteboard)

### Task 2 — 4 string-output ViewModels conformed + views wired (b09eae1)

- **JSONFormatterViewModel**: `primaryOutput()` returns `output` or nil; `clearInput()` sets `input = ""`
- **Base64ViewModel**: `primaryOutput()` returns `output` or nil; `clearInput()` sets `input = ""`
- **URLViewModel**: `primaryOutput()` returns `rebuiltURL` in `.parse` mode, `encodedOutput` otherwise; `clearInput()` sets `input = ""`
- **TimestampViewModel**: extracted `buildOutputString()` private helper (shared by `primaryOutput()` and the history write in `runTransform()`); `clearInput()` sets `input = ""`
- All 4 content views received `.toolShortcuts(viewModel)` on their root container

### Task 3 — 3 composite-output ViewModels conformed + views wired (abc5143)

- **JWTViewModel**: `primaryOutput()` returns `headerJSON + "\n---\n" + payloadJSON` when decoded; nil on error or empty token; `clearInput()` sets `token = ""`. SECURITY: HMAC secret is View-local `@State` — never a ViewModel property, never referenced in copy path.
- **HashViewModel**: `primaryOutput()` returns `allHashesText(from: textHashResult!)` when result available; nil otherwise; `clearInput()` sets `textInput = ""`. SECURITY: `hmacKey` is View-local `@State`, never referenced here.
- **UUIDViewModel**: `primaryOutput()` returns `exportText()` (honours `exportFormat` + `uppercase`) when `generatedUUIDs` non-empty; `clearInput()` resets `inspectInput = ""`, `generatedUUIDs = []`, `v5Name = ""` — leaves `selectedVersion` and `uppercase` as user preferences
- `JWTContentView`, `HashView`, `UUIDView` all received `.toolShortcuts(viewModel)` on their root containers

## Verification

All source-level checks pass (Xcode CLI not available in this environment):

| Check | Result |
|-------|--------|
| `ToolShortcutActions.swift` has `publisher(for: .copyOutput)` | count=1 |
| `ToolShortcutActions.swift` has `publisher(for: .clearInput)` | count=1 |
| All 7 ViewModels conform to `ToolShortcutActions` | 7/7 found |
| All 7 content views call `.toolShortcuts(viewModel)` exactly once | 7/7 count=1 |
| `MenuBarPopoverView.swift` unchanged | no `ToolShortcutActions`/`toolShortcuts` added |
| JWT `primaryOutput()` never references `hmacSecret` | source-asserted |
| Hash `primaryOutput()` never references `hmacKey` | source-asserted |
| No stubs or TODO markers in modified files | none found |

Note: `xcodebuild` builds cannot run in this environment. Source-level verification is complete. Full build validation should be confirmed at next Xcode open or CI run.

## Deviations from Plan

### Auto-refactored

**1. [Rule 1 - Refactor] Extracted buildOutputString() in TimestampViewModel**
- **Found during:** Task 2
- **Issue:** The history-write in `runTransform()` built the composite output string inline. Reusing the same string for `primaryOutput()` would have duplicated the logic.
- **Fix:** Extracted `buildOutputString()` as a private helper called from both `primaryOutput()` and `runTransform()`. History behavior is identical.
- **Files modified:** `Tools/Timestamp/TimestampViewModel.swift`
- **Commit:** b09eae1

None other — plan executed as written.

## Threat Flags

No new threat surface introduced. This plan adds no new network endpoints, auth paths, file access patterns, or schema changes. The pasteboard write was already the intended clipboard path — the shortcut adds a keyboard trigger to an existing data flow. JWT and Hash copy paths are provably isolated from their respective secrets by the existing View-local `@State` pattern (T-09-01 mitigated at implementation level, verified by source).

## Self-Check: PASSED

- `UI/Components/ToolShortcutActions.swift` — EXISTS
- `Tools/JSONFormatter/JSONFormatterViewModel.swift` conforms — VERIFIED
- `Tools/Base64/Base64ViewModel.swift` conforms — VERIFIED
- `Tools/URLEncoder/URLViewModel.swift` conforms — VERIFIED
- `Tools/Timestamp/TimestampViewModel.swift` conforms — VERIFIED
- `Tools/JWT/JWTViewModel.swift` conforms — VERIFIED
- `Tools/Hash/HashViewModel.swift` conforms — VERIFIED
- `Tools/UUID/UUIDViewModel.swift` conforms — VERIFIED
- Commits a2cb4b3, b09eae1, abc5143 — VERIFIED via `git log`
