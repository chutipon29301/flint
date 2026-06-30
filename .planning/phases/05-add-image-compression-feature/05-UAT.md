---
status: diagnosed
phase: 05-add-image-compression-feature
source: [05-01-SUMMARY.md, 05-02-SUMMARY.md, 05-03-SUMMARY.md, 05-04-SUMMARY.md, 05-05-SUMMARY.md]
started: 2026-06-30T09:30:00Z
updated: 2026-07-01T00:10:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Cold Start Smoke Test
expected: Quit Flint, then launch it fresh from the canonical build product (not a stale DerivedData copy). Menubar icon appears, popover opens fast, and the Image Compressor tool is present in the grid. No crash, no missing tool on cold launch.
result: pass
note: "Cold-launched clean Debug build (PID 21999) from canonical BUILD_DIR. Tool present, no crash. Separately observed an auto-update warning on launch — logged as out-of-scope issue below (not a phase-05 deliverable)."

### 2. Launcher search routing
expected: Searching the launcher for "image" or "compress" finds and routes to the Image Compressor tool.
result: pass

### 3. Drop images → live results table
expected: Dropping one or more images onto the tool shows a per-row thumbnail, original→new size, and a green "−NN%" saved (or secondary "+N%"/"0%" if it grew), updating live as each image finishes. A `-compressed` file is written beside each original.
result: pass

### 4. PNG photographic compression ratio (UAT Test 8 re-test)
expected: Compressing a photographic PNG now shrinks it meaningfully (indexed-color output) — comparable to a dedicated PNG optimizer, not the near-0% from before. Output stays the same dimensions and is a valid PNG.
result: pass

### 5. PNG transparency preserved
expected: Compressing a PNG that has transparent areas keeps those areas transparent after compression — no black/white fill replacing the transparency.
result: issue
reported: "transparency works, but the output is BIGGER — Google-Logo-2015.png went 30 KB → 46 KB (+55%)"
severity: major

### 6. Lossless slider gate (D-05)
expected: When every dropped file is PNG/TIFF, the quality slider is disabled and a helper line explains lossless formats ignore the quality setting.
result: issue
reported: "slider IS disabled correctly, but the slider/presets are contradictory with the workflow — dropping an image compresses it immediately, so there's no point at which the slider can affect the images you just dropped. When does it actually take effect?"
severity: minor

### 7. Quality presets (Web/Email/Max)
expected: The matching preset button (Web 60 / Email 75 / Max 95) renders prominent when active and plain otherwise; selecting a preset moves the slider. Lower quality on a JPEG produces a smaller file.
result: pass

### 8. Non-image / corrupt input never crashes (INFRA-17)
expected: Dropping a non-image (or corrupt image) alongside valid images shows a warning on the failed row; the app never crashes and the valid images still compress.
result: pass

### 9. Cancel mid-batch
expected: Pressing Cancel during a large batch stops pending rows; already-finished rows keep their results; the Cancel button hides afterward.
result: issue
reported: "after pressing Cancel the row keeps spinning (still processing) — the compressing image never stops and the row stays stuck in the spinner state"
severity: major

### 10. Collision disambiguation (D-07/D-08)
expected: Compressing the same source twice produces `photo-compressed.jpg` then `photo-compressed-1.jpg` — the original is never overwritten.
result: issue
reported: "dropping the same image a second time shows nothing new in the table AND writes no second file to disk — the re-drop appears to do nothing"
severity: major
note: "Tested immediately after the stuck-Cancel issue (Test 9). The disambiguation logic (-compressed-1) cannot be reached because the second compression never produces output. Likely interacts with the Test-9 stuck state; diagnosis must confirm whether a clean-state re-drop disambiguates correctly or whether the drop handler itself is at fault."

## Summary

total: 10
passed: 6
issues: 4
pending: 0
skipped: 0
blocked: 0

## Gaps

- truth: "App launches cleanly without spurious update/error warnings"
  status: failed
  reason: "User reported: an auto-update warning appears on app launch"
  severity: minor
  test: 1
  scope: out-of-phase
  note: "Surfaced during phase-05 cold-start test but belongs to the Sparkle auto-update subsystem (Phase 03), not the image-compression feature. Logged for follow-up; does not block phase-05 verification."
  artifacts: []
  missing: []

- truth: "Compressed PNG output is never larger than the original file (it's a compressor)"
  status: failed
  reason: "User reported: Google-Logo-2015.png 30 KB → 46 KB (+55%). Transparency preserved, but file grew."
  severity: major
  test: 5
  root_cause: "ImageCompressTransformer.writePNGCompressed (lines 151-173) gates the never-larger guard against a TRUECOLOR RE-ENCODE, not the ORIGINAL FILE. For an already-optimized PNG (small palette/low-color logo), the quantized indexed output (46 KB) is larger than the original (30 KB) but smaller than a fresh truecolor RGBA re-encode, so quantized wins the {quantized, truecolor} comparison and gets written. The original 30 KB file is never a candidate. D-06's contract ('never larger than a truecolor re-encode') does not match the user expectation ('a compressor must never make a file bigger')."
  artifacts:
    - path: "Tools/ImageCompress/ImageCompressTransformer.swift"
      issue: "writePNGCompressed never-larger guard compares vs truecolor re-encode, not vs original source bytes (lines 151-173)"
  missing:
    - "Change the guard baseline from the truecolor re-encode to the ORIGINAL source file size; make the original a writable candidate — write the smallest of {original, quantized, truecolor}. When the original wins, copy it through so output is never larger than input."
    - "Apply the same never-larger-than-original guard to the non-PNG ImageIO path (lines 82-105 have NO guard; size is measured post-write at 107-115 for reporting only). After Finalize, if the re-encode grew, replace destURL with a copy of the original (or skip + report 0%)."
    - "Optional: reduce how often the fallback fires — give IndexedPNGEncoder adaptive row filtering and cap palette to the actual color count (currently filter-0 + default-effort zlib + 256-color cap, which bloats output for low-color logos)."
  debug_session: ".planning/debug/png-output-larger-than-input.md"

- truth: "The quality slider/presets have a clear, non-contradictory relationship to the compress action"
  status: failed
  reason: "User reported: drop-to-compress is immediate, so the quality slider can never affect the images already dropped. Its effect is invisible/deferred-to-next-drop, and it's disabled entirely for PNG/TIFF — so for the all-lossless case it appears to do nothing at all."
  severity: minor
  test: 6
  root_cause: "ImageCompressView triggers viewModel.compress(urls:quality:) immediately on drop (onDrop → DispatchGroup join → compress). The @AppStorage quality value is only read at drop time, so changing the slider after a drop has no effect on the current results — there is no 're-run with new quality' affordance. The slider reads as a control over 'this compression' but is actually 'the next one'. UX-design gap, not a code defect."
  artifacts:
    - path: "Tools/ImageCompress/ImageCompressView.swift"
      issue: "compress fires immediately onDrop; no re-run-on-quality-change path; slider effect is deferred and non-obvious"
  missing:
    - "RECOMMENDED (option C): add an explicit 'Re-compress at {n}%' action. Store lastSourceURLs + add recompress() on the ViewModel; show a button when quality/preset changes after a batch exists. Preserves the deliberate drop-driven trigger (05-UI-SPEC line 119) AND respects that compression WRITES FILES — so each write stays an explicit user action."
    - "Why NOT Hash-style auto .onChange: Hash is pure/in-memory/idempotent so re-running is free; compression writes a disambiguated -compressed-N file per run, so auto-re-run on every slider tick would spew files. The sibling idiom cannot be copied verbatim."
    - "Optional (option B): clarify pre-first-drop copy ('Set quality, then drop'). Design decision — route through discuss/plan, not a one-line fix."
  debug_session: ".planning/debug/quality-slider-workflow-contradiction.md"

- truth: "Pressing Cancel stops in-flight work and the compressing row leaves the spinner state"
  status: failed
  reason: "User reported: after Cancel the single compressing row keeps spinning; the image never stops processing and the row stays stuck in .compressing."
  severity: major
  test: 9
  root_cause: "ImageCompressViewModel.compress runs the heavy ImageIO/quantization work as a synchronous `autoreleasepool { ImageCompressTransformer.compress(...) }` inside `await Task.detached(...).value` (lines 173-177). That synchronous work has NO cancellation check, so cancel() cannot interrupt it — a slow PNG quantization runs to completion. Worse, on return the post-await `guard !Task.isCancelled else { break }` (line 181) breaks BEFORE applying the result, so rows[i] is never moved out of .compressing — the row spins forever. cancel() also sets isCompressing=false immediately (hides the Cancel button) even though work is still running, matching the screenshot (button gone, spinner persists)."
  root_cause_refined: "CONFIRMED. Exact stranding line is ImageCompressViewModel.swift:181 — the post-await `guard !Task.isCancelled else { break }` breaks BEFORE line 187 rows[i].apply(result), so the row set to .compressing at line 165 never reaches a terminal state. The View renders ProgressView for .compressing (ImageCompressView 261-264), so the spinner persists forever. Two compounding defects: (1) the work is non-cancellable — ImageCompressTransformer.compress has zero Task.isCancelled checks AND runs inside Task.detached, whose context is DELIBERATELY DISCONNECTED from the parent's cancellation, so a cooperative check alone wouldn't even observe cancel(); (2) cancel() (235-239) flips isCompressing=false immediately, hiding the Cancel button (View 168) while work continues. The existing testCancellation passes blind: it only asserts isCompressing==false, never inspects row state, and uses a trivially-fast 2x2 JPEG."
  artifacts:
    - path: "Tools/ImageCompress/ImageCompressViewModel.swift"
      issue: "line 181 break strands the .compressing row before apply; lines 173-177 run non-cancellable detached work; cancel() (235-239) flips isCompressing=false while work continues"
    - path: "Tools/ImageCompress/ImageCompressTransformer.swift"
      issue: "compress (line 52) + quantization path (118-160) have no cancellation checks"
    - path: "FlintTests/ImageCompressViewModelTests.swift"
      issue: "testCancellation (147-173) asserts only isCompressing==false, never row state, uses fast fixture — blind to the stuck-.compressing outcome"
  missing:
    - "On cancel, resolve any .compressing row to a terminal state (apply the result if it returned, else reset to .pending / a new .cancelled state) — do NOT silently break at line 181 leaving it dangling"
    - "Use a CHILD task (not Task.detached) so parent cancellation propagates, AND add a cooperative Task.isCancelled checkpoint inside the long quantization loop in the Transformer so in-flight work can actually stop"
    - "Keep the Cancel button visible (or show 'Cancelling…') until the in-flight row resolves; don't flip isCompressing=false eagerly"
    - "Update testCancellation to use a slow fixture and assert NO row remains .compressing after cancel"
  debug_session: ".planning/debug/cancel-leaves-row-stuck.md"

- truth: "Compressing the same source twice writes photo-compressed then photo-compressed-1 without overwriting the original (D-07/D-08)"
  status: failed
  reason: "User reported (clarified): dropping the same image a second time shows nothing new in the table AND writes no second file to disk — the re-drop appears to do nothing."
  severity: major
  test: 10
  root_cause: "DOWNSTREAM OF TEST 9 — NOT an independent defect. There is no software-state poisoning: a fresh compress() rebuilds rows (146), sets isCompressing=true (147), and assigns a brand-new uncancelled task (156); the no-op task?.cancel() at 143 is harmless. disambiguatedCompressedURL (Transformer 198-217) is correct in isolation. The symptom is the Test-9 bug's RUNTIME RESIDUE: Test 10 re-dropped the SAME file Test 9 left stuck. (1) Test 9's non-cancellable Task.detached is still grinding slow PNG quantization on that source, so no file written yet. (2) The re-drop's fresh .pending row for the same filename is visually indistinguishable from the stuck spinner → 'nothing new in the table'. (3) Two Task.detached jobs now run on the same source; both hit disambiguatedCompressedURL inside the TOCTOU window (Transformer 196) where photo-compressed.jpg doesn't exist yet, so both target photo-compressed.jpg — '-compressed-1' never triggers — and while both are still quantizing, no new file appears → 'no second file written'."
  verdict: "downstream-of-test-9 — a clean-launch first-drop → second-drop (no cancel) disambiguates correctly and writes -compressed-1. Fix COORDINATED with the Test-9 cancel fix; do not treat as standalone."
  artifacts:
    - path: "Tools/ImageCompress/ImageCompressViewModel.swift"
      issue: "Test-9 non-cancellable Task.detached (173-177) leaves residual in-flight work that masks the re-drop. NOT defective for the re-drop path itself."
    - path: "Tools/ImageCompress/ImageCompressTransformer.swift"
      issue: "disambiguatedCompressedURL (198-217) is correct; TOCTOU window (196) lets two concurrent same-source batches both target photo-compressed.jpg"
    - path: "Tools/ImageCompress/ImageCompressView.swift"
      issue: "onDrop (43-69) has no in-progress guard, allowing a re-drop to spawn a second concurrent batch on the same file"
  missing:
    - "Fix alongside Test-9: once cancel resolves the in-flight row and stops the orphaned task, the same-source concurrency disappears and a clean re-drop correctly produces -compressed-1"
    - "Optional hardening: close the disambiguation TOCTOU window (atomic create with O_EXCL, or reserve destURL before the slow encode) so two genuinely-concurrent batches can't both target photo-compressed.jpg"
    - "Optional: an in-progress / dedupe guard on onDrop so re-dropping a file already compressing is handled deliberately"
  debug_session: ".planning/debug/redrop-produces-no-output.md"
