# Phase 1: Infrastructure + Core Tools — Research

**Researched:** 2026-06-25
**Domain:** Native macOS SwiftUI + MVVM menubar app — greenfield Xcode project scaffold, MenuBarExtra popover, ToolRegistry abstraction, GRDB history, seven core tool transformers
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**D-01:** Search-first launcher. Popover (~480×600) opens with autofocused search field at top, a row of 6 pinned tools below it, and recent history filling the body when search is empty. (Raycast/Spotlight feel.)

**D-02:** Search bar stays pinned at top even inside a tool view — typing there filters/switches tools. No explicit back button; navigation is search-driven.

**D-03:** Esc is two-stage: first Esc returns from tool to launcher (empty search + pinned + recent); second Esc closes the popover. Wire via MenuBarExtraAccess `isPresented` binding — `@Environment(\.dismiss)` does not work for MenuBarExtra.

**D-04:** Detection surfaces as non-destructive banner ("Detected: JWT — Open JWT Decoder?") with manual Accept/Dismiss. Does NOT auto-open the tool. Banner sits between search bar and pinned row.

**D-05:** Always re-show banner on focus when clipboard matches, even after prior dismissal. No per-value dismissal tracking.

**D-06:** Single best match only. Ordered predicate chain (JSON → JWT → Base64 → URL-encoded → URL → timestamp → hex color → UUID → regex) is first-match-wins. Banner shows one suggestion. No alternate chips.

**D-07:** Full history is a first-class view reachable via search ("history") or pinned/quick slot. Opens dedicated full-list view (last 100) with filter/search, pins, delete.

**D-08:** Clicking a history item restores saved input into matched tool and re-runs transform live. Output in the row is preview-only — always recomputed.

**D-09:** Pinned history items are exempt from 100-item eviction cap and sort to top. "Clear" removes unpinned items only. Individual delete works on any item.

**D-10:** Live, debounced transform (~150ms) for lightweight tools (JSON, Base64, URL, JWT, Timestamp, UUID-inspect). Heavy ops stay button-triggered: file hashing (HASH-02), bulk UUID generation up to 1000 (UUID-01), file Base64 (B64-04).

**D-11:** Graceful inline errors that never blank output. On malformed input mid-typing, show inline error (with line:column for JSON per JSON-03) while keeping last valid output visible but dimmed. No flicker-to-empty while typing.

**D-12:** Per-field copy buttons on every output field/row (each hash, each timezone, each URL component, each generated UUID), plus a primary "Copy output" / "Copy all" for the main result.

**D-13:** Default pinned tools (6): JSON, Base64, JWT, URL, Timestamp, UUID. Hash is unpinned by default (still searchable).

### Claude's Discretion

- Exact debounce timing (within ~150ms guidance), banner animation/transition style, icon choices (SF Symbols per ToolDefinition), spacing, visual treatment of "dimmed last-good output" — consistent with macOS HIG and Light/Dark/accent support (INFRA-14).
- Whether History first-class view occupies a default pinned slot or is search-only (D-13 fills all 6 pins with tools; History reachable via search regardless).

### Deferred Ideas (OUT OF SCOPE)

- JSONPath tab — Phase 2
- JSON semantic diff — Phase 2
- UUID v7 (UUID-02) — gated on package vetting; move to Phase 2 if unresolved within half a day
- App Store sandboxing — Phase 2

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| INFRA-01 | Menubar app via MenuBarExtra, compact popover ~480×600 | MenuBarExtra `.window` style; MenuBarExtraAccess `isPresented` for programmatic dismiss |
| INFRA-02 | Detachable workspace window (min 800×600); tool remembers mode | WindowGroup + WindowCoordinator activation-policy dance |
| INFRA-03 | ToolDefinition/ToolRegistry abstraction (id, name, category, keywords, SF Symbol, detection predicate, view factory) | Pattern 2 in ARCHITECTURE.md; freeze shape before any tool work |
| INFRA-04 | Global hotkey ⌘⇧Space, configurable, no Accessibility prompt | KeyboardShortcuts 3.0.1; Carbon `RegisterEventHotKey` |
| INFRA-05 | Auto-detect clipboard → non-destructive banner (manual accept/dismiss) | ClipboardDetector + DetectionBannerView; D-04/D-05 |
| INFRA-06 | Detection predicate chain fires within 100ms of focus | DispatchSourceTimer on background queue; NSPasteboardDidChangeNotification alternative |
| INFRA-07 | Persist last 100 transformations locally across restarts | GRDB 7.11.1 DatabaseQueue + DatabaseMigrator |
| INFRA-08 | History searchable, re-openable, pin/delete/clear | GRDB SQL LIKE; ValueObservation for reactive updates; D-07..D-09 |
| INFRA-09 | History never persists JWT HMAC keys or HMAC hash keys | Schema design: per-tool serialization excludes secret fields; Pitfall #11 |
| INFRA-10 | Global fuzzy search (tools + history), keyboard navigable ↑↓ Enter | ToolRegistry.search() + GRDB LIKE query |
| INFRA-11 | Pin up to 6 tools, drag-to-reorder; defaults per D-13 | PreferencesStore (UserDefaults) stores ordered pinned tool IDs |
| INFRA-12 | Preferences window ⌘, (General, Appearance, History, per-tool) | WindowCoordinator activation dance for Settings scene; openSettings() broken on macOS 14 with .accessory |
| INFRA-13 | Prefs: launch at login (SMAppService), show-in-Dock, hotkey, open mode, clipboard auto-detect, theme, font, font size, history limits | SMAppService.mainApp.register() / .unregister() |
| INFRA-14 | Light/Dark mode + system accent color, zero visual artifacts | @Environment(\.colorScheme); SwiftUI native |
| INFRA-15 | VoiceOver labels all interactive elements; Dynamic Type | NSViewRepresentable: setAccessibilityLabel() + setAccessibilityRole() on AppKit side |
| INFRA-16 | All documented keyboard shortcuts work | KeyboardShortcuts + SwiftUI .keyboardShortcut() |
| INFRA-17 | No tool crashes on malformed/oversized/invalid-UTF-8 input | Pure Transformer layer returns Result<Output, Error>; never force-unwrap |
| INFRA-18 | Cold start <500ms, hotkey-to-popover <200ms, <100MB RAM | Lazy ViewModel init; GRDB open off main thread; WKWebView deferred |
| JSON-01 | Pretty-print with configurable indent (2, 4, tab) | JSONSerialization with .prettyPrinted; custom indent via string replacement |
| JSON-02 | Minify JSON | JSONSerialization without .prettyPrinted |
| JSON-03 | Real-time validation, inline error with line + column | Parse NSError character offset → compute line/col by scanning prefix |
| JSON-04 | Sort keys alphabetically (toggle) | JSONSerialization `.sortedKeys` option |
| JSON-05 | JSON syntax highlighting | Custom NSTextStorage subclass (editable); HighlightSwift 1.1.0 (display-only output) |
| JSON-06 | Copy formatted output one click | D-12 CopyButtonView; UIPasteboard / NSPasteboard |
| B64-01 | Encode text → Base64, decode Base64 → text | Foundation Data.base64EncodedString() / Data(base64Encoded:) |
| B64-02 | URL-safe variant (-/_), padding handled | Character substitution + padding before decode; encode with custom options |
| B64-03 | Auto-detect encode vs decode direction | Heuristic: all chars in Base64 alphabet + length multiple of 4 → decode |
| B64-04 | Encode dropped file to Base64; decode Base64 to saved file | NSOpenPanel (read) / NSSavePanel (write); chunked read for large files |
| B64-05 | Show decoded byte length + character count | Swift String.count; Data.count |
| URL-01 | Percent-encode for query params; decode percent-encoded strings | Foundation addingPercentEncoding(withAllowedCharacters:) / removingPercentEncoding |
| URL-02 | Parse full URL → scheme, host, path, query params, fragment | URLComponents |
| URL-03 | Edit query params (add/delete key-value table), rebuild URL | URLComponents.queryItems mutate + .url |
| URL-04 | Copy individual URL components | D-12 per-field copy |
| JWT-01 | Decode JWT → header, payload, signature; base64url correct | Custom base64url decoder (char subst + pad); split on "." |
| JWT-02 | Header + payload as pretty-printed JSON | JSONSerialization + JSONTransformer.prettyPrint |
| JWT-03 | Expiry (exp) as human-readable date + countdown; timezone-correct | Date(timeIntervalSince1970:); DateComponentsFormatter relative |
| JWT-04 | Verify signature with supplied secret (HMAC-SHA256/384/512); secret NOT written to history | CryptoKit HMAC<SHA256/384/512>.authenticationCode; secret excluded from HistoryEntry.input by design |
| JWT-05 | Claims table: standard vs custom claims; algorithm display | alg from header; partition claim keys against known set |
| JWT-06 | Warning banners: expired, alg:none, missing standard claims | Logic in JWTTransformer |
| TS-01 | Convert Unix timestamp (s or ms, auto-detected) to human-readable date | Date(timeIntervalSince1970:); digit-count heuristic + boundary validation |
| TS-02 | Show date across local, UTC, additional timezones | TimeZone; DateFormatter with timeZone |
| TS-03 | Reverse-convert picked date/time to Unix timestamp | DatePicker binding → Date.timeIntervalSince1970 |
| TS-04 | "Now" button inserts current timestamp; relative time display | Date(); RelativeDateTimeFormatter |
| TS-05 | ISO 8601 output format option | ISO8601DateFormatter |
| HASH-01 | MD5, SHA-1, SHA-256, SHA-384, SHA-512, CRC32 simultaneously | CryptoKit (SHA); CommonCrypto CC_MD5; zlib crc32() |
| HASH-02 | Drop file → hash without blocking UI | FileHandle chunked read in Task.detached; progress publish |
| HASH-03 | HMAC mode with secret key; key NOT written to history | CryptoKit HMAC<SHA256/384/512>; secret excluded from HistoryEntry |
| HASH-04 | Toggle uppercase/lowercase; copy individual hash | D-12 per-field copy; String.uppercased() |
| UUID-01 | Generate single or bulk UUIDs (up to 1000) v1/v4/v5; button-triggered for bulk | UUID() for v4; external package for v1/v5 (uuid-kit or similar) |
| UUID-02 | v7 time-ordered UUIDs — gated on package vetting | nthState/UUIDV7 (10 stars, no semver releases) — HIGH risk; defer to Phase 2 |
| UUID-03 | Parse/inspect UUID — version, variant, embedded timestamp (v1/v7), component breakdown | Bit-mask extraction; RFC 9562 layout |
| UUID-04 | Export bulk UUIDs to clipboard (newline) or CSV/JSON; uppercase/lowercase toggle | NSPasteboard; String join |

</phase_requirements>

---

## Summary

Phase 1 creates a greenfield Xcode project from nothing and delivers the complete "clipboard-detect → transform → history → search" pipeline, proven end-to-end through the JSON Formatter before the remaining six tools are added. The architecture, stack, and pitfalls are fully settled in SUMMARY.md. This research document focuses on the **implementation-ready specifics** the planner needs: exact API patterns, the walking-skeleton slice, per-tool native API recipes, pitfall remediation code, and debounce/error UX mechanics.

The environment is Xcode 26.5 / Swift 6.3.2 — both exceed GRDB 7's Xcode 16.3+ requirement. All packages have been verified at their locked versions (GRDB 7.11.1, KeyboardShortcuts 3.0.1, HighlightSwift 1.1.0, swift-markdown 0.8.0, MenuBarExtraAccess 1.3.0). Foundation does NOT generate UUID v1, v5, or v7 natively; external packages are required for those versions — UUID v7 is HIGH risk (leading candidate nthState/UUIDV7 has 10 stars and no semver releases) and must be gated.

The walking skeleton is: project scaffold → FlintApp with empty MenuBarExtra → HistoryStore opens (async) → ToolRegistry initialised with one stub → ClipboardDetector wired → HotkeyManager registered → JSONTransformer (pure) → JSONFormatterViewModel (live debounced + last-good-output-dimmed error) → JSONFormatterView → history row appears → search finds it. Everything after that is repetition of the 4-file tool pattern.

**Primary recommendation:** Build in strict infra-first order (steps 1–11 from ARCHITECTURE.md). Do not start any tool until the registry, history store, clipboard detector, hotkey manager, and popover shell are wired and the app launches with no crash on blank input. Use JSON Formatter as the integration test. Gate UUID v7 (UUID-02) as a separate one-day spike; if no sound package is found by day 1, defer to Phase 2 with a documented stub.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Global hotkey registration | App (HotkeyManager) | — | Cross-app event; must live at app startup, not inside any view |
| Clipboard detection + predicate chain | App (ClipboardDetector) | Core Services (ToolRegistry) | Background actor polls NSPasteboard; ToolRegistry owns predicate definitions |
| Detection banner display | Frontend (MenuBarPopoverView) | — | Non-destructive UI element in launcher; accepts/dismisses |
| Tool navigation / search | Frontend (MenuBarPopoverView + SearchView) | Core Services (ToolRegistry) | ToolRegistry provides ordered data; view drives navigation |
| Transform logic (JSON, B64, URL, JWT, TS, Hash, UUID) | Tools (Transformer layer — pure structs, no UI) | — | Must be testable without any UI or AppKit imports |
| Transform orchestration + debounce | Tools (ViewModel layer — @Observable) | — | Owns timer/Task lifecycle; calls Transformer; invokes history closure |
| History write | Tools (ViewModel layer) via injected closure | — | ViewModel calls onSaveHistory(); never imports GRDB directly |
| History storage + reactive reads | Infrastructure (GRDB DatabaseQueue) | Core Services (HistoryStore wrapper) | SQLite persistence; ValueObservation fires on @MainActor |
| Preferences persistence | Infrastructure (UserDefaults) | Core Services (PreferencesStore) | Simple key-value; no SQL needed |
| Popover dismiss / two-stage Esc | App (MenuBarExtraAccess isPresented) | Frontend view | @Environment(\.dismiss) does not work; isPresented binding is the only path |
| Window mode / activation policy | App (WindowCoordinator) | — | NSApp.setActivationPolicy must toggle around every window open/close |
| Syntax highlighting (editable editor) | Tools (custom NSTextStorage subclass) | — | No package works for editable NSTextView; must own NSTextStorageDelegate |
| Syntax highlighting (display-only) | Tools (HighlightSwift 1.1.0) | — | AttributedString output; usable in SwiftUI Text |
| Launch at login | App (SMAppService) | — | Apple-only API; macOS 13+ |

---

## Standard Stack

### Core (Phase 1 only — Swift packages needed immediately)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| GRDB.swift | 7.11.1 [VERIFIED: github.com/groue/GRDB.swift] | SQLite history store | SwiftData has critical macOS 14 bugs; only option with typed queries + ValueObservation + migrations |
| KeyboardShortcuts | 3.0.1 [VERIFIED: github.com/sindresorhus/KeyboardShortcuts] | Global hotkey, zero permissions | CGEventTap requires Accessibility dialog; Carbon RegisterEventHotKey needs no entitlement |
| MenuBarExtraAccess | 1.3.0 [VERIFIED: github.com/orchetect/MenuBarExtraAccess] | Programmatic popover dismiss | MenuBarExtra has no 1st-party dismiss API (FB10185203 open since 2022) |
| HighlightSwift | 1.1.0 [VERIFIED: github.com/appstefan/HighlightSwift] | Display-only syntax highlight | Highlightr deprecated 2026; HighlightSwift is the official replacement |

### Native Frameworks (no packages needed)

| Framework | Purpose | Key APIs |
|-----------|---------|----------|
| SwiftUI + @Observable (macOS 14) | Primary UI, MenuBarExtra, property-level re-render | `MenuBarExtra`, `@Observable`, `.environment()` |
| Foundation | JSON, Base64, URL encoding, UUID v4, Date/Timezone | `JSONSerialization`, `Data.base64EncodedString()`, `URLComponents`, `UUID()`, `DateFormatter`, `ISO8601DateFormatter` |
| CryptoKit (macOS 10.15+) | SHA-1/256/384/512, HMAC | `SHA256.hash()`, `HMAC<SHA256>.authenticationCode()` |
| CommonCrypto / zlib | MD5 (CC_MD5), CRC32 (crc32()) | Link `libz.tbd`; `import CommonCrypto` |
| AppKit | NSTextView editor, clipboard, windows | `NSTextView`, `NSPasteboard`, `NSStatusItem`, `NSColorSampler` |
| ServiceManagement | Launch at login | `SMAppService.mainApp.register()` / `.unregister()` |

### Phase 2 only (DO NOT add in Phase 1)

| Library | Version | Purpose |
|---------|---------|---------|
| swift-markdown | 0.8.0 [VERIFIED: github.com/swiftlang/swift-markdown] | GFM Markdown AST → HTML → WKWebView |
| ChromaKit | 0.1.1 [VERIFIED: github.com/HarshilShah/ChromaKit] | OKLCH ↔ NSColor (no native API) |
| SwiftDiff | Oct 2024 commit [VERIFIED: github.com/turbolent/SwiftDiff] | Word-level diff within changed lines |

### Phase 3 only

| Library | Version | Purpose |
|---------|---------|---------|
| Sparkle | 2.9.3 [VERIFIED: github.com/sparkle-project/Sparkle] | Auto-update (EdDSA-signed appcast) |

### Installation (Phase 1 packages only)

```
# Add via Xcode → File → Add Package Dependencies
GRDB.swift:         https://github.com/groue/GRDB.swift.git          (exact: 7.11.1)
KeyboardShortcuts:  https://github.com/sindresorhus/KeyboardShortcuts (exact: 3.0.1)
MenuBarExtraAccess: https://github.com/orchetect/MenuBarExtraAccess    (exact: 1.3.0)
HighlightSwift:     https://github.com/appstefan/HighlightSwift        (exact: 1.1.0)

# CommonCrypto/zlib: no SPM entry needed
# Xcode → Build Phases → Link Binary With Libraries → add libz.tbd
# Then: import CommonCrypto  (or import zlib for CRC32)
```

---

## Package Legitimacy Audit

> slopcheck could not be installed in this environment. All packages below are marked with provenance tags based on manual verification via GitHub API and official documentation.

| Package | Registry | Age | Downloads/Stars | Source Repo | slopcheck | Disposition |
|---------|----------|-----|-----------------|-------------|-----------|-------------|
| GRDB.swift 7.11.1 | GitHub/SPM | 9+ yrs | 8.5k stars | github.com/groue/GRDB.swift | N/A — manual [VERIFIED: GitHub API] | Approved |
| KeyboardShortcuts 3.0.1 | GitHub/SPM | 5+ yrs | 5k+ stars | github.com/sindresorhus/KeyboardShortcuts | N/A — manual [VERIFIED: GitHub API] | Approved |
| MenuBarExtraAccess 1.3.0 | GitHub/SPM | 2+ yrs | 500+ stars | github.com/orchetect/MenuBarExtraAccess | N/A — manual [VERIFIED: GitHub API] | Approved |
| HighlightSwift 1.1.0 | GitHub/SPM | 2+ yrs | 400+ stars | github.com/appstefan/HighlightSwift | N/A — manual [VERIFIED: GitHub API] | Approved |
| nthState/UUIDV7 | GitHub/SPM | ~1-2 yrs | 10 stars | github.com/nthState/UUIDV7 | N/A — [ASSUMED] | **FLAGGED — do not add without human vetting** |

**Packages removed due to slopcheck [SLOP] verdict:** none (slopcheck unavailable; all packages are [ASSUMED] as far as slopcheck is concerned)

**Packages flagged for human review:** `nthState/UUIDV7` — 10 stars, no semver releases, unknown maintenance status. Planner must gate UUID-02 behind a `checkpoint:human-verify` task and default to Phase 2 deferral.

---

## Architecture Patterns

### System Architecture Diagram

```
User (hotkey / menubar click)
       │
       ▼
HotkeyManager ──────────────► MenuBarExtra (.window style)
                                      │
                            MenuBarPopoverView
                            ┌──────────────────┐
                            │  SearchBar (D-01) │ ◄── focus triggers ClipboardDetector
                            │  DetectionBanner  │     (shows non-destructive suggestion)
                            │  PinnedToolsRow   │
                            │  RecentHistory    │
                            └──────────────────┘
                                      │ user selects tool
                                      ▼
                            WindowCoordinator
                            (activation-policy toggle)
                                      │
                            MainWindowView (WindowGroup)
                            ┌──────────────────────────┐
                            │  Sidebar (ToolRegistry)  │
                            │  ToolContentArea         │
                            │    *View → *ViewModel    │
                            │          │               │
                            │     *Transformer         │
                            │    (pure, no UI)         │
                            │          │               │
                            │    HistoryEntry          │
                            │          │               │
                            └──────────┼───────────────┘
                                       ▼
                               HistoryStore (GRDB)
                               ~/Library/Application Support/Flint/history.db
                                       │
                               ValueObservation ──► HistoryPanelView
```

Data flows:
- Clipboard change → ClipboardDetector (background) → DetectionResult? → banner
- User input → ToolView → ToolViewModel.transform() → Transformer → Result<Output, Error>
- ViewModel (on success) → onSaveHistory closure → HistoryStore.save() → GRDB INSERT
- GRDB ValueObservation → @MainActor → HistoryPanelView re-renders

### Recommended Project Structure

```
Flint/
├── App/
│   ├── FlintApp.swift              ← @main; @State services; .environment() injection
│   ├── WindowCoordinator.swift     ← NSActivationPolicy switching
│   └── AppDelegate.swift           ← @NSApplicationDelegateAdaptor (Phase 3: Services)
│
├── Core/
│   ├── Services/
│   │   ├── ToolRegistry.swift      ← [ToolDefinition]; search(); detect()
│   │   ├── HistoryStore.swift      ← GRDB DatabaseQueue wrapper; ValueObservation
│   │   ├── ClipboardDetector.swift ← DispatchSourceTimer background; publishes DetectionResult?
│   │   ├── HotkeyManager.swift     ← KeyboardShortcuts registration
│   │   └── PreferencesStore.swift  ← @Observable UserDefaults wrapper
│   │
│   ├── Models/
│   │   ├── ToolDefinition.swift    ← struct; id, name, category, keywords, sfSymbol, detectionPredicate, makeView
│   │   ├── HistoryEntry.swift      ← Codable + FetchableRecord + PersistableRecord
│   │   ├── DetectionResult.swift   ← struct; toolId, confidence, sample
│   │   └── ToolCategory.swift      ← enum; Encoding, Formatting, Conversion, Generation, Analysis
│   │
│   └── Extensions/
│       ├── Data+Base64URL.swift    ← base64url decode (JWT pitfall fix)
│       └── View+CopyButton.swift   ← .copyButton(text:) modifier
│
├── Tools/
│   ├── JSONFormatter/
│   │   ├── JSONFormatterDefinition.swift
│   │   ├── JSONFormatterViewModel.swift
│   │   ├── JSONFormatterView.swift
│   │   └── JSONTransformer.swift           ← NO SwiftUI/AppKit imports
│   ├── Base64/       (same 4-file pattern)
│   ├── URLEncoder/   (same 4-file pattern)
│   ├── JWT/          (same 4-file pattern)
│   ├── Timestamp/    (same 4-file pattern)
│   ├── Hash/         (same 4-file pattern)
│   └── UUID/         (same 4-file pattern)
│
├── UI/
│   ├── MenuBarPopoverView.swift
│   ├── MainWindowView.swift
│   ├── SearchView.swift
│   ├── HistoryPanelView.swift
│   ├── PreferencesView.swift
│   └── Components/
│       ├── DetectionBannerView.swift
│       ├── CopyButtonView.swift
│       ├── SyntaxEditorView.swift    ← NSViewRepresentable wrapping NSTextView
│       └── CodeDisplayView.swift     ← HighlightSwift AttributedString display
│
└── Resources/
    ├── Assets.xcassets
    ├── Flint-debug.entitlements    ← includes get-task-allow
    └── Flint-release.entitlements  ← NO get-task-allow; Hardened Runtime
```

### Pattern 1: FlintApp — Service Ownership and Injection

**What:** All shared services are `@State` in the `App` struct — the only lifecycle-stable ownership point. Services are injected into all scenes via `.environment()`. Tool ViewModels are NOT held here; they are created on-demand per navigation destination.

```swift
// App/FlintApp.swift
// Source: ARCHITECTURE.md + Apple Developer Docs — @Observable + .environment() [VERIFIED]
@main
struct FlintApp: App {
    @State private var historyStore = HistoryStore()
    @State private var prefs = PreferencesStore()
    @State private var clipboard = ClipboardDetector()
    @State private var hotkeyManager = HotkeyManager()
    @State private var toolRegistry = ToolRegistry()

    var body: some Scene {
        MenuBarExtra("Flint", systemImage: "wrench.and.screwdriver") {
            MenuBarPopoverView()
        }
        .menuBarExtraStyle(.window)
        .menuBarExtraAccess(isPresented: $clipboard.isPopoverPresented) { _ in }
        .environment(historyStore)
        .environment(prefs)
        .environment(clipboard)
        .environment(toolRegistry)

        WindowGroup(id: "workspace") {
            MainWindowView()
        }
        .environment(historyStore)
        .environment(prefs)
        .environment(clipboard)
        .environment(toolRegistry)

        Settings {
            PreferencesView()
        }
        .environment(prefs)
        .environment(hotkeyManager)
    }
}
```

**Note:** `openWindow` environment action is NOT available inside `MenuBarExtra` views. Use `NotificationCenter` to trigger workspace window opening from within the popover.

### Pattern 2: MenuBarExtraAccess — Two-Stage Esc (D-03)

**What:** MenuBarExtraAccess 1.3.0 exposes an `isPresented` binding. Wire it to an observable property on `ClipboardDetector` (or a dedicated `PopoverCoordinator`). Two-stage Esc:

1. If the user is inside a tool view: first Esc call navigates back to launcher (reset navigation state to `.root`).
2. If already at launcher: second Esc sets `isPresented = false` → popover closes.

```swift
// Wire the scene modifier (in FlintApp.swift)
// Source: MenuBarExtraAccess 1.3.0 README [VERIFIED: github.com/orchetect/MenuBarExtraAccess]
.menuBarExtraAccess(isPresented: $isPopoverPresented) { statusItem in
    // statusItem: NSStatusItem — use for additional configuration if needed
}

// Inside MenuBarPopoverView — intercept Esc via .onKeyPress or focusedValue
.onKeyPress(.escape) {
    if navigationState != .root {
        navigationState = .root   // first Esc: return to launcher
        return .handled
    }
    isPopoverPresented = false    // second Esc: close popover
    return .handled
}
```

**Critical:** Do NOT use `@Environment(\.dismiss)` — it has no effect inside `MenuBarExtra` windows. `isPresented = false` via MenuBarExtraAccess is the only reliable path. [VERIFIED: pitfall #1 in PITFALLS.md]

### Pattern 3: ToolDefinition / ToolRegistry

```swift
// Core/Models/ToolDefinition.swift
// Source: ARCHITECTURE.md — Pattern 2 [VERIFIED]
struct ToolDefinition: Identifiable {
    let id: String
    let name: String
    let category: ToolCategory
    let keywords: [String]
    let sfSymbol: String
    let detectionPredicate: ((String) -> DetectionResult?)?
    let makeView: () -> AnyView
}

// Core/Services/ToolRegistry.swift
@Observable
final class ToolRegistry {
    let tools: [ToolDefinition]

    init() {
        tools = [
            JSONFormatterDefinition.make(),
            Base64Definition.make(),
            URLEncoderDefinition.make(),
            JWTDefinition.make(),
            TimestampDefinition.make(),
            HashDefinition.make(),
            UUIDDefinition.make(),
        ]
    }

    func search(_ query: String) -> [ToolDefinition] {
        guard !query.isEmpty else { return tools }
        return tools.filter { tool in
            tool.name.localizedCaseInsensitiveContains(query) ||
            tool.keywords.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    // First-match-wins predicate chain (D-06)
    func detect(from string: String) -> DetectionResult? {
        for tool in tools {
            if let result = tool.detectionPredicate?(string) { return result }
        }
        return nil
    }
}
```

**Adding a Phase 2 tool:** append one `*Definition.make()` call in `ToolRegistry.init()`. No other file changes required.

### Pattern 4: GRDB History Store

```swift
// Core/Models/HistoryEntry.swift
// Source: GRDB documentation + STACK.md [VERIFIED: groue/GRDB.swift v7.11.1]
struct HistoryEntry: Codable, FetchableRecord, PersistableRecord, Sendable {
    var id: Int64?
    var tool: String
    var input: String       // NEVER includes HMAC/JWT secrets — enforced at ViewModel layer
    var output: String
    var timestamp: Date
    var pinned: Bool
}

// Core/Services/HistoryStore.swift
@Observable
final class HistoryStore {
    private(set) var dbQueue: DatabaseQueue?
    var entries: [HistoryEntry] = []
    private var observation: AnyDatabaseCancellable?

    init() {
        // Open GRDB off main thread — cold-start budget protection (Pitfall #4)
        Task.detached(priority: .utility) { [weak self] in
            let queue = try HistoryStore.openDatabase()
            await MainActor.run {
                self?.dbQueue = queue
                self?.startObservation(queue: queue)
            }
        }
    }

    private static func openDatabase() throws -> DatabaseQueue {
        let url = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask,
                 appropriateFor: nil, create: true)
            .appendingPathComponent("Flint/history.db")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let queue = try DatabaseQueue(path: url.path)
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "historyEntry") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("tool", .text).notNull()
                t.column("input", .text).notNull()
                t.column("output", .text).notNull()
                t.column("timestamp", .datetime).notNull()
                t.column("pinned", .boolean).notNull().defaults(to: false)
            }
            try db.create(index: "historyEntry_on_timestamp",
                          on: "historyEntry", columns: ["timestamp"])
        }
        try migrator.migrate(queue)
        return queue
    }

    private func startObservation(queue: DatabaseQueue) {
        // ValueObservation is @MainActor-friendly in GRDB 7 [VERIFIED: GRDB 7 migration guide]
        observation = ValueObservation
            .tracking { db in
                try HistoryEntry
                    .order(Column("pinned").desc, Column("timestamp").desc)
                    .limit(200)         // fetch slightly over 100 for eviction pass
                    .fetchAll(db)
            }
            .start(in: queue) { [weak self] error in
                // handle error
            } onChange: { [weak self] entries in
                // D-09: pinned items exempt from 100-item cap
                let pinned = entries.filter { $0.pinned }
                let unpinned = Array(entries.filter { !$0.pinned }.prefix(100))
                self?.entries = (pinned + unpinned).sorted {
                    if $0.pinned != $1.pinned { return $0.pinned }
                    return $0.timestamp > $1.timestamp
                }
            }
    }

    func save(_ entry: HistoryEntry) {
        guard let queue = dbQueue else { return }
        Task.detached(priority: .utility) {
            try await queue.write { db in
                var e = entry
                try e.insert(db)
            }
        }
    }

    func clearUnpinned() {
        guard let queue = dbQueue else { return }
        Task.detached(priority: .utility) {
            try await queue.write { db in
                try HistoryEntry.filter(Column("pinned") == false).deleteAll(db)
            }
        }
    }
}
```

### Pattern 5: Per-Tool MVVM — Debounce + Last-Good-Output-Dimmed Error (D-10, D-11)

The debounce and dimmed-output pattern are ViewModel concerns, not View concerns.

```swift
// Tools/JSONFormatter/JSONFormatterViewModel.swift
// Debounce actor pattern — Source: livsycode.com (MEDIUM confidence, Swift Concurrency approach)
actor Debounce: Sendable {
    private var task: Task<Void, Never>?
    func schedule(delay: Duration, action: @Sendable @escaping () async -> Void) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await action()
        }
    }
}

@Observable
@MainActor
final class JSONFormatterViewModel {
    var input: String = "" {
        didSet { scheduleTransform() }
    }
    var output: String = ""                 // always shows last good output
    var outputDimmed: Bool = false          // true while input is currently invalid (D-11)
    var errors: [JSONError] = []
    var indentSize: Int = 2

    private let onSaveHistory: (HistoryEntry) -> Void
    private let debounce = Debounce()

    init(onSaveHistory: @escaping (HistoryEntry) -> Void) {
        self.onSaveHistory = onSaveHistory
    }

    private func scheduleTransform() {
        Task {
            await debounce.schedule(delay: .milliseconds(150)) { [weak self] in
                await self?.runTransform()
            }
        }
    }

    private func runTransform() {
        switch JSONTransformer.prettyPrint(input, indent: indentSize) {
        case .success(let result):
            output = result
            outputDimmed = false
            errors = []
            onSaveHistory(HistoryEntry(
                tool: "json-formatter",
                input: input,
                output: result,
                timestamp: Date(),
                pinned: false
            ))
        case .failure(let error):
            // D-11: keep last valid output visible but dimmed
            outputDimmed = true
            errors = [error]
            // Do NOT clear output
        }
    }
}
```

### Pattern 6: Clipboard Detection Pipeline

```swift
// Core/Services/ClipboardDetector.swift
// Source: ARCHITECTURE.md Pattern 4 [VERIFIED] + Pitfall #18 avoidance
@Observable
@MainActor
final class ClipboardDetector {
    var detectionResult: DetectionResult? = nil
    var isEnabled: Bool = true
    var isPopoverPresented: Bool = false {   // wired to MenuBarExtraAccess isPresented
        didSet {
            if isPopoverPresented { checkPasteboard(force: true) }  // D-05: re-show on focus
        }
    }

    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var timer: DispatchSourceTimer?
    private weak var registry: ToolRegistry?

    func start(registry: ToolRegistry) {
        self.registry = registry
        // Poll only when popover is visible — Pitfall #18 avoidance
        // Alternative: observe NSPasteboardDidChangeNotification (0% idle CPU)
        // Decision: use both — notification for instant detection, timer as fallback
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pasteboardDidChange),
            name: NSNotification.Name("NSPasteboardDidChangeNotification"),
            object: nil
        )
    }

    @objc private func pasteboardDidChange() {
        guard isEnabled, isPopoverPresented else { return }
        checkPasteboard(force: false)
    }

    private func checkPasteboard(force: Bool) {
        let current = NSPasteboard.general.changeCount
        guard force || current != lastChangeCount else { return }
        lastChangeCount = current
        guard isEnabled,
              let string = NSPasteboard.general.string(forType: .string),
              !string.isEmpty else {
            detectionResult = nil
            return
        }
        detectionResult = registry?.detect(from: string)
    }
}
```

### Pattern 7: WindowCoordinator — Activation Policy Dance (Pitfall #2)

```swift
// App/WindowCoordinator.swift
// Source: PITFALLS.md Pitfall #2 + steipete.me post-mortem [VERIFIED]
final class WindowCoordinator: NSObject {
    static let shared = WindowCoordinator()
    private var windowCount = 0

    func openWorkspace() {
        windowCount += 1
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: .openWorkspace, object: nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        windowCount = max(0, windowCount - 1)
        if windowCount == 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}

// Preferences: openSettings() is broken on macOS 14 with .accessory policy.
// Use the same dance: setActivationPolicy(.regular) → activate → then open the Settings scene.
// SettingsLink and openSettings() both fail silently on macOS 14 from .accessory context.
```

### Pattern 8: NSTextView NSViewRepresentable Anti-Infinite-Loop Guard (Pitfall #5)

```swift
// UI/Components/SyntaxEditorView.swift
// Source: PITFALLS.md Pitfall #5 + Apple Developer Forums [VERIFIED]
struct SyntaxEditorView: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.setAccessibilityLabel("Code editor")
        textView.setAccessibilityRole(.textArea)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let textView = nsView.documentView as! NSTextView
        // CRITICAL: guard prevents infinite re-render loop
        guard textView.string != text else { return }
        let ranges = textView.selectedRanges
        textView.string = text
        textView.selectedRanges = ranges    // preserve cursor position
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            // Async dispatch breaks the synchronous update cycle
            DispatchQueue.main.async { self.text.wrappedValue = tv.string }
        }
    }
}
```

### Anti-Patterns to Avoid

- **ViewModel imports GRDB directly:** Makes testing impossible. Inject `onSaveHistory: (HistoryEntry) -> Void` at init.
- **Tool state shared between popover and workspace window:** Each navigation destination creates its own ViewModel instance. Shared state is only in the four app-level services.
- **@Environment(\.dismiss) for MenuBarExtra:** Silently does nothing. Use MenuBarExtraAccess `isPresented = false`.
- **Clipboard polling as a global background timer:** Drains battery. Use NSPasteboardDidChangeNotification + visibility gate.
- **GRDB open on main thread:** Causes launch stutter. Use `Task.detached(priority: .utility)`.
- **Data(base64Encoded:) directly on JWT segments:** Returns nil for tokens with `-` or `_`. Use base64url decoder.
- **NSApp.setActivationPolicy(.regular) permanently:** Shows Dock icon at all times. Toggle only during window open/close.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Global hotkey | CGEventTap wrapper | KeyboardShortcuts 3.0.1 | CGEventTap triggers Accessibility permission dialog |
| Popover dismiss | AppKit NSWindow introspection | MenuBarExtraAccess `.isPresented` | No public API; introspection is fragile across OS updates |
| SQLite persistence | Raw sqlite3 C API | GRDB 7.11.1 `FetchableRecord` + `PersistableRecord` | Type safety, migrations, ValueObservation — 500+ lines of boilerplate avoided |
| SHA-256/384/512 hashing | Manual byte manipulation | `CryptoKit.SHA256.hash()` | System-library, FIPS-compliant, zero deps |
| HMAC verification | Manual HMAC implementation | `CryptoKit.HMAC<SHA256>` | Constant-time comparison, correct key handling |
| Base64url decode for JWT | Custom decoder from scratch | `Data+Base64URL.swift` utility (5 lines, see Code Examples) | Reuse same pattern across JWT and B64 tools |
| Launch at login | LSSharedFileList (removed) / SMLoginItemSetEnabled (deprecated) | SMAppService.mainApp.register() | Only Apple-supported API on macOS 13+ |

**Key insight:** The tool layer must contain zero cryptographic primitives — all hashing lives in `*Transformer.swift` calling system frameworks. No custom hash algorithms, no custom base64 implementations beyond the 5-line base64url adapter.

---

## Native API Recipes (Per-Tool)

### JSON Tool (JSON-01..06)

```swift
// JSONTransformer.swift — Source: Apple Foundation JSONSerialization [VERIFIED]
enum JSONTransformer {
    struct JSONError: Error {
        let message: String
        let line: Int?
        let column: Int?
    }

    // JSON-01: Pretty-print
    static func prettyPrint(_ input: String, indent: Int) -> Result<String, JSONError> {
        guard let data = input.data(using: .utf8) else {
            return .failure(JSONError(message: "Invalid UTF-8", line: nil, column: nil))
        }
        do {
            let obj = try JSONSerialization.jsonObject(with: data)
            let options: JSONSerialization.WritingOptions = [.prettyPrinted]
            let output = try JSONSerialization.data(withJSONObject: obj, options: options)
            var str = String(data: output, encoding: .utf8) ?? ""
            // Replace 4-space indent with requested indent
            if indent == 2 { str = str.replacingOccurrences(of: "    ", with: "  ") }
            if indent == 0 { str = str.replacingOccurrences(of: "    ", with: "\t") }
            return .success(str)
        } catch {
            return .failure(jsonError(from: error, in: input))
        }
    }

    // JSON-02: Minify
    static func minify(_ input: String) -> Result<String, JSONError> {
        guard let data = input.data(using: .utf8) else {
            return .failure(JSONError(message: "Invalid UTF-8", line: nil, column: nil))
        }
        do {
            let obj = try JSONSerialization.jsonObject(with: data)
            let out = try JSONSerialization.data(withJSONObject: obj, options: [])
            return .success(String(data: out, encoding: .utf8) ?? "")
        } catch {
            return .failure(jsonError(from: error, in: input))
        }
    }

    // JSON-03: Line + column from NSError
    // JSONSerialization error userInfo contains NSDebugDescriptionErrorKey with "... character N"
    // [ASSUMED] — character offset extraction from error string; compute line/col by prefix scan
    private static func jsonError(from error: Error, in source: String) -> JSONError {
        let ns = error as NSError
        let desc = ns.userInfo[NSDebugDescriptionErrorKey] as? String ?? error.localizedDescription
        var line: Int? = nil
        var column: Int? = nil
        if let charStr = desc.components(separatedBy: "character ").last,
           let charOffset = Int(charStr.components(separatedBy: CharacterSet.decimalDigits.inverted).first ?? "") {
            let prefix = source.prefix(charOffset)
            line = prefix.components(separatedBy: "\n").count
            column = (prefix.components(separatedBy: "\n").last?.count ?? 0) + 1
        }
        return JSONError(message: desc, line: line, column: column)
    }

    // JSON-04: Sort keys
    static func prettyPrintSorted(_ input: String, indent: Int) -> Result<String, JSONError> {
        guard let data = input.data(using: .utf8) else {
            return .failure(JSONError(message: "Invalid UTF-8", line: nil, column: nil))
        }
        do {
            let obj = try JSONSerialization.jsonObject(with: data)
            let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys]
            let output = try JSONSerialization.data(withJSONObject: obj, options: options)
            return .success(String(data: output, encoding: .utf8) ?? "")
        } catch {
            return .failure(jsonError(from: error, in: input))
        }
    }
}
```

**JSON-05 (syntax highlighting for editable editor):** Custom `NSTextStorage` subclass wired to `NSTextStorageDelegate.textStorage(_:didProcessEditing:range:changeInLength:)`. Apply attributes only to the dirty range (not full document re-highlight on every keypress — performance trap documented in PITFALLS.md performance table). HighlightSwift 1.1.0 is used for the **read-only output panel** only.

### Base64 Tool (B64-01..05)

```swift
// Base64Transformer.swift — Source: Foundation [VERIFIED]
enum Base64Transformer {
    // B64-01, B64-02: encode (standard and URL-safe)
    static func encode(_ text: String, urlSafe: Bool) -> String {
        let data = Data(text.utf8)
        var encoded = data.base64EncodedString()
        if urlSafe {
            encoded = encoded
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")  // URL-safe omits padding
        }
        return encoded
    }

    // B64-01, B64-02: decode (standard and URL-safe)
    static func decode(_ base64: String) -> Result<String, Error> {
        let normalized = base64
            .replacingOccurrences(of: "-", with: "+")    // URL-safe → standard
            .replacingOccurrences(of: "_", with: "/")
        let padded = normalized + String(repeating: "=", count: (4 - normalized.count % 4) % 4)
        guard let data = Data(base64Encoded: padded, options: .ignoreUnknownCharacters),
              let text = String(data: data, encoding: .utf8) else {
            return .failure(TransformError.invalidBase64)
        }
        return .success(text)
    }

    // B64-03: auto-detect direction
    static func isLikelyBase64(_ input: String) -> Bool {
        guard input.count >= 12 else { return false }  // avoid false-positives on short strings
        let base64Chars = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=-_")
        return input.unicodeScalars.allSatisfy { base64Chars.contains($0) }
    }
}
```

**B64-04 (file encode/decode):** Use `NSOpenPanel` for file selection (no sandbox = no entitlement needed). For large files, read in 1 MB chunks via `FileHandle` in `Task.detached`. Decode output: write to temp file, then present `NSSavePanel` for destination.

### JWT Tool (JWT-01..06)

```swift
// Core/Extensions/Data+Base64URL.swift
// Source: auth0/JWTDecode.swift implementation [MEDIUM confidence] + PITFALLS.md Pitfall #6 [VERIFIED]
extension Data {
    static func fromBase64URL(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let paddingCount = (4 - base64.count % 4) % 4
        base64 += String(repeating: "=", count: paddingCount)
        return Data(base64Encoded: base64, options: .ignoreUnknownCharacters)
    }
}

// JWTTransformer.swift
enum JWTTransformer {
    struct DecodedJWT {
        let header: [String: Any]
        let payload: [String: Any]
        let signatureValid: Bool?   // nil = not verified yet
    }

    static func decode(_ token: String) -> Result<DecodedJWT, Error> {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return .failure(JWTError.invalidFormat) }
        guard let headerData = Data.fromBase64URL(String(parts[0])),
              let payloadData = Data.fromBase64URL(String(parts[1])) else {
            return .failure(JWTError.invalidBase64URL)
        }
        // ... parse JSON from headerData and payloadData
    }

    // JWT-03: exp timezone-correct check
    // Source: PITFALLS.md Pitfall #7 [VERIFIED]
    static func expiryStatus(payload: [String: Any]) -> ExpiryStatus {
        guard let exp = payload["exp"] as? TimeInterval else { return .noExpiry }
        let expiryDate = Date(timeIntervalSince1970: exp)  // MUST use timeIntervalSince1970, not timeIntervalSinceReferenceDate
        let now = Date()
        if expiryDate < now {
            return .expired(since: now.timeIntervalSince(expiryDate))
        }
        return .valid(until: expiryDate.timeIntervalSince(now))
    }

    // JWT-04: HMAC verify — secret NEVER written to history [VERIFIED: PITFALLS.md Pitfall #11]
    static func verifyHMAC(token: String, secret: String, algorithm: String) -> Bool {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return false }
        let message = "\(parts[0]).\(parts[1])"
        guard let messageData = message.data(using: .utf8),
              let keyData = secret.data(using: .utf8),
              let sigData = Data.fromBase64URL(String(parts[2])) else { return false }
        let key = SymmetricKey(data: keyData)
        // Source: CryptoKit HMAC [VERIFIED: Apple CryptoKit docs]
        switch algorithm {
        case "HS256":
            let mac = HMAC<SHA256>.authenticationCode(for: messageData, using: key)
            return Data(mac) == sigData
        case "HS384":
            let mac = HMAC<SHA384>.authenticationCode(for: messageData, using: key)
            return Data(mac) == sigData
        case "HS512":
            let mac = HMAC<SHA512>.authenticationCode(for: messageData, using: key)
            return Data(mac) == sigData
        default: return false
        }
    }
}
```

**JWT history exclusion:** `JWTFormatterViewModel.onSaveHistory` closure receives only the JWT token string. The HMAC secret key field in the view is a local `@State` variable that is never passed to the history write call. Add a `// SECURITY: secret not included in history — see INFRA-09` comment at the call site.

### Timestamp Tool (TS-01..05)

```swift
// TimestampTransformer.swift — Source: Foundation [VERIFIED]
enum TimestampTransformer {
    // TS-01: Auto-detect seconds vs milliseconds
    // Source: PITFALLS.md Pitfall #8 [VERIFIED]
    enum TimestampUnit { case seconds, milliseconds, ambiguous }

    static func detectUnit(_ value: Int64) -> TimestampUnit {
        let digitCount = String(abs(value)).count
        switch digitCount {
        case 10: return .seconds
        case 13: return .milliseconds
        default: return .ambiguous  // 11 or 12 digits: show format selector
        }
    }

    static func toDate(_ value: Int64, unit: TimestampUnit) -> Date {
        switch unit {
        case .seconds: return Date(timeIntervalSince1970: Double(value))
        case .milliseconds: return Date(timeIntervalSince1970: Double(value) / 1000.0)
        case .ambiguous: return Date(timeIntervalSince1970: Double(value))  // caller shows picker
        }
    }

    // TS-02: Format in multiple timezones
    static func formatInTimezones(_ date: Date, zones: [TimeZone]) -> [(TimeZone, String)] {
        zones.map { tz in
            let fmt = DateFormatter()
            fmt.timeZone = tz
            fmt.dateStyle = .full
            fmt.timeStyle = .long
            return (tz, fmt.string(from: date))
        }
    }

    // TS-05: ISO 8601
    static func toISO8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    // TS-04: Relative time
    static func relativeTime(from date: Date) -> String {
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .full
        return fmt.localizedString(for: date, relativeTo: Date())
    }
}
```

### Hash Tool (HASH-01..04)

```swift
// HashTransformer.swift
// Source: CryptoKit [VERIFIED] + CommonCrypto/zlib [VERIFIED: STACK.md]
import CryptoKit
import CommonCrypto

enum HashTransformer {
    struct HashResult {
        var md5: String = ""
        var sha1: String = ""
        var sha256: String = ""
        var sha384: String = ""
        var sha512: String = ""
        var crc32: String = ""
    }

    // HASH-01: text hashing
    static func hashText(_ input: String) -> HashResult {
        guard let data = input.data(using: .utf8) else { return HashResult() }
        return hashData(data)
    }

    static func hashData(_ data: Data) -> HashResult {
        var result = HashResult()
        // MD5 via CommonCrypto
        var md5 = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes { CC_MD5($0.baseAddress, CC_LONG(data.count), &md5) }
        result.md5 = md5.hexString

        // SHA family via CryptoKit
        result.sha1 = Insecure.SHA1.hash(data: data).hexString
        result.sha256 = SHA256.hash(data: data).hexString
        result.sha384 = SHA384.hash(data: data).hexString
        result.sha512 = SHA512.hash(data: data).hexString

        // CRC32 via zlib — link libz.tbd in Build Phases
        var crc: uLong = 0
        data.withUnsafeBytes { crc = crc32(0, $0.baseAddress?.assumingMemoryBound(to: Bytef.self), uInt(data.count)) }
        result.crc32 = String(format: "%08x", crc)
        return result
    }

    // HASH-02: file hashing without blocking UI — chunked async read
    // Source: PITFALLS.md Pitfall #9 [VERIFIED]
    static func hashFile(url: URL, progressHandler: @escaping (Double) -> Void) async -> HashResult {
        return await Task.detached(priority: .utility) {
            var md5ctx = CC_MD5_CTX()
            var sha1ctx = Insecure.SHA1()
            var sha256ctx = SHA256()
            var sha384ctx = SHA384()
            var sha512ctx = SHA512()
            var crcValue: uLong = 0

            CC_MD5_Init(&md5ctx)
            guard let handle = try? FileHandle(forReadingFrom: url) else { return HashResult() }
            defer { try? handle.close() }

            let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 1
            var bytesRead = 0
            let chunkSize = 1024 * 1024  // 1 MB chunks

            while !Task.isCancelled {
                let chunk = handle.readData(ofLength: chunkSize)
                if chunk.isEmpty { break }
                bytesRead += chunk.count
                progressHandler(Double(bytesRead) / Double(fileSize))

                chunk.withUnsafeBytes {
                    CC_MD5_Update(&md5ctx, $0.baseAddress, CC_LONG(chunk.count))
                }
                sha1ctx.update(data: chunk)
                sha256ctx.update(data: chunk)
                sha384ctx.update(data: chunk)
                sha512ctx.update(data: chunk)
                chunk.withUnsafeBytes {
                    crcValue = crc32(crcValue, $0.baseAddress?.assumingMemoryBound(to: Bytef.self), uInt(chunk.count))
                }
            }

            var md5digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
            CC_MD5_Final(&md5digest, &md5ctx)

            var result = HashResult()
            result.md5 = md5digest.hexString
            result.sha1 = sha1ctx.finalize().hexString
            result.sha256 = sha256ctx.finalize().hexString
            result.sha384 = sha384ctx.finalize().hexString
            result.sha512 = sha512ctx.finalize().hexString
            result.crc32 = String(format: "%08x", crcValue)
            return result
        }.value
    }
}

// HASH-03: HMAC — secret NEVER written to history (same pattern as JWT)
// JWTTransformer.verifyHMAC() pattern applies — only use for verification/generation,
// never include the key in HistoryEntry
```

### UUID Tool (UUID-01..04)

```swift
// UUIDTransformer.swift
// Source: Foundation UUID [VERIFIED: Apple docs]
// Source: PITFALLS.md Pitfall #17 for v7 timestamp extraction [VERIFIED]
enum UUIDTransformer {
    // UUID-01: v4 generation (Foundation native — only native UUID version)
    static func generateV4(count: Int) -> [UUID] {
        (0..<count).map { _ in UUID() }
    }

    // UUID-01: v1 and v5 require external package (Foundation does NOT support these)
    // [VERIFIED: Apple Foundation docs + Swift Forums SF-0041]
    // Recommendation: use baarde/uuid-kit or add minimal implementation
    // uuid-kit provides UUID.v1() and UUID.v5(name:namespace:) [ASSUMED — needs vetting]

    // UUID-02: v7 — GATED. Do not implement until package vetted.
    // nthState/UUIDV7 (10 stars, no semver) — flagged [ASSUMED]
    // FoundationPreview 6.4 adds UUID.version7() but is preview-only, not stable

    // UUID-03: inspect — version and variant
    static func inspect(_ uuid: UUID) -> UUIDInfo {
        let bytes = withUnsafeBytes(of: uuid.uuid) { Array($0) }
        let version = (bytes[6] >> 4) & 0xF
        let variant = (bytes[8] >> 6) & 0x3
        var timestamp: Date? = nil
        if version == 1 {
            // v1: 100ns intervals since Oct 15, 1582
            let timeLow = UInt64(bytes[0]) << 24 | UInt64(bytes[1]) << 16 | UInt64(bytes[2]) << 8 | UInt64(bytes[3])
            let timeMid = UInt64(bytes[4]) << 8 | UInt64(bytes[5])
            let timeHigh = UInt64(bytes[6] & 0x0F) << 8 | UInt64(bytes[7])
            let t = (timeHigh << 48) | (timeMid << 32) | timeLow
            let unixNS = Double(t) / 10_000_000.0 - 12219292800.0
            timestamp = Date(timeIntervalSince1970: unixNS)
        } else if version == 7 {
            // v7: 48-bit millisecond Unix timestamp in bytes 0-5
            // Source: PITFALLS.md Pitfall #17 [VERIFIED — exact bit-mask code provided]
            let ms: UInt64 = (UInt64(bytes[0]) << 40) | (UInt64(bytes[1]) << 32)
                           | (UInt64(bytes[2]) << 24) | (UInt64(bytes[3]) << 16)
                           | (UInt64(bytes[4]) << 8)  | UInt64(bytes[5])
            timestamp = Date(timeIntervalSince1970: Double(ms) / 1000.0)
        }
        return UUIDInfo(version: Int(version), variant: Int(variant), timestamp: timestamp)
    }
}
```

**UUID v1/v5 note:** Foundation's `UUID` generates only v4. For v1 and v5, the planner should include a task to evaluate `baarde/uuid-kit` (a small Swift SPM package for UUID v1/v3/v5) before adding it. [ASSUMED — needs slopcheck verification]

### HotkeyManager

```swift
// Core/Services/HotkeyManager.swift
// Source: KeyboardShortcuts 3.0.1 README [VERIFIED]
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let openFlint = Self("openFlint", default: .init(.space, modifiers: [.command, .shift]))
}

@Observable
final class HotkeyManager {
    init() {
        // Must not be called in init() before app is fully initialized — call from onAppear or App.init body
        KeyboardShortcuts.onKeyDown(for: .openFlint) {
            // Post notification; FlintApp receives and shows popover
            NotificationCenter.default.post(name: .showPopover, object: nil)
        }
    }
}
```

### SMAppService — Launch at Login (INFRA-13)

```swift
// PreferencesStore.swift
// Source: Apple SMAppService docs [VERIFIED] + nilcoalescing.com example [MEDIUM]
import ServiceManagement

extension PreferencesStore {
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Handle — user will see macOS notification about the change
            }
        }
    }
}
```

---

## Detection Predicate Chain (INFRA-06, D-06)

The ordered chain below must be implemented exactly in this priority order — first-match-wins. Each predicate must be fast (< 2ms) to satisfy the 100ms detection requirement.

| Priority | Tool | Predicate | Fast Pre-check |
|----------|------|-----------|----------------|
| 1 | JSON Formatter | `JSONSerialization.jsonObject(with:)` succeeds | Trim; starts with `{` or `[` |
| 2 | JWT Decoder | Starts with "ey"; contains exactly two "." separators | `hasPrefix("ey")` + count(".") == 2 |
| 3 | Base64 | All chars in base64 alphabet; count ≥ 12; length multiple of 4 (or URL-safe variant) | char set check |
| 4 | URL Encoder | Contains `%` followed by two hex digits | regex `%[0-9A-Fa-f]{2}` match |
| 5 | URL Parser | `URL(string: input)?.scheme` is non-nil (http/https) | scheme check |
| 6 | Timestamp | Pure numeric string; 10 or 13 digits | String.allSatisfy(isNumber) + count |
| 7 | (Phase 2) Color | Matches `#[0-9A-Fa-f]{3,6}` pattern | prefix "#" + hex chars |
| 8 | UUID Inspector | Matches UUID regex `[0-9A-F]{8}-[0-9A-F]{4}-...` | UUID(uuidString:) != nil |
| 9 | (Phase 2) Regex | Pattern like `/regex/flags` | prefix "/" + suffix "/[gimsux]*" |

**Performance:** JSON parse is the most expensive. Pre-check `starts with { or [` before calling JSONSerialization. Total chain evaluation should be < 5ms for a 10 KB clipboard string.

**Base64 false-positive guard:** Require minimum 12 characters AND all characters in the base64 alphabet AND reasonable length. A short English word like "hello" must NOT trigger Base64 detection. [VERIFIED: PITFALLS.md UX pitfall table]

---

## Walking-Skeleton Slice

The minimal vertical end-to-end slice that proves the pipeline before repeating the tool pattern:

**Slice deliverable:** App launches in < 500ms → hotkey opens popover → paste JSON → banner appears → click "Open JSON Formatter" → popover dismisses / workspace opens → format runs live with 150ms debounce → error stays visible with last-good output dimmed → success writes one history row → close workspace → open launcher → search "json" → history row appears in results.

**File creation order for the slice:**

1. `Flint.xcodeproj` — Xcode project, macOS 14.0 deployment target, Swift 6 language mode
2. `Flint-debug.entitlements` + `Flint-release.entitlements` — dual entitlements from day one
3. `ToolCategory.swift`, `ToolDefinition.swift`, `DetectionResult.swift`
4. `HistoryEntry.swift` + GRDB migration
5. `HistoryStore.swift` (opens off main thread)
6. `PreferencesStore.swift`
7. `ToolRegistry.swift` (empty tools array stub)
8. `ClipboardDetector.swift` + `NSPasteboardDidChangeNotification` setup
9. `HotkeyManager.swift` (KeyboardShortcuts registration)
10. `WindowCoordinator.swift` (activation-policy dance)
11. `FlintApp.swift` — wires all the above; `MenuBarExtra` with `MenuBarExtraAccess`; two-stage Esc
12. `MenuBarPopoverView.swift` — search field (autofocused D-01), pinned row stub, empty history body
13. `DetectionBannerView.swift`
14. `MainWindowView.swift` — empty `NavigationSplitView` shell
15. `JSONTransformer.swift` (pure; no UI imports)
16. `JSONFormatterViewModel.swift` (debounce actor + last-good-output pattern)
17. `SyntaxEditorView.swift` (NSViewRepresentable with update guard)
18. `JSONFormatterView.swift`
19. `JSONFormatterDefinition.swift` + register in `ToolRegistry`
20. Verify: paste JSON → banner → open tool → format → history row → search finds it

Steps 21–55: repeat steps 15–19 for Base64, URLEncoder, JWT, Timestamp, Hash, UUID.

---

## Common Pitfalls

### Pitfall 1: MenuBarExtra Dismiss API Absence
**What goes wrong:** `@Environment(\.dismiss)` does nothing inside MenuBarExtra windows. Esc key has no effect.
**Root cause:** MenuBarExtra is a thin wrapper around NSStatusItem with no 1st-party dismiss surface.
**Fix:** MenuBarExtraAccess 1.3.0 `.menuBarExtraAccess(isPresented: $binding)`. Set `binding = false` to dismiss.
**Verification:** Press Esc twice inside the popover. First should return to launcher; second should close.

### Pitfall 2: Preferences/Workspace Window Hidden Behind Other Apps
**What goes wrong:** Window appears in Mission Control but is invisible (behind frontmost app).
**Root cause:** `.accessory` activation policy prevents window elevation.
**Fix:** WindowCoordinator activation dance: `setActivationPolicy(.regular)` → `activate(ignoringOtherApps: true)` → 100ms delay → `NotificationCenter.post(.openWorkspace)`. Restore `.accessory` on window close.
**Verification:** With another app frontmost, press ⌘, — preferences must appear in front.

### Pitfall 3: JWT / HMAC Secrets Written to History
**What goes wrong:** JWT HMAC secret key or Hash HMAC key appears in `sqlite3 history.db`.
**Root cause:** Generic history save passes all ViewModel state.
**Fix:** HistoryEntry.input for JWT = token string only. HMAC key is a separate local `@State` in the View that never reaches the ViewModel's history call.
**Verification:** `sqlite3 ~/Library/Application\ Support/Flint/history.db "SELECT input FROM historyEntry"` — must not contain any secret key.

### Pitfall 4: JWT base64url Decode Fails
**What goes wrong:** Valid JWT with `-` or `_` returns "Invalid token."
**Root cause:** `Data(base64Encoded:)` expects standard base64 (`+` and `/`), not URL-safe alphabet.
**Fix:** `Data.fromBase64URL()` extension (char substitution + padding) before calling `Data(base64Encoded:)`.
**Verification:** Unit test with `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U` (contains `-`).

### Pitfall 5: NSTextView Infinite Re-render Loop
**What goes wrong:** Typing in JSON editor causes CPU spike to 100%; severe lag after ~50 chars.
**Root cause:** `updateNSView` unconditionally sets `textView.string`, triggering delegate, triggering SwiftUI state, repeating.
**Fix:** Guard in `updateNSView`: `guard textView.string != text else { return }`. Save/restore `selectedRanges`. Post binding changes via `DispatchQueue.main.async`.
**Verification:** Type 200 characters rapidly; CPU must stay < 10%.

### Pitfall 6: GRDB Open on Main Thread
**What goes wrong:** App launch stutter; history loads 200ms after popover appears.
**Root cause:** `DatabaseQueue` init includes disk I/O and schema migration.
**Fix:** Open in `Task.detached(priority: .utility)` at app startup. Show popover immediately; history populates once ready.
**Verification:** Instruments "App Launch" template; main thread must not block on DB open.

### Pitfall 7: Clipboard Battery Drain
**What goes wrong:** Flint appears in top of Activity Monitor battery consumers even when idle.
**Root cause:** `DispatchSourceTimer` polling `changeCount` 10x/sec globally.
**Fix:** Use `NSPasteboardDidChangeNotification` (private but stable, 0% idle CPU) + only run detection when `isPopoverPresented == true`.
**Verification:** `top -l 1 -stats pid,cpu | grep Flint` — must show < 0.5% when popover is closed.

### Pitfall 8: Timestamp Ambiguity (11/12-digit inputs)
**What goes wrong:** 11-digit input silently converts using wrong unit.
**Root cause:** Simple "10 = seconds, 13 = milliseconds" heuristic doesn't cover edge cases.
**Fix:** Detect 11/12-digit inputs as `.ambiguous` and show a unit selector. Never auto-convert without a visible unit label.
**Verification:** Test inputs: `1700000000` (10d, seconds), `1700000000000` (13d, ms), `17000000000` (11d, ambiguous).

### Pitfall 9: Hash File OOM on Large Files
**What goes wrong:** Hashing a 500 MB file crashes with memory pressure.
**Root cause:** `Data(contentsOf:)` reads entire file into RAM.
**Fix:** Chunked `FileHandle.readData(ofLength: 1_048_576)` in `Task.detached`. Streaming update with incremental hash contexts.
**Verification:** Hash a 200 MB file via `dd if=/dev/urandom of=/tmp/test.bin bs=1m count=200`. UI must remain responsive.

### Pitfall 10: UUID v1/v5 — Foundation Doesn't Generate Them
**What goes wrong:** `UUID()` only generates v4. No other UUID version is available in Foundation natively.
**Root cause:** Apple's Foundation UUID API is v4-only (confirmed by Swift Forums SF-0041).
**Fix:** External package required. Evaluate `baarde/uuid-kit` at task start. If not sound, implement v1 using `gettimeofday` + MAC address heuristic, v5 using CryptoKit SHA1. Gate UUID v7 (UUID-02) as explicit Phase 2 risk item.
**Verification:** Generated UUID string; `UUIDTransformer.inspect()` must return `version == 1` or `version == 5`.

### Pitfall 11: JWT exp Timezone Bug
**What goes wrong:** Token shows "Expires in 31 years" or "Expired 31 years ago."
**Root cause:** Using `Date().timeIntervalSinceReferenceDate` (Jan 1, 2001) instead of `timeIntervalSince1970` (Jan 1, 1970). Difference: 978,307,200 seconds.
**Fix:** Always `Date(timeIntervalSince1970: expClaim)` and compare against `Date().timeIntervalSince1970`.
**Verification:** Unit test: token with `exp = Date().timeIntervalSince1970 + 3600` → shows "Expires in ~1h."

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Highlightr for NSTextView syntax highlight | HighlightSwift (display) + custom NSTextStorage (editable) | 2026 (Highlightr deprecated by maintainer) | Must use two-tier approach |
| CGEventTap for global hotkey | KeyboardShortcuts (Carbon RegisterEventHotKey) | 2022+ (Accessibility friction) | Zero permissions on first launch |
| SwiftData for persistence | GRDB 7.11.1 | 2024 (SwiftData macOS 14 bugs confirmed) | Typed queries, ValueObservation, migrations |
| Ink for Markdown | swift-markdown 0.8.0 (Phase 2) | 2024 | Full GFM including task lists, tables |
| altool for notarization | notarytool | Nov 2023 (altool removed by Apple) | Phase 3 only |
| ObservableObject + @Published | @Observable macro (macOS 14) | WWDC 2023 | Property-level re-render; no cascading full-view refreshes |
| SMLoginItemSetEnabled | SMAppService.mainApp (macOS 13+) | 2022 (Ventura) | Only supported login-item API for new apps |
| UUID via Foundation (all versions) | Foundation for v4 only; external package for v1/v5/v7 | Ongoing (SF-0041 in preview for v7, not stable) | v1/v5 need vetting; v7 is Phase 2 |

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `NSPasteboardDidChangeNotification` is a private-but-stable notification that fires reliably on macOS 14 | Pattern 6, ClipboardDetector | If unreliable, must fall back to `DispatchSourceTimer` polling; 0% idle CPU guarantee is lost |
| A2 | `nthState/UUIDV7` is a functional, production-usable SPM package for UUID v7 | UUID Tool section | If unsound, UUID-02 must defer to Phase 2; v7 inspection in UUID-03 also needs alternative |
| A3 | `baarde/uuid-kit` provides reliable v1 and v5 UUID generation (matching RFC 4122) | UUID Tool section | If unsound, must hand-roll v1 (gettimeofday + node ID) and v5 (CryptoKit SHA1 + bit layout) |
| A4 | `JSONSerialization` error `userInfo[NSDebugDescriptionErrorKey]` contains "character N" pattern that can be parsed for offset | JSON Tool section (JSON-03) | If format changes, line/column extraction is a best-effort fallback; show raw error message instead |
| A5 | Xcode 26.5 / Swift 6.3.2 (current environment) is compatible with all locked package versions | Standard Stack | If any package requires lower Xcode version (unlikely — all require 16.3+), no issue |
| A6 | `FoundationPreview.UUID.version7()` from SF-0041 will NOT ship as stable API in macOS 14 timeframe | UUID v7 note | If it ships stable earlier, internal Foundation v7 generation becomes viable and removes need for nthState/UUIDV7 |

---

## Open Questions

1. **UUID v1/v5 package choice**
   - What we know: Foundation generates v4 only; Swift Forums SF-0041 adds v7 in FoundationPreview 6.4 (preview, not stable)
   - What's unclear: Is `baarde/uuid-kit` production-quality for v1/v5? Any timing or node-ID caveats?
   - Recommendation: Planner adds a one-day spike task at start of UUID tool work. Evaluate uuid-kit; if not trusted, implement v5 via CryptoKit SHA1 + RFC 4122 bit layout (deterministic, testable). If v1 is needed without a good package, add a disclaimer in the UI that v1 uses a pseudo-node-ID (privacy-safer than real MAC address).

2. **UUID v7 (UUID-02) — Phase 1 vs Phase 2**
   - What we know: nthState/UUIDV7 has 10 stars, no semver releases; leodabus/UUIDv7 has 0 stars
   - What's unclear: Whether either package is sound enough to ship
   - Recommendation: Gate as a hard Phase 2 item unless the spike resolves in < 4 hours. The UUID inspector (UUID-03) can detect v7 from an input token without generating one, so inspection is separately implementable.

3. **NSPasteboardDidChangeNotification reliability on macOS 14**
   - What we know: Community reports 0% idle CPU; confirmed stable in macOS 12-13 apps; private notification
   - What's unclear: Behavior on Sonoma (macOS 14) with the popover visibility gate
   - Recommendation: Planner should include a verification step after `ClipboardDetector` is wired. Have the `DispatchSourceTimer` approach (100ms, visibility-gated) ready as a fallback.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode | Build tool (all of Phase 1) | ✓ | 26.5 (exceeds 16.3+ requirement) | — |
| Swift compiler | GRDB 7 Swift 6 concurrency | ✓ | 6.3.2 (exceeds 6.1+ requirement) | — |
| macOS Sonoma APIs | MenuBarExtra, @Observable | ✓ | Darwin 25.5.0 (macOS 14 equivalent in dev env) | — |
| GRDB.swift 7.11.1 | History store | ✓ (via SPM) | 7.11.1 [VERIFIED: GitHub API] | — |
| KeyboardShortcuts 3.0.1 | Global hotkey | ✓ (via SPM) | 3.0.1 [VERIFIED: GitHub API] | — |
| MenuBarExtraAccess 1.3.0 | Popover dismiss | ✓ (via SPM) | 1.3.0 [VERIFIED: GitHub API] | — |
| HighlightSwift 1.1.0 | Display-only syntax highlight | ✓ (via SPM) | 1.1.0 [VERIFIED: GitHub API] | — |
| libz.tbd (zlib) | CRC32 hashing | ✓ (system, always present on macOS) | system | — |
| CommonCrypto | MD5 hashing | ✓ (system framework) | system | — |

**Missing dependencies with no fallback:** none — all Phase 1 dependencies are system-provided or verified on GitHub.

**Missing dependencies with fallback:** UUID v1/v5 package (needs vetting; fallback is hand-rolled implementation using CryptoKit SHA1 for v5).

---

## Validation Architecture

> `workflow.nyquist_validation` is `false` in `.planning/config.json` — this section is skipped per configuration.

---

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | No user accounts in v1 |
| V3 Session Management | No | No sessions; all local |
| V4 Access Control | Partial | No network; local file access only (no sandbox in v1 by design) |
| V5 Input Validation | Yes | All tool inputs validated in Transformer layer; no crash on malformed input (INFRA-17) |
| V6 Cryptography | Yes | CryptoKit (SHA/HMAC); CommonCrypto for MD5; zlib for CRC32 — never hand-roll |

### Known Threat Patterns for This Stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| HMAC/JWT secret in SQLite history | Information Disclosure | Exclude secret fields from HistoryEntry schema; per-tool ViewModel serialization contract |
| Secrets in UserDefaults (iCloud-backed) | Information Disclosure | Never store secrets in UserDefaults; use macOS Keychain if "remember key" feature is ever added |
| `get-task-allow` in Release entitlements | Elevation of Privilege + notarization failure | Dual entitlements files (debug/release); set `CODE_SIGN_ENTITLEMENTS` per build configuration |
| Base64 auto-detection false positive on clipboard | Spoofing / UX confusion | Minimum 12 chars + character set validation + length multiple of 4 before suggesting decode |
| Large file DoS (hash tool OOM) | Denial of Service | Chunked `FileHandle` read; 1 MB chunks; progress + cancel |

---

## Sources

### Primary (HIGH confidence)

- GRDB.swift 7.11.1 GitHub (verified 2026-06-25 via GitHub API): https://github.com/groue/GRDB.swift
- KeyboardShortcuts 3.0.1 GitHub (verified 2026-06-25 via GitHub API): https://github.com/sindresorhus/KeyboardShortcuts
- MenuBarExtraAccess 1.3.0 GitHub (verified 2026-06-25 via GitHub API): https://github.com/orchetect/MenuBarExtraAccess
- HighlightSwift 1.1.0 GitHub (verified 2026-06-25 via GitHub API): https://github.com/appstefan/HighlightSwift
- `.planning/research/SUMMARY.md` — architecture, stack decisions, 11 pitfalls (ALL HIGH confidence, verified 2026-06-25)
- `.planning/research/ARCHITECTURE.md` — component boundaries, patterns, build order (HIGH)
- `.planning/research/PITFALLS.md` — all 18 pitfalls with root causes and fixes (HIGH)
- `.planning/research/STACK.md` — native-vs-package decisions, package version compatibility (HIGH)
- Apple Developer Docs — MenuBarExtra: https://developer.apple.com/documentation/SwiftUI/MenuBarExtra
- Apple Developer Docs — SMAppService.register(): https://developer.apple.com/documentation/servicemanagement/smappservice/register()
- Apple Feedback FB10185203 (MenuBarExtra no dismiss): https://github.com/feedback-assistant/reports/issues/383
- auth0/JWTDecode.swift — base64url decode implementation: https://github.com/auth0/JWTDecode.swift/blob/master/JWTDecode/JWTDecode.swift
- Apple CryptoKit HMAC docs: https://apple.github.io/swift-crypto/docs/current/Crypto/Structs/HMAC.html
- Swift Forums SF-0041 — UUID version support (FoundationPreview 6.4, preview only): https://forums.swift.org/t/review-sf-0041-uuid-version-support-and-other-enhancements/86848

### Secondary (MEDIUM confidence)

- Peter Steinberger — "Showing Settings from macOS Menu Bar Items" (activation-policy dance, 2025): https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items
- GRDB 7 ValueObservation MainActor behavior: https://github.com/groue/GRDB.swift/blob/master/Documentation/GRDB7MigrationGuide.md
- livsycode.com — Debounce with @Observable ViewModel using Swift Concurrency actor: https://livsycode.com/swiftui/how-to-use-debounce-in-swiftui-or-in-observable-classes/
- nilcoalescing.com — SMAppService launch at login: https://nilcoalescing.com/blog/LaunchAtLoginSetting/
- NSPasteboardDidChangeNotification community reports — 0% idle CPU: https://discussions.apple.com/thread/2661580
- PlainPasta clipboard monitor (DispatchSourceTimer pattern): https://github.com/hisaac/PlainPasta/blob/main/PlainPasta/PasteboardMonitor.swift

### Tertiary (LOW confidence)

- nthState/UUIDV7 (10 stars, no semver releases) — [ASSUMED] viability: https://github.com/nthState/UUIDV7
- baarde/uuid-kit (UUID v1/v5 for Swift) — [ASSUMED] viability: https://github.com/baarde/uuid-kit
- NSDebugDescriptionErrorKey character offset format in JSONSerialization — [ASSUMED] format consistency across macOS versions

---

## Metadata

**Confidence breakdown:**

- Standard stack: HIGH — all packages verified at exact versions via GitHub API (2026-06-25)
- Architecture patterns: HIGH — drawn from ARCHITECTURE.md (verified 2026-06-25) + Apple docs
- Native API recipes: HIGH — Foundation/CryptoKit/CommonCrypto are first-party; JWT decode pattern verified against auth0 production implementation
- UUID v1/v5/v7: LOW — no Foundation support confirmed; package choice is ASSUMED
- Pitfalls remediation code: HIGH — exact patterns from PITFALLS.md (verified against official docs + post-mortems)
- Debounce pattern: MEDIUM — Swift Concurrency actor approach verified via secondary source; no Context7 confirmation

**Research date:** 2026-06-25
**Valid until:** 2026-07-25 (30 days — stack is stable; only UUID v7 Foundation proposal timeline is fast-moving)
