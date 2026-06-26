# Requirements: Flint — macOS Developer Toolkit

**Defined:** 2026-06-25
**Core Value:** A developer can paste content and get the right transformation in under a second — fully offline, from anywhere on the system, never crashing on bad input.

> Source of truth: `requirement.md` (PRD). Scope adjustments from `.planning/research/SUMMARY.md` are folded in (JSONPath/JSON-diff deferred out of the Phase-1 formatter; UUID v7 gated on package vetting; secrets excluded from history by design).

## v1 Requirements

### Infrastructure (INFRA)

- [x] **INFRA-01**: App lives in the menubar via MenuBarExtra and opens a compact popover launcher (~480×600)
- [x] **INFRA-02**: User can detach a tool into a resizable workspace window (min 800×600); tool remembers its last mode
- [x] **INFRA-03**: A `ToolDefinition`/`ToolRegistry` abstraction enumerates all tools uniformly (id, name, category, keywords, SF Symbol, detection predicate, view factory) — single source for launcher, search, detection, and services routing
- [x] **INFRA-04**: User can open/focus the app from any app via a global hotkey (`⌘⇧Space`, configurable) with no Accessibility permission prompt
- [x] **INFRA-05**: On focus, app auto-detects clipboard content and shows a non-destructive suggestion banner ("Detected: JWT — Open JWT Decoder?") that the user can accept or dismiss
- [x] **INFRA-06**: Clipboard detection runs the ordered predicate chain (JSON → JWT → Base64 → URL-encoded → URL → 10-digit timestamp → hex color → UUID → regex) and fires within 100ms of focus
- [x] **INFRA-07**: App persists the last 100 transformations (tool, input, output, timestamp) in a local SQLite store across restarts
- [x] **INFRA-08**: History is searchable, re-openable (click restores input/output into the tool), and items can be pinned, deleted, or cleared
- [x] **INFRA-09**: History never persists user secrets (JWT HMAC verification keys, HMAC hash keys are excluded from the store by schema design)
- [x] **INFRA-10**: Global fuzzy search spans tool names, descriptions, and history, and is keyboard-navigable (↑↓, Enter)
- [x] **INFRA-11**: User can pin up to 6 tools to the popover quick-access bar (drag-to-reorder); ships with sensible defaults
- [x] **INFRA-12**: Preferences window (`⌘,`) covers General, Appearance, History, and per-tool defaults
- [x] **INFRA-13**: Preferences settings work: launch at login (SMAppService), show-in-Dock toggle, default open mode, clipboard auto-detect on/off, theme, code font, font size, history limits
- [x] **INFRA-14**: App fully supports Light/Dark mode and system accent color with no visual artifacts
- [x] **INFRA-15**: All interactive elements have VoiceOver labels and support Dynamic Type scaling
- [x] **INFRA-16**: Documented global keyboard shortcuts work (open, prefs, close, next/prev tool, focus search, copy output, paste-and-detect, clear input, toggle history, new window)
- [x] **INFRA-17**: No tool crashes on malformed, oversized, or invalid-UTF-8 input; all inputs are validated gracefully
- [x] **INFRA-18**: App meets performance targets — cold start < 500ms, hotkey-to-popover < 200ms, < 100MB RAM under normal use

### Core Tools — JSON (JSON)

- [x] **JSON-01**: User can pretty-print JSON with configurable indent (2, 4, or tab)
- [x] **JSON-02**: User can minify JSON to compact form
- [x] **JSON-03**: Editor shows real-time validation with inline error location (line + column)
- [x] **JSON-04**: User can sort keys alphabetically (toggle)
- [x] **JSON-05**: Editor provides JSON syntax highlighting
- [x] **JSON-06**: User can copy formatted output in one click

### Core Tools — Base64 (B64)

- [x] **B64-01**: User can encode text to Base64 and decode Base64 to text
- [x] **B64-02**: User can switch to the URL-safe Base64 variant (`-`/`_`), with padding handled correctly
- [x] **B64-03**: Tool auto-detects encode vs decode direction
- [x] **B64-04**: User can encode a dropped file to Base64 and decode Base64 to a saved file
- [x] **B64-05**: Tool shows decoded byte length and character count

### Core Tools — URL (URL)

- [x] **URL-01**: User can percent-encode text for URL query params and decode percent-encoded strings
- [x] **URL-02**: User can parse a full URL into scheme, host, path, query params, and fragment
- [x] **URL-03**: User can edit query params in an add/delete key-value table and rebuild the URL
- [x] **URL-04**: User can copy individual URL components

### Core Tools — JWT (JWT)

- [x] **JWT-01**: User can decode a JWT into header, payload, and signature, correctly handling base64url (no corruption on `-`/`_`)
- [x] **JWT-02**: Header and payload render as pretty-printed JSON
- [x] **JWT-03**: Tool shows expiry (`exp`) as a human-readable date plus countdown ("Expires in 2h 14m" / "EXPIRED 3 days ago"), timezone-correct
- [x] **JWT-04**: User can verify the signature with a supplied secret (HMAC-SHA256/384/512); the secret is never written to history
- [x] **JWT-05**: Claims table separates standard claims (iss/sub/aud/exp/iat/nbf) from custom claims and shows the algorithm
- [x] **JWT-06**: Tool shows warning banners for expired token, `alg: none`, and missing standard claims

### Core Tools — Timestamp (TS)

- [x] **TS-01**: User can convert a Unix timestamp (seconds or millis, auto-detected) to a human-readable date
- [x] **TS-02**: Tool shows the date across local, UTC, and user-configured additional timezones simultaneously
- [x] **TS-03**: User can reverse-convert a picked date/time to a Unix timestamp
- [x] **TS-04**: "Now" button inserts the current timestamp; relative time ("3 days ago", "in 2 hours") is shown
- [x] **TS-05**: User can output ISO 8601 format

### Core Tools — Hash (HASH)

- [x] **HASH-01**: User can hash text and show MD5, SHA-1, SHA-256, SHA-384, SHA-512, and CRC32 simultaneously
- [x] **HASH-02**: User can drop a file to hash it (shows file size + all hashes) without blocking the UI
- [x] **HASH-03**: HMAC mode adds a secret key for keyed hashes; the key is never written to history
- [x] **HASH-04**: User can toggle uppercase/lowercase output and copy any individual hash

### Core Tools — UUID (UUID)

- [x] **UUID-01**: User can generate single or bulk UUIDs (up to 1000) in v1, v4, and v5
- [x] **UUID-02**: User can generate v7 (time-ordered) UUIDs (gated on package vetting; falls back to v1/v4/v5 if no sound implementation is found)
- [x] **UUID-03**: User can parse/inspect a UUID — version, variant, embedded timestamp (v1/v7), component breakdown
- [x] **UUID-04**: User can export bulk UUIDs to clipboard (newline) or as CSV/JSON array, with uppercase/lowercase toggle and nil-UUID display

### Extended Tools — Regex (RGX)

- [x] **RGX-01**: User can enter a pattern with flag toggles (g, i, m, s, x) and a multi-line test string
- [x] **RGX-02**: Matches highlight live in the test string, color-coded per capture group, with a match-count badge — never freezing the UI (background eval + timeout guard against catastrophic backtracking)
- [x] **RGX-03**: Match results table shows index, position, full match, and capture groups (named groups supported)
- [x] **RGX-04**: Replace mode previews substitution output; a common-pattern library (email, URL, phone, date, IP) offers quick-insert

### Extended Tools — Color (CLR)

- [x] **CLR-01**: User can input any of HEX, RGB, HSL, HSV, OKLCH and see all formats output simultaneously with a preview swatch and alpha support
- [ ] **CLR-02**: User can pick a color from anywhere on screen (NSColorSampler eyedropper) and via the system color panel
- [ ] **CLR-03**: User can adjust R/G/B or H/S/L sliders interactively
- [ ] **CLR-04**: Contrast checker reports WCAG AA/AAA result for two colors; any format copies in one click

### Extended Tools — Markdown (MD)

- [x] **MD-01**: Split editor/preview view renders GFM live (tables, strikethrough, task lists, fenced code) with debounced updates
- [ ] **MD-02**: Editor highlights Markdown syntax; preview highlights code blocks
- [x] **MD-03**: User can export as copied HTML, saved `.html`, or saved `.pdf` (WKWebView)
- [ ] **MD-04**: Tool shows word count and reading-time estimate; toolbar inserts bold/italic/link/image/code/table

### Extended Tools — Number Base (NUM)

- [ ] **NUM-01**: User can type a value in binary, octal, decimal, or hex and see all bases update in real time
- [ ] **NUM-02**: Bit-length selector (8/16/32/64) and signed/unsigned toggle with two's-complement display for negatives
- [ ] **NUM-03**: A bit-field of toggleable bit buttons flips bits and updates all fields, handling overflow gracefully

### Extended Tools — Text Diff (DIFF)

- [ ] **DIFF-01**: User can compare two text blocks in side-by-side or unified view (toggle)
- [x] **DIFF-02**: Diff shows line-level changes with word-level highlighting, added/removed/unchanged color coding, and line numbers
- [ ] **DIFF-03**: User can jump to next/previous difference and copy the diff as a unified patch
- [ ] **DIFF-04**: User can toggle ignore-whitespace and ignore-case

### Polish & Distribution (DIST)

- [ ] **DIST-01**: macOS Services menu lets a user select text anywhere, route it to the best-matching tool pre-filled
- [ ] **DIST-02**: All tools accept drag-and-drop of text files; binary tools (Base64, Hash) accept any file
- [ ] **DIST-03**: App ships as a signed, notarized `.dmg` that passes Gatekeeper, with a first-run onboarding flow
- [ ] **DIST-04**: App auto-updates via Sparkle (EdDSA-signed updates)

## v2 Requirements

### Sync & Account
- **V2-SYNC-01**: Cloud sync of history/preferences
- **V2-SYNC-02**: Account system

### Distribution
- **V2-DIST-01**: Mac App Store build with sandboxing

### Tools
- **V2-TOOL-01**: Cron expression parser (high demand — ships in DevUtils/Wring/DevToys)
- **V2-TOOL-02**: YAML ↔ JSON converter
- **V2-TOOL-03**: String case converter
- **V2-TOOL-04**: JSONPath query tab in the JSON tool (deferred out of the Phase-1 formatter to keep MVP lean)
- **V2-TOOL-05**: JSON-vs-JSON diff (covered by Text Diff in v1; dedicated semantic JSON diff deferred)

### Observability
- **V2-OBS-01**: Opt-in crash reporting (Sentry)

### Notifications
- **V2-NOTF-01**: Notify when a long file-hash operation completes (PRD v1.1 optional)

## Out of Scope

| Feature | Reason |
|---------|--------|
| Cloud sync / accounts | Local-first, offline-by-design product; deferred to v2 |
| iOS / mobile version | Desktop-only product focus |
| Plugin marketplace | Platform/maintenance burden unjustified for v1 |
| Collaboration / multiplayer | Single-user tool |
| Analytics / telemetry | Privacy stance; opt-in Sentry is a v2 item |
| App Store sandboxing (v1) | v1 needs clipboard + arbitrary file access; sandboxed build is a v2 target |
| Network entitlement | No tool needs the network; none will be requested |
| QR code / Lorem Ipsum tools | Outside the encode/transform persona; competitors that ship them are broader scope |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| INFRA-01 | Phase 1 | Complete |
| INFRA-02 | Phase 1 | Complete |
| INFRA-03 | Phase 1 | Complete |
| INFRA-04 | Phase 1 | Complete |
| INFRA-05 | Phase 1 | Complete |
| INFRA-06 | Phase 1 | Complete |
| INFRA-07 | Phase 1 | Complete |
| INFRA-08 | Phase 1 | Complete |
| INFRA-09 | Phase 1 | Complete |
| INFRA-10 | Phase 1 | Complete |
| INFRA-11 | Phase 1 | Complete |
| INFRA-12 | Phase 1 | Complete |
| INFRA-13 | Phase 1 | Complete |
| INFRA-14 | Phase 1 | Complete |
| INFRA-15 | Phase 1 | Complete |
| INFRA-16 | Phase 1 | Complete |
| INFRA-17 | Phase 1 | Complete |
| INFRA-18 | Phase 1 | Complete |
| JSON-01 | Phase 1 | Complete |
| JSON-02 | Phase 1 | Complete |
| JSON-03 | Phase 1 | Complete |
| JSON-04 | Phase 1 | Complete |
| JSON-05 | Phase 1 | Complete |
| JSON-06 | Phase 1 | Complete |
| B64-01 | Phase 1 | Complete |
| B64-02 | Phase 1 | Complete |
| B64-03 | Phase 1 | Complete |
| B64-04 | Phase 1 | Complete |
| B64-05 | Phase 1 | Complete |
| URL-01 | Phase 1 | Complete |
| URL-02 | Phase 1 | Complete |
| URL-03 | Phase 1 | Complete |
| URL-04 | Phase 1 | Complete |
| JWT-01 | Phase 1 | Complete |
| JWT-02 | Phase 1 | Complete |
| JWT-03 | Phase 1 | Complete |
| JWT-04 | Phase 1 | Complete |
| JWT-05 | Phase 1 | Complete |
| JWT-06 | Phase 1 | Complete |
| TS-01 | Phase 1 | Complete |
| TS-02 | Phase 1 | Complete |
| TS-03 | Phase 1 | Complete |
| TS-04 | Phase 1 | Complete |
| TS-05 | Phase 1 | Complete |
| HASH-01 | Phase 1 | Complete |
| HASH-02 | Phase 1 | Complete |
| HASH-03 | Phase 1 | Complete |
| HASH-04 | Phase 1 | Complete |
| UUID-01 | Phase 1 | Complete |
| UUID-02 | Phase 1 | Complete |
| UUID-03 | Phase 1 | Complete |
| UUID-04 | Phase 1 | Complete |
| RGX-01 | Phase 2 | Complete |
| RGX-02 | Phase 2 | Complete |
| RGX-03 | Phase 2 | Complete |
| RGX-04 | Phase 2 | Complete |
| CLR-01 | Phase 2 | Complete |
| CLR-02 | Phase 2 | Pending |
| CLR-03 | Phase 2 | Pending |
| CLR-04 | Phase 2 | Pending |
| MD-01 | Phase 2 | Complete |
| MD-02 | Phase 2 | Pending |
| MD-03 | Phase 2 | Complete |
| MD-04 | Phase 2 | Pending |
| NUM-01 | Phase 2 | Pending |
| NUM-02 | Phase 2 | Pending |
| NUM-03 | Phase 2 | Pending |
| DIFF-01 | Phase 2 | Pending |
| DIFF-02 | Phase 2 | Complete |
| DIFF-03 | Phase 2 | Pending |
| DIFF-04 | Phase 2 | Pending |
| DIST-01 | Phase 3 | Pending |
| DIST-02 | Phase 3 | Pending |
| DIST-03 | Phase 3 | Pending |
| DIST-04 | Phase 3 | Pending |

**Coverage:**
- v1 requirements: 75 total (18 INFRA + 34 core tools + 19 extended tools + 4 dist)
- Mapped to phases: 75
- Unmapped: 0

---
*Requirements defined: 2026-06-25*
*Last updated: 2026-06-25 — traceability expanded to per-ID rows by roadmapper*
