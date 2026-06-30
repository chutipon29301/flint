---
status: diagnosed
trigger: "UAT Test 6 — slider/presets are contradictory with compress-on-drop workflow; quality only affects the NEXT drop, not the images you just dropped. When does it actually take effect?"
created: 2026-07-01T00:00:00Z
updated: 2026-07-01T00:00:00Z
---

## Current Focus

hypothesis: CONFIRMED — ImageCompressView.onDrop reads @AppStorage quality at drop time and fires compress() immediately, with no affordance to re-run on the already-dropped batch. The slider reads as a control over "this compression" but actually governs "the next one." Design contradiction, not a code defect.
test: Read view + viewModel + spec/context/discussion + surveyed sibling tools (Hash) for parameter+input ordering.
expecting: Confirm compress-on-drop was deliberate (spec calls the trigger "implicit (drop-driven)"); quality-applies-to-next-drop is an unaddressed UX consequence that breaks the parameter-re-runs-transform pattern Hash establishes.
next_action: Deliver ROOT CAUSE FOUND (diagnose-only; no fix).

## Symptoms

expected: When the user adjusts quality, it visibly affects the images being compressed.
actual: Dropping an image compresses it immediately; the slider only affects the NEXT drop. For PNG/TIFF the slider is disabled entirely. User: "there's no point at which the slider can affect the images you just dropped. When does it actually take effect?"
errors: none (UX/workflow contradiction, not a crash)
reproduction: UAT Test 6 — drop an image; it compresses instantly using the quality value at drop time. Changing the slider afterward has no effect on the displayed results.
started: Discovered during Phase 05 UAT.

## Eliminated

## Evidence

- timestamp: 2026-07-01
  checked: Tools/ImageCompress/ImageCompressView.swift lines 43-69 (.onDrop) and 333-337 (chooseImages)
  found: onDrop gathers URLs, then at line 62 captures `quality / 100.0` (the @AppStorage value AT DROP TIME), and at line 65 calls viewModel.compress(urls:quality:) immediately via Task @MainActor. chooseImages() (line 335) does the same — reads quality at invocation, compresses immediately.
  implication: Quality is read once, at the moment of drop/pick. There is no binding between the live slider and the in-flight or completed batch.

- timestamp: 2026-07-01
  checked: ImageCompressViewModel.compress(urls:quality:) lines 141-229
  found: compress() takes quality as a value parameter, builds rows, runs the batch. It does NOT observe the slider. There is no recompress(quality:) method, no stored lastURLs, no re-run trigger. The only way to re-run is a NEW drop or a NEW Choose Images… pick.
  implication: No affordance exists to re-apply a changed quality to the already-dropped batch. Confirmed.

- timestamp: 2026-07-01
  checked: View slider/preset bindings lines 101, 134, 132-148
  found: Slider binds to $quality (@AppStorage) and presets set quality directly. Changing them mutates the persisted value but triggers nothing — no .onChange, no recompress. isEntirelyLossless (line 82) disables the slider only when the CURRENT batch is entirely PNG/TIFF.
  implication: Adjusting quality after a drop silently updates a value that will only be consumed by the next compress() call.

- timestamp: 2026-07-01
  checked: 05-UI-SPEC.md line 119 and CONTEXT.md D-01/D-04
  found: Spec explicitly states "the 'Compress' trigger is implicit (drop-driven)." CONTEXT D-04 says "slider stays adjustable after a preset" but never specifies WHEN quality is applied relative to the input. The drop-driven model was deliberate; the parameter-application ordering was simply unspecified — an oversight, not a decision.
  implication: Compress-on-drop is intended. The quality-applies-to-next-drop behavior was never designed; it falls out of "implicit drop-driven trigger" + "quality read at the call site." This is the design gap.

- timestamp: 2026-07-01
  checked: Sibling-tool pattern — Tools/Hash/HashView.swift lines 117-137 (the designated analog per CONTEXT canonical_refs)
  found: Hash re-runs its transform via .onChange when its PARAMETERS change — .onChange(of: hmacKey) → computeHMAC, .onChange(of: hmacAlgorithm) → recompute. Hash's established pattern is "parameter change re-applies the transform to the existing input." ImageCompress has NO equivalent .onChange(of: quality) hook.
  implication: ImageCompress breaks the parameter-re-runs-transform idiom Hash establishes. KEY ASYMMETRY: Hash transforms are pure/in-memory and idempotent — re-running is free and invisible. Compression WRITES FILES to disk (D-07) and disambiguates collisions (D-08), so a naive .onChange(of: quality) re-run would write a NEW -compressed-N file on every slider tick — unacceptable. So Hash's exact mechanism cannot be copied verbatim; the recommendation must account for the disk-write side effect.

## Resolution

root_cause: |
  Design contradiction (UX gap), not a code defect. ImageCompressView.onDrop (lines 43-69)
  joins the dropped URLs via DispatchGroup, captures the @AppStorage `quality` value AT DROP
  TIME (line 62: `min(max(quality / 100.0, 0.0), 1.0)`), and immediately calls
  viewModel.compress(urls:quality:) (line 65). chooseImages() (line 335) does the same.
  compress() takes quality as a one-shot value parameter (ViewModel line 141) and exposes NO
  recompress(quality:) method, stores no last-batch URLs, and the slider/presets have NO
  .onChange re-trigger (View lines 101, 132-148). Therefore the quality control governs only
  the NEXT drop, never the batch already on screen. For an all-lossless (PNG/TIFF) batch the
  slider is additionally disabled (lines 102, 82-84), so in that case it appears to do nothing
  at all. The "Compress" trigger being implicit/drop-driven was deliberate (05-UI-SPEC line 119);
  the ordering of when quality applies relative to the dropped input was never specified — an
  oversight. The result violates the parameter-re-runs-transform idiom the Hash tool (the
  designated analog) establishes via .onChange.

fix: "(none — diagnose-only mode)"

verification: "(none — diagnose-only mode)"

files_changed: []
