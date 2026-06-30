---
phase: 05-add-image-compression-feature
plan: "03"
subsystem: tools/image-compress
tags: [swiftui, view, definition, registry, drop, batch, quality-slider, results-table, xcode-target]
dependency_graph:
  requires:
    - ImageCompressViewModel.compress(urls:quality:) + rows + isCompressing + cancel()
    - ImageCompressTransformer.CompressedImage (percentSaved, originalBytes, compressedBytes)
    - CompressRow (sourceURL, format, state: .pending/.compressing/.done/.failed)
    - ImageFormatTag (displayTag, isLossless)
    - DropOverlayView(label:)
    - WarningBannerView(message:severity:)
    - ToolShortcutActions + .toolShortcuts(_:)
    - HistoryStore.save(_:)
  provides:
    - ImageCompressView (SwiftUI view: drop surface + quality slider/presets + live results table)
    - ImageCompressDefinition.make() -> ToolDefinition (id: image-compress, category: .conversion)
    - ToolRegistry registration via sanctioned-append line
  affects:
    - Tools/ImageCompress/ImageCompressView.swift (new)
    - Tools/ImageCompress/ImageCompressDefinition.swift (new)
    - Core/Services/ToolRegistry.swift (modified: 1 sanctioned-append line + comment)
    - Flint.xcodeproj/project.pbxproj (modified: 4 new entries)
tech_stack:
  added: []
  patterns:
    - "@AppStorage for persisted quality (not computed PreferencesStore — MEMORY.md pitfall)"
    - "DispatchGroup multi-provider .onDrop for batch file collection (all providers, not first)"
    - "@State private var viewModel: ImageCompressViewModel + init(onSaveHistory:) mirrors HashView"
    - "isEntirelyLossless computed from viewModel.rows — gating D-05 slider disable at view level"
    - "ByteCountFormatter(.file) for monospaced size delta strings"
    - "NSImage(contentsOf:) lazy thumbnail in View (never Transformer) per UI-SPEC"
    - "HashDefinition.swift wholesale copy + rename for ImageCompressDefinition"
key_files:
  created:
    - Tools/ImageCompress/ImageCompressView.swift
    - Tools/ImageCompress/ImageCompressDefinition.swift
  modified:
    - Core/Services/ToolRegistry.swift
    - Flint.xcodeproj/project.pbxproj
decisions:
  - "category: .conversion chosen over .analysis — image compress is a data conversion, not analytical inspection"
  - "isEntirelyLossless computed in View body (not ViewModel) — pure view-gating concern, no business logic"
  - "NSImage(contentsOf:) used for thumbnails (adequate per RESEARCH A1; ImageIO thumbnail API reserved for memory-pressured batches)"
  - "@AppStorage(imageCompressQuality) default 75 (Email preset) per MEMORY.md pitfall avoidance"
  - "DispatchGroup join then single compress() call — matches RESEARCH L391-413 verified snippet"
  - "Choose Images… NSOpenPanel included as optional secondary affordance (plan marked it optional)"
metrics:
  duration: "~20 min"
  completed: "2026-06-30"
  tasks_completed: 2
  files_created: 2
  files_modified: 2
---

# Phase 05 Plan 03: Image Compressor View + Definition + Registry Summary

**One-liner:** SwiftUI ImageCompressView with DispatchGroup multi-provider drop, @AppStorage quality slider (0–100, Web/Email/Max presets), lossless-gate (D-05), live per-row results table (thumbnail + ByteCountFormatter size delta + green/secondary % saved), and ImageCompressDefinition wired into ToolRegistry via a single sanctioned-append line — xcodebuild BUILD SUCCEEDED.

## Tasks Completed

| # | Name | Type | Commit | Status |
|---|------|------|--------|--------|
| 1 | ImageCompressView — multi-file drop + quality slider/presets + results table | feat | 1095633 | Done |
| 2 | ImageCompressDefinition + ToolRegistry registration + Xcode target membership + build | feat | 645d357 | Done |

## Commits

- `1095633` — `feat(05-03): ImageCompressView — multi-file drop + quality slider/presets + results table`
- `645d357` — `feat(05-03): ImageCompressDefinition + ToolRegistry registration + Xcode target membership`

## What Was Built

### Task 1: ImageCompressView (Tools/ImageCompress/ImageCompressView.swift)

`struct ImageCompressView: View` — 264 lines, mirrors HashView structure:

**Drop surface (D-01):**
- `.onDrop(of: [.fileURL], isTargeted: $isDragTargeted)` on root `ScrollView`
- Iterates ALL providers via `DispatchGroup` (not `providers.first` — the Hash single-file pattern)
- Each provider's `loadItem` is joined before calling `viewModel.compress(urls:quality:)` once
- `quality / 100.0` maps the 0–100 slider to ImageIO 0.0–1.0 at the call site (RESEARCH L369-378)
- `.overlay { if isDragTargeted { DropOverlayView(label: "Drop images to compress").transition(...) } }`

**Quality controls (D-04/D-05):**
- `@AppStorage("imageCompressQuality") private var quality: Double = 75` — persists across launches, avoids MEMORY.md computed-PreferencesStore pitfall
- `Slider(value: $quality, in: 0...100, step: 1)` with "Quality" label left, "{n}%" right
- Three preset `Button`s: Web(60), Email(75), Max(95) — active preset `.borderedProminent`, others `.bordered`
- `isEntirelyLossless` computed: `!rows.isEmpty && rows.allSatisfy { $0.format.isLossless }`
- When entirely lossless: slider `.disabled(true)` + helper line "PNG and TIFF are lossless — they're re-encoded, but quality doesn't apply." (exact UI-SPEC copy)
- Accessibility: slider `.accessibilityLabel("Compression quality")`, preset buttons `.accessibilityLabel("{name} quality preset")` + `.accessibilityAddTraits(.isSelected)` for active

**Results table (D-09):**
- Empty state: `"Drop images here to compress them."` — 13pt .secondary centered
- Results container: `.padding(10)` + `.background(.quaternary.opacity(0.3))` + `.cornerRadius(8)` — matches HashView fileHashSection idiom
- Rows separated by `Divider()`, each row `frame(minHeight: 56)`
- Per-row `HStack`: thumbnail (40×40 `NSImage(contentsOf:)`, `cornerRadius(4)`, fill-clipped; `.quaternary` placeholder) + name+formatTag `VStack` + Spacer + trailing state content
- `.accessibilityElement(children: .combine)` with constructed row label per UI-SPEC
- State-driven trailing:
  - `.pending` → dim `"—"` in `.secondary`
  - `.compressing` → `ProgressView().scaleEffect(0.6)` with a11y label "Compressing {filename}…"
  - `.done(img)` → `"{orig} → {new}"` via `ByteCountFormatter(.file)` in 13pt monospaced `.secondary` + `"−{n}%"` in 11pt semibold `Color.green` (saved) / `"+{n}%"/"0%"` in `Color.secondary` (grew)
  - `.failed(reason)` → `WarningBannerView(message: reason, severity: .warning)`
- Cancel button: `.foregroundStyle(.red)` shown when `isCompressing`, calls `viewModel.cancel()`

**No side-by-side comparison pane (D-10 — absent by design).**
**Semantic colors only (INFRA-14 — no hardcoded hex).**
**Choose Images… NSOpenPanel with `allowsMultipleSelection = true`, `allowedContentTypes = [.png, .jpeg, .heic, .tiff]`.**

### Task 2: ImageCompressDefinition (Tools/ImageCompress/ImageCompressDefinition.swift)

`enum ImageCompressDefinition` — mirrors HashDefinition.swift wholesale:

- `static func make() -> ToolDefinition` returns:
  - `id: "image-compress"`, `name: "Image Compressor"`, `category: .conversion`
  - `keywords: ["image","compress","jpeg","png","heic","tiff","optimize","shrink","photo"]`
  - `sfSymbol: "photo"`, `detectionPredicate: nil` (MANDATORY — T-05-09, INFRA-06)
  - `makeView: { @MainActor in AnyView(ImageCompressViewWrapper()) }`
- Private `struct ImageCompressViewWrapper`: injects `@Environment(HistoryStore.self)`, passes `historyStore.save` into `ImageCompressView(onSaveHistory:)`

### Task 2: ToolRegistry sanctioned append (Core/Services/ToolRegistry.swift)

Single new line appended after `TextDiffDefinition.make()`:
```swift
ImageCompressDefinition.make(),
```
Plus a Phase-5 sanctioned-append comment block. `search()` and `detect()` are NOT touched. `detect()` skips this tool via the nil predicate optional chain.

### Task 2: Xcode target membership (Flint.xcodeproj/project.pbxproj)

4 new entries mirroring the Transformer/ViewModel precedent:
- `001100000007005` / `001200000007005` — `ImageCompressView.swift` in Flint app Sources
- `001100000007006` / `001200000007006` — `ImageCompressDefinition.swift` in Flint app Sources
- Both file references added to the `001500000007001 ImageCompress` group
- Both build files added to the Flint app target Sources build phase

**`xcodebuild build -scheme Flint`: BUILD SUCCEEDED** — all four ImageCompress files compile and link (A5 gate closed).

## Verification

| Check | Result |
|-------|--------|
| `DropOverlayView(label: "Drop images to compress")` present | CONFIRMED |
| `viewModel.compress(urls:` present | CONFIRMED |
| `imageCompressQuality` @AppStorage key present | CONFIRMED |
| `WarningBannerView` present | CONFIRMED |
| `quality / 100` mapping at call site | CONFIRMED |
| `providers.first` NOT in code (only in multi-file note comment) | CONFIRMED |
| `detectionPredicate: nil` in Definition | CONFIRMED |
| `HistoryStore.self` in Definition wrapper | CONFIRMED |
| `ImageCompressDefinition.make()` in ToolRegistry | CONFIRMED |
| `xcodebuild build -scheme Flint` | BUILD SUCCEEDED |

## Deviations from Plan

None — plan executed exactly as written.

The plan marked "Choose Images… NSOpenPanel" as optional this phase; it was included for completeness (secondary affordance, does not affect any acceptance criteria).

## Known Stubs

None. All results table columns are wired to live ViewModel data:
- Row count → `viewModel.rows.count` (real batch entries)
- Thumbnail → `NSImage(contentsOf: row.sourceURL)` (real image load)
- Size delta → `ByteCountFormatter` on `img.originalBytes` / `img.compressedBytes` (real byte counts)
- % saved → `img.percentSaved` (computed from real byte counts in Transformer)
- Format tag → `row.format.displayTag` (derived from URL extension pre-compression)
- State → `row.state` (live enum transitions from ViewModel batch loop)

## Threat Surface Scan

No new network endpoints, auth paths, or schema changes introduced.

All three threats from the plan's `<threat_model>` are mitigated:

- **T-05-07** (DoS via dropped non-image / corrupt file): All dropped URLs route to `viewModel.compress(urls:quality:)` without type-checking at the drop site. The Transformer's guard-gated ImageIO calls produce `CompressRow.state = .failed(reason:)`, rendered as `WarningBannerView(.warning)` — no crash path. Confirmed by 05-01 tests.
- **T-05-08** (Tampering — edit to FROZEN ToolRegistry.swift): Only one new line `ImageCompressDefinition.make(),` was appended; `search()`/`detect()` and the tools array structure are untouched. The Phase-5 sanctioned-append comment documents the mutation scope.
- **T-05-09** (Spoofing — image tool participates in clipboard detection): `detectionPredicate: nil` (MANDATORY) — the tool is invisible to `ToolRegistry.detect()` via optional chaining. Confirmed by grep check.
- **T-05-SC** (npm/pip/cargo installs): zero new external packages — D-03 constraint honored.

## Self-Check: PASSED

| Item | Status |
|------|--------|
| Tools/ImageCompress/ImageCompressView.swift | FOUND |
| Tools/ImageCompress/ImageCompressDefinition.swift | FOUND |
| Core/Services/ToolRegistry.swift (contains ImageCompressDefinition.make()) | FOUND |
| Flint.xcodeproj/project.pbxproj (contains 001100000007005, 001100000007006) | FOUND |
| Commit 1095633 (feat: ImageCompressView) | FOUND |
| Commit 645d357 (feat: Definition + Registry + pbxproj) | FOUND |
| xcodebuild build -scheme Flint | BUILD SUCCEEDED |
| All automated verify checks | PASSED |
