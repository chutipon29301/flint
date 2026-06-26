# Roadmap: Flint — macOS Developer Toolkit

## Overview

Flint ships in three coarse phases that mirror the PRD's validated delivery plan. Phase 1 builds the complete infrastructure skeleton and seven core tools, proving the entire clipboard-detect → transform → history → search pipeline end-to-end. Phase 2 adds the five extended tools that complete the toolkit and deliver the remaining differentiators. Phase 3 delivers the app to users via a signed, notarized DMG with auto-update, drag-and-drop, and Services menu integration.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Infrastructure + Core Tools** - Full infra skeleton (ToolRegistry, HistoryStore, ClipboardDetector, HotkeyManager) plus JSON, Base64, URL, JWT, Timestamp, Hash, and UUID tools (completed 2026-06-25)
- [ ] **Phase 2: Extended Tools** - Regex, Color, Markdown, Number Base, and Text Diff tools with ChromaKit, HighlightSwift, and SwiftDiff added
- [ ] **Phase 3: Polish & Distribution** - Services menu, drag-and-drop, signed/notarized DMG, Sparkle auto-update, and VoiceOver audit

## Phase Details

### Phase 1: Infrastructure + Core Tools
**Goal**: A developer can open the app from anywhere via global hotkey, paste content and have it auto-detected, transform it with any of the seven core tools, and find past transformations in searchable history — all offline, under the performance targets, and without crashing on bad input
**Mode:** mvp
**Depends on**: Nothing (first phase)
**Requirements**: INFRA-01, INFRA-02, INFRA-03, INFRA-04, INFRA-05, INFRA-06, INFRA-07, INFRA-08, INFRA-09, INFRA-10, INFRA-11, INFRA-12, INFRA-13, INFRA-14, INFRA-15, INFRA-16, INFRA-17, INFRA-18, JSON-01, JSON-02, JSON-03, JSON-04, JSON-05, JSON-06, B64-01, B64-02, B64-03, B64-04, B64-05, URL-01, URL-02, URL-03, URL-04, JWT-01, JWT-02, JWT-03, JWT-04, JWT-05, JWT-06, TS-01, TS-02, TS-03, TS-04, TS-05, HASH-01, HASH-02, HASH-03, HASH-04, UUID-01, UUID-02, UUID-03, UUID-04
**Success Criteria** (what must be TRUE):
  1. User presses the global hotkey (⌘⇧Space) from any app and the Flint popover opens within 200ms with no Accessibility permission dialog required
  2. When the user copies a JSON string, JWT, Base64 blob, URL, or Unix timestamp, the app shows a non-destructive suggestion banner within 100ms of the popover gaining focus, and the user can accept it to open the matched tool pre-filled
  3. User can run all seven core tools (JSON Formatter, Base64, URL Encoder, JWT Decoder, Timestamp Converter, Hash Generator, UUID Generator) and each produces correct output on valid input and a graceful error message on malformed or oversized input — no crash in any case
  4. Every transformation is recorded in a searchable, re-openable history panel (last 100 items, persisted across restarts); HMAC and JWT secret keys are never written to history by schema design
  5. App cold-starts in under 500ms, stays under 100MB RAM under normal use, and all interactive elements have VoiceOver labels and support Light/Dark mode without visual artifacts
**Plans**: 10 plans (3 build waves + 1 gap-closure wave)
Plans:
- [x] 01-01-PLAN.md — Walking Skeleton: frozen infra (registry/history/clipboard/hotkey/popover) + JSON Formatter integration test
- [x] 01-02-PLAN.md — Base64 + URL tools (encoding category)
- [x] 01-03-PLAN.md — JWT Decoder (base64url, expiry, HMAC verify, secret-exclusion)
- [x] 01-04-PLAN.md — Timestamp Converter + Hash Generator (chunked file hash, HMAC key-exclusion)
- [x] 01-05-PLAN.md — UUID Generator/Inspector (v7 gated on package vetting)
- [x] 01-06-PLAN.md — First-class History view + global fuzzy search + pin/reorder + keyboard shortcuts
- [x] 01-07-PLAN.md — Preferences + launch-at-login + workspace window + Light/Dark/VoiceOver/perf audit
- [x] 01-08-PLAN.md — GAP: pinned-tool drag-to-reorder — SCOPE CHANGED per UAT: drag-reorder removed (gesture conflicted with tap-to-open; not needed in launcher). Pinned icons are tap-to-open only. INFRA-11 drag-reorder dropped. UAT passed.
- [x] 01-09-PLAN.md — GAP: ⌘⇧C copy-output + ⌘Delete clear-input observers across all 7 tools (shared ToolShortcutActions). UAT passed.
- [x] 01-10-PLAN.md — GAP: reliable first-Esc-to-launcher via popover-wide local NSEvent monitor (covers editor + history List focus). UAT passed.
**UI hint**: yes

### Phase 2: Extended Tools
**Goal**: The toolkit is complete — a developer can test regex patterns with live highlighting, convert colors across HEX/RGB/HSL/HSV/OKLCH with a screen eyedropper and WCAG contrast check, preview Markdown with GFM live, convert number bases with an interactive bit-field, and diff two text blocks with word-level precision
**Mode:** mvp
**Depends on**: Phase 1
**Requirements**: RGX-01, RGX-02, RGX-03, RGX-04, CLR-01, CLR-02, CLR-03, CLR-04, MD-01, MD-02, MD-03, MD-04, NUM-01, NUM-02, NUM-03, DIFF-01, DIFF-02, DIFF-03, DIFF-04
**Success Criteria** (what must be TRUE):
  1. User can enter a regex pattern and see matches highlighted live in the test string, color-coded per capture group, with the UI never freezing even on pathological patterns (background eval with 2-second timeout and 300ms debounce)
  2. User can input a color in any of HEX, RGB, HSL, HSV, or OKLCH and see all formats update simultaneously; user can pick a color from the screen via the NSColorSampler eyedropper; WCAG AA/AAA contrast result is shown for two colors; out-of-gamut OKLCH values display a warning badge
  3. User can write Markdown in a split editor and see a live GFM preview (tables, task lists, fenced code, strikethrough); user can export the result as copied HTML or a saved HTML file
  4. User can type a value in any of binary, octal, decimal, or hex and see all other bases update in real time; toggling individual bits in the bit-field UI updates all number fields; signed/unsigned two's-complement is handled correctly for all bit widths
  5. User can compare two text blocks and see line-level changes with word-level inline highlighting, line numbers, and added/removed/unchanged color coding; user can jump between differences and export a unified patch
**Plans**: TBD
**UI hint**: yes

### Phase 3: Polish & Distribution
**Goal**: Flint is in users' hands — it passes Gatekeeper, auto-updates via Sparkle, accepts dragged files and selected text routed from the system Services menu, and every tool is accessible via VoiceOver
**Mode:** mvp
**Depends on**: Phase 2
**Requirements**: DIST-01, DIST-02, DIST-03, DIST-04
**Success Criteria** (what must be TRUE):
  1. User can select text in any macOS app, right-click, and route it to the best-matching Flint tool via the Services menu, with the tool opening pre-filled
  2. User can drag a text file into any tool and a binary file (e.g., arbitrary bytes) into Base64 or Hash, and the tool processes it correctly without blocking the UI
  3. App ships as a signed, notarized DMG that mounts and installs without a Gatekeeper warning; a first-run onboarding flow greets new users
  4. App auto-updates via Sparkle with EdDSA-signed update bundles; the v0.0.1 to v0.0.2 pipeline is validated locally before the v1.0 release; the EdDSA public key is embedded in Info.plist from first release
**Plans**: TBD
**UI hint**: yes

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Infrastructure + Core Tools | 10/10 | Complete   | 2026-06-26 |
| 2. Extended Tools | 0/TBD | Not started | - |
| 3. Polish & Distribution | 0/TBD | Not started | - |
