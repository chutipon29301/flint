# Phase 5: add-image-compression-feature - Context

**Gathered:** 2026-06-30
**Status:** Ready for planning

<domain>
## Phase Boundary

Add a new **Image Compressor** tool to Flint: a developer drops one or more image
files and gets smaller versions back. Compress-only — re-encode each image at a
chosen quality to reduce file size. Same format in = same format out. No format
conversion, no resizing.

</domain>

<decisions>
## Implementation Decisions

### Input & Formats
- **D-01:** Batch input — accept one OR many images dropped at once (reuse the
  file-drop pipeline pattern from Hash: `.onDrop(of: [.fileURL])`).
- **D-02:** Formats = whatever ImageIO encodes natively: **PNG, JPEG, HEIC, TIFF**.
  Same format in = same format out (compress-only, no conversion).
- **D-03:** **WebP dropped.** Was only justified for format conversion, which is now
  out of scope. Avoids bundling libwebp (C dependency) — keeps the tool zero-new-dep.

### Compression Controls
- **D-04:** **Quality slider + presets.** A 0–100% quality slider, plus preset buttons
  (e.g. Web / Email / Max) that set the slider; slider stays adjustable after a preset.
- **D-05:** Quality maps to ImageIO `kCGImageDestinationLossyCompressionQuality`
  for JPEG/HEIC. PNG is lossless — quality slider doesn't apply; PNG just re-encodes
  (best-effort optimization). Make this distinction visible in the UI (don't imply
  the slider shrinks PNG by quality).
- **D-06:** **Quality only — no resize.** Original pixel dimensions are preserved.
  Resizing/downscaling is explicitly out of scope (candidate for a future phase).

### Output Destination
- **D-07:** Write each compressed file **beside the original** with a `-compressed`
  suffix (e.g. `photo.jpg` → `photo-compressed.jpg`). No save dialogs for the batch.
- **D-08:** **Never overwrite the original.** If a `-compressed` file already exists,
  disambiguate (e.g. numeric suffix) rather than clobbering — aligns with the
  "never lose data" product stance. (App is non-sandboxed, so writing beside the
  source is permitted; no security-scoped bookmark needed for v1.)

### Preview & Feedback
- **D-09:** **Results table with savings** — one row per image: thumbnail,
  original size → new size, % saved. Live per-row progress as each finishes.
- **D-10:** No side-by-side visual before/after comparison in this phase (richer
  image-viewer pane deferred). Table + savings is the feedback surface.

### Claude's Discretion
- Exact preset names and their quality values (Web/Email/Max are suggestions).
- Thumbnail size, table layout/column order, progress-indicator style.
- Whether a single dropped file shows the same table (1 row) or a simpler view —
  planner/UI may simplify, but the table is the baseline.
- Off-main-thread encoding strategy (mirror Hash's `Task` + progress-callback
  pipeline) — implementation detail for the planner.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Tool architecture (the contract every tool follows)
- `Core/Models/ToolDefinition.swift` — FROZEN tool abstraction. New tool must
  conform: `id`, `name`, `category`, `keywords`, `sfSymbol`, `detectionPredicate`,
  `makeView`. NOTE: `detectionPredicate` is `(String) -> DetectionResult?` — it is
  TEXT-only, so the image tool has **no clipboard detection** (set `nil`), like Hash.
- `Core/.../ToolRegistry.swift` — where new `*Definition.make()` is registered.
- `Tools/Hash/HashDefinition.swift` — closest analog Definition (search-only,
  `detectionPredicate: nil`, history-store wrapper pattern).

### File-input pipeline (reuse this)
- `Tools/Hash/HashView.swift` (§ DIST-02 `.onDrop`) — accepts ANY dropped file via
  `provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier)`. Direct analog
  for the image-drop surface.
- `Tools/Hash/HashViewModel.swift` (§ File hashing) — off-main `Task` + per-file
  progress callback + cancellation. Mirror this for off-main image encode.
- `UI/Components/DropOverlayView.swift` — stateless drag-over overlay; pass a
  contextual label ("Drop images to compress").
- `UI/Components/WarningBannerView.swift` — post-drop rejection feedback (e.g. a
  dropped non-image file).

### Product guardrails
- `CLAUDE.md` (root) — tech stack constraints: SwiftUI + MVVM, macOS 14+, offline,
  no new dependency unless native APIs can't do it (ImageIO/CoreGraphics suffice here).
- `.planning/PROJECT.md` — core value (never crash on bad input, fully offline) and
  footprint targets (<20MB bundle). No libwebp / no new dep keeps this intact.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **Hash file pipeline** (`HashView` + `HashViewModel`): drop → off-main `Task` →
  per-file progress → result. The image compressor is structurally the same shape
  (binary-in, process off-main, report progress) — strongest reuse target.
- **`DropOverlayView`** / **`WarningBannerView`**: drag-over UI + post-drop error
  feedback, ready to reuse with new labels.
- **HistoryStore** injection via `@Environment(HistoryStore.self)` + a
  `*ViewWrapper` (see `HashDefinition`): consistent way to record a transformation.

### Established Patterns
- Every tool = `Definition` + `Transformer` + `ViewModel` + `View`. New tool MUST
  follow this 4-file layout under `Tools/ImageCompress/` (or similar).
- `Transformer` is the pure, testable core (no UI). Image encode logic (ImageIO
  CGImageDestination + quality) belongs here so it can be unit-tested on bad input.
- Tools never crash on malformed input — a non-image / corrupt file must surface a
  warning, not throw.

### Integration Points
- Register `ImageCompressDefinition.make()` in `ToolRegistry` (the registry comment
  notes it's been edited per-tool before — confirm current freeze status at plan time).
- This is the FIRST tool that writes to the filesystem (all others → clipboard +
  history only). The write-beside-original path (D-07/D-08) is net-new surface area —
  flag for the planner; no prior pattern to copy for file output.

</code_context>

<specifics>
## Specific Ideas

- Output naming: `<name>-compressed.<ext>`, never overwriting the source.
- Feedback framing: "original → new size, % saved" per row — the savings number is
  the hero metric of this tool.

</specifics>

<deferred>
## Deferred Ideas

- **Format conversion** (e.g. PNG→JPEG, anything→WebP) — explicitly cut from this
  phase; the user plans a separate convert feature. WebP support rides along with that.
- **Image resizing / downscaling** — biggest file-size lever but out of "compress"
  scope; candidate for its own phase or a later addition to this tool.
- **Target-file-size mode** (binary-search quality to hit e.g. 500 KB) — considered,
  deferred in favor of the simpler slider+presets.
- **Side-by-side visual before/after preview** (quality-loss eyeballing) — deferred;
  results table is the v1 feedback surface.
- **Choose-output-folder / Save-As / overwrite modes** — considered for output
  destination; "beside original with suffix" chosen for v1, others deferred.

</deferred>

---

*Phase: 5-add-image-compression-feature*
*Context gathered: 2026-06-30*
