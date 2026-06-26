# Project Research Summary

**Project:** Flint — macOS Developer Toolkit (Menubar)
**Domain:** Native macOS menubar developer-utility app (SwiftUI, MVVM, macOS 14.0+)
**Researched:** 2026-06-25
**Confidence:** HIGH

## Executive Summary

Flint is a native macOS menubar utility in a well-defined competitive category (DevToys, DevUtils, Wring, Boop). The research confirms that the PRD's three-phase structure is sound, but several package picks in the original PROJECT.md are stale and must be corrected before coding begins: Highlightr is deprecated (replace with HighlightSwift for display, custom NSTextStorage for editable views), Ink lacks full GFM (replace with swift-markdown), SwiftData has critical macOS 14 bugs (replace with GRDB 7), and CGEventTap for global hotkeys triggers an Accessibility permission dialog (replace with KeyboardShortcuts 3.0.1). CRC32 has no CryptoKit support and must be sourced from zlib via CommonCrypto. OKLCH conversion has no Apple-native path and requires ChromaKit 0.1.1 in Phase 2.

The architecture centers on a single highest-leverage decision: the `ToolDefinition` / `ToolRegistry` abstraction. Every cross-cutting concern — clipboard auto-detection, history writing, search, keyboard routing — flows through this abstraction. It must be designed and frozen in the first week of Phase 1 before any tool implementation starts. The build order is strictly infrastructure-first: the skeleton (registry, history store, clipboard detector, hotkey manager, popover shell) must be fully wired before the first tool (JSON Formatter) is built. The JSON Formatter then serves as the integration test that proves the entire data-flow pipeline works end-to-end before adding the remaining six tools.

The most dangerous risks are all Phase 1 architectural decisions that cannot be retrofitted cheaply: history must exclude HMAC/JWT secrets by design from day one; MenuBarExtraAccess must be added before tool UIs are built on top of the popover; activation-policy juggling for the detached window must be solved in the skeleton; NSTextView `updateNSView` guard must be built into the first editable view; GRDB must open off the main thread; clipboard polling must limit to when the popover is visible (or use the NSNotification approach). Getting these seven decisions right in Phase 1 eliminates the highest-severity retrofit costs later.

## Key Findings

### Recommended Stack

The stack is almost entirely Apple-native. Swift 6 toolchain / Xcode 16.3+ is required by GRDB 7, which is the only viable history store given SwiftData's documented critical bugs on macOS 14. The six external packages that are genuinely necessary are: GRDB 7.11.1 (history), KeyboardShortcuts 3.0.1 (global hotkey without Accessibility permission), HighlightSwift 1.1.0 (display-only syntax highlighting), swift-markdown 0.8.0 (GFM-compliant Markdown AST, Apple-backed), SwiftDiff (word-level inline diff within changed lines), and ChromaKit 0.1.1 (OKLCH conversion, Phase 2 only). Sparkle 2.9.3 is added in Phase 3 for auto-update. All packages are SPM-native and compatible with the macOS 14.0 deployment target. Total package footprint excluding Sparkle is approximately 2 MB.

**Core technologies:**
- Swift 6 / Xcode 16.3+: language — required by GRDB 7 strict concurrency
- SwiftUI + `@Observable` (macOS 14): primary UI — property-level re-render tracking avoids cascading refreshes
- AppKit via `NSViewRepresentable`: editable `NSTextView`, `NSColorSampler`, `WKWebView` — unavoidable for editor and eyedropper
- GRDB 7.11.1: history SQLite store — SwiftData has critical macOS 14 bugs; GRDB gives typed queries, ValueObservation, migrations
- CryptoKit + CommonCrypto + zlib: hashing — CryptoKit for SHA/HMAC; CommonCrypto/zlib for MD5 and CRC32 (CryptoKit excludes CRC32)
- KeyboardShortcuts 3.0.1: global hotkey — Carbon `RegisterEventHotKey`, zero permissions, no Accessibility dialog
- HighlightSwift 1.1.0: display-only syntax highlighting — replaces deprecated Highlightr per the original maintainer's recommendation
- swift-markdown 0.8.0: Markdown parsing — full GFM via cmark-gfm; replaces Ink which lacks task lists and tables
- ChromaKit 0.1.1: OKLCH conversion (Phase 2) — no native Apple OKLCH API exists
- MenuBarExtraAccess: programmatic popover dismiss — required because `MenuBarExtra` has no built-in dismiss API (FB10185203 open since 2022)
- Sparkle 2.9.3: auto-update (Phase 3 only) — the only production-ready non-MAS update framework

**Do not use:**
- SwiftData: critical macOS 14 bugs (broken observation, random reordering, non-functional `didSave`)
- Highlightr: explicitly deprecated by maintainer as of 2026
- Ink: no full GFM support, static-site oriented
- CGEventTap: requires Accessibility permission dialog on first launch
- CryptoSwift: 500 KB addition, slower than native CryptoKit/CommonCrypto
- `altool`: removed from Apple notary service November 2023; use `notarytool`

### Expected Features

Feature research is based on verified competitor analysis (DevToys v2, DevUtils 47 tools, Wring, Boop, CyberChef). The PRD's feature set is strong and correctly positions several genuine differentiators: URL param editor with rebuild, JWT HMAC verification without persisting the secret, UUID v7 generation and inspection, OKLCH color output, NSColorSampler screen picker, WCAG contrast checker, interactive bit-field UI, and word-level inline diff.

**Must have (table stakes) — users switch tools if missing:**
- JSON pretty-print, minify, real-time validation with error location
- Base64 encode/decode (text + URL-safe variant)
- URL encode/decode
- JWT decode (header/payload/expiry display)
- Unix timestamp to human date
- Hash generation (SHA-256, SHA-512 minimum)
- UUID v4 generation
- Regex tester with live match highlight
- Color format conversion (HEX/RGB/HSL)
- Line-level text diff
- Clipboard auto-detection with smart routing
- Global hotkey to open app
- History (re-openable past transformations)
- Fuzzy search across tools

**Should have (genuine differentiators vs. all 5 competitors):**
- URL parser with editable query-param table + rebuild from params
- JWT HMAC signature verification (HS256/384/512) without persisting the secret
- UUID v7 generation + timestamp inspection (no competitor ships this)
- OKLCH color output (no competitor ships OKLCH)
- NSColorSampler screen eyedropper (Wring and DevUtils lack this)
- WCAG AA/AAA contrast checker inline with color conversion (no competitor ships this)
- Interactive 8-bit clickable bit-field UI (no competitor ships interactive bit toggles)
- Word-level diff within changed lines (rare at this fidelity)

**Scope corrections — cut from Phase 1 to Phase 2:**
- JSONPath query: ambitious scope inside the formatter; extract to a Phase 2 tab within the JSON tool (requires Sextant/SwiftPath package)
- JSON diff embedded in the formatter: redundant with the Phase 2 standalone Text Diff tool; remove from Phase 1 formatter spec

**Gate UUID v7 on package vetting:**
- UUID v7 requires an external Swift package (Foundation only generates v4; the Swift Forums pitch has not shipped)
- Keep as a Phase 1 differentiator but validate the package choice (`nthState/UUIDV7` or equivalent) in the first sprint; move to Phase 2 if vetting delays Phase 1

**Defer to v2+:**
- YAML to JSON (needs Yams package; no native Foundation YAML parser)
- Cron expression parser (moderate scope; high demand but not MVP-critical)
- String case converter (low daily utility for API-focused devs; bundle into Text Utilities in v2)
- QR Code generator/reader (Vision + CoreImage; new permission surface)
- HTML entity encoder, Lorem Ipsum, SQL formatter, plugin marketplace — confirmed out of scope

### Architecture Approach

The architecture is a layered SwiftUI app with four tiers: App (owns and injects all services), Core Services (ToolRegistry, HistoryStore, ClipboardDetector, HotkeyManager, PreferencesStore), Tools (each tool is a `ToolDefinition` + `ToolViewModel` + `ToolView` + pure `Transformer`), and Infrastructure (GRDB, UserDefaults, KeyboardShortcuts, NSPasteboard, CryptoKit/CommonCrypto, AppKit bridges). Services are `@Observable` classes held as `@State` in `FlintApp` and injected via `.environment()` — this is the only lifecycle-safe ownership point. Tools' ViewModels are created lazily per navigation destination and are never shared between the popover and the workspace window.

**Major components:**
1. `ToolDefinition` (struct) — immutable metadata per tool: id, name, category, keywords, detection predicate, view factory. The central abstraction; changing its shape later requires touching every `*Definition.swift` file.
2. `ToolRegistry` (`@Observable` class) — ordered array of `ToolDefinition`; provides fuzzy search and the clipboard predicate chain (`detect(from:)` — first match wins). Adding a Phase 2 tool requires one line here.
3. `HistoryStore` (GRDB `DatabaseQueue` wrapper) — receives `HistoryEntry` writes from tool ViewModels via injected closure (never direct import); publishes reactive updates via `ValueObservation`.
4. `ClipboardDetector` — `DispatchSourceTimer` on a background queue (not main thread) polls `NSPasteboard.changeCount`; publishes `DetectionResult?` to `@MainActor`; must stop polling when popover is hidden.
5. `WindowCoordinator` — manages `NSActivationPolicy` toggle (`.accessory` to `.regular`) when the detached workspace window opens and closes; required because `.accessory` apps cannot bring windows to front reliably.
6. Per-tool MVVM triad: `*Transformer.swift` (pure, no UI imports, fully testable), `*ViewModel.swift` (`@Observable`, orchestrates state + calls transformer + invokes history closure), `*View.swift` (reads ViewModel only).

### Critical Pitfalls

**Phase 1 — must resolve in the skeleton, cannot be retrofitted cheaply:**

1. **MenuBarExtra has no programmatic dismiss API (FB10185203 open since 2022)** — Add `MenuBarExtraAccess` before building any tool UIs on top of the popover. Wire `isPresented` binding to Esc keypress and all "close" buttons. Do not attempt `@Environment(\.dismiss)` — it does not work for `MenuBarExtra` windows.

2. **Activation-policy trap for detached window and Preferences** — Apps run as `.accessory`; windows silently appear behind the frontmost app. Implement `WindowCoordinator` with the activation dance: `setActivationPolicy(.regular)` then `activate(ignoringOtherApps: true)` then 100ms async delay then open window. Restore `.accessory` on `NSWindow.willCloseNotification`. `openSettings()` and `SettingsLink` are broken on macOS 14 with `.accessory` policy.

3. **History must exclude HMAC/JWT secrets by design** — Define per-tool history serialization in the schema before any tool writes. The JWT tool's `HistoryEntry.input` stores only the token, never the HMAC key. The Hash tool's entry stores only the content path/text, never the HMAC key. If secrets ever need remembering, use the Keychain, never SQLite or UserDefaults.

4. **JWT segments require base64url decoding, not standard base64** — `Data(base64Encoded:)` fails on JWT segments containing `-` or `_` (base64url uses these instead of `+` and `/`). Write a dedicated decoder that substitutes characters and pads to a multiple of 4 before calling `Data(base64Encoded:)`. Unit-test with a known JWT from jwt.io.

5. **NSTextView `NSViewRepresentable` infinite re-render loop** — The naive `updateNSView` unconditionally sets `textView.string`, triggering the text storage delegate, triggering a SwiftUI state update, repeating forever. Guard with `if textView.string == newValue { return }`, preserve selection ranges, and post binding updates asynchronously via `DispatchQueue.main.async`.

6. **Eager ViewModel/WKWebView initialization exceeds 500ms cold-start budget** — Do not instantiate all tool ViewModels at startup. Open GRDB's `DatabaseQueue` off the main thread in `Task.detached`. Defer `WKWebView` instantiation to first appearance of the Markdown tool. Measure with Instruments "App Launch" before shipping Phase 1.

7. **Clipboard polling on a global background timer drains battery** — Either use the `NSPasteboardDidChangeNotification` private-but-stable notification (0% idle CPU) or start the polling timer only when the popover is visible (`onAppear`/`onDisappear`). Never poll at 100ms globally in the background.

**Phase 2 — address when building the relevant tool:**

8. **Regex catastrophic backtracking hangs the UI** — Run all `NSRegularExpression` evaluation in a `Task.detached` with a 2-second timeout. Debounce input by 300ms before evaluating. Consider Swift 5.7+ `Regex` type (PEG engine, no catastrophic backtracking) for new patterns.

9. **OKLCH values outside sRGB gamut are silently clamped by NSColor** — After ChromaKit conversion, check if any sRGB component exceeds [0, 1]. Show an out-of-gamut warning badge and mark the HEX output as approximate. Test against oklch.com reference values.

**Phase 3:**

10. **Sparkle EdDSA key must be embedded from v1.0; losing the private key locks all users out of auto-update** — Generate the EdDSA keypair once; store private key in CI Keychain; embed `SUPublicEDKey` in `Info.plist` before shipping v1.0; validate the v0.0.1 to v0.0.2 update pipeline locally before the real release.

11. **`get-task-allow` entitlement in Release build fails notarization** — Maintain separate `Flint-debug.entitlements` and `Flint-release.entitlements`. Set `CODE_SIGN_ENTITLEMENTS` per Xcode build configuration. Test `notarytool submit` on the first Release archive.

## Implications for Roadmap

### Phase 1: Infrastructure + Core Tools (MVP)

**Rationale:** The `ToolDefinition`/`ToolRegistry` abstraction is the central dependency for every subsequent decision. Build the full infrastructure skeleton first, then use the JSON Formatter as the integration test that proves clipboard detection, history writing, and search all work end-to-end before adding the remaining six tools.

**Week 1-2 — pure infrastructure (no tool work until this is done):**
1. `ToolDefinition` + `ToolCategory` + `DetectionResult` structs (no deps — start here)
2. `HistoryEntry` struct + GRDB schema + `HistoryStore` (async open off main thread)
3. `PreferencesStore` (UserDefaults wrapper)
4. `ToolRegistry` stub (no tools registered yet)
5. `ClipboardDetector` (NSNotification approach or on-visible polling, not global timer)
6. `HotkeyManager` using KeyboardShortcuts 3.0.1 (not CGEventTap)
7. `WindowCoordinator` with activation-policy dance
8. `FlintApp` + scene wiring + `.environment()` injection for all services
9. `MenuBarPopoverView` empty shell + `MenuBarExtraAccess` wiring
10. `MainWindowView` empty shell (NavigationSplitView)
11. `DetectionBannerView`

**Week 3-4 — JSON Formatter as full integration test:**
12. `JSONTransformer` (pure, no UI imports)
13. `JSONFormatterViewModel` (calls transformer, injects history closure)
14. `JSONFormatterView` (without JSONPath or diff — those are Phase 2)
15. `JSONFormatterDefinition.make()`
16. Register in `ToolRegistry`

After step 16: clipboard auto-detection routes JSON input, history records it, search finds it. The entire pipeline is proven.

**Remaining Phase 1 tools (each following the same 4-file pattern):**
- Base64: text + URL-safe + file; base64url decoding unit-tested
- URL Encoder/Decoder + editable query-param table (differentiator)
- JWT Decoder: header/payload/expiry/warnings + HMAC verify; secrets excluded from history by design; base64url decoder reused from Base64 tool
- Unix Timestamp: multi-timezone + ISO 8601 + relative; seconds/ms ambiguity handled with format selector for 11/12-digit inputs
- Hash Generator: all CryptoKit algorithms + CRC32 via zlib + HMAC; file hashing chunked via FileHandle async; HMAC key excluded from history
- UUID Generator: v1/v4/v5 + bulk + inspect; UUID v7 gated on package vetting (move to Phase 2 if package choice unresolved at sprint start)

**Addresses:** All table-stakes features. Validates the core value proposition before building extended tools.

**Avoids:** All seven Phase 1 architectural pitfalls listed above — particularly secret leakage in history (JWT, HMAC), the activation-policy trap, the NSTextView re-render loop, and the cold-start budget.

**Research flag:** Standard patterns for the tool layer — no additional phase research needed. The infrastructure patterns are well-documented. The JWT base64url decoder and CRC32 via zlib have exact implementation guidance in PITFALLS.md.

---

### Phase 2: Extended Tools

**Rationale:** Phase 1 validates the core value proposition and proves the data-flow pipeline. Phase 2 adds the five extended tools that round out the toolkit and deliver the remaining differentiators (word-level diff, OKLCH, WCAG, bit-field UI). The JSON tool also gets its JSONPath tab here. Add ChromaKit 0.1.1 (OKLCH) and SwiftDiff at the start of this phase.

**Delivers:**
- Regex Tester: live highlight, capture groups, replace mode, pattern library; regex evaluation always in `Task.detached` with 2s timeout and 300ms debounce
- Color Converter: HEX/RGB/HSL/HSV + OKLCH (ChromaKit) + NSColorSampler screen picker + WCAG AA/AAA contrast checker; out-of-gamut warning badge for OKLCH
- Markdown Previewer: split live preview, GFM (swift-markdown to WKWebView), syntax highlighting in editor; HTML export; PDF export deferred to Phase 2.1 (styling-polish intensive)
- Number Base Converter: bin/oct/dec/hex simultaneous + bit-width selector + signed/unsigned + clickable 8-bit bit-field UI; canonical `UInt64` internal representation with overflow indicator for signed edge cases
- Text Diff Viewer: line-level (CollectionDifference native) + word-level within changed lines (SwiftDiff) + unified/side-by-side toggle + patch export
- JSONPath tab within JSON Formatter (using Sextant package; moved from Phase 1)
- UUID v7 generation + timestamp inspection (if deferred from Phase 1)

**Avoids:** Regex catastrophic backtracking (background task + timeout), OKLCH gamut clamping without warning, Number Base two's complement overflow without indicator, WKWebView XSS via raw HTML (swift-markdown AST to controlled HTML emission only; JS disabled in WKWebViewConfiguration unless required).

**Research flag:** Regex Tester and OKLCH conversion may benefit from a focused research spike at phase-planning time. The timeout strategy for NSRegularExpression vs Swift `Regex` has tradeoffs worth a 30-minute review. OKLCH conversion correctness needs a reference-implementation test vector.

---

### Phase 3: Polish and Distribution

**Rationale:** Phase 3 delivers the app to users. Add Sparkle only now — no-op until there is a v1.0 to update from. Set up the notarization pipeline early in this phase, not as a last step.

**Delivers:**
- macOS Services menu integration (`NSServicesProvider` in `AppDelegate` routing selected text via `ToolRegistry.detect()`)
- Drag & drop universal handler for text and binary files into all tools
- `.dmg` packaging: Xcode Archive to Developer ID sign to `create-dmg 8.1.0` to `xcrun notarytool submit` to `xcrun stapler staple`
- Auto-update via Sparkle 2.9.3 with EdDSA signing; EdDSA keypair generated and embedded in `Info.plist` before v1.0 ships; validate v0.0.1 to v0.0.2 pipeline locally first
- Onboarding flow
- VoiceOver audit: all `NSViewRepresentable` wrappers pass Accessibility Inspector check for `AXLabel`, `AXRole`, `AXPlaceholderValue`

**Avoids:** Notarization failure from `get-task-allow` in Release entitlements (dual entitlements files); Sparkle EdDSA key mismatch that locks v1.0 users out of auto-update.

**Research flag:** Standard patterns — Sparkle and notarytool have comprehensive official documentation.

---

### Phase Ordering Rationale

- Infrastructure before tools because `ToolDefinition` shape affects every subsequent file. A shape change after 7 tools are built costs 28+ file edits.
- JSON Formatter first among tools because it exercises the most paths: editable NSTextView, clipboard JSON detection, history write, search match. It is a complete integration test of the pipeline.
- Phase 2 extended tools after Phase 1 because they all depend on the predicate chain and history infrastructure being stable. The Color Converter also depends on ChromaKit being added to SPM, which is a non-trivial package addition.
- Sparkle and distribution last because they require an app version to exist and are entirely decoupled from the tool layer.

### Research Flags

Phases needing deeper research during planning:
- **Phase 2 (Regex Tester):** NSRegularExpression timeout strategy vs Swift `Regex` PEG engine tradeoffs; evaluate at Phase 2 planning time
- **Phase 2 (OKLCH):** Correctness validation of ChromaKit's OKLCH conversion against Evil Martians reference picker; add test vectors before marking done
- **Phase 1 (UUID v7 package):** Evaluate `nthState/UUIDV7` vs alternatives before Phase 1 sprint start; gate v7 feature on this decision

Phases with well-documented standard patterns (skip research-phase):
- **Phase 1 infrastructure:** GRDB, KeyboardShortcuts, MenuBarExtraAccess, activation-policy dance — all have exact implementation guidance in ARCHITECTURE.md and PITFALLS.md
- **Phase 1 tool layer:** All 6 remaining tools (Base64, URL, JWT, Timestamp, Hash, UUID v4/v5) follow an identical 4-file pattern proven by the JSON Formatter integration test
- **Phase 3:** Sparkle 2.9.3 EdDSA signing, notarytool, create-dmg 8.1.0 — comprehensive official documentation

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All package picks verified against current GitHub releases and official docs on 2026-06-25; version numbers confirmed |
| Features | HIGH | Competitor analysis based on live product pages for DevToys v2, DevUtils 47 tools, Wring, Boop; PRD scope corrections confirmed by complexity analysis |
| Architecture | HIGH | All critical patterns verified against Apple official docs and open-source macOS menubar apps; `@Observable` / `.environment()` patterns confirmed against Context7 |
| Pitfalls | HIGH | All 18 pitfalls verified against official Apple docs, community post-mortems (steipete 5-hour session), or official package repos |

**Overall confidence:** HIGH

### Gaps to Address

- **UUID v7 Swift package choice:** `nthState/UUIDV7` and `leodabus/UUIDv7` are the leading candidates but have not been benchmarked or stress-tested. Evaluate at Phase 1 sprint start; fall back to Phase 2 if vetting takes more than half a day.
- **MenuBarExtraAccess vs NSStatusItem decision:** STACK.md marks this as "conditional — evaluate first." Recommendation: start with `MenuBarExtra` + `MenuBarExtraAccess`. If programmatic control needs exceed what `MenuBarExtraAccess` provides, escalate to `NSStatusItem` + `NSPopover` — but this abandons SwiftUI lifecycle management and should be the last resort.
- **Markdown PDF export polish:** `WKWebView.createPDF()` is the correct API, but CSS styling parity between the live preview and the exported PDF is polish-intensive. Included in Phase 2 but tagged as Phase 2.1 — implement HTML export first, add PDF after HTML export is verified.
- **NSPasteboardDidChangeNotification stability:** Using the private notification instead of polling is recommended for battery reasons. Verify the notification fires reliably on macOS 14 in integration testing; have the `DispatchSourceTimer` polling approach ready as a fallback.

## Sources

### Primary (HIGH confidence)
- KeyboardShortcuts GitHub (verified 2026-06-25): https://github.com/sindresorhus/KeyboardShortcuts — v3.0.1, Swift 6.2, zero permissions
- GRDB.swift GitHub releases (verified 2026-06-25): https://github.com/groue/GRDB.swift — v7.11.1, Xcode 16.3+, Swift 6 strict concurrency
- Highlightr deprecation notice (verified 2026-06-25): https://github.com/raspu/Highlightr — deprecated, maintainer recommends HighlightSwift
- HighlightSwift GitHub (verified 2026-06-25): https://github.com/appstefan/HighlightSwift — v1.1.0
- swift-markdown GitHub (verified 2026-06-25): https://github.com/swiftlang/swift-markdown — v0.8.0, Apple-backed, cmark-gfm
- ChromaKit GitHub (verified 2026-06-25): https://github.com/HarshilShah/ChromaKit — v0.1.1, OKLCH + NSColor
- Sparkle GitHub (verified 2026-06-25): https://github.com/sparkle-project/Sparkle — v2.9.3, EdDSA signing
- create-dmg GitHub (verified 2026-06-25): https://github.com/sindresorhus/create-dmg — v8.1.0
- Apple Developer Docs — MenuBarExtra: https://developer.apple.com/documentation/SwiftUI/MenuBarExtra
- Apple Developer Docs — SMAppService: https://developer.apple.com/documentation/servicemanagement/smappservice
- Apple Developer Docs — NSColorSampler: zero permissions, macOS 10.15+
- Apple Feedback FB10185203 (MenuBarExtra no dismiss): https://github.com/feedback-assistant/reports/issues/383
- MenuBarExtraAccess (programmatic dismiss): https://github.com/orchetect/MenuBarExtraAccess
- Peter Steinberger — activation policy 5-hour post-mortem (2025): https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items
- SwiftData macOS 14 bugs: https://mjtsai.com/blog/2024/06/04/swiftdata-issues-in-macos-14-and-ios-17/
- Apple — Customizing the Notarization Workflow (notarytool): https://developer.apple.com/documentation/security/customizing-the-notarization-workflow
- RFC 9562 UUID v7 (May 2024): https://www.rfc-editor.org/rfc/rfc9562

### Secondary (MEDIUM confidence)
- DevToys v2 GitHub — built-in tool list: https://github.com/DevToys-app/DevToys
- DevUtils.app official site — 47+ tools list: https://devutils.com/
- Wring macOS app — 12 tools list: https://getwring.app/
- Boop GitHub — feature list: https://github.com/IvanMathy/Boop
- Evil Martians — OKLCH in CSS, gamut behavior: https://evilmartians.com/chronicles/oklch-in-css-why-quit-rgb-hsl
- Snyk — ReDoS and catastrophic backtracking: https://snyk.io/blog/redos-and-catastrophic-backtracking/
- Swift Forums — base64 urlencoding / Data(base64Encoded:) behavior: https://forums.swift.org/t/pitch-adding-base64-urlencoding-and-omitting-padding-options-to-base64-encoding-and-decoding/77659
- Sparkle Discussion #2597 — EdDSA DMG signing pitfalls: https://github.com/sparkle-project/Sparkle/discussions/2597
- PlainPasta/PasteboardMonitor.swift — DispatchSourceTimer clipboard polling: https://github.com/hisaac/PlainPasta/blob/main/PlainPasta/PasteboardMonitor.swift
- Alexey Naumov — Clean Architecture for SwiftUI: https://nalexn.github.io/clean-architecture-swiftui/

### Tertiary (LOW confidence)
- SwiftDiff (turbolent) — no semver, Oct 2024 last commit; functionally complete for the word-level diff use case but lightly maintained
- NSPasteboardDidChangeNotification — private notification; behavior verified by community reports but not official documentation; have polling fallback ready

---
*Research completed: 2026-06-25*
*Ready for roadmap: yes*
