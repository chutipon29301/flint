---
phase: 06-remove-the-history-feature
plan: "01"
subsystem: tools/hash,tools/jwt,tools/base64,tools/url-encoder
tags: [refactor, history-removal, cleanup, security]
dependency_graph:
  requires: []
  provides: [hash-no-history, jwt-no-history, base64-no-history, url-no-history]
  affects: [HistoryStore-removal-wave3]
tech_stack:
  added: []
  patterns: [environment-in-view-cleanup, wrapper-pattern-cleanup]
key_files:
  modified:
    - Tools/Hash/HashViewModel.swift
    - Tools/Hash/HashView.swift
    - Tools/Hash/HashDefinition.swift
    - Tools/Hash/HashTransformer.swift
    - Tools/JWT/JWTViewModel.swift
    - Tools/JWT/JWTView.swift
    - Tools/JWT/JWTTransformer.swift
    - Tools/Base64/Base64ViewModel.swift
    - Tools/Base64/Base64View.swift
    - Tools/URLEncoder/URLViewModel.swift
    - Tools/URLEncoder/URLView.swift
decisions:
  - "Removed stale 'never imports GRDB' security comment lines from Hash/Base64/URL ViewModels during orchestrator close-out — they would otherwise trip the phase-06 repo-wide GRDB grep gate in plan 06-07."
metrics:
  completed: "2026-07-02"
  tasks_completed: 3
  files_modified: 11
---

# Phase 06 Plan 01: Remove History from Hash, JWT, Base64, and URL Tools Summary

Strip all per-tool history capture from the Hash, JWT, Base64, and URL tools — removing each ViewModel's `onSaveHistory` closure, stored property, and call sites; the `@Environment(HistoryStore.self)` reads in each View; the preview `.environment(HistoryStore())` wiring; and the now-obsolete INFRA-09 SECURITY comments that only described the onSaveHistory exclusion. Keep all digest/HMAC/encode/decode behavior unchanged and keep HMAC key / JWT secret View-local.

## Tasks Completed

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | Remove history from Hash tool (Wrapper pattern) | fd5a9c0 | HashViewModel.swift, HashView.swift, HashDefinition.swift, HashTransformer.swift |
| 2 | Remove history from JWT tool (Environment-in-View pattern) | ddfb6d1 | JWTViewModel.swift, JWTView.swift, JWTTransformer.swift |
| 3 | Remove history from Base64 and URL tools (Environment-in-View pattern) | 0d4ef44 | Base64View.swift, Base64ViewModel.swift, URLView.swift, URLViewModel.swift |

## What Was Built

**Hash tool (Wrapper pattern):**
- `HashViewModel`: removed the `onSaveHistory` stored property, the `onSaveHistory:` init param, and the history-capture call. Kept all digest/HMAC computation. Obsolete INFRA-09 SECURITY comment lines describing the onSaveHistory exclusion removed; HMAC key stays View-local @State.
- `HashView`: removed history wiring; ViewModel constructed without the closure.
- `HashDefinition`: dropped the history-capturing wrapper wiring, constructs the view directly.
- `HashTransformer`: updated the doc comment to drop the "never passed to onSaveHistory" clause.

**JWT tool (Environment-in-View):**
- `JWTViewModel`: removed the `onSaveHistory` property/param and its call in the verify path. Decode/verify/claims logic unchanged.
- `JWTView`: removed `@Environment(HistoryStore.self)`, dropped the `onSaveHistory:` closure argument, removed `.environment(HistoryStore())` from `#Preview`. Secret stays View-local @State.
- `JWTTransformer`: updated the doc comment to drop the "secret never reaches onSaveHistory" clause.

**Base64 + URL tools (Environment-in-View):**
- `Base64ViewModel` / `URLViewModel`: removed the `onSaveHistory` property/param and call sites; encode/decode/auto-detect behavior unchanged.
- `Base64View` / `URLView`: removed `@Environment(HistoryStore.self)` and the closure argument.

## Verification Results

Final grep across all four tool directories:
```
grep -rnE "onSaveHistory|HistoryEntry|HistoryStore|GRDB" Tools/Hash/ Tools/JWT/ Tools/Base64/ Tools/URLEncoder/
```
Returns nothing. All four tools have zero history/GRDB references (including the removed "never imports GRDB" comment lines).

## Deviations from Plan

The original executor agent stalled immediately after its verification passed but before writing SUMMARY.md. During orchestrator close-out, three stale security comment lines mentioning GRDB (`HashViewModel.swift`, `Base64ViewModel.swift`, `URLViewModel.swift`) were found still present. The plan's grep-clean target and the phase-06 gate (plan 06-07) grep the literal string `GRDB` across all `.swift` files, so these comment lines were removed to keep the phase gate green. This is a minor completion of the plan's stated "remove obsolete SECURITY comments" intent, not a scope change.

## Known Stubs

None.

## Threat Flags

None — pure removal/refactor. HMAC key and JWT secret remain View-local @State; no verification behavior changed; no new network, auth, file, or schema surface.

## Self-Check: PASSED

Files exist (all 11 modified files present). Commits fd5a9c0, ddfb6d1, 0d4ef44 present in git log. Residual history/GRDB grep across the four tool directories returns nothing.
