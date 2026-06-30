# Phase 5: add-image-compression-feature - Pattern Map

**Mapped:** 2026-06-30
**Files analyzed:** 5 (4 new + 1 modify)
**Analogs found:** 4 strong (exact role+flow) / 5 — 1 file (the disk-write path) has NO in-codebase analog (flagged)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `Tools/ImageCompress/ImageCompressDefinition.swift` | definition (tool registration + env wrapper) | request-response (search-only, no detection) | `Tools/Hash/HashDefinition.swift` | exact |
| `Tools/ImageCompress/ImageCompressTransformer.swift` | transformer (pure, testable core) | transform + **file-I/O (write)** | `Tools/Hash/HashTransformer.swift` (structure) + `Tools/Base64/Base64ViewModel.swift` L278-300 (write) | role-match; **write path = no exact analog** |
| `Tools/ImageCompress/ImageCompressViewModel.swift` | viewmodel (`@Observable @MainActor`) | batch / event-driven (off-main Task + per-row progress + cancel) | `Tools/Hash/HashViewModel.swift` (`startFileHash` L105-136) | exact |
| `Tools/ImageCompress/ImageCompressView.swift` | view (SwiftUI) | request-response + drag-drop | `Tools/Hash/HashView.swift` | exact (drop + overlay); **results table = no analog** |
| `Core/Services/ToolRegistry.swift` | config (registration array) | n/a | self (sanctioned-append precedent, L23-36) | exact — but see freeze note below |

## Pattern Assignments

### `Tools/ImageCompress/ImageCompressDefinition.swift` (definition, search-only)

**Analog:** `Tools/Hash/HashDefinition.swift` (entire file — 35 lines, copy wholesale and rename).

**Full pattern to copy** (`HashDefinition.swift` lines 8-34):
```swift
enum HashDefinition {
    static func make() -> ToolDefinition {
        ToolDefinition(
            id: "hash-generator",
            name: "Hash Generator",
            category: .analysis,
            keywords: ["hash", "md5", ...],
            sfSymbol: "number.square",
            detectionPredicate: nil,  // search-only — no clipboard detection
            makeView: { @MainActor in AnyView(HashViewWrapper()) }
        )
    }
}

// MARK: - Wrapper for environment-injected history store
private struct HashViewWrapper: View {
    @Environment(HistoryStore.self) private var historyStore
    var body: some View {
        HashView { entry in historyStore.save(entry) }
    }
}
```

**Concrete substitutions for ImageCompress:**
- `id: "image-compress"` (or similar slug), `name: "Image Compressor"`.
- `category:` — pick an existing `ToolCategory` case (Hash uses `.analysis`; confirm the right case at plan time by reading `ToolCategory`).
- `keywords:` e.g. `["image", "compress", "jpeg", "png", "heic", "tiff", "optimize", "shrink", "photo"]`.
- `sfSymbol:` e.g. `"photo"` or `"arrow.down.right.and.arrow.up.left"`.
- `detectionPredicate: nil` — **MANDATORY**. `ToolDefinition.detectionPredicate` is `(@Sendable (String) -> DetectionResult?)?` — it is TEXT-only (see `ToolDefinition.swift` L16). An image tool has no text to detect, so `nil` exactly like Hash (D-13/CONTEXT canonical_refs).
- `ImageCompressViewWrapper` injecting `@Environment(HistoryStore.self)` and passing the `historyStore.save` closure into `ImageCompressView(onSaveHistory:)`.

**Why this exact analog:** Hash is the ONLY search-only file-input tool with `detectionPredicate: nil` + a HistoryStore wrapper. Identical shape.

---

### `Tools/ImageCompress/ImageCompressTransformer.swift` (transformer, transform + file-I/O write)

**Analog (structure):** `Tools/Hash/HashTransformer.swift` — `enum` namespace, `static` functions, pure (no SwiftUI/AppKit), result struct nested inside, INFRA-17 never-crash via optional gating.

**Imports pattern to copy** (`HashTransformer.swift` lines 6-9 — replace crypto imports with ImageIO):
```swift
import Foundation
// NEW for this tool (not in Hash): ImageIO, CoreGraphics, UniformTypeIdentifiers
```
The Transformer MUST NOT import SwiftUI or AppKit — same constraint as `HashTransformer` (header comment L2: "NO SwiftUI/AppKit imports"). Thumbnail rendering (which needs AppKit/NSImage) belongs in the View/ViewModel, NOT here.

**Result-struct-nested-in-enum pattern** (`HashTransformer.swift` lines 11-22):
```swift
enum HashTransformer {
    struct HashResult { var md5: String = ""; ... }
    static func hashText(_ input: String) -> HashResult { ... }
}
```
Mirror as `enum ImageCompressTransformer { struct CompressedImage {...}; enum CompressError {...}; static func compress(url:quality:) -> Result<CompressedImage, CompressError> }`. The full `compress` and `disambiguatedCompressedURL` bodies are spec'd in RESEARCH.md Pattern 1 & 2 — copy from there.

**File-size read pattern** (`HashTransformer.swift` line 79 — reuse the no-decode size read):
```swift
let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 1
```
RESEARCH prefers the `resourceValues(forKeys: [.fileSizeKey])` variant for the before/after byte counts; either is the established "never `Data(contentsOf:)`" pattern (HashTransformer header pitfall #9). Pick one and stay consistent.

**INFRA-17 never-crash pattern** (HashTransformer L74 `guard let handle = try? ...` → returns empty result, no throw): mirror with `guard let src = CGImageSourceCreateWithURL(...) else { return .failure(.notAnImage) }`. Every ImageIO call is optional/Bool-gated; NO force-unwrap. This is the same contract HashTransformer honors for unreadable files.

---

### `Tools/ImageCompress/ImageCompressViewModel.swift` (viewmodel, batch + cancellation)

**Analog:** `Tools/Hash/HashViewModel.swift` — specifically `startFileHash(url:)` (lines 105-136) and `cancelFileHash()` (lines 138-142). This is the EXACT off-main + progress + cancel template.

**Class declaration + history injection pattern** (`HashViewModel.swift` lines 10-51):
```swift
@Observable
@MainActor
final class HashViewModel: ToolShortcutActions {
    var fileHashProgress: Double = 0.0
    var isHashing: Bool = false
    var fileHashTask: Task<Void, Never>? = nil
    var errorMessage: String? = nil

    private let onSaveHistory: (HistoryEntry) -> Void
    init(onSaveHistory: @escaping (HistoryEntry) -> Void) {
        self.onSaveHistory = onSaveHistory
    }
}
```
Mirror: `@Observable @MainActor final class ImageCompressViewModel: ToolShortcutActions`, holding `var rows: [CompressRow]`, `var isCompressing`, `private var task: Task<Void, Never>?`, and the same `onSaveHistory` closure injected via `init`.

**Off-main Task + progress callback + cancellation pattern** (`HashViewModel.swift` lines 105-136 — the core template):
```swift
func startFileHash(url: URL) {
    fileHashTask?.cancel()          // cancel any in-flight work first
    fileURL = url
    fileHashResult = nil
    fileHashProgress = 0.0
    isHashing = true
    errorMessage = nil

    let capturedOnSave = onSaveHistory   // capture closure, not self
    fileHashTask = Task {
        let result = await HashTransformer.hashFile(url: url) { [weak self] progress in
            Task { @MainActor [weak self] in self?.fileHashProgress = progress }
        }
        await MainActor.run { [weak self] in
            guard let self else { return }
            self.fileHashResult = result
            self.isHashing = false
            capturedOnSave(HistoryEntry(tool: "hash", input: url.lastPathComponent,
                                        output: outputLines, timestamp: Date(), pinned: false))
        }
    }
}

func cancelFileHash() {
    fileHashTask?.cancel(); fileHashTask = nil; isHashing = false
}
```
**Adapt for batch (D-01):** loop over `urls`, set each row `.pending`, check `if Task.isCancelled { break }` per iteration, wrap each compress in `autoreleasepool { ImageCompressTransformer.compress(...) }` (RESEARCH Pitfall 4 / Pattern 3), and `await MainActor.run { self.rows[i].apply(result) }` for live per-row updates (D-09). RESEARCH Pattern 3 (lines 261-291) has the full batch adaptation — copy from there.

**`ToolShortcutActions` conformance** (`HashViewModel.swift` lines 149-159) — REQUIRED because `.toolShortcuts(viewModel)` in the View needs it (see `ToolShortcutActions.swift` L25-32):
```swift
func primaryOutput() -> String? { ... }   // e.g. a summary of saved bytes, or nil
func clearInput() { ... }                 // e.g. clear rows
```
Both are `@MainActor`. Empty/nil returns are harmless no-ops (T-09-02).

**HistoryEntry write** — use the existing `HistoryEntry` shape (`Core/Models/HistoryEntry.swift` L21-33): `HistoryEntry(tool: "image-compress", input: <source filename(s)>, output: <savings summary>, timestamp: Date(), pinned: false)`. NO new column. No secrets involved (unlike Hash's HMAC), so no special redaction.

---

### `Tools/ImageCompress/ImageCompressView.swift` (view, drag-drop + table)

**Analog:** `Tools/Hash/HashView.swift` for the drop surface, overlay, and ViewModel wiring. The results table has NO analog (flagged below).

**Imports + View-owned ViewModel + init pattern** (`HashView.swift` lines 5-28):
```swift
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct HashView: View {
    @State private var viewModel: HashViewModel
    @State private var isDragTargeted = false
    init(onSaveHistory: @escaping (HistoryEntry) -> Void) {
        _viewModel = State(initialValue: HashViewModel(onSaveHistory: onSaveHistory))
    }
}
```
Mirror exactly: `ImageCompressView` owns `@State private var viewModel: ImageCompressViewModel`, an `isDragTargeted` flag, and an `init(onSaveHistory:)` constructing the VM.

**`.onDrop` + `DropOverlayView` overlay pattern** (`HashView.swift` lines 45-61):
```swift
.onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
    guard let provider = providers.first else { return false }   // ← Hash takes FIRST only
    _ = provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
        guard let data = item as? Data,
              let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
        Task { @MainActor in viewModel.startFileHash(url: url) }
    }
    return true
}
.overlay {
    if isDragTargeted {
        DropOverlayView(label: "Drop to load file")
            .transition(.opacity.animation(.easeOut(duration: 0.15)))
    }
}
```
**Adapt for batch (D-01):** Hash reads only `providers.first`. Image Compressor must iterate ALL providers and join their async loads (DispatchGroup) before calling `viewModel.compress(urls:quality:)`. RESEARCH Code Examples (lines 391-413) has the verified multi-provider snippet. Use `DropOverlayView(label: "Drop images to compress")` (canonical_refs).

**`.toolShortcuts(viewModel)` modifier** (`HashView.swift` line 42) — attach it; requires the `ToolShortcutActions` conformance above.

**Quality slider + presets (D-04/D-05):** No direct analog. Use SwiftUI `Slider` (0–100) + preset `Button`s that set the slider value. Per MEMORY.md `@Observable`-computed-UserDefaults pitfall: if quality persists across launches, bind the control to `@AppStorage` with a stable key — do NOT bind to a computed `PreferencesStore` property (writes drop). Disable/grey the slider for PNG/TIFF rows with a "lossless — quality N/A" label (D-05, RESEARCH Pitfall 2).

**`WarningBannerView` for per-row failures** (`UI/Components/WarningBannerView.swift` L13-50) — render `.failed(reason)` rows as `WarningBannerView(message:..., severity: .warning)` rather than throwing (INFRA-17). `.warning` for "not an image / grew slightly"; `.error` only for hard write failures.

**File picker fallback (optional)** — Hash's `selectAndHashFile()` (`HashView.swift` L257-268) uses `NSOpenPanel`; set `allowsMultipleSelection = true` if you offer a "Choose Images…" button alongside drag-drop.

---

### `Core/Services/ToolRegistry.swift` (MODIFY — registration)

**Pattern:** Append `ImageCompressDefinition.make()` to the `tools` array (`ToolRegistry.swift` lines 15-36).

**FREEZE STATUS — read carefully:** The file header (L2-3) and the in-array FREEZE MARKER (L14, L23) say Wave-2 tool plans do NOT edit this file. However, the Phase-2 work established a "SANCTIONED APPEND" precedent (L23-36) where five Definition lines were the explicitly-approved mutation. Registering a new tool genuinely requires one line here — there is no alternative registration path. **Planner action:** treat this as a sanctioned single-line append (the same kind already present), add `ImageCompressDefinition.make()` to the array, and extend the sanctioned-append comment to cover it. Confirm no newer freeze directive supersedes this at plan time (CONTEXT integration-points note).

```swift
tools = [
    JSONFormatterDefinition.make(),
    ...
    TextDiffDefinition.make(),
    ImageCompressDefinition.make(),   // ← Phase-5 sanctioned append
]
```
No change to `search()` (keyword search works automatically) and no change to `detect()` (predicate is `nil`, so it's skipped by the existing `tool.detectionPredicate?(string)` optional chain at L53).

---

## Shared Patterns

### Tool 4-file layout (FROZEN contract)
**Source:** `Tools/Hash/` (Definition + Transformer + ViewModel + View) + `Core/Models/ToolDefinition.swift`
**Apply to:** All 4 new files. Conform `ImageCompressDefinition.make()` to `ToolDefinition` (id, name, category, keywords, sfSymbol, detectionPredicate, makeView). The struct is FROZEN (`ToolDefinition.swift` L3) — do not change its shape.

### HistoryStore injection via environment wrapper
**Source:** `Tools/Hash/HashDefinition.swift` lines 26-34
**Apply to:** Definition + ViewModel. A private `*ViewWrapper` reads `@Environment(HistoryStore.self)` and passes `historyStore.save` as the `onSaveHistory: (HistoryEntry) -> Void` closure into the View's `init`. ViewModel captures the closure (`let capturedOnSave = onSaveHistory`) before the off-main Task.

### Off-main work + per-item progress + cancellation
**Source:** `Tools/Hash/HashViewModel.swift` lines 105-142 (`startFileHash` / `cancelFileHash`)
**Apply to:** ViewModel batch entry point. `task?.cancel()` first; `Task` (or `Task.detached`) for work; `await MainActor.run` to publish; `Task.isCancelled` checked per loop iteration; `autoreleasepool` per image (net-new vs Hash — added for the multi-image batch, RESEARCH Pitfall 4).

### INFRA-17 never-crash on bad input
**Source:** `Tools/Hash/HashTransformer.swift` line 74 (`guard let ... = try? ...`) + RESEARCH Anti-Patterns
**Apply to:** Transformer. Every `CGImageSource*` / `CGImageDestination*` call optional/Bool-gated; corrupt/non-image input returns a typed `.failure`, never throws across the UI boundary. No force-unwrap near any ImageIO call.

### Drag-drop surface + overlay + post-drop warning
**Source:** `Tools/Hash/HashView.swift` L45-61 + `UI/Components/DropOverlayView.swift` + `UI/Components/WarningBannerView.swift`
**Apply to:** View. `.onDrop(of: [.fileURL], isTargeted:)` → `DropOverlayView` while dragging → `WarningBannerView` for rejected/failed items after drop. (Drag-time rejection styling is intentionally absent — see DropOverlayView header.)

### No-decode file-size read
**Source:** `Tools/Hash/HashTransformer.swift` line 79 (`attributesOfItem(atPath:)[.size]`)
**Apply to:** Transformer before/after byte counts. Never `Data(contentsOf:)` to size a file.

### `ToolShortcutActions` conformance for ⌘-shortcuts
**Source:** `UI/Components/ToolShortcutActions.swift` L25-32 + `HashViewModel.swift` L149-159
**Apply to:** ViewModel must implement `primaryOutput() -> String?` and `clearInput()`; View attaches `.toolShortcuts(viewModel)`.

## No Analog Found (planner: use RESEARCH.md patterns instead)

| Surface | Role | Data Flow | Reason / Closest-but-not-exact |
|---------|------|-----------|--------------------------------|
| **Write-beside-original with `-compressed` suffix + collision disambiguation** (D-07/D-08) | transformer | file-I/O write | **No precedent.** Every other tool writes to clipboard/history only. Base64 (`Base64ViewModel.swift` L269-300) and Markdown (`MarkdownView.swift` L238-296) DO write files — but BOTH go through `NSSavePanel` (user picks the path). There is NO "beside-original, no dialog, auto-disambiguate" write anywhere. Closest reusable fragment is the atomic-write call itself: `try data.write(to: url, options: .atomic)` (`Base64ViewModel.swift` L283) — but ImageIO's `CGImageDestinationFinalize` writes the destination URL directly, so even that differs. Use RESEARCH Pattern 1 (encode) + Pattern 2 (`disambiguatedCompressedURL`) as the source of truth. TOCTOU caveat noted in RESEARCH A3. |
| **ImageIO round-trip re-encode** (`CGImageSourceCreateWithURL` → `CGImageSourceGetType` → `CGImageDestinationAddImageFromSource` → `Finalize`) | transformer | transform | **No precedent.** Grep of `Tools/`/`Core/` found zero ImageIO/CGImage usage (greenfield, RESEARCH Runtime State). Use RESEARCH Pattern 1 (lines 164-225). The HashTransformer gives the *shape* (pure enum, typed result, guard-gated) but not the ImageIO calls. |
| **Results table: thumbnail + original→new size + % saved + per-row progress** (D-09) | view | request-response | No tabular results view exists. `LazyVGrid`/`Grid` appear in `UI/AllToolsGridView.swift`, `Tools/Regex/RegexView.swift`, `Tools/Markdown/MarkdownView.swift` — but those are content grids, not a per-file results/progress table. No thumbnail-rendering view exists either (thumbnails are net-new — render via `NSImage(contentsOf:)` or ImageIO thumbnail API in the View/ViewModel, RESEARCH A1). Planner designs this fresh; reuse `WarningBannerView` only for the failed-row cells. |
| **Multi-file drop (iterate all providers)** (D-01) | view | batch drag-drop | Partial. `HashView` L45-49 reads `providers.first` only (single file). The all-providers + DispatchGroup join is net-new — use RESEARCH Code Examples L391-413 (verified snippet). |
| **Quality slider + presets, lossy/lossless gating** (D-04/D-05) | view | request-response | No analog control. Build with SwiftUI `Slider` + preset `Button`s; persist via `@AppStorage` if needed (MEMORY.md pitfall). |

## Metadata

**Analog search scope:** `Tools/` (Hash, Base64, Markdown, Regex), `Core/Models/` (ToolDefinition, HistoryEntry), `Core/Services/` (ToolRegistry), `UI/Components/` (DropOverlayView, WarningBannerView, ToolShortcutActions)
**Files scanned:** 11 read in full/targeted + grep sweeps for ImageIO usage (none), table/grid patterns, file-write prior art
**Pattern extraction date:** 2026-06-30
