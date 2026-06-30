---
status: diagnosed
trigger: "UAT Test 9 — pressing Cancel while a single large PNG is compressing leaves the row stuck spinning in .compressing forever; Cancel button disappears but work continues."
created: 2026-07-01T00:00:00Z
updated: 2026-07-01T00:00:00Z
goal: find_root_cause_only
symptoms_prefilled: true
---

## Current Focus

hypothesis: CONFIRMED — line 181 `guard !Task.isCancelled else { break }` breaks out of the loop AFTER the synchronous quantization finishes but BEFORE rows[i].apply(result), abandoning the .compressing row. The detached ImageIO/quantization work is non-cancellable (no isCancelled checks in ImageCompressTransformer.compress), so cancel() cannot interrupt it. cancel() also flips isCompressing=false immediately, hiding the Cancel button while work continues.
test: Static trace of the structured-concurrency control flow + read of ImageCompressTransformer.compress for cancellation checks.
expecting: A confirmed line-level mechanism leaving the row in .compressing, plus a downstream link to Test 10.
next_action: Return ROOT CAUSE FOUND.

## Symptoms

expected: After Cancel, pending rows stop, finished rows keep results, no row left spinning, Cancel button hides.
actual: Single compressing row keeps spinning indefinitely; image never stops processing; row stays in .compressing. Cancel button is already gone (screenshot).
errors: none (no crash, no log)
reproduction: UAT Test 9 — drop one large/slow PNG (slow due to quantization), press Cancel while compressing.
started: Phase 05 UAT.

## Eliminated

- hypothesis: "The spinner persists because isCompressing stays true."
  evidence: cancel() sets isCompressing=false at line 238, so the Cancel button hides (matches screenshot). The spinner is driven by the PER-ROW state (.compressing), not isCompressing. The View's ProgressView (ImageCompressView.swift line 261-264) renders for `case .compressing`, independent of isCompressing.
  timestamp: 2026-07-01T00:00:00Z

## Evidence

- timestamp: 2026-07-01T00:00:00Z
  checked: ImageCompressViewModel.swift lines 156-190 (the batch Task loop)
  found: Order of operations per image — (a) line 165 set rows[i].state = .compressing on MainActor; (b) line 173-177 `await Task.detached(...) { autoreleasepool { ImageCompressTransformer.compress(...) } }.value` runs the heavy work; (c) line 181 `guard !Task.isCancelled else { break }`; (d) line 184-188 rows[i].apply(result).
  implication: If cancellation lands during step (b), step (c) breaks BEFORE step (d). The row was set to .compressing in (a) and is NEVER moved out. Spinner persists forever.

- timestamp: 2026-07-01T00:00:00Z
  checked: ImageCompressTransformer.compress (Transformer lines 52+, quantization path 118-160) for any Task.isCancelled or cooperative-cancellation checks
  found: ZERO cancellation checks. compress() is a plain synchronous func returning Result. The PNG quantization (PNGColorQuantizer.quantize → IndexedPNGEncoder.encode) is pure CPU work with no yield points.
  implication: Wrapping synchronous work in `Task.detached { ... }.value` does NOT make it cancellable. Task.isCancelled is cooperative — code must poll it. The detached task carries its own (un-cancelled) context anyway: cancelling the PARENT task does not propagate to a Task.detached child (detached tasks are explicitly disconnected from the parent's cancellation). So even a cooperative check inside the detached closure would not see the parent's cancellation. The slow PNG runs to completion regardless of Cancel.

- timestamp: 2026-07-01T00:00:00Z
  checked: cancel() lines 235-239
  found: cancel() calls task?.cancel() (sets isCancelled on the parent Task — but the detached child is unaffected), task = nil, isCompressing = false. Immediate, synchronous, on MainActor.
  implication: isCompressing=false hides the Cancel button (View line 168) instantly, while the detached work keeps running and the row stays .compressing. Exactly matches the screenshot: button gone, spinner stuck.

- timestamp: 2026-07-01T00:00:00Z
  checked: Single-image batch timing (reproduction is ONE large PNG)
  found: With one URL, the loop body runs once. cancel() during the detached work sets parent isCancelled=true. When .value returns, line 181 guard fails → break. Loop ends. Line 195 `guard !Task.isCancelled else { return }` then returns before the completion block — so isCompressing is NOT re-touched there (already false from cancel()), and history does not fire. The row remains .compressing with no terminal transition anywhere.
  implication: There is no code path that resets a .compressing row on cancel. The break at 181 is the exact line that strands the row.

- timestamp: 2026-07-01T00:00:00Z
  checked: FlintTests/ImageCompressViewModelTests.swift testCancellation (lines 147-173)
  found: It compresses ONE 2x2 tiny JPEG then calls cancel() synchronously in the SAME MainActor.run block (lines 160-163). It only asserts isCompressing==false (lines 167, 171). It never inspects row state and never uses a slow input.
  implication: The test passes for two reasons: (1) it only checks isCompressing, which cancel() sets to false deterministically; (2) the tiny JPEG is so fast that by the time the detached task runs, the row-state outcome is irrelevant to the assertions. The test has a blind spot — it does not assert that a .compressing row is resolved to a terminal state after cancel, and it uses a trivially-fast fixture. This is why a real bug ships green.

- timestamp: 2026-07-01T00:00:00Z
  checked: Downstream link to UAT Test 10 (re-drop does nothing) — ImageCompressViewModel.compress lines 141-156
  found: compress() begins with task?.cancel() (line 143), then rebuilds rows and sets isCompressing=true (146-147), then assigns a NEW task (156). The orphaned detached work from the prior batch is fire-and-forget; its parent task is cancelled but the detached child keeps running and writes its `-compressed` file to disk independently. A fresh compress() does fully supersede rows and task.
  implication: From a CLEAN ViewModel state, a re-drop SHOULD work — compress() replaces rows wholesale and launches a new task. The Test-10 "re-drop does nothing" is NOT caused by ViewModel state poisoning from cancel. See Resolution for the real Test-10 mechanism.

## Resolution

root_cause: |
  Primary (Test 9): In ImageCompressViewModel.compress, the heavy work runs as synchronous
  `autoreleasepool { ImageCompressTransformer.compress(url:quality:) }` inside
  `await Task.detached(priority: .userInitiated) { ... }.value` (lines 173-177).

  Two compounding defects:
  1. NON-CANCELLABLE WORK: ImageCompressTransformer.compress has zero Task.isCancelled checks,
     and it runs in a Task.detached whose context is disconnected from the parent task's
     cancellation. So cancel() (which only cancels the parent task) can neither interrupt nor
     even signal the in-flight quantization. A slow PNG runs to completion regardless.
  2. ROW STRANDED IN .compressing: When the detached work finally returns, line 181
     `guard !Task.isCancelled else { break }` evaluates true (parent was cancelled) and BREAKS
     out of the loop BEFORE line 187 `rows[i].apply(result)`. The row was set to .compressing
     at line 165 and is never transitioned to any terminal state. The View renders a
     ProgressView for `case .compressing` (ImageCompressView.swift lines 261-264), so the
     spinner persists forever.

  Additionally, cancel() (lines 235-239) sets isCompressing = false immediately, which hides the
  Cancel button (View line 168) while the detached work is still running and the row still spins —
  exactly the screenshot symptom (button gone, spinner stuck).

  The exact stranding line is ImageCompressViewModel.swift:181 (the post-await
  `guard !Task.isCancelled else { break }`).

fix: "" # find_root_cause_only — no fix applied
verification: ""
files_changed: []

test_10_relationship: |
  Question posed: could this cancel bug ALSO cause a subsequent re-drop to silently do nothing (Test 10)?

  Answer: NO — Test 10 is NOT downstream of the cancel bug at the ViewModel-state level, but the
  two ARE causally linked through the stuck UI and the orphaned task, just not the way the UAT note
  speculated.

  Reasoning:
  - compress() unconditionally calls task?.cancel(), rebuilds `rows` wholesale, sets
    isCompressing=true, and assigns a fresh task (lines 143-156). So a second drop that actually
    REACHES compress() will always supersede prior state and produce output. There is no persistent
    ViewModel poisoning.
  - Therefore, if a CLEAN-LAUNCH re-drop disambiguates correctly (writes -compressed-1), Test 10 is
    independent of the cancel bug and lives in the drop handler / disambiguation path.
  - The most likely real Test-10 mechanism, GIVEN it was tested immediately after the stuck Test 9:
    the prior batch's ORPHANED Task.detached was still running (non-cancellable) and eventually wrote
    `photo-compressed.jpg`. The new drop's compress() launches and its transformer computes
    disambiguatedCompressedURL — but disambiguation is decided by a filesystem existence check
    (Transformer line 212 `while fm.fileExists(atPath: url.path)`). There is a RACE: depending on
    whether the orphaned task has finished writing `-compressed.jpg` by the time the new task checks,
    the second run may either reuse/collide on the same target or behave inconsistently. This is a
    race/timing artifact of the orphaned non-cancellable task from Test 9, NOT state poisoning inside
    the ViewModel.
  - Net: Test 10 should be re-tested FROM A CLEAN LAUNCH (no preceding cancel). The strong expectation
    is that clean-state re-drop works and disambiguates correctly, which would confirm Test 10 is a
    test-sequencing artifact of the Test-9 orphaned task rather than an independent drop-handler defect.
    If clean-state re-drop ALSO fails, then Test 10 is a genuinely separate bug in the onDrop →
    DispatchGroup → compress path (e.g. NSItemProvider re-load of the same provider) and must be
    diagnosed on its own.

specialist_hint: swift_concurrency
