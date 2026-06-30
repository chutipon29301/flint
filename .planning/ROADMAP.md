# Roadmap: Flint — macOS Developer Toolkit

## Overview

Flint ships in three coarse phases that mirror the PRD's validated delivery plan. Phase 1 builds the complete infrastructure skeleton and seven core tools, proving the entire clipboard-detect → transform → history → search pipeline end-to-end. Phase 2 adds the five extended tools that complete the toolkit and deliver the remaining differentiators. Phase 3 delivers the app to users via a signed, notarized DMG with auto-update, drag-and-drop, and Services menu integration.

## Phases

**Phase Numbering:**

- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Infrastructure + Core Tools** - Full infra skeleton (ToolRegistry, HistoryStore, ClipboardDetector, HotkeyManager) plus JSON, Base64, URL, JWT, Timestamp, Hash, and UUID tools (completed 2026-06-25)
- [x] **Phase 2: Extended Tools** - Regex, Color, Markdown, Number Base, and Text Diff tools with ChromaKit, HighlightSwift, and SwiftDiff added (completed 2026-06-26)
- [x] **Phase 3: Polish & Distribution** - Services menu, drag-and-drop, signed/notarized DMG, Sparkle auto-update, and VoiceOver audit (completed 2026-06-26)
- [ ] **Phase 4: UX Improvement** - Fix the failing update checker and the menu-landing navigation (browse all tools + back-to-picker), then a UX pass on visual polish, onboarding/discoverability, and interaction-flow speed across all 12 tools

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

**Plans**: 7 plans (1 setup wave + 5 tool waves + 1 integration wave)
Plans:
**Wave 1**

- [x] 02-01-PLAN.md — Dependency setup: ChromaKit + swift-markdown (SPM), vendored+patched SwiftDiff, bundled GitHub CSS

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 02-02-PLAN.md — Regex Tester (NSRegularExpression, never-freeze off-main + 2s timeout, color-coded groups, replace, pattern library)

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 02-03-PLAN.md — Color Converter (HEX/RGB/HSL/HSV/OKLCH, eyedropper, sliders, WCAG, out-of-gamut)

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 02-04-PLAN.md — Markdown Previewer (swift-markdown→HTML, WebPreviewView, toolbar/footer, HTML/.html/.pdf export)

**Wave 5** *(blocked on Wave 4 completion)*

- [x] 02-05-PLAN.md — Number Base Converter (canonical bit pattern, two's-complement, interactive BitFieldView)

**Wave 6** *(blocked on Wave 5 completion)*

- [x] 02-06-PLAN.md — Text Diff (CollectionDifference line + vendored SwiftDiff word, unified/side-by-side, patch export)

**Wave 7** *(blocked on Wave 6 completion)*

- [x] 02-07-PLAN.md — Integration: register all five in ToolRegistry, wire detection predicates, end-to-end verification

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

**Plans**: 8 plans (7 waves — 03-02 split into 03-02a/03-02b per checker; 03-06/03-07 added as gap closure for the drag-drop popover-dismiss blocker, UAT Tests 5-8)
Plans:
**Wave 1**

- [x] 03-01-PLAN.md — Services menu routing (DIST-01): manual Info.plist + NSServices, AppDelegate/FlintServiceProvider, detect()→ToolSeed→activation-dance routing, no-match search staging

**Wave 2** *(blocked on Wave 1 — shares MenuBarPopoverView)*

- [x] 03-02a-PLAN.md — Drag-and-drop foundation + binary (DIST-02): DropOverlayView (single state) + shared FileDropHandler, any-file drop on Base64/Hash via chunked pipeline, launcher detect() routing + post-drop WarningBannerView rejection

**Wave 3** *(blocked on Wave 1/2)*

- [x] 03-02b-PLAN.md — Drag-and-drop text tools (DIST-02): apply shared .fileDrop + DropOverlayView to the 9 text-tool views (mechanical boilerplate), end-to-end drop verification *(depends on 03-02a)*
- [x] 03-03-PLAN.md — Sparkle code wiring (DIST-04): Sparkle 2.9.3 SPM, SUPublicEDKey+SUFeedURL in Info.plist [BLOCKING: key from first build], lazy SparkleUpdaterService off cold-start path *(depends on 03-01, 03-02a — shares MenuBarPopoverView)*

**Wave 4** *(blocked on Wave 1 + 3 — shares FlintApp/WindowCoordinator/Info.plist)*

- [x] 03-04-PLAN.md — First-run onboarding (DIST-03) + full-app VoiceOver audit (INFRA-15): hasSeenOnboarding pref, OnboardingWindowView, openOnboarding activation dance, and a BLOCKING VoiceOver audit across all 12 tools + launcher + 3 Phase 3 surfaces

**Wave 5** *(blocked on Wave 1 + 3 + 4 — distribution capstone, non-autonomous)*

- [x] 03-05-PLAN.md — Signed/notarized DMG + update dry-run (DIST-03/04): release.sh (Archive→Developer ID→notarytool→staple→create-dmg), dry-run-update.sh (v0.0.1→v0.0.2 appcast), DISTRIBUTION.md

**Wave 6 — GAP CLOSURE** *(drag-drop blocker, UAT Tests 5-8; root cause: popover NSPanel dismisses on resign-key)*

- [x] 03-06-PLAN.md — GAP: launcher-routed seed-consume across the 6 detectable tools (JSON/Base64/URL/JWT/Timestamp/UUID) so detect()-routing actually pre-fills, not just Color (DIST-02)

**Wave 7 — GAP CLOSURE** *(blocked on 03-06)*

- [x] 03-07-PLAN.md — GAP: route file drag-and-drop to the normal workspace window (Option 2) — MainWindowView becomes a launcher-routing drop target + discoverable popover affordance; unblocks UAT Tests 5/6/7/8 (DIST-02) *(depends on 03-06)*

**UI hint**: yes

### Phase 4: UX Improvement

**Goal**: Flint feels effortless to navigate and trustworthy to keep — the menu landing lets a user see and reach every tool and return to the tool picker from inside any tool, the update checker works correctly, and the app's visual polish, onboarding, and common-task flows make the "paste → right transform in under a second" promise obvious from first launch
**Mode:** mvp
**Depends on**: Phase 3
**Requirements**: UX-01, UX-02, UX-03, UX-04, UX-05, UX-06, UX-07, UX-08, INFRA-14, INFRA-15, INFRA-16, DIST-04
**Scope** (what this phase addresses):

  - **Defect — menu landing navigation**: the launcher has no way to browse all 12 tools, and there is no way to navigate back from inside a tool to the tool-selection screen. Add tool browsing/grid and a consistent back-to-picker affordance.
  - **Defect — update checker**: the current "Check for Updates" behavior is failing; diagnose and fix the Sparkle wiring so an update check completes and reports correctly.
  - **Visual / aesthetic polish**: spacing, typography, color, iconography, empty states, and Light/Dark consistency across the 12 tools and the launcher.
  - **Onboarding & discoverability**: improve first-run flow and surface hidden capabilities (global hotkey, Services menu, drag-and-drop, clipboard auto-detect).
  - **Interaction & flow speed**: reduce friction on common tasks — faster tool switching, keyboard navigation, and clipboard suggestion/copy-on-result behavior.

**Success Criteria** (what must be TRUE):

  1. From the menu landing, the user can see and open every one of the 12 tools without prior knowledge of which exist, and from inside any tool can return to the tool-selection screen in one obvious action
  2. "Check for Updates" completes a real update check and reports its result correctly (up-to-date, update available, or a clear error) — the previously-failing behavior is fixed and verified
  3. The 12 tools and launcher share a consistent, intentional visual treatment (spacing, type, color, empty/loading states) with no Light/Dark artifacts
  4. A new user, on first launch, is shown how to find tools and is made aware of the hotkey, Services, drag-and-drop, and clipboard auto-detect features
  5. Common transformations take fewer clicks/keystrokes than before — tool switching and result-copying are reachable from the keyboard, and the clipboard suggestion flow is discoverable

**Plans**: 5 plans (4 waves)
Plans:
**Wave 1**

- [x] 04-01-PLAN.md — Menu-landing navigation: all-12-tools grid (D-01) + back-to-picker header (D-02)
- [x] 04-02-PLAN.md — Update checker fix: SPUUpdaterDelegate + Check-for-Updates button + status/error (D-03/D-04)

**Wave 2** *(blocked on 04-01 — shares MenuBarPopoverView)*

- [x] 04-03-PLAN.md — Keyboard ⌘1–⌘9 row copy (D-08) + arrow-key search nav verify (D-07) — copy-only, no new permissions

**Wave 3** *(blocked on 04-03 — shares the multi-output tool views)*

- [x] 04-04-PLAN.md — Visual consistency pass across 12 tools (D-05) + onboarding Steps 3/4 (D-06)

**Wave 4** *(blocked on 04-02/04-03/04-04 — paste-back opt-in, non-autonomous)*

- [ ] 04-05-PLAN.md — Paste-back (D-09): default-off Accessibility opt-in + CGEvent ⌘V; completes the keyboard loop

**UI hint**: yes

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Infrastructure + Core Tools | 10/10 | Complete   | 2026-06-26 |
| 2. Extended Tools | 8/8 | Complete   | 2026-06-26 |
| 3. Polish & Distribution | 8/8 | Complete   | 2026-06-29 |
| 4. UX Improvement | 4/5 | In Progress|  |

### Phase 5: add image compression feature

**Goal:** A developer drops one or more image files onto the new Image Compressor tool and gets smaller, same-format versions back — re-encoded at a chosen quality, written beside each original as `-compressed`, never overwriting the source, with a live results table showing per-image thumbnail, original→new size, and % saved — all offline and never crashing on a non-image or corrupt file.
**Requirements**: D-01..D-10 (CONTEXT.md locked decisions), INFRA-17 (never crash), INFRA-18 (memory)
**Depends on:** Phase 4
**Plans:** 5 plans (3 build waves complete + 2 gap-closure plans for PNG quantization, UAT Test 8)

Plans:
**Wave 1**
- [x] 05-01-PLAN.md — ImageCompressTransformer: pure ImageIO round-trip re-encode (same format in/out) + `-compressed` disambiguation + size delta + unit tests (D-02/03/05/06/07/08, INFRA-17)

**Wave 2** *(blocked on 05-01)*
- [x] 05-02-PLAN.md — ImageCompressViewModel: off-main batch loop + CompressRow + per-row progress + cancellation + history + autoreleasepool memory bound (D-01/05/09, INFRA-17/18)

**Wave 3** *(blocked on 05-02)*
- [x] 05-03-PLAN.md — ImageCompressView (multi-file drop + quality slider/presets + live results table) + Definition + ToolRegistry sanctioned-append registration + full build (D-01/04/05/09/10, INFRA-14/15/17)

**Wave 4 — GAP CLOSURE** *(UAT Test 8: photographic PNGs barely shrink — root cause: ImageIO cannot emit indexed-color PNG)*
- [ ] 05-04-PLAN.md — GAP: pure-Swift PNG quantization engine — median-cut PNGColorQuantizer (RGBA→≤256-color palette) + IndexedPNGEncoder (color-type-3 PNG via Compression-framework zlib, PLTE/tRNS) + full unit tests, zero external deps (D-02, INFRA-17)

**Wave 5 — GAP CLOSURE** *(blocked on 05-04)*
- [ ] 05-05-PLAN.md — GAP: wire quantize+encode into ImageCompressTransformer PNG path (with never-larger truecolor fallback, D-06), register 3 new files in Flint.xcodeproj, transformer PNG-savings/alpha tests, full build + test suite green (D-02/05/06, INFRA-17/18) *(depends on 05-04)*
