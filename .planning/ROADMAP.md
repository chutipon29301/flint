### Phase 5: add image compression feature

**Goal:** A developer drops one or more image files onto the new Image Compressor tool and gets smaller, same-format versions back — re-encoded at a chosen quality, written beside each original as `-compressed`, never overwriting the source, with a live results table showing per-image thumbnail, original→new size, and % saved — all offline and never crashing on a non-image or corrupt file.
**Requirements**: D-01..D-10 (CONTEXT.md locked decisions), INFRA-17 (never crash), INFRA-18 (memory)
**Depends on:** Phase 4
**Plans:** 6/9 plans executed

Plans:
**Wave 1**
- [x] 05-01-PLAN.md — ImageCompressTransformer: pure ImageIO round-trip re-encode (same format in/out) + `-compressed` disambiguation + size delta + unit tests (D-02/03/05/06/07/08, INFRA-17)

**Wave 2** *(blocked on 05-01)*
- [x] 05-02-PLAN.md — ImageCompressViewModel: off-main batch loop + CompressRow + per-row progress + cancellation + history + autoreleasepool memory bound (D-01/05/09, INFRA-17/18)

**Wave 3** *(blocked on 05-02)*
- [x] 05-03-PLAN.md — ImageCompressView (multi-file drop + quality slider/presets + live results table) + Definition + ToolRegistry sanctioned-append registration + full build (D-01/04/05/09/10, INFRA-14/15/17)

**Wave 4 — GAP CLOSURE** *(UAT Test 8: photographic PNGs barely shrink — root cause: ImageIO cannot emit indexed-color PNG)*
- [x] 05-04-PLAN.md — GAP: pure-Swift PNG quantization engine — median-cut PNGColorQuantizer (RGBA→≤256-color palette) + IndexedPNGEncoder (color-type-3 PNG via Compression-framework zlib, PLTE/tRNS) + full unit tests, zero external deps (D-02, INFRA-17)

**Wave 5 — GAP CLOSURE** *(blocked on 05-04)*
- [x] 05-05-PLAN.md — GAP: wire quantize+encode into ImageCompressTransformer PNG path (with never-larger truecolor fallback, D-06), register 3 new files in Flint.xcodeproj, transformer PNG-savings/alpha tests, full build + test suite green (D-02/05/06, INFRA-17/18) *(depends on 05-04)*

**Wave 6 — GAP CLOSURE** *(UAT Test 5: compressed output can be LARGER than the original)*
- [x] 05-06-PLAN.md — GAP 1: never-larger-than-ORIGINAL guard — make the original source a writable candidate on the PNG path (smallest of {original, quantized, truecolor}) AND add a post-finalize guard to the non-PNG ImageIO path; TDD failing-first tests (D-02/06, INFRA-17)

**Wave 7 — GAP CLOSURE** *(UAT Tests 9 & 10, coupled; blocked on 05-06)*
- [ ] 05-07-PLAN.md — GAP 3+4: cancellable compression — cooperative Task.isCancelled checkpoint in the quantize loop + cancellation-propagating off-main work (not Task.detached, keep outer Task { } MainActor-bound per 05-02 Sendable gotcha) + resolve the in-flight .compressing row + keep Cancel visible until resolved; verify clean re-drop writes -compressed-1; slow-fixture cancellation test (D-01/09, INFRA-17/18)

**Wave 8 — GAP CLOSURE** *(UAT Test 6; blocked on 05-07)*
- [ ] 05-08-PLAN.md — GAP 2: explicit "Re-compress at {n}%" button (locked Option C) — store lastSourceURLs + lastRunQuality + recompress() on the ViewModel; show button when rows non-empty AND quality changed AND not entirely lossless; no auto-spew, compress-on-drop unchanged (D-04/05)

**Wave 9 — GAP CLOSURE — RE-VERIFY** *(blocked on 05-06/07/08)*
- [ ] 05-09-PLAN.md — Clean build + full test gate, then human re-test of UAT Tests 5/6/9/10 on the freshly-built binary; update 05-UAT.md (checkpoint:human-verify)
