---
phase: 05-add-image-compression-feature
plan: 08
subsystem: ui
tags: [swiftui, image-compression, observable, recompress, gap-closure]

# Dependency graph
requires:
  - phase: 05-07
    provides: cancellable batch compression with resolved in-flight rows + clean re-drop
provides:
  - "ImageCompressViewModel.lastSourceURLs / lastRunQuality retained on every compress() run"
  - "ImageCompressViewModel.recompress(quality:) replaying the retained batch (no-op when empty)"
  - "ImageCompressView conditional 'Re-compress at {n}%' button (explicit, non-auto-spew re-run)"
affects: [image-compress, UAT, phase-05-verification]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Explicit re-run affordance over auto-onChange: re-compression fires only on button press (no disk-spew per slider tick)"
    - "MainActor-confined @Observable retained-input state (lastSourceURLs/lastRunQuality) drives a derived View visibility predicate"

key-files:
  created: []
  modified:
    - Tools/ImageCompress/ImageCompressViewModel.swift
    - Tools/ImageCompress/ImageCompressView.swift
    - FlintTests/ImageCompressViewModelTests.swift

key-decisions:
  - "Re-compression fires ONLY on explicit button press — no .onChange(of: quality) auto-trigger (would spew a new -compressed-N file per slider tick, T-05-08A locked decision)"
  - "Re-compress button hidden when the batch is entirely lossless (PNG/TIFF) and only quality changed — quality doesn't apply there (D-05)"
  - "recompress(quality:) guards lastSourceURLs non-empty → no-op on a fresh VM (never compresses an empty set, T-05-08B)"
  - "Button placed inside the rows-non-empty resultsSection header, mutually exclusive with Cancel (shouldShowRecompress requires !isCompressing) — empty state needs no Re-compress branch"

patterns-established:
  - "Pattern: retained-input replay — store source URLs + last params on each run so a derived action can re-execute without re-input"
  - "Pattern: derived View visibility predicate (shouldShowRecompress) composing @AppStorage live value + @Observable VM state"

requirements-completed: [D-04, D-05]

# Metrics
duration: 2min
completed: 2026-06-30
---

# Phase 05 Plan 08: Re-compress at {n}% Button Summary

**Explicit "Re-compress at {n}%" affordance resolving the slider/workflow contradiction (GAP 2 / UAT Test 6) — quality changes never auto-write files; compress-on-drop stays immediate, and the user re-applies a changed quality to the existing batch via one button press.**

## Performance

- **Duration:** 2 min
- **Started:** 2026-06-30T18:12:29Z
- **Completed:** 2026-06-30T18:14:33Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- ViewModel now retains `lastSourceURLs` + `lastRunQuality` on every `compress()` run, set synchronously at the top so the View can detect a pending quality change immediately.
- `recompress(quality:)` replays the retained batch at a new quality; no-op (no crash, no empty compress) when there is no prior batch.
- View surfaces a conditional `Re-compress at {n}%` button in the results header — shown only when rows exist, no batch is running, the live slider quality differs from the last run, and the batch is not entirely lossless.
- No `.onChange(of: quality)` auto-trigger was added — re-compression fires exclusively on button press (locked anti-disk-spew constraint), and compress-on-drop is unchanged.

## Task Commits

Each task was committed atomically (Task 1 is TDD: test → feat):

1. **Task 1 (RED): failing tests for recompress + retained source URLs** - `90825dd` (test)
2. **Task 1 (GREEN): retain source URLs + last-run quality + recompress()** - `3275505` (feat)
3. **Task 2: conditional Re-compress at {n}% button** - `92df116` (feat)

**Plan metadata:** committed separately (docs: complete plan)

## Files Created/Modified
- `Tools/ImageCompress/ImageCompressViewModel.swift` - Added `private(set) var lastSourceURLs` / `lastRunQuality` (set at top of `compress()`); added `recompress(quality:)` guarding non-empty retained URLs.
- `Tools/ImageCompress/ImageCompressView.swift` - Added `mappedQuality` + `shouldShowRecompress` computed properties; rendered the `Re-compress at {n}%` button in the results header HStack (mutually exclusive with Cancel), with INFRA-15 accessibility label.
- `FlintTests/ImageCompressViewModelTests.swift` - Added `testCompressRecordsLastRun`, `testRecompressReplaysBatch`, `testRecompressNoOpWhenEmpty`.

## Decisions Made
- **No auto re-run on slider change** (T-05-08A): re-compression fires only on the explicit button press. An `.onChange(of: quality)` would write a new `-compressed-N` file on every slider tick — exactly the disk side effect the locked decision forbids.
- **Hidden when entirely lossless** (D-05): for a PNG/TIFF-only batch a quality-only change is meaningless, so `shouldShowRecompress` excludes that case.
- **recompress no-ops on empty** (T-05-08B): `recompress` guards `lastSourceURLs` non-empty, so a fresh VM never compresses an empty set.
- **Button in resultsSection header**: lives in the rows-non-empty branch, so the empty/placeholder state automatically shows no button; mutually exclusive with Cancel because `shouldShowRecompress` requires `!isCompressing`.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None. The `xcodebuild test` log emitted unrelated iOS device-passcode noise ("The device is passcode protected"); the macOS destination built and all tests passed — `** TEST SUCCEEDED **`.

## Verification

- **RED:** `xcodebuild test` failed to compile (members `lastSourceURLs`/`lastRunQuality`/`recompress` absent) — confirmed failing before implementation.
- **GREEN:** Full `FlintTests` suite green. New tests pass: `testCompressRecordsLastRun` (0.055s), `testRecompressReplaysBatch` (0.107s), `testRecompressNoOpWhenEmpty` (0.101s). 05-07 regressions green: `testBatchStateProgression`, `testMixedBatchNeverCrashes`, `testCancellation`, `testHistoryFiresOnce`, `testOffMainProof`.
- **Task 2:** `xcodebuild build -scheme Flint -destination 'platform=macOS'` → `** BUILD SUCCEEDED **`.
- **Locked constraint (no auto-spew):** `grep -n "onChange" ImageCompressView.swift` finds only a comment reference — no `.onChange(of: quality)` that triggers compression exists.

### must_haves
- ✅ After a batch exists and quality changes, a "Re-compress at {n}%" button appears (`shouldShowRecompress`).
- ✅ Clicking re-runs compression on the retained source URLs at the current quality (`recompress(quality: mappedQuality)` → `compress(urls: lastSourceURLs, …)`).
- ✅ Hidden when the batch is entirely lossless and only quality changed (`!isEntirelyLossless` in predicate).
- ✅ Quality changes do NOT auto-spew files — re-compression fires only on explicit button press (no `.onChange` trigger).
- ✅ Compress-on-drop unchanged (`.onDrop` / `chooseImages` untouched).

## Next Phase Readiness
- GAP 2 (UAT Test 6) closed. Image Compressor's slider/workflow contradiction resolved.
- Ready for phase-05 verification / remaining gap-closure plans.

## Self-Check: PASSED
- Files: all 3 modified files present on disk.
- Commits: `90825dd`, `3275505`, `92df116` all found in `git log`.
- Acceptance criteria (must_haves) re-verified via build + test + grep.

---
*Phase: 05-add-image-compression-feature*
*Completed: 2026-06-30*
