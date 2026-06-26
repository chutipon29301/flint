# Stack Research

**Domain:** Native macOS menubar developer-utility app (SwiftUI, MVVM, macOS 14.0+)
**Researched:** 2026-06-25
**Confidence:** HIGH (all package picks verified against current GitHub releases and official docs)

---

## Recommended Stack

### Core Technologies

| Technology | Version / Target | Purpose | Why Recommended |
|------------|-----------------|---------|-----------------|
| Swift | 5.9+ (Swift 6 toolchain, Xcode 16.3+) | Language | Required by GRDB 7; Swift 6 strict concurrency safe for async DB access |
| SwiftUI | macOS 14.0+ | Primary UI framework | Native MVVM, MenuBarExtra, live previews — no bridge code needed |
| AppKit | macOS 14.0+ | NSTextView, NSColorSampler, NSColorPanel | Unavoidable for syntax-highlighted editor and eyedropper; bridged via NSViewRepresentable |
| Foundation | macOS 14.0+ | URL/Base64/UUID/Timestamp encoding, JSONSerialization | Covers Base64, URL encoding, UUID v4, JSON, regex via NSRegularExpression natively |
| CryptoKit | macOS 10.15+ | SHA-1/256/384/512, HMAC | Native, zero-dependency; covers all SHA family + HMAC-SHA2 for JWT verification |
| CommonCrypto | macOS 10.0+ | MD5, CRC32 | CryptoKit explicitly excludes CRC32 and surfaces MD5 only via `Insecure.MD5`; use CommonCrypto directly for CRC32 via `CC_CRC32` (bridging header or `import CommonCrypto`) |
| WKWebView / WebKit | macOS 14.0+ | Markdown HTML preview, PDF export | Sandboxed, zero-dep renderer; `WKWebView.createPDF(configuration:completionHandler:)` produces PDF directly |
| ServiceManagement | macOS 13.0+ | Launch at login (SMAppService) | Apple-approved replacement for all legacy login-item APIs since Ventura; works non-sandboxed and sandboxed |
| NSColorSampler | macOS 10.15+ | Screen color eyedropper | Zero entitlements needed — does NOT require Screen Recording permission; used by Xcode/Keynote |
| NSColorPanel | macOS 10.0+ | System color picker | Integrates with SwiftUI via `ColorPicker` view (wraps NSColorPanel under the hood) |
| CollectionDifference (Foundation) | Swift 5.1+ | Line-level diff computation | Native, production-ready Myers diff; adequate for line-level diffing |

### Swift Packages

| Package | Current Version | Purpose | Decision: Package vs Native | Why |
|---------|----------------|---------|----------------------------|-----|
| **KeyboardShortcuts** (sindresorhus/KeyboardShortcuts) | 3.0.1 | Global hotkey registration with user-customizable UI | **Use package** | CGEventTap requires Accessibility permission prompt — a friction blocker for v1 UX. KeyboardShortcuts uses Carbon `RegisterEventHotKey` under the hood: no accessibility prompt, fully sandbox-compatible, App Store safe. Built-in `KeyboardShortcuts.Recorder` SwiftUI component for Preferences panel. |
| **GRDB.swift** (groue/GRDB.swift) | 7.11.1 | SQLite history store (100 items, searchable) | **Use package** | SwiftData on macOS 14 has documented critical bugs (broken inverse-relationship observation, random element reordering, broken `didSave`). Core Data is mature but overpowered for a 100-row store. UserDefaults has no SQL query capability. GRDB gives typed FetchRequest, ValueObservation for reactive updates, and migrations — all with zero runtime surprises. |
| **HighlightSwift** (appstefan/HighlightSwift) | 1.1.0 | Syntax highlighting for display-only code views (Markdown preview code blocks, JSON read-only output) | **Use package (limited scope)** | Replaces previously-considered Highlightr. Highlightr v2.3.0 was last released June 2020; as of 2026 the maintainer has explicitly deprecated it, recommending HighlightSwift instead. HighlightSwift outputs `AttributedString` suitable for SwiftUI `Text`/`NSAttributedString`. For the full editable NSTextView (JSON editor, Regex test input), use a custom `NSViewRepresentable` wrapping `NSTextView` with `CodeAttributedString` from Highlightr OR write a minimal custom highlighter — see note below. |
| **SwiftDiff** (turbolent/SwiftDiff) | no semver (Oct 2024 commit) | Word/character-level inline diff within changed lines | **Use package** | `CollectionDifference` handles line-level diff natively. Word-level highlight inside a changed line requires the Google Diff Match and Patch algorithm. SwiftDiff is a Swift port of that library. It is lightly maintained (14 commits) but functionally complete — only the diff algorithm is needed, not match/patch. Acceptable for this scope. |
| **swift-markdown** (swiftlang/swift-markdown) | 0.8.0 | Markdown parsing + AST for HTML generation | **Use package over Ink** | swift-markdown is the Apple-backed package powered by cmark-gfm: full GFM support (tables, task lists, strikethrough, fenced code blocks). Ink v0.6.0 (Apr 2024) is community-maintained, lacks full GFM, and is designed for static-site HTML generation — not AST manipulation. For Flint, the parsed AST renders to HTML via a custom visitor; `WKWebView` displays it. |
| **Sparkle** (sparkle-project/Sparkle) | 2.9.3 | Auto-update for .dmg distribution | **Use package** | The only mature, production-tested update framework for non-MAS macOS apps. EdDSA-signed appcast, delta updates, XPC-sandboxed installer. Add in Phase 3 only — no-op until there is a v1.0 to update from. |
| **ChromaKit** (HarshilShah/ChromaKit) | 0.1.1 | OKLCH ↔ NSColor conversion | **Use package (Phase 2 only)** | macOS has no native OKLCH API. ChromaKit adds `NSColor.oklch(L, C, H)` and conversion back, following CSS Color Level 4 math. Minimal (single file), no transitive deps. Accepted risk on small version number — the math is straightforward to vendor if needed. |
| **MenuBarExtraAccess** (orchetect/MenuBarExtraAccess) | latest | Programmatic show/hide of MenuBarExtra `.window` style | **Conditional — evaluate first** | SwiftUI's `MenuBarExtra` lacks any API to programmatically dismiss the popover (confirmed open Apple Feedback: FB10185203). MenuBarExtraAccess bridges this via `isPresented` Binding. Evaluate whether `@NSApplicationDelegateAdaptor` + `NSStatusItem` is cleaner for this project's level of control before adding this dep. |

### Development & Distribution Tools

| Tool | Version | Purpose | Notes |
|------|---------|---------|-------|
| Xcode | 16.3+ | Build, sign, archive | Required by GRDB 7 (Swift 6 compiler). Use Xcode's built-in Archive → Notarize workflow. |
| create-dmg (sindresorhus/create-dmg) | 8.1.0 | DMG packaging with background image and symlink | Node.js 20+ required. `create-dmg <App.app> ./dist` produces a notarization-ready, code-signed DMG in one command. |
| notarytool (Xcode CLI) | bundled with Xcode | Apple notary service submission | `altool` deprecated Nov 2023; `notarytool` is the only supported path. `xcrun notarytool submit app.dmg --keychain-profile "AC_PASSWORD" --wait` |
| GRDBQuery (groue/GRDBQuery) | 0.x | SwiftUI `@Query` property wrapper for GRDB | Optional companion to GRDB; consider if views need reactive DB reads without manual `ValueObservation` plumbing. |

---

## Native-vs-Package Decisions (Explicit)

### MenuBarExtra vs NSStatusItem

**Decision: Use `MenuBarExtra` (SwiftUI native) as the primary API.**

`MenuBarExtra` with `.windowStyle(.automatic)` (window style, not menu style) is available from macOS 13+, works with `@main App`, and is the officially supported SwiftUI path. Its limitation — no 1st-party programmatic dismiss API — is real (FB10185203 is open since 2022) but workable: add `MenuBarExtraAccess` or intercept dismiss via `NSWindow` introspection if needed. NSStatusItem + manual NSPopover is more flexible but abandons SwiftUI lifecycle management entirely and costs significant boilerplate. Start with `MenuBarExtra`; escalate to NSStatusItem only if a hard blocker emerges.

**Detachable window pattern:** Implement a separate `WindowGroup` scene. The popover (MenuBarExtra) contains a "Detach" button that calls `NSApp.activate(ignoringOtherApps: true)` and `openWindow(id:)`. Tools retain their state in `@StateObject` ViewModels — shared between popover and window via `@EnvironmentObject`.

### Global Hotkey: KeyboardShortcuts vs CGEventTap

**Decision: KeyboardShortcuts 3.0.1.**

CGEventTap requires an Accessibility entitlement prompt at runtime — a jarring permission dialog for a developer tool that has no other reason to request Accessibility access. The Carbon API (`RegisterEventHotKey`) that KeyboardShortcuts uses under the hood requires zero permissions and is Mac App Store compatible. No reason to add friction for v1. KeyboardShortcuts also provides the `KeyboardShortcuts.Recorder` SwiftUI component so the configurable shortcut preference UI is free.

### Syntax Highlighting: Highlightr vs HighlightSwift vs Native

**Decision: Two-tier approach.**

1. **Editable NSTextView (JSON editor, Regex test input):** Use a custom `NSViewRepresentable` wrapping `NSTextView`. For syntax highlighting in an editable context, wire up `NSTextStorageDelegate.textStorage(_:didProcessEditing:range:changeInLength:)` and apply `NSAttributedString` attributes using `JavaScriptCore` + highlight.js directly (same engine as Highlightr, no third-party dep) OR fork only the `CodeAttributedString` NSTextStorage subclass from Highlightr's source. Highlightr itself is deprecated as of 2026.

2. **Display-only code (Markdown preview code blocks, JWT payload JSON):** HighlightSwift 1.1.0 outputs `AttributedString` from highlight.js, usable directly in SwiftUI `Text` or via `NSAttributedString` bridge. Actively maintained, replaces Highlightr per the original maintainer's recommendation.

### History Store: GRDB vs SwiftData vs Core Data vs UserDefaults

**Decision: GRDB 7.11.1.**

| Option | Verdict |
|--------|---------|
| SwiftData | Reject for v1. Documented critical bugs on macOS 14: inverse relationship observation broken, random element reordering, `ModelContext.didSave` non-functional. Targeting macOS 14 specifically makes these bugs unavoidable. |
| Core Data | Overkill. 100-item history does not need a persistent store coordinator + managed object context stack. Core Data adds ~5 MB cold-start cost and significant boilerplate for what is essentially a log table. |
| UserDefaults | Inadequate. No SQL `LIKE` for search, no ordered pagination, plist serialization of 100 items with large inputs may hit 4 MB limit edge cases. |
| GRDB | Use. Lightweight (< 1 MB), typed Swift Records via `FetchableRecord` + `PersistableRecord`, SQL `LIKE` for fuzzy search, `ValueObservation` for reactive SwiftUI updates. `DatabaseQueue` is thread-safe and Swift 6 compliant with `Sendable` structs. Migration support handles schema evolution. |

Schema sketch:
```sql
CREATE TABLE history (
  id        INTEGER PRIMARY KEY AUTOINCREMENT,
  tool      TEXT    NOT NULL,
  input     TEXT    NOT NULL,
  output    TEXT    NOT NULL,
  timestamp REAL    NOT NULL,
  pinned    INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX history_timestamp ON history(timestamp DESC);
CREATE INDEX history_tool ON history(tool);
```

### Markdown: swift-markdown vs Ink vs AttributedString

**Decision: swift-markdown 0.8.0 → HTML string → WKWebView render.**

Ink is a simpler HTML generator but lacks full GFM (no task lists in v0.6.0, limited table support). `AttributedString(markdown:)` is Apple native but renders inline Markdown only — no fenced code blocks, no tables, not suitable for a live preview pane. `swift-markdown` provides a full GFM-compliant AST via cmark-gfm; write a `MarkupVisitor` that emits HTML, inject a CSS stylesheet, and load into WKWebView. PDF export: `WKWebView.createPDF(configuration:completionHandler:)` — no extra dependency.

For syntax highlighting of code blocks inside the Markdown preview: embed highlight.js as a local resource file and call it from the WKWebView JavaScript context. No additional Swift package needed.

### Diffing: SwiftDiff vs CollectionDifference

**Decision: Both — different layers.**

- `CollectionDifference` (native, Swift 5.1+): Use for line-level diff. Split both texts into `[String]` by line, compute `b.difference(from: a)`. Produces `.insert`/`.remove` operations for the side-by-side or unified view. Fast, zero-dep.
- `SwiftDiff` (turbolent): Use only for word-level highlight within a changed line. Feed the old and new versions of a single changed line into `Diff.diff(text1, text2)`. Produces `.equal`/`.insert`/`.delete` character-range operations for inline highlighting.

Do NOT use SwiftDiff for full-document diffing — performance degrades on large inputs due to character-level diffing. Keep line-level in native CollectionDifference.

### Hashing: CryptoKit + CommonCrypto

**Decision: CryptoKit for SHA family + HMAC; CommonCrypto for MD5 and CRC32.**

CryptoKit (macOS 10.15+):
- `SHA256`, `SHA384`, `SHA512`: use directly
- `SHA1` via `Insecure.SHA1`: use (JWT validation uses SHA1 in some contexts)
- `HMAC<SHA256>.authenticationCode(for:using:)` etc.: use for JWT HMAC verify

CommonCrypto (system framework, no import needed beyond `import CommonCrypto` after adding bridging header or using `@_implementationOnly import`):
- MD5: `CC_MD5(data, len, result)` — CryptoKit surfaces `Insecure.MD5` but CommonCrypto is the safe import path for non-sandboxed targets
- CRC32: `crc32(0, data, len)` from `<zlib.h>` — CryptoKit has no CRC32; zlib ships on every macOS

**No external crypto package needed.** CryptoSwift is an alternative but adds ~500 KB and pure-Swift re-implementations that are slower than the system library for SHA/HMAC.

### Color: NSColorSampler, NSColorPanel, OKLCH

**Native first:**
- `NSColorSampler` (macOS 10.15+): use directly. Zero permissions, zero deps. `NSColorSampler().show(selectionHandler:)` returns an `NSColor?` asynchronously.
- `NSColorPanel`: already wrapped by SwiftUI `ColorPicker`. Use `ColorPicker("", selection: $color)` in SwiftUI; drop to `NSColorPanel.shared` only if custom panel configuration is needed.
- OKLCH conversion: **ChromaKit 0.1.1**. No native macOS API exists for OKLCH. ChromaKit follows CSS Color Level 4 math and extends `NSColor`. Acceptable addition for Phase 2.

### Launch at Login: SMAppService

**Decision: Native `SMAppService` (ServiceManagement framework, macOS 13.0+).**

`SMAppService.mainApp.register()` / `.unregister()` are the only Apple-supported APIs for login items on Sonoma. All prior APIs (`SMLoginItemSetEnabled`, `LSSharedFileList`) are deprecated or removed. No package needed. Works without sandboxing; a user notification informs the user when a login item is added (macOS 13+ behavior, cannot be suppressed by design).

### Auto-Update: Sparkle

**Decision: Sparkle 2.9.3 via Swift Package Manager.**

No viable alternative for non-MAS .dmg distribution. Integrate in Phase 3 only. Use EdDSA signing (`generate_keys` → store private key in Keychain → embed public key in `Info.plist` as `SUPublicEDKey`). Host an `appcast.xml` at a stable URL. Use delta updates after v1.1 to minimize download size.

The Sparkle XPC service runs in a separate sandboxed process — no additional entitlements needed in the main app.

### .dmg Packaging + Notarization

**Decision: create-dmg 8.1.0 + Xcode notarytool.**

1. Archive and export Developer ID-signed `.app` from Xcode
2. `create-dmg Flint.app ./dist` — produces a styled DMG with background + alias
3. `xcrun notarytool submit ./dist/Flint*.dmg --keychain-profile "AC_PASSWORD" --wait`
4. `xcrun stapler staple ./dist/Flint*.dmg`

`altool` was deprecated and removed in November 2023. `notarytool` is the only current path.

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| **SwiftData** | Critical bugs on macOS 14: broken observation, random reordering, non-functional `didSave`. Not stable enough for production on the minimum-supported OS. | GRDB 7 |
| **Highlightr (raspu)** | Explicitly deprecated by maintainer as of 2026. Last release June 2020, 22 open issues, no Swift 6 compatibility statement. | HighlightSwift for display; custom NSTextStorage for editable views |
| **Ink** | No full GFM (missing task lists, limited tables in v0.6.0), community-maintained, static-site oriented. | swift-markdown (swiftlang-backed, cmark-gfm) |
| **CryptoSwift** | ~500 KB addition, pure-Swift implementations slower than system CryptoKit/CommonCrypto for SHA/HMAC. No benefit over native for this use case. | CryptoKit + CommonCrypto (system) |
| **CGEventTap for global hotkey** | Requires Accessibility permission prompt at runtime — kills zero-friction UX for a dev tool with no other Accessibility need. | KeyboardShortcuts 3.0.1 |
| **Core Data** | Overkill for 100-row history log. Adds ~5 MB cold-start overhead and significant boilerplate. | GRDB 7 |
| **NSStatusItem bare (without MenuBarExtra)** | Abandons SwiftUI lifecycle, requires manual NSWindow management and NSPopover wiring. Only justified if `MenuBarExtra` proves unworkable. | SwiftUI `MenuBarExtra` (.window style) |
| **altool** | Removed from Apple notary service November 2023. Submitting with altool fails. | `xcrun notarytool` |
| **SwiftUI AttributedString(markdown:)** | Inline Markdown only (bold, italic, links). No fenced code blocks, tables, or task lists. Insufficient for a Markdown preview pane. | swift-markdown → WKWebView |

---

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| History store | GRDB 7.11.1 | SwiftData | Critical macOS 14 bugs make it unreliable on the min OS |
| History store | GRDB 7.11.1 | Core Data | Overkill for 100 rows; heavy boilerplate |
| History store | GRDB 7.11.1 | UserDefaults | No SQL search, plist size risk |
| Markdown parsing | swift-markdown 0.8.0 | Ink 0.6.0 | Incomplete GFM; not AST-based |
| Markdown rendering | WKWebView + swift-markdown | swift-markdown-ui | swift-markdown-ui is in maintenance mode (redirects to Textual); WKWebView gives PDF export for free |
| Syntax highlight (edit) | Custom NSTextStorage | Highlightr | Deprecated as of 2026 |
| Syntax highlight (display) | HighlightSwift 1.1.0 | Sourceful | Sourceful last released 2021, unmaintained |
| Global hotkey | KeyboardShortcuts 3.0.1 | CGEventTap | Requires Accessibility permission dialog |
| Auto-update | Sparkle 2.9.3 | Squirrel | Squirrel designed for Electron; unmaintained for native macOS |
| OKLCH | ChromaKit 0.1.1 | swift-oklch | swift-oklch is a single-file gist-level project; ChromaKit has proper SPM packaging |
| .dmg packaging | create-dmg 8.1.0 | Packages.app GUI | Not CI-automatable; create-dmg is scriptable and integrates with notarytool |

---

## Package Integration (Swift Package Manager)

All packages are added via Xcode → File → Add Package Dependencies.

```
KeyboardShortcuts:  https://github.com/sindresorhus/KeyboardShortcuts  (exact: 3.0.1)
GRDB.swift:         https://github.com/groue/GRDB.swift.git             (exact: 7.11.1)
HighlightSwift:     https://github.com/appstefan/HighlightSwift         (up to next minor: 1.1.0)
SwiftDiff:          https://github.com/turbolent/SwiftDiff               (branch: main — no semver)
swift-markdown:     https://github.com/swiftlang/swift-markdown          (exact: 0.8.0)
Sparkle:            https://github.com/sparkle-project/Sparkle           (exact: 2.9.3)  [Phase 3]
ChromaKit:          https://github.com/HarshilShah/ChromaKit             (exact: 0.1.1)  [Phase 2]
MenuBarExtraAccess: https://github.com/orchetect/MenuBarExtraAccess       (evaluate before adding)
```

CommonCrypto (CRC32 via zlib) requires no SPM entry — link `libz.tbd` in Xcode → Build Phases → Link Binary With Libraries, then `import zlib` (or use `CC_CRC32` via `import CommonCrypto`).

---

## Version Compatibility

| Package | Swift Req | macOS Min | Notes |
|---------|-----------|-----------|-------|
| KeyboardShortcuts 3.0.1 | 6.2 (tools) | 10.15 | Swift 6 toolchain required; Xcode 16+ |
| GRDB 7.11.1 | 6.1+ | 10.15 | Requires Xcode 16.3+; Swift 6 strict concurrency; use Sendable structs for records |
| HighlightSwift 1.1.0 | 5.9+ | 13.0 (est.) | Uses JavaScriptCore via highlight.js |
| SwiftDiff | 5.x | 10.10+ | No formal version; pin to Oct 2024 commit |
| swift-markdown 0.8.0 | 5.9+ | — | cmark-gfm C dependency; cross-platform |
| Sparkle 2.9.3 | 5.x | 10.13 | Requires Hardened Runtime + Developer ID signing |
| ChromaKit 0.1.1 | 5.x | 12.0 (est.) | Uses SwiftUI.Color API; verify against macOS 14 |

All packages are compatible with the project's macOS 14.0 deployment target.

---

## Footprint Estimate

| Component | Approx. Size Impact |
|-----------|-------------------|
| GRDB.swift (static) | ~800 KB |
| KeyboardShortcuts | ~200 KB |
| HighlightSwift + highlight.js bundle | ~400 KB |
| swift-markdown + cmark-gfm | ~600 KB |
| Sparkle.framework | ~4 MB (Phase 3) |
| ChromaKit | ~50 KB |
| SwiftDiff | ~30 KB |
| **Total packages (excl. Sparkle)** | **~2 MB** |

App bundle target is < 20 MB — well within budget even with Sparkle.

---

## Sources

- KeyboardShortcuts GitHub (verified 2026-06-25): https://github.com/sindresorhus/KeyboardShortcuts — version 3.0.1, Swift 6.2 tools, macOS 10.15+
- GRDB.swift GitHub releases (verified 2026-06-25): https://github.com/groue/GRDB.swift — version 7.11.1, Xcode 16.3+
- GRDB Migration Guide (Context7 HIGH): v7 requires Swift 6 compiler and Xcode 16+
- Highlightr deprecation notice (verified 2026-06-25): https://github.com/raspu/Highlightr — "no longer actively maintained, use HighlightSwift"
- HighlightSwift GitHub (verified 2026-06-25): https://github.com/appstefan/HighlightSwift — version 1.1.0
- Sparkle GitHub releases (verified 2026-06-25): https://github.com/sparkle-project/Sparkle — version 2.9.3
- swift-markdown GitHub releases (verified 2026-06-25): https://github.com/swiftlang/swift-markdown — version 0.8.0
- ChromaKit GitHub (verified 2026-06-25): https://github.com/HarshilShah/ChromaKit — version 0.1.1, OKLCH + NSColor
- create-dmg GitHub (verified 2026-06-25): https://github.com/sindresorhus/create-dmg — version 8.1.0
- SwiftDiff GitHub (verified 2026-06-25): https://github.com/turbolent/SwiftDiff — Google Diff port, Oct 2024 last commit
- Apple Developer Docs — SMAppService: https://developer.apple.com/documentation/servicemanagement/smappservice — macOS 13+
- Apple Developer Docs — NSColorSampler: macOS 10.15+, zero permissions needed
- Apple Developer Docs — MenuBarExtra: https://developer.apple.com/documentation/SwiftUI/MenuBarExtra
- MenuBarExtraAccess (programmatic dismiss workaround): https://github.com/orchetect/MenuBarExtraAccess
- SwiftData macOS 14 bugs documented: https://mjtsai.com/blog/2024/06/04/swiftdata-issues-in-macos-14-and-ios-17/
- Apple notarytool (altool deprecated Nov 2023): https://developer.apple.com/documentation/security/customizing-the-notarization-workflow
- CryptoKit limitations (no CRC32): https://www.andyibanez.com/posts/cryptokit-not-enough/
- Sparkle docs (EdDSA signing, appcast): https://sparkle-project.org/documentation/

---
*Stack research for: Flint — native macOS menubar developer-utility app*
*Researched: 2026-06-25*
