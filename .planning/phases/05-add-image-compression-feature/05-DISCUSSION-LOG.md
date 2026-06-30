# Phase 5: add-image-compression-feature - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-30
**Phase:** 05-add-image-compression-feature
**Areas discussed:** Input & formats, Compression controls, Output destination, Preview & feedback

---

## Input & Formats — scope

| Option | Description | Selected |
|--------|-------------|----------|
| Batch, common formats | Drop one/many; PNG/JPEG/HEIC/TIFF via native ImageIO | |
| Single file, common formats | One at a time, simpler UI | |
| Batch + WebP | Batch plus WebP encode/decode (needs libwebp) | ✓ (later reversed) |

**User's choice:** Initially Batch + WebP, then **reversed**: "this feature should only cover the compress no need to include the convert scope … webp is not necessary since i plan to use that for converting the file."

**Final:** Batch input; formats limited to native ImageIO (PNG/JPEG/HEIC/TIFF); WebP dropped; no format conversion.
**Notes:** WebP was only justified for conversion. Dropping it also avoids the libwebp C dependency.

---

## Output Format direction (rolled into Input)

| Option | Description | Selected |
|--------|-------------|----------|
| Same format only + WebP both ways | Re-compress in-format, WebP in/out (libwebp) | |
| Cross-format convert to anything | Full convert matrix | |
| Native-encode formats only | PNG/JPEG/HEIC/TIFF out, no WebP-out | (superseded) |

**User's choice:** Mid-question, user cut conversion entirely. Compress-only, same format in = same format out.

---

## Compression Controls

| Option | Description | Selected |
|--------|-------------|----------|
| Quality slider | Single 0–100% slider | |
| Presets (Web/Email/Max) | Named buttons | |
| Slider + presets | Presets set an adjustable slider | ✓ |
| Target file size | Binary-search quality to hit a size | |

**User's choice:** Slider + presets.
**Notes:** Quality applies to JPEG/HEIC (lossy); PNG is lossless and just re-encodes.

### Resize sub-decision

| Option | Description | Selected |
|--------|-------------|----------|
| Quality only, no resize | Keep original dimensions | ✓ |
| Optional max-dimension | One optional max width/height field | |
| Full resize controls | Width/height/%/lock-aspect | |

**User's choice:** Quality only, no resize.

---

## Output Destination

| Option | Description | Selected |
|--------|-------------|----------|
| Beside original w/ suffix | `name-compressed.ext`, no dialogs, never overwrites | ✓ |
| Choose output folder | One folder picker for the batch | |
| Save-As per file | A Save dialog per image | |
| Overwrite originals | Replace in place (destructive) | |

**User's choice:** Beside original with `-compressed` suffix.
**Notes:** First Flint tool to write to the filesystem; never overwrites the source.

---

## Preview & Feedback

| Option | Description | Selected |
|--------|-------------|----------|
| Results table w/ savings | Row per image: thumbnail, old→new size, % saved | ✓ |
| Table + visual before/after | Adds side-by-side image preview on select | |
| Minimal summary | One-line total only | |

**User's choice:** Results table with savings (thumbnail, original → new size, % saved, live progress).

---

## Claude's Discretion

- Exact preset names/values (Web/Email/Max suggested).
- Thumbnail size, table layout, progress style.
- Single-file simplified view vs always-table.
- Off-main encode strategy (mirror Hash's Task + progress pipeline).

## Deferred Ideas

- Format conversion (PNG→JPEG, →WebP) — separate convert feature the user plans; WebP rides with it.
- Image resizing/downscaling — out of "compress" scope.
- Target-file-size mode.
- Side-by-side visual before/after preview.
- Choose-output-folder / Save-As / overwrite output modes.
