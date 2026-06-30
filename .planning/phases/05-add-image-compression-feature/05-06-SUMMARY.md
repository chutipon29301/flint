---
phase: 05-add-image-compression-feature
plan: 06
subsystem: tools
tags: [imageio, png, jpeg, compression, quantization, swift-testing, gap-closure]

# Dependency graph
requires:
  - phase: 05-add-image-compression-feature
    provides: ImageCompressTransformer (PNG quantization path + non-PNG ImageIO re-encode path), IndexedPNGEncoder, PNGColorQuantizer, transformer test suite
provides:
  - never-larger-than-ORIGINAL guard on both the PNG quantization path and the non-PNG ImageIO path
  - byte-identical copy-through of the original source when no candidate beats it
  - percentSaved is never negative for any successful compression
  - failing-first transformer tests (A/B/C) proving neither path grows a file beyond the original
affects: [05-07, 05-08, image-compression-uat]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Original source file is a first-class writable candidate alongside {quantized, truecolor}; smallest wins"
    - "Post-finalize never-larger guard on the ImageIO path: copyItem(source -> dest) when the re-encode grew"
    - "Size comparisons use URL.resourceValues(.fileSizeKey) only — never Data(contentsOf:) (T-05-06B)"
    - "Hand-crafted minimal already-optimized PNG fixture to reach the original-wins copy-through branch deterministically"

key-files:
  created: []
  modified:
    - Tools/ImageCompress/ImageCompressTransformer.swift
    - FlintTests/ImageCompressTransformerTests.swift

key-decisions:
  - "Make the ORIGINAL source file a writable candidate on BOTH paths rather than only comparing against a truecolor re-encode (the D-06 contract that caused GAP 1)"
  - "On the non-PNG path, guard AFTER finalize: if the re-encode grew, remove it and copyItem the original through (try? throughout; leave re-encode in place on copy failure so a valid same-format file always remains — INFRA-17)"
  - "Replace Test C's fixture (2x2 ImageIO PNG, which the quantizer always beats) with a 67-byte hand-crafted already-optimized PNG so the original-wins copy-through branch is actually exercised"

patterns-established:
  - "When a compressor has multiple candidate encoders, the untouched original is always an eligible output and the global minimum is selected"

requirements-completed: [D-02, D-06, INFRA-17]

# Metrics
duration: 9min
completed: 2026-07-01
---

# Phase 05 Plan 06: Never-larger-than-original guard Summary

**ImageCompressTransformer now treats the original source file as a writable candidate on both the PNG quantization path and the non-PNG ImageIO path, copying it through byte-identically whenever no re-encode beats it — so a compressed file can never be larger than its input (closes GAP 1 / UAT Test 5).**

## Performance

- **Duration:** 9 min
- **Started:** 2026-06-30T17:35:06Z
- **Completed:** 2026-06-30T17:44:29Z
- **Tasks:** 2 (TDD: RED + GREEN)
- **Files modified:** 2

## Accomplishments
- PNG path (`writePNGCompressed`): the ORIGINAL source is now compared against `{quantized, truecolor}` and copied through verbatim when it is the smallest — an already-optimized PNG (the Google-logo 30 KB -> 46 KB +55% case) can no longer grow.
- Non-PNG ImageIO path: added a post-finalize never-larger guard — when a re-saved JPEG/HEIC/TIFF grows beyond the original, the output is replaced with a byte copy of the source.
- `percentSaved` can no longer be negative for any successful compression (honest reporting, D-06 generalized to the original baseline).
- Three failing-first tests (A: PNG never grows; B: JPEG never grows + same UTI; C: byte-identical copy-through when the original wins) added and green; all prior transformer tests (photographic shrink >30%, alpha preservation, D-06 truecolor bound, INFRA-17 corrupt/empty inputs) stay green.

## Task Commits

Each task was committed atomically:

1. **RED — failing never-larger-than-original tests** - `dede547` (test)
2. **GREEN — never-larger-than-original guard on PNG and non-PNG paths** - `2707c08` (feat)

**Plan metadata:** committed with this SUMMARY (docs)

_TDD: test (RED) -> feat (GREEN). No refactor commit needed — implementation was minimal and clean._

## Files Created/Modified
- `Tools/ImageCompress/ImageCompressTransformer.swift` - PNG path selects the smallest of `{original, quantized, truecolor}` (copyItem the source when it wins); non-PNG path gains a post-finalize size guard that copies the original through if the re-encode grew. All size checks via `fileSizeKey`.
- `FlintTests/ImageCompressTransformerTests.swift` - Added Tests A/B/C and a `writeAlreadyOptimizedPNG` helper (67-byte minimal already-optimized PNG fixture) that deterministically reaches the original-wins copy-through branch.

## Decisions Made
- The fix changes the comparison baseline from "never larger than a truecolor re-encode" (the original D-06 contract that baked in GAP 1) to "never larger than the ORIGINAL source," with the original itself as an eligible output on both paths.
- The non-PNG guard uses `try?` throughout and leaves the (valid, same-format) re-encode in place if the copy fails, so the operation never fails purely because of the size guard (INFRA-17 preserved).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Test C fixture redesigned so the original-wins copy-through branch is reachable**
- **Found during:** RED (Test C)
- **Issue:** The plan suggested reusing `writeTinyPNG` (a 2x2 ImageIO PNG) for Test C's "original wins" scenario. Measurement of the real quantizer + encoder (compiled standalone) showed the 256-color quantized indexed output is 83 B vs the 157 B original — i.e. the quantizer **always beats** any ImageIO-synthesised low-color PNG, so the "original is the smallest candidate" precondition is structurally unreachable with that fixture, and Test C could never exercise copy-through. ImageIO cannot emit a PNG small enough to lose.
- **Fix:** Added a `writeAlreadyOptimizedPNG` helper that writes a hand-crafted 67-byte minimal already-optimized grayscale PNG. For this fixture `original (67 B) < quantized (82 B) < truecolor (3479 B)`, so the original is the smallest candidate and the copy-through path is forced — a faithful reproduction of the real GAP-1 trigger (an externally pngquant/zopfli-optimized PNG). Tests A and B keep the ImageIO fixtures (`writeTinyPNG` / `writeTinyJPEG`) and assert the never-larger invariant, which holds regardless of which candidate wins.
- **Files modified:** FlintTests/ImageCompressTransformerTests.swift
- **Verification:** Standalone probe (compiled against the real `PNGColorQuantizer` + `IndexedPNGEncoder`) confirmed `originalWins=true` for the 67-byte fixture; full `xcodebuild test` suite green with Test C passing on the copy-through path.
- **Committed in:** `2707c08` (GREEN commit)

---

**Total deviations:** 1 auto-fixed (1 bug — test fixture correction)
**Impact on plan:** The implementation matches the plan's GREEN spec exactly on both paths. Only the Test C fixture had to change because the planner's suggested fixture could not reach the branch under test. No scope creep; the deviation strengthens the test's fidelity to the real defect.

## Issues Encountered
- Test A and Test B passed against the pre-fix code during RED (their ImageIO fixtures did not happen to grow), so only Test C was a deterministic RED. This is expected and was anticipated by the plan ("JPEG *may* grow"). Test C is the deterministic proof of the gap (copy-through did not exist); A and B remain valid never-larger / no-regression assertions. Resolved by confirming, via standalone measurement, that Test C's redesigned fixture genuinely fails pre-fix (quantized 82 B written ≠ 67 B original) and passes post-fix.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- GAP 1 closed: no code path in `ImageCompressTransformer.compress` can produce a file larger than the original source; `percentSaved` is never negative; D-02 (same format + dimensions) and INFRA-17 (typed failure, no crash) preserved.
- Build-and-test only — no manual UAT for this plan. Ready for remaining phase-05 gap-closure plans (05-07, 05-08).

## Self-Check: PASSED

- `Tools/ImageCompress/ImageCompressTransformer.swift` — FOUND
- `FlintTests/ImageCompressTransformerTests.swift` — FOUND
- Commit `dede547` (RED) — FOUND
- Commit `2707c08` (GREEN) — FOUND
- Full `xcodebuild test` (FlintTests) — `** TEST SUCCEEDED **`; Tests A/B/C green; all regressions green
- Acceptance patterns: `copyItem` present on both paths; `originalBytes`/`origBytes`/`origSize` guards present; tests reference originalBytes (11 occurrences)

---
*Phase: 05-add-image-compression-feature*
*Completed: 2026-07-01*
