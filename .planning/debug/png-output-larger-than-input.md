---
status: diagnosed
trigger: "transparency works, but the output is BIGGER — Google-Logo-2015.png went 30 KB → 46 KB (+55%)"
created: 2026-07-01T00:00:00Z
updated: 2026-07-01T00:00:00Z
---

## Current Focus

hypothesis: writePNGCompressed's never-larger guard compares quantized output against the source file size correctly at line 154, BUT when quantized loses it compares against a TRUECOLOR re-encode (not the original source bytes) — so the original is never a candidate and a bigger-than-original file can still be written. Also the non-PNG ImageIO path has no never-larger guard at all.
test: Read full transformer + quantizer + encoder + UAT + summary; trace the min() candidates
expecting: original source bytes absent from the final write decision
next_action: read PNGColorQuantizer, IndexedPNGEncoder, UAT test 5, summary D-06

## Symptoms

expected: Compressing an already-optimized PNG either shrinks it or leaves it unchanged — never larger.
actual: Google-Logo-2015.png went 30 KB → 46 KB (+55%). Transparency preserved.
errors: None (no crash).
reproduction: UAT Test 5. Drop a small, already-optimized PNG (Google 2015 logo, ~30 KB, low color count, transparency).
started: Phase 05 UAT.

## Eliminated

## Evidence

- timestamp: 2026-07-01
  checked: ImageCompressTransformer.writePNGCompressed lines 132-174
  found: candidates considered are {quantized indexedData, truecolor re-encode}. The ORIGINAL source bytes are read at line 153 (origBytes) but only used as a THRESHOLD comparison at line 154 (`if indexedData.count < origBytes` write quantized). When quantized is NOT smaller than original, code re-encodes truecolor (lines 161-171) and keeps min(quantized, truecolor) — neither of which is the original. The original file is never copied as a candidate output.
  implication: For an already-optimized PNG where origBytes(30KB) < quantized(46KB), line 154 is false. Truecolor re-encode of an optimized 30KB logo is typically >46KB (no palette, filter-0 only), so line 167 is false too. Fall-through at line 173 writes quantized (46KB). Output bigger than input.

- timestamp: 2026-07-01
  checked: IndexedPNGEncoder.encode + zlibDeflate (lines 79-191) — WHY quantized is 46KB > 30KB original
  found: encoder uses filter type 0x00 (None) on every scanline (line 83) and COMPRESSION_ZLIB with nil/default options (line 161-166). A well-optimized source PNG (pngquant/zopfli/optipng) uses adaptive per-row filters (Sub/Up/Avg/Paeth) and max-effort deflate. So this encoder's indexed-but-weakly-filtered+fast-deflate output can exceed an already-optimized truecolor-or-indexed source. The 256-color median-cut output (line 34 cap=256) for a low-color logo also wastes a near-full PLTE.
  implication: The quantized path is NOT guaranteed to beat an already-optimized source; the guard is the only protection, and it does not include the original as a candidate.

- timestamp: 2026-07-01
  checked: non-PNG ImageIO re-encode path lines 82-105
  found: NO never-larger guard at all. CGImageDestinationAddImageFromSource + Finalize writes unconditionally; size delta (lines 107-115) is reported AFTER the write, never used to gate it. A re-saved JPEG/HEIC/TIFF can grow and is handed to the user as-is.
  implication: The "never larger than input" truth is violated on BOTH paths; PNG via wrong comparison baseline, non-PNG via no guard whatsoever.

- timestamp: 2026-07-01
  checked: 05-UAT.md test 5 (lines 86-98) and 05-05-SUMMARY.md D-06 (lines 12, 20, 59-67)
  found: D-06 was implemented to contract "output never larger than a TRUECOLOR RE-ENCODE", not "never larger than the original input". UAT independently recorded the same root cause and the two missing behaviors: (1) when neither quantized nor truecolor beats the original, copy original through (or skip/report 0%); (2) apply a never-larger-than-original guard to the non-PNG path too.
  implication: This is a spec/contract mismatch baked into D-06, not a coding slip. The fix must change the comparison baseline to the ORIGINAL SOURCE FILE and make the original a writable candidate, on both paths.

## Resolution

root_cause: |
  The "never-larger guard" in ImageCompressTransformer.writePNGCompressed compares the
  quantized output only against a TRUECOLOR RE-ENCODE of the source (D-06 contract), never
  against — and never falling back to — the ORIGINAL SOURCE FILE. The original source bytes
  are read at line 153 but used only as a pass/skip threshold (line 154); the original is
  never an eligible output. For an already-optimized PNG (Google 2015 logo, 30KB), the
  256-color median-cut + filter-0/fast-deflate indexed encoder produces a 46KB file that is
  larger than the original yet smaller than (or simply chosen over) a fresh truecolor RGBA
  re-encode, so the 46KB quantized output wins min(quantized, truecolor) and is written.
  Result: +55% growth. Separately, the non-PNG ImageIO re-encode path (lines 82-105) has NO
  guard at all and can also grow a re-saved JPEG/HEIC/TIFF.
fix: (diagnose-only — not applied)
verification: (diagnose-only)
files_changed: []
