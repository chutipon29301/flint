---
phase: 02-extended-tools
plan: 02
subsystem: regex-tester
tags: [regex, nsregularexpression, never-freeze, timeout, debounce, capture-groups, tdd]
dependency_graph:
  requires: [02-01]
  provides: [RegexTransformer, RegexViewModel, RegexView, RegexDefinition, RegexTransformerTests]
  affects: [02-07-registration]
tech_stack:
  added: []
  patterns: [off-main-eval, withThrowingTaskGroup-timeout, cancel-in-flight, attribute-only-highlight, re-entrancy-guard]
key_files:
  created:
    - Tools/Regex/RegexTransformer.swift
    - Tools/Regex/RegexViewModel.swift
    - Tools/Regex/RegexView.swift
    - Tools/Regex/RegexDefinition.swift
    - FlintTests/RegexTransformerTests.swift
  modified:
    - Flint.xcodeproj/project.pbxproj
decisions:
  - "RegexDefinition.detectionPredicate=nil (search-only): aggressive /…/ predicate would shadow the existing detection chain (JSON→JWT→Base64→URL→Timestamp→UUID per RESEARCH §0)"
  - "NSRegularExpression over Swift 5.7 Regex: pragmatic choice for named+numbered groups, x-flag, and results-table ergonomics (RESEARCH §3)"
  - "Flag g implemented at call-site not as NSRegularExpression.Options: g is not an NSRegularExpression flag — it controls enumerate-all vs first-only"
  - "Re-entrancy guard (isApplyingAttributes) in RegexHighlightedEditorView prevents attribute-only pass from triggering textDidChange → infinite loop (Pitfall #5)"
  - "testMatches_flagM_anchoredPerLine test fixed to include .g flag: multiline flag enables per-line anchoring but enumerate-all requires .g"
metrics:
  duration: "~45 minutes"
  completed: "2026-06-26"
  tasks: 3
  files: 6
---

# Phase 02 Plan 02: Regex Tester Summary

NSRegularExpression-backed Regex Tester with off-main-actor eval, 300ms debounce, 2s withThrowingTaskGroup timeout, cancel-in-flight, and attribute-only per-capture-group highlight — UI never freezes on pathological patterns.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | RegexTransformer (pure) + RegexTransformerTests (TDD) | 0bc95fd | RegexTransformer.swift, RegexTransformerTests.swift, stubs, pbxproj |
| 2 | RegexViewModel — never-freeze off-main eval | 59ae7b2 | RegexViewModel.swift |
| 3 | RegexView (vertical stack + highlight) + RegexDefinition | 841071f | RegexView.swift, RegexDefinition.swift |

## Verification

- `xcodebuild test -only-testing:FlintTests/RegexTransformerTests` — 21/21 passed
- `xcodebuild build -scheme Flint` — BUILD SUCCEEDED
- All acceptance criteria met (grepped: RegexDefinition, category: .analysis, toolShortcuts, isApplyingAttributes)
- MANUAL/UAT (deferred per RESEARCH §10, cannot be unit-tested): paste `(a+)+$` against `"aaaaaaaaaaaaaaaaaaaa!"` — UI stays responsive, timeout warning shows, last-good highlight stays dimmed

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] testMatches_flagM_anchoredPerLine test was incorrect**
- **Found during:** Task 1 TDD GREEN phase — test failed with 1 match expected 2
- **Issue:** The test used `flags: [.m]` without `.g` — since `.g` controls enumerate-all vs first-only (not part of NSRegularExpression.Options), only the first match was returned despite multiline flag being correctly applied
- **Fix:** Added `.g` to the test flags (`flags: [.m, .g]`) and updated the assertion message to reflect "Flags m+g"
- **Files modified:** `FlintTests/RegexTransformerTests.swift`
- **Commit:** 0bc95fd (same commit, in-place fix before commit)

## TDD Gate Compliance

- TDD approach: Tests written first (RED), then implementation to make them pass (GREEN), no REFACTOR needed
- 21 tests covering all RGX-01..04 behaviors: numbered groups, named groups, all 5 flags (g/i/m/s/x), substitute, index/position, no-crash guarantees (INFRA-17)
- Transformer is pure and synchronous — all ViewModel debounce/timeout logic is UI-state (not unit-tested, per PATTERNS.md)

## Never-Freeze Architecture (D-02, T-02-RGX-DoS)

The three-layer safety system in RegexViewModel:
1. **300ms debounce**: `evalTask = Task { await debounce.schedule(delay: .milliseconds(300)) { … } }` — cancels and reschedules on every keystroke
2. **Cancel-in-flight**: `evalTask?.cancel()` at the top of `scheduleEval()` — previous eval Task is cancelled before new debounce starts
3. **2s timeout race**: `withThrowingTaskGroup` races `RegexTransformer.matches(...)` against `Task.sleep(for: .seconds(2))` — winner wins, `group.cancelAll()` kills the loser

On timeout: `timedOut=true`, `outputDimmed=true`, error message shown, last-good matches retained (CF-02 keep-last-good-dimmed).

## Known Stubs

None — all four files are complete implementations. RegexDefinition.make() is intentionally NOT appended to ToolRegistry (Wave-7 integration plan, per plan spec).

## Threat Model Coverage

| Threat ID | Mitigation Applied |
|-----------|-------------------|
| T-02-RGX-DoS | Off-MainActor eval + 300ms debounce + 2s withThrowingTaskGroup timeout + cancel-in-flight (RegexViewModel) |
| T-02-RGX-IV | Invalid pattern → Result.failure (no force-unwrap); 50MB input guard in RegexTransformer; empty/garbage tested in 21 unit tests |

## Self-Check: PASSED

Files exist on disk:
- Tools/Regex/RegexTransformer.swift: FOUND
- Tools/Regex/RegexViewModel.swift: FOUND
- Tools/Regex/RegexView.swift: FOUND
- Tools/Regex/RegexDefinition.swift: FOUND
- FlintTests/RegexTransformerTests.swift: FOUND

Commits verified in git log:
- 0bc95fd: feat(02-02): RegexTransformer + RegexTransformerTests (Task 1 TDD)
- 59ae7b2: feat(02-02): RegexViewModel — never-freeze off-main eval (Task 2)
- 841071f: feat(02-02): RegexView (vertical stack + highlight) + RegexDefinition (Task 3)

Build succeeds; 21/21 tests pass.
