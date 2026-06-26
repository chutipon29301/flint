---
phase: 01-infrastructure-core-tools
plan: 02
subsystem: encoding
tags: [base64, url-encoder, swiftui, foundation, mvvm, grdb]

requires:
  - phase: 01-01
    provides: "ToolDefinition/ToolRegistry frozen abstraction, HistoryStore, Base64Definition stub, URLEncoderDefinition stub, SyntaxEditorView, CodeDisplayView, CopyButtonView, InlineErrorView, Debounce actor"

provides:
  - "Base64Transformer — pure encode/decode (standard + URL-safe), auto-detect, byte/char counts (B64-01..05)"
  - "Base64ViewModel — 150ms debounce, auto-detect direction, file I/O off-main (B64-04)"
  - "Base64View — full UI with file buttons, URL-safe toggle, byte/char labels, per-field copy"
  - "URLTransformer — pure percent-encode/decode, URLComponents parse/rebuild, ParsedURL model (URL-01..03)"
  - "URLViewModel — 3-mode (encode/decode/parse), 150ms debounce, editable query param table (URL-03)"
  - "URLView — encode/decode split, parsed-component rows with per-field copy (URL-04), query param table with add/delete and rebuild"
  - "Base64Definition (real) — detection predicate chain priority 3, isLikelyBase64 guard (T-02-SP)"
  - "URLEncoderDefinition (real) — detection predicates priority 4 (percent-encoded) + 5 (URL scheme)"

affects:
  - 01-03 (JWT tool — shares base64url decode pattern; URLComponents parse pattern reusable)
  - All Wave-2 tool plans (reinforce the 4-file MVVM pattern)

tech-stack:
  added: []
  patterns:
    - "Pattern 5 (reused): pure *Transformer.swift + @Observable *ViewModel + *View + *Definition — enforced across Base64 and URL"
    - "Pattern: isLikelyBase64 ≥12-char + full-alphabet guard for clipboard auto-detect false-positive prevention (T-02-SP)"
    - "Pattern: URLComponents.queryItems → editable [QueryItem] array with Identifiable UUID for SwiftUI ForEach binding (URL-03)"
    - "Pattern: NSOpenPanel/NSSavePanel + Task.detached for non-blocking file I/O (B64-04, T-02-DOS)"

key-files:
  created:
    - Tools/Base64/Base64Transformer.swift
    - Tools/Base64/Base64ViewModel.swift
    - Tools/Base64/Base64View.swift
    - Tools/URLEncoder/URLTransformer.swift
    - Tools/URLEncoder/URLViewModel.swift
    - Tools/URLEncoder/URLView.swift
    - FlintTests/Base64TransformerTests.swift
    - FlintTests/URLTransformerTests.swift
  modified:
    - Tools/Base64/Base64Definition.swift (stub → real definition)
    - Tools/URLEncoder/URLEncoderDefinition.swift (stub → real definition)
    - Flint.xcodeproj/project.pbxproj (added file refs for both tool slices)

key-decisions:
  - "URLTransformer.percentEncode uses urlQueryAllowed minus '&=+?#' to produce RFC 3986-safe query-value encoding (not .urlHostAllowed which is too restrictive)"
  - "ParsedURL.QueryItem uses a stable UUID id (not name-based) so list editing via ForEach @Binding survives duplicate keys"
  - "URLView uses three-mode Picker (encode/decode/parse) rather than auto-detection — URL input is too ambiguous for reliable auto-mode"
  - "File encode (B64-04) uses aligned chunk size = (1MB / 3) * 3 = 1,047,552 bytes so each chunk encodes to clean base64 with no inter-chunk padding artifacts"

requirements-completed: [B64-01, B64-02, B64-03, B64-04, B64-05, URL-01, URL-02, URL-03, URL-04]

duration: 25min
completed: 2026-06-25
---

# Phase 1 Plan 2: Base64 + URL Encoder Tool Slices Summary

**Base64 encoder/decoder (standard + URL-safe, file I/O, auto-detect, byte/char counts) and URL encoder/decoder/parser (percent encode/decode, URLComponents parse, query-param table edit + rebuild, per-component copy) — both registered in ToolRegistry and reachable via search.**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-06-25T12:50:00Z
- **Completed:** 2026-06-25T13:15:00Z
- **Tasks:** 2
- **Files modified:** 10 (8 created, 2 overwritten stubs, 1 project file)

## Accomplishments

- Base64Transformer: pure encode/decode supporting standard and URL-safe (RFC 4648 §5) variants, isLikelyBase64 auto-detect heuristic with T-02-SP security guard (≥12 chars + full alphabet), byte/char count helpers — 18 unit tests all passing.
- Base64ViewModel + Base64View: 150ms debounced live transform, auto-detect direction, file encode/decode off main thread via Task.detached + NSOpenPanel/NSSavePanel, graceful inline errors with last-good-output-dimmed (D-11).
- URLTransformer: pure percent-encode/decode (Foundation addingPercentEncoding), URLComponents parse to ParsedURL struct, rebuild from edited ParsedURL — 22 unit tests all passing.
- URLViewModel + URLView: three-mode selector (encode/decode/parse), parsed-component rows each with per-field CopyButtonView (URL-04, D-12), editable query param table (add/delete/edit) with live rebuild (URL-03), inline error display.
- Both Definition stubs overwritten with real implementations including correct detection predicates; ToolRegistry untouched.

## Task Commits

Each task was committed atomically:

1. **Task 1: Base64 tool slice** — `5b44062` (feat)
2. **Task 2: URL Encoder/Decoder tool slice** — `d5eb32b` (feat)

## Files Created/Modified

- `Tools/Base64/Base64Transformer.swift` — Pure Base64 encode/decode/auto-detect/counts; zero UI imports
- `Tools/Base64/Base64ViewModel.swift` — @Observable debounce ViewModel with file I/O
- `Tools/Base64/Base64View.swift` — Full UI: split input/output, URL-safe toggle, file buttons, counts
- `Tools/Base64/Base64Definition.swift` — Overwrites stub: real detection predicate + Base64View factory
- `Tools/URLEncoder/URLTransformer.swift` — Pure percent-encode/decode + URLComponents parse/rebuild
- `Tools/URLEncoder/URLViewModel.swift` — @Observable 3-mode ViewModel with query param table state
- `Tools/URLEncoder/URLView.swift` — Encode/decode split + parse mode with component rows + query table
- `Tools/URLEncoder/URLEncoderDefinition.swift` — Overwrites stub: two detection predicates + URLView factory
- `FlintTests/Base64TransformerTests.swift` — 18 tests: B64-01..05, INFRA-17, T-02-SP
- `FlintTests/URLTransformerTests.swift` — 22 tests: URL-01..03, INFRA-17 no-crash
- `Flint.xcodeproj/project.pbxproj` — Added PBXFileReference + PBXBuildFile entries for all new files

## Decisions Made

- **URLTransformer.percentEncode charset:** Used `urlQueryAllowed` minus `&=+?#` (the characters that have semantic meaning inside a query string) rather than `urlHostAllowed`. This produces `%20` for space and `%26` for `&` in query value context — correct for URL-01.
- **ParsedURL.QueryItem UUID id:** URLQueryItem names are not guaranteed unique (duplicate key names are valid). Using a UUID id ensures ForEach list editing via @Binding survives duplicate parameter names.
- **URLView mode selector (not auto-detect):** URL input is too ambiguous for reliable auto-detect (a raw URL could need encoding; a percent-encoded string could be a URL). Three-mode Picker makes intent explicit.
- **File chunk alignment:** `(chunkSize / 3) * 3` ensures each 1MB chunk is a multiple of 3 bytes, so its base64 output has no trailing padding. Padding-free chunks can be concatenated cleanly without interstitial `=` artifacts.

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None — all files compiled clean on first attempt. Both test suites passed immediately.

## User Setup Required

None — no external service configuration required.

## Threat Model Coverage

| Threat | Mitigation Status |
|--------|-------------------|
| T-02-SP (Base64 false-positive auto-detect) | MITIGATED — isLikelyBase64 requires ≥12 chars + full base64 alphabet; verified by testIsLikelyBase64_shortString_isFalse |
| T-02-DOS (large file DoS) | MITIGATED — chunked 1MB FileHandle read in Task.detached; no Data(contentsOf:) whole-file load |
| T-02-IV (malformed input) | MITIGATED — both transformers return Result<_, Error>; 5 no-crash tests in Base64, 4 in URL |
| T-02-ID (history info disclosure) | ACCEPTED — Base64/URL inputs are not credentials; normal history rows expected |

## Next Phase Readiness

- Base64 and URL tools fully functional; both reachable via search and the pinned row launcher
- Plan 01-03 can begin immediately: JWT tool (builds on base64url decode pattern already proven in Base64Transformer)
- The 4-file MVVM pattern is fully established and documented across 3 tools (JSON, Base64, URL)

## Self-Check: PASSED

Files verified to exist:
- /Users/chutipon/Documents/project/flint/Tools/Base64/Base64Transformer.swift — FOUND
- /Users/chutipon/Documents/project/flint/Tools/Base64/Base64ViewModel.swift — FOUND
- /Users/chutipon/Documents/project/flint/Tools/Base64/Base64View.swift — FOUND
- /Users/chutipon/Documents/project/flint/Tools/URLEncoder/URLTransformer.swift — FOUND
- /Users/chutipon/Documents/project/flint/Tools/URLEncoder/URLViewModel.swift — FOUND
- /Users/chutipon/Documents/project/flint/Tools/URLEncoder/URLView.swift — FOUND
- /Users/chutipon/Documents/project/flint/FlintTests/Base64TransformerTests.swift — FOUND
- /Users/chutipon/Documents/project/flint/FlintTests/URLTransformerTests.swift — FOUND

Commits verified:
- 5b44062: feat(01-02): implement Base64 tool slice
- d5eb32b: feat(01-02): implement URL Encoder/Decoder tool slice
