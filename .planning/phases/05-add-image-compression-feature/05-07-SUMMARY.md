---
phase: 05-add-image-compression-feature
plan: 07
subsystem: ui
tags: [swift-concurrency, cancellation, imageio, png-quantization, swift6, mainactor]

# Dependency graph
requires:
  - phase: 05-add-image-compression-feature (05-06)
    provides: never-larger PNG copy-through + disambiguation (-compressed-1) transformer logic
provides:
  - Cooperative cancellation of in-flight PNG quantization (Task.isCancelled checkpoints)
  - Off-main per-image work via Task.detached + nonisolated compressOffMain wrapper
  - Cancel resolves the .compressing row to a terminal state (no row stuck spinning)
  - Non-eager cancel() — Cancel button stays visible until the in-flight row resolves
  - batchGeneration guard distinguishing user-cancel from supersede (CR-02)
affects: [image-compress, swift-concurrency-patterns, ui-cancellation]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Off-main + cancellable heavy work: Task.detached (NOT plain Task) running a nonisolated synchronous helper, stored in a property so cancel() can .cancel() it directly"
    - "Cooperative cancellation: amortized O(1) Task.isCancelled checkpoints (every 4096 iterations) in the long quantization loops; return nil routes through the existing typed-Result fallback"
    - "Non-eager cancel: signal cancellation only; let the work's own completion path resolve UI state and flip the loading flag on the MainActor"
    - "batchGeneration counter to tell user-cancel (this batch still current) from supersede (newer batch owns shared state)"

key-files:
  created: []
  modified:
    - Tools/ImageCompress/ImageCompressViewModel.swift
    - Tools/ImageCompress/ImageCompressTransformer.swift
    - Tools/ImageCompress/PNGColorQuantizer.swift
    - FlintTests/ImageCompressViewModelTests.swift

key-decisions:
  - "Used Task.detached (not a plain inner Task) for the per-image work: a plain Task created inside the @MainActor batch Task inherits MainActor isolation, and calling a SYNCHRONOUS nonisolated function from it does NOT hop off-actor — so the heavy quantization would run on the main thread (breaking INFRA-18 and freezing the UI so the Cancel tap could not even be processed). This corrects the plan's prescribed mechanism."
  - "Cancellation reaches the work via an explicit .cancel() on the stored currentWorkTask handle, not via inherited cancellation. Detached opts out of INHERITED cancellation only; an explicit .cancel() still flips Task.isCancelled inside the work."
  - "On cancel, the in-flight .compressing row resets to .pending (renders the dash placeholder) — no View change and no .cancelled enum case needed."
  - "Skipped the optional TOCTOU destURL placeholder hardening (plan-stated optional): GAP 4 is already proven by the existing disambiguation tests once the orphaned non-cancellable task is gone."

patterns-established:
  - "Off-main cancellable work: Task.detached + nonisolated static helper + stored handle for direct .cancel() (extends the MEMORY 'Off-main cancellable work pattern' with the detached-vs-plain-Task isolation correction)"
  - "Tight-deadline cancellation test: assert the in-flight item leaves its in-progress state within a deadline far shorter than the un-cancelled work time, proving the work was actually interrupted (not merely completed)"

requirements-completed: [D-01, D-09, INFRA-17, INFRA-18]

# Metrics
duration: ~80 min
completed: 2026-06-30
---

# Phase 05 Plan 07: Cancellable Image Compression Summary

**Cancel now actually stops in-flight PNG quantization (cooperative Task.isCancelled checkpoints + Task.detached off-main work with a stored handle cancelled directly) and resolves the .compressing row to a terminal state — testCancellation dropped from 58s to 0.79s.**

## Performance

- **Duration:** ~80 min
- **Started:** 2026-06-30T17:xx (approx)
- **Completed:** 2026-06-30T18:09:56Z
- **Tasks:** 2 (TDD RED + GREEN)
- **Files modified:** 4

## Accomplishments
- Cooperative cancellation: Task.isCancelled checkpoints added to the three long loops in `PNGColorQuantizer.quantize` (counts build, median-cut split, per-pixel nearest-palette map). Returning nil routes cleanly through the transformer's existing truecolor fallback / typed Result — never a crash (INFRA-17).
- Off-main wrapper: `nonisolated static func compressOffMain` (autoreleasepool + compress) on `ImageCompressTransformer`, run via `Task.detached` so the heavy work stays off the MainActor (INFRA-18).
- In-flight row resolution: removed the stranding `break` before `apply`; on cancel the `.compressing` row resets to `.pending`, so no row spins forever (GAP 3 / UAT Test 9).
- Non-eager cancel: `cancel()` only signals cancellation (cancels both the work Task and the batch Task); the batch loop resolves the row and flips `isCompressing = false` on the MainActor afterward, so the Cancel button stays visible until the row resolves.
- GAP 4 (UAT Test 10): with the orphaned non-cancellable task gone, a clean re-drop disambiguates correctly — proven by the existing `testDisambiguate_collision_producesNumberedSuffix` (`-compressed-1`).
- Swift 6 strict concurrency clean: the outer batch loop stays a MainActor-bound `Task {}`, so the non-Sendable `onSaveHistory`/`capturedOnSave` closure is never sent across an actor boundary (no "sending ... risks data races" warnings).

## Task Commits

1. **RED: slow-fixture cancellation test** - `013ed88` (test) — `writeSlowGradientPNG` 1024×1024 fixture + rewritten `testCancellation` asserting no row stays `.compressing`; failed against current code (row stuck the full 5s deadline).
2. **GREEN: cancellable compression resolves in-flight row** - `75f3568` (feat) — quantizer checkpoints, `compressOffMain`, `Task.detached` + `currentWorkTask` direct cancel, row resolution, non-eager `cancel()`, `batchGeneration`, strengthened test assertion.

**Plan metadata:** (this commit)

## Files Created/Modified
- `Tools/ImageCompress/PNGColorQuantizer.swift` - Three cooperative `Task.isCancelled` checkpoints (amortized O(1), every 4096 iterations) in the counts-build, median-cut split, and per-pixel mapping loops.
- `Tools/ImageCompress/ImageCompressTransformer.swift` - Added `nonisolated static func compressOffMain(url:quality:)` wrapping `autoreleasepool { compress(...) }`.
- `Tools/ImageCompress/ImageCompressViewModel.swift` - Per-image work now `Task.detached` stored in `currentWorkTask`; `cancel()` cancels it directly (non-eager); in-flight `.compressing` row resets to `.pending` instead of stranding; `batchGeneration` guard for CR-02 supersede; completion path flips `isCompressing` only when still the current generation.
- `FlintTests/ImageCompressViewModelTests.swift` - `writeSlowGradientPNG` helper + rewritten `testCancellation` (slow fixture, cancel mid-flight, tight 5s deadline asserting the row left `.compressing`).

## Decisions Made
- **Task.detached over a plain inner Task (corrects the plan's prescribed mechanism).** The plan instructed using a plain child `Task { compressOffMain(...) }`, asserting it would inherit cancellation AND run off-main. Both assumptions were wrong: (1) a plain `Task {}` created in a `@MainActor` context runs a synchronous `nonisolated` function ON the main thread (verified empirically), so the 58s quantization froze the MainActor and the Cancel tap could not be processed until the work finished; (2) unstructured Tasks do not inherit cancellation anyway. The robust fix is `Task.detached` (off-main) + a stored handle that `cancel()` cancels directly (explicit cancel IS observed by `Task.isCancelled`).
- **Reset cancelled row to `.pending`** (no new `.cancelled` enum case) per the plan's stated preference — zero View changes, renders the dash placeholder.
- **Optional TOCTOU destURL placeholder hardening: SKIPPED** (plan marked it optional and "do not block"). GAP 4 is downstream of GAP 3; once the orphaned non-cancellable task is gone, the existing disambiguation tests already prove `-compressed-1`. Adding a 0-byte placeholder would complicate the 05-06 never-larger copy-through for no proven benefit.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Plan's cancellation mechanism did not stop the work**
- **Found during:** Task 2 (GREEN)
- **Issue:** Following the plan exactly (plain inner `Task { compressOffMain(...) }` + `withTaskCancellationHandler` as an intermediate attempt) left `testCancellation` running ~58s — cancel never interrupted the quantization. Root cause: a plain `Task {}` in a `@MainActor` context runs a synchronous `nonisolated` function on the main thread (so the work ran ON the MainActor, freezing it and blocking the Cancel tap), and unstructured Tasks do not inherit cancellation.
- **Fix:** Switched the per-image work to `Task.detached` (runs the synchronous nonisolated helper off-main, verified) and stored the handle in `currentWorkTask` so `cancel()` cancels it directly. Verified `Task.isCancelled` then fires inside the quantizer checkpoint.
- **Files modified:** Tools/ImageCompress/ImageCompressViewModel.swift
- **Verification:** `testCancellation` dropped from ~58s to 0.79s; `testOffMainProof` still green (off-main preserved); no data-race warnings.
- **Committed in:** 75f3568

**2. [Rule 2 - Missing Critical] Cooperative checkpoints in more than one loop**
- **Found during:** Task 2 (GREEN)
- **Issue:** The plan suggested a checkpoint only in the per-pixel mapping loop. For a 1024×1024 fully-unique-color fixture, the counts-build dictionary insertion and the median-cut split loop dominate runtime and precede the mapping loop, so a single checkpoint would not be responsive.
- **Fix:** Added amortized-O(1) `Task.isCancelled` checkpoints to all three long loops (counts build, median-cut split, per-pixel map). The plan explicitly allowed the median-cut checkpoint as optional; the counts-loop checkpoint was added for responsiveness.
- **Files modified:** Tools/ImageCompress/PNGColorQuantizer.swift
- **Verification:** Cancellation resolves in <1s regardless of where in quantization the cancel lands.
- **Committed in:** 75f3568

**3. [Rule 1 - Bug] Strengthened the cancellation test assertion**
- **Found during:** Task 2 (GREEN)
- **Issue:** The original rewritten test read `vm.rows` after the poll loop regardless of whether the row had resolved, so a non-cancelling implementation that eventually completed (58s) still "passed". It did not enforce must_have #2 (cancel actually STOPS work).
- **Fix:** Added an explicit `#expect(anyCompressing == false)` after the bounded 5s poll, so the test fails if the row is still `.compressing` at the deadline — which a non-cancellable implementation (tens of seconds) would be.
- **Files modified:** FlintTests/ImageCompressViewModelTests.swift
- **Verification:** With the broken plain-Task mechanism this assertion fails; with the Task.detached + direct-cancel fix it passes in 0.79s.
- **Committed in:** 75f3568

---

**Total deviations:** 3 auto-fixed (2 Rule 1 bugs, 1 Rule 2 missing-critical). **Impact on plan:** The plan's prescribed inner-work mechanism was unworkable (would freeze the MainActor and never cancel); the deviations were required to satisfy the must_haves. No scope creep — all changes stay within the four files in scope. The transformer's `compressOffMain` wrapper and the off-main + cooperative-cancellation intent are preserved exactly; only the concurrency primitive (detached + direct cancel) and the number of checkpoints changed.

## Issues Encountered
- Diagnosing the "cancel does nothing" behavior took several iterations because xcodebuild does not surface the test-host process's stderr, and the test process could not write probe files to the session scratchpad. Resolved by an isolated standalone Swift probe that proved a plain `Task {}` runs a synchronous `nonisolated` function on the main thread (`true`) while `Task.detached` runs it off-main (`false`) — pinpointing the root cause.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- GAP 3 (UAT Test 9) and GAP 4 (UAT Test 10) closed. Cancel stops work, resolves the row, and a clean re-drop disambiguates to `-compressed-1`.
- The off-main + cancellable pattern (Task.detached + stored handle + cooperative checkpoints) is reusable for any future heavy synchronous tool work that must remain cancellable.
- No blockers.

## Self-Check: PASSED
- Modified files exist on disk (verified via Edit/Write success and git tracking).
- Commits exist: `013ed88` (RED test), `75f3568` (GREEN feat) — both in `git log`.
- Full FlintTests suite: TEST SUCCEEDED. `testCancellation` 0.79s, all regression + transformer tests green, no Swift 6 data-race warnings.

---
*Phase: 05-add-image-compression-feature*
*Completed: 2026-06-30*
