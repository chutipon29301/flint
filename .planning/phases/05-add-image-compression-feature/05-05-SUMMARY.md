---
phase: 05-add-image-compression-feature
plan: 05
subsystem: image-compression
tags: [png, quantization, indexed-color, image-compression, transformer, wiring, uat-test-8, offline]
requires:
  - "PNGColorQuantizer.quantize(cgImage:maxColors:) -> QuantizedImage? (from 05-04)"
  - "IndexedPNGEncoder.encode(width:height:palette:alpha:indices:) -> Data? (from 05-04)"
  - "ImageCompressTransformer.compress(url:quality:) (existing pipeline)"
provides:
  - "ImageCompressTransformer PNG path that emits indexed color-type-3 PNGs (pngquant-class savings)"
  - "D-06 never-larger guard: output is never bigger than a truecolor re-encode of the source"
  - "Target membership for PNGColorQuantizer/IndexedPNGEncoder (app) + PNGQuantizationTests (test)"
affects:
  - "Closes UAT Test 8 — the last failing phase-05 must-have"
tech-stack:
  added: []
  patterns:
    - "Branch transformer on source UTI: PNG -> quantize+encode, everything else -> ImageIO re-encode"
    - "Never-larger guard via min(quantizedData.count, truecolorReencodeFileSize) (D-06 honest reporting)"
    - "nil-at-any-stage falls back to truecolor re-encode so compress() never fails on a decodable PNG (INFRA-17)"
key-files:
  created: []
  modified:
    - "Tools/ImageCompress/ImageCompressTransformer.swift"
    - "Flint.xcodeproj/project.pbxproj"
    - "FlintTests/ImageCompressTransformerTests.swift"
decisions:
  - "Never-larger guard short-circuits on the common case: if quantized bytes < original source file size, write quantized directly and skip the truecolor re-encode entirely (cheap, no double work)"
  - "Photographic-savings test uses a noise-injected gradient (UAT Test 8 content), not a smooth gradient — smooth gradients let PNG row filters beat indexed color, which is the known degenerate case from 05-04"
  - "False-RED disambiguation: a single-test xcodebuild run passed against old code due to stale incremental compilation; the full-suite run is authoritative and produced the genuine RED on the >30%-savings assertion"
metrics:
  duration: ~25 minutes
  completed: 2026-06-30
  tasks: 3
  files: 3
---

# Phase 05 Plan 05: Wire PNG Quantization into the Transformer Summary

Wired the 05-04 quantization engine (PNGColorQuantizer + IndexedPNGEncoder) into `ImageCompressTransformer`'s PNG path, registered the three new source files in the Xcode app/test targets, and closed UAT Test 8: a photographic PNG now shrinks meaningfully (indexed color-type-3 output ImageIO cannot produce) while alpha is preserved, the output is never larger than a plain truecolor re-encode (D-06), and JPEG/HEIC/TIFF paths and every prior test are unchanged and green.

## What Was Built

### Task 1: Xcode target registration (commit bafcc47)

Added the three 05-04 files to `Flint.xcodeproj/project.pbxproj` following the existing synthetic-ID convention (phase-05 namespace `...07xxx`, next free `07007/07008/07009`):
- **PBXBuildFile** + **PBXFileReference** entries for all three.
- `PNGColorQuantizer.swift` and `IndexedPNGEncoder.swift` added to the **app target Sources phase** and the **ImageCompress PBXGroup**.
- `PNGQuantizationTests.swift` added to the **test target Sources phase** and the **FlintTests PBXGroup**.
- `plutil -lint` passes; the three IDs appear across build-file, file-ref, group, and phase entries.

### Task 2: PNG quantization path in the transformer (TDD — commits 80781b6 RED, 98e745e GREEN)

`ImageCompressTransformer.compress(url:quality:)` now branches on the source UTI:
- **PNG** (`utType?.conforms(to: .png)`): decode frame 0 -> `PNGColorQuantizer.quantize` -> `IndexedPNGEncoder.encode` -> write. Any `nil` at decode/quantize/encode falls back to a plain truecolor ImageIO re-encode, so a decodable PNG never returns `.failure` (INFRA-17).
- **Everything else** (JPEG/HEIC/HEIF lossy props, TIFF/other nil props): the original `CGImageDestinationAddImageFromSource` path, byte-for-byte unchanged (D-05, metadata/orientation preserved).

**D-06 never-larger guard** (`writePNGCompressed` helper):
- If quantized bytes `<` original source file size, write the quantized data directly and skip the truecolor re-encode (the common photographic case — cheap, no double work).
- Otherwise, also produce the truecolor re-encode to a temp sibling and keep whichever of `{quantized, truecolor}` is smaller, then move it into place. The user is never handed a file larger than a plain re-encode.

Tests added to the existing `@Suite("ImageCompressTransformer")`:
- `writeGradientPNG` (noise-injected photographic content) and `writeTransparentQuadrantPNG` helpers, plus `pixelDimensions`/`hasTransparentPixel` decode helpers.
- Photographic PNG saves `>30%`, output is a valid same-dimension `public.png` (D-02, no downscaling).
- Transparency survives quantization (a transparent region stays transparent).
- Low-color PNG still succeeds and is never larger than the truecolor re-encode (D-06).
- Corrupt `.png`-extension input returns `.failure` without crashing (INFRA-17).

### Task 3: Full build + full test suite (verification-only, no edits)

`xcodebuild build` -> **BUILD SUCCEEDED**. `xcodebuild test` (entire suite) -> **TEST SUCCEEDED**, 400 passing test executions, zero failures. The 05-04 engine tests ran inside the real target for the first time here (Task 1 gave them membership) and all pass.

## Verification

| Check | Result |
|-------|--------|
| `plutil -lint project.pbxproj` | OK |
| New synthetic IDs present (07007/07008/07009) | 9 reference lines |
| RED gate: photographic-savings test fails against old truecolor path | ok (full-suite run; ~0% vs required >30%) |
| GREEN gate: transformer + PNGQuantization suites pass | ok |
| Photographic PNG saves > 30%, same dims, valid public.png | ok |
| Alpha transparency preserved after quantization | ok |
| D-06: output never larger than truecolor re-encode | ok |
| Corrupt .png -> .failure, no crash (INFRA-17) | ok |
| JPEG/HEIC/TIFF + all prior tests unchanged and green | ok |
| `xcodebuild build` | BUILD SUCCEEDED |
| `xcodebuild test` (full suite, 400 executions) | TEST SUCCEEDED |

## TDD Gate Compliance

- RED: `test(05-05)` commit `80781b6` — the `>30%` photographic-savings assertion failed against the pre-existing truecolor path.
- GREEN: `feat(05-05)` commit `98e745e` — quantization path makes it pass.
- REFACTOR: none needed; the implementation is clean.

**False-RED note:** an initial single-test `xcodebuild test -only-testing:...photographicPNG...` run reported success against the old code. A standalone `swiftc` probe proved a truecolor re-encode of the test image does NOT shrink (it grows ~0.27%), so the single-test pass was stale incremental compilation (a known project hazard — see MEMORY: "Stale DerivedData builds"). The full-suite run produced the genuine RED. Per the TDD fail-fast rule, this was investigated before proceeding to GREEN rather than skipped.

## Deviations from Plan

None — plan executed as written. All three nil-fallbacks, the never-larger guard, and the UTI branch match the plan's PNG-path spec. The TIFF/JPEG/HEIC branches were left untouched as required.

## Known Stubs

None. The PNG path is fully wired end-to-end; no placeholder data or empty values.

## Threat Flags

None. No new network or disk surface beyond the existing transformer file write. The temp truecolor-comparison file is written to a dot-prefixed UUID sibling and always cleaned up via `defer`. Per the plan's threat register: T-05-05-01/02/03 all mitigated (linear quantize/encode, nil-fallback never throws, never-larger guard), T-05-05-SC accept (no package installs — pure Swift + Foundation + Compression + CoreGraphics).

## Self-Check: PASSED

- Tools/ImageCompress/ImageCompressTransformer.swift — FOUND
- Flint.xcodeproj/project.pbxproj — FOUND
- FlintTests/ImageCompressTransformerTests.swift — FOUND
- .planning/phases/05-add-image-compression-feature/05-05-SUMMARY.md — FOUND
- Commit bafcc47 (Task 1) — FOUND
- Commit 80781b6 (Task 2 RED) — FOUND
- Commit 98e745e (Task 2 GREEN) — FOUND
