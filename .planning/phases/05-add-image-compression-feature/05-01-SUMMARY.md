---
phase: 05-add-image-compression-feature
plan: "01"
subsystem: tools/image-compress
tags: [imageio, compression, transformer, tdd, pure-core]
dependency_graph:
  requires: []
  provides:
    - ImageCompressTransformer.compress(url:quality:) -> Result<CompressedImage, CompressError>
    - ImageCompressTransformer.disambiguatedCompressedURL(for:) -> URL
  affects:
    - Tools/ImageCompress/ (new tool directory)
    - FlintTests/ImageCompressTransformerTests.swift (new test coverage)
tech_stack:
  added: [ImageIO, CoreGraphics, UniformTypeIdentifiers]
  patterns:
    - pure-enum transformer (same shape as HashTransformer)
    - CGImageSource→CGImageDestination round-trip via CGImageDestinationAddImageFromSource
    - guard-gated ImageIO calls for INFRA-17 never-crash guarantee
    - fileExists loop for collision-safe disambiguation (D-07/D-08)
    - resourceValues(forKeys:fileSizeKey) no-decode byte count
key_files:
  created:
    - Tools/ImageCompress/ImageCompressTransformer.swift
    - FlintTests/ImageCompressTransformerTests.swift
  modified:
    - Flint.xcodeproj/project.pbxproj
decisions:
  - "Lossy detection uses UTType.conforms(to:) for .jpeg and .heic; UTType(\"public.heif\") checked with == for HEIF"
  - "Test fixtures synthesised at runtime via CGContext/CGImageDestination — no binary test assets committed"
  - "Disambiguation loop uses fileExists on candidate URL before write (best-effort TOCTOU, acceptable per RESEARCH A3)"
metrics:
  duration: "4 min 41 sec"
  completed: "2026-06-30T07:44:43Z"
  tasks_completed: 2
  files_created: 2
  files_modified: 1
---

# Phase 05 Plan 01: ImageCompressTransformer Pure Core Summary

**One-liner:** Pure ImageIO round-trip compressor with same-format-out guarantee (CGImageSourceGetType → CGImageDestinationAddImageFromSource), guard-gated for INFRA-17 never-crash, with collision-safe `-compressed` filename disambiguation.

## Tasks Completed

| # | Name | Type | Commit | Status |
|---|------|------|--------|--------|
| 1 | ImageCompressTransformer pure core | feat | de2d755 | Done |
| 2 | Unit tests + Xcode target membership | test | abf873b | Done |

## Commits

- `de2d755` — `feat(05-01): implement ImageCompressTransformer pure core`
- `abf873b` — `test(05-01): add ImageCompressTransformer unit tests + Xcode target membership`

## What Was Built

### Task 1: ImageCompressTransformer (Tools/ImageCompress/ImageCompressTransformer.swift)

Pure `enum ImageCompressTransformer` with:

- `enum CompressError { case notAnImage, unsupportedType, writeFailed }` — typed failure cases
- `struct CompressedImage` with `destURL`, `originalBytes`, `compressedBytes`, computed `percentSaved` (guards `originalBytes > 0`)
- `static func compress(url:quality:) -> Result<CompressedImage, CompressError>` — 9-step ImageIO pipeline:
  1. `CGImageSourceCreateWithURL` guard → `.notAnImage` on nil
  2. `CGImageSourceGetType` guard → `.unsupportedType` on nil (this UTI IS the same-format-out guarantee, D-02)
  3. `CGImageSourceGetCount > 0` guard → `.notAnImage` for empty/header-only files
  4. `disambiguatedCompressedURL(for:)` → collision-safe path beside original
  5. `CGImageDestinationCreateWithURL(destURL, uti, 1, nil)` guard
  6. Lossy detection via `UTType.conforms(to: .jpeg/.heic)` — JPEG/HEIC/HEIF get quality prop; PNG/TIFF get nil (D-05)
  7. `CGImageDestinationAddImageFromSource` (NOT AddImage) — carries EXIF/ICC/orientation forward
  8. `CGImageDestinationFinalize` Bool guard — removes partial write on false
  9. `resourceValues(forKeys: [.fileSizeKey])` — no-decode byte counts for percent-saved metric
- `static func disambiguatedCompressedURL(for:) -> URL` — pure path math: `<stem>-compressed.<ext>`, then `-1`, `-2`, … via `fileExists` loop

Imports: `Foundation`, `ImageIO`, `CoreGraphics`, `UniformTypeIdentifiers` — NO `SwiftUI`, NO `AppKit`.

### Task 2: Tests + Xcode Target Membership

`FlintTests/ImageCompressTransformerTests.swift` with 5 Swift Testing `@Test` cases:

1. **Valid JPEG round-trip** — synthesises 2×2 CGImage, encodes as JPEG, calls `compress(quality: 0.5)`, asserts `.success`, dest file exists, dest name is `photo-compressed.jpg`, UTI of source == UTI of dest (D-02)
2. **Corrupt content never crashes** — writes "not an image" bytes with `.jpg` extension, asserts `.failure` (INFRA-17)
3. **0-byte file never crashes** — empty `Data()` written to `.jpg`, asserts `.failure` (INFRA-17)
4. **Disambiguation collision** — creates `photo.png` AND `photo-compressed.png` beside it, asserts `disambiguatedCompressedURL` returns `photo-compressed-1.png` (D-08)
5. **Disambiguation base case** — creates `image.png` with no sibling, asserts URL ends in `image-compressed.png` and is beside original (D-07)

**project.pbxproj additions:**
- `001200000007001` / `001100000007001` — `ImageCompressTransformer.swift` in Flint app target Sources
- `001200000007002` / `001100000007002` — `ImageCompressTransformerTests.swift` in FlintTests target Sources
- Group `001500000007001` `ImageCompress` added to `Tools` group

**Test result:** `** TEST SUCCEEDED **` — all 5 cases green.

## Verification

- `CGImageDestinationAddImageFromSource` present: confirmed
- `CGImageSourceGetType` present: confirmed
- `disambiguatedCompressedURL` present: confirmed
- No `import SwiftUI`, no `import AppKit`: confirmed
- No bare `CGImageDestinationAddImage(` (anti-pattern): confirmed
- No `Data(contentsOf:)` for sizing: confirmed
- All ImageIO calls guard-gated, no `!` force-unwrap near ImageIO: confirmed
- `xcodebuild test -only-testing:FlintTests/ImageCompressTransformer`: PASSED

## Deviations from Plan

None — plan executed exactly as written.

The `ImageCompressTransformerTests.swift` helper `writeTinyJPEG` uses `CGImageDestinationAddImage` (not AddImageFromSource) — this is correct for the test fixture helper since we are creating a fresh synthetic image with no metadata to carry. The anti-pattern restriction applies only to the re-encode path in `ImageCompressTransformer.compress` itself, which correctly uses `AddImageFromSource`.

## Known Stubs

None. This plan is a pure logic layer (Transformer) — no UI data binding, no placeholders, no TODOs in the production code.

## Threat Surface Scan

No new network endpoints, auth paths, or trust boundary changes introduced.

The Transformer writes files to disk — covered by the plan's `<threat_model>`:
- T-05-01 (DoS via corrupt input): mitigated — all ImageIO calls guard-gated, proven by tests 2 and 3
- T-05-02 (Tampering / data loss): mitigated — destination path derived from original URL with `-compressed` suffix and fileExists collision loop; original never overwritten; partial writes cleaned up on `Finalize` failure
- T-05-03 (Path redirection): accepted — pure path math from dropped URL's own components; no user-supplied string concatenation

## Self-Check: PASSED

| Item | Status |
|------|--------|
| Tools/ImageCompress/ImageCompressTransformer.swift | FOUND |
| FlintTests/ImageCompressTransformerTests.swift | FOUND |
| Commit de2d755 (feat: transformer core) | FOUND |
| Commit abf873b (test: unit tests + pbxproj) | FOUND |
| xcodebuild test suite GREEN | CONFIRMED |
