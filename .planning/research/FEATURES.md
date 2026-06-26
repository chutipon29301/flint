# Feature Research

**Domain:** macOS Developer Utility Menubar App
**Researched:** 2026-06-25
**Confidence:** HIGH (competitor analysis based on DevToys v2, DevUtils 47+ tools, Wring, Boop — all verified via official sources and live product pages)

---

## Competitor Baseline

Before categorizing, a snapshot of what direct competitors ship:

| Tool | Count | Notable inclusions | Notable gaps vs Flint PRD |
|------|-------|-------------------|--------------------------|
| **DevToys v2** | 30 built-in | JSON↔YAML, SQL formatter, XML formatter, Lorem Ipsum, Password gen, QR Code, GZip, Color Blindness Simulator, PNG/JPEG compressor | No OKLCH, no UUID v7, no Markdown PDF export, no screen color picker |
| **DevUtils.app** | 47+ | Cron parser, String case converter, YAML↔JSON, JSON↔CSV, HTML entity encode/decode, ULID, Lorem Ipsum, QR Code, SQL formatter, CSS/JS beautify, PHP serializer, cURL-to-code, X.509 cert decoder | Pays $40–80, no diff word-level highlight |
| **Boop** | ~100 scripts | Scriptable transforms, case conversion, line sort/dedup, regex replace | No persistent history, no clipboard auto-detect, modal UX not tool-per-view |
| **Wring** | 12 | Cron parser, .env Keychain manager, load monitor, HTML/hex encode, case conversion, HS256 JWT verify | No Markdown, no Number Base bit-field UI, no OKLCH, no bulk UUID |
| **CyberChef** | 483 | Chained operations pipeline, 483 ops including XOR, AES, X.509, compression | Browser-based, not native macOS, not offline-guaranteed |

---

## Feature Landscape

### Table Stakes (Users Expect These)

Features that every serious developer utility ships. Missing any of these will cause users to reach for a competitor without filing a bug report.

| Feature | Why Expected | Complexity | PRD Status | Notes |
|---------|--------------|------------|------------|-------|
| JSON pretty-print + minify | First thing anyone pastes; shipped by all 5 competitors | LOW | Included (5.1) | Core formatter |
| JSON real-time validation with error location | Baked into every JSON tool; line+column is the standard | LOW | Included (5.1) | `JSONSerialization` covers this |
| Base64 encode/decode (text) | Ubiquitous; ships in every dev toolkit without exception | LOW | Included (5.2) | |
| URL encode/decode (percent-encoding) | URL manipulation is daily for any backend/API dev | LOW | Included (5.3) | |
| JWT decode (header + payload display) | Auth debugging is universal; all 5 competitors ship this | LOW | Included (5.4) | Decode only (not verify) is table stakes |
| Unix timestamp → human date | Log debugging staple; ships in every competitor | LOW | Included (5.5) | |
| Hash generation (SHA-256, SHA-512 at minimum) | File integrity and API signing are ubiquitous; all competitors ship | LOW | Included (5.6) | CryptoKit covers all required algorithms natively |
| UUID v4 generation | Daily dev task; built into Foundation; all competitors ship | LOW | Included (5.7) | `UUID()` in Foundation is v4 |
| Regex test + live match highlight | Every competitor ships this; developers expect REPL-style regex | MEDIUM | Included (5.8) | NSRegularExpression handles the engine |
| Color format conversion (HEX/RGB/HSL) | All 5 competitors include color conversion | MEDIUM | Included (5.9) | Standard 3 formats are table stakes |
| Text diff (line-level) | All competitors ship diff; side-by-side or unified are both standard | MEDIUM | Included (5.12) | |
| Clipboard auto-detection + smart routing | DevToys, DevUtils, Wring all ship this; sets UX expectation | MEDIUM | Included (4.1) | Non-destructive banner is the right pattern |
| Global hotkey to open app | Menubar apps without a hotkey feel broken | LOW | Included (3.2) | KeyboardShortcuts package |
| Copy output in one click | Universal UX expectation; listed in acceptance criteria | LOW | Included (AC) | |
| Light/Dark mode | macOS system expectation since Mojave | LOW | Included (8.3) | |
| Search across tools | All menubar dev apps ship fuzzy search from the launcher | LOW | Included (4.3) | |
| History (re-open past transformations) | DevUtils and DevToys both ship history; users rely on it | MEDIUM | Included (4.2) | SQLite via GRDB is correct choice |

### Differentiators (Competitive Advantage)

Features where Flint can meaningfully exceed the competitive baseline or offer something competitors lack.

| Feature | Value Proposition | Complexity | PRD Status | Notes |
|---------|-------------------|------------|------------|-------|
| **URL parser with editable query-param table** | DevUtils has URL parse but no interactive param editor; editing + rebuilding URL is rare among competitors | MEDIUM | Included (5.3) | Genuine differentiator; rebuild-from-params is genuinely useful |
| **JWT HMAC signature verification** | Wring ships HS256 verify; DevUtils does NOT; debugging signed tokens locally avoids pasting secrets into jwt.io | HIGH | Included (5.4) | See security note below — high complexity, sensitive data risk |
| **UUID v7 generation + inspect** | UUID v7 (RFC 9562, May 2024) is not yet in Foundation; no competitor ships it; sortable UUIDs are a growing need for DB-heavy developers | HIGH | Included (5.7) | Requires third-party Swift package; v7 inspection (extract embedded timestamp) adds more value than generation alone |
| **UUID v5 (namespace+name SHA-1)** | Less common but deterministic UUIDs matter for reproducible IDs; only some competitors cover this | MEDIUM | Included (5.7) | SHA-1 via CryptoKit |
| **OKLCH color space output** | No competitor ships OKLCH; CSS Color Module Level 4 is current; frontend devs increasingly need OKLCH values | HIGH | Included (5.9) | Conversion math is non-trivial (OKLAB perceptual intermediate); no native Apple API; manual float math required |
| **Screen color picker (NSColorSampler)** | Wring and DevUtils lack a screen eyedropper; picking from any pixel is a design/dev workflow tool | LOW | Included (5.9) | NSColorSampler is native, no entitlement needed beyond macOS 10.15; simple API |
| **WCAG contrast ratio checker** | No competitor ships contrast checking inline with color conversion; accessibility tooling in a dev utility is rare | MEDIUM | Included (5.9) | WCAG AA/AAA ratio algorithm is a few dozen lines of math |
| **JSONPath query on formatter output** | DevToys has a standalone JSONPath tester; shipping it embedded in the JSON formatter creates a tighter workflow | HIGH | Included (5.1) | Requires Sextant or SwiftPath package; adds meaningful power but scope risk in MVP |
| **Markdown → PDF export** | DevUtils has Markdown Preview (HTML export only); PDF via WKWebView is not common among competitors | HIGH | Included (5.10) | WKWebView.createPDF() on macOS 14+ is the path; non-trivial styling parity between preview and PDF |
| **Number base converter bit-field UI** | DevUtils and DevToys ship number base conversion but no interactive bit toggles; the 8-bit clickable bit visualizer is unique | MEDIUM | Included (5.11) | The bit-toggle UI is genuinely differentiated; pure SwiftUI state management |
| **Two's complement for signed numbers** | Rare in competitor tools; important for embedded/systems developers | LOW | Included (5.11) | Math-only; no library needed |
| **Bulk UUID generation to 1000 + bulk export** | DevUtils ships single UUID; DevToys ships bulk but not JSON/CSV export formats | MEDIUM | Included (5.7) | Copy-all to clipboard or save file |
| **Word-level diff within changed lines** | Line-level diff is table stakes; word-level diff within changed lines (not just changed lines) is higher fidelity | MEDIUM | Included (5.12) | SwiftDiff or custom Levenshtein; some packages only do line-level |

### Anti-Features (Deliberately NOT Build)

Features that appear on competitor lists and will be requested by users, but should be out of scope for v1.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| **YAML↔JSON converter** | Ships in DevToys, DevUtils; YAML is common in CI/devops config | Requires a YAML parser (no native Foundation support); Yams package adds ~500KB; first-class YAML handling is a significant scope addition for a tool most non-devops developers won't use daily | Defer to v2; JSON formatter covers 80% of use cases |
| **SQL formatter** | DevToys and DevUtils both ship SQL formatting | SQL AST parsing is a hard problem requiring a full parser; quality bar is high (keywords, indentation, dialect awareness); no lightweight Swift SQL formatter exists natively | Out of scope; SQLiteParser or similar adds weight; not core to Flint's identity |
| **Lorem Ipsum generator** | Ships in DevToys, DevUtils; trivially easy to implement | It's a 10-line text generator; the opportunity cost is zero but it also adds essentially zero value to a developer toolkit focused on encoding/debugging; it's a novelty filler | Omit; users have a dozen browser extensions for this |
| **QR Code generator/reader** | Ships in DevToys, DevUtils; frequent user request | Requires CoreImage CIFilter (generation) + Vision framework (reading); reading requires camera or image file; adds framework overhead and a new permission surface for a tool most developers use rarely | Omit v1; add as a v2 standalone extension if demanded |
| **String case converter** (camelCase, snake_case, PascalCase, kebab-case) | Ships in DevUtils and Wring; trivially useful | Adds a tool slot for what is a 30-line tokenizer; tokenizing edge cases (XMLHttpRequest, iOS prefix) are tricky; the tool competes with the text editor's built-in transformations in most IDEs | Defer to v2 as a lightweight addition to a "Text Utilities" catch-all tool |
| **Cron expression parser** | Ships in DevUtils, Wring, DevToys (via extension); frequently requested | Core cron parsing requires building or importing a cron grammar (no native Foundation support); "next N runs" display requires date arithmetic across DST; moderate scope for a tool used occasionally | Defer to v2; it's a high-signal feature but not MVP-critical |
| **HTML entity encoder/decoder** | Ships in DevUtils, DevToys; web dev staple | Flint's current identity is API/backend dev tools; HTML entity encoding is a web/content dev task at a lower frequency; easily done with a browser console | Defer; if the URL tool proves popular, add HTML encode as a sibling |
| **Plugin / extension marketplace** | CyberChef model; Boop is entirely script-based; power users want custom transforms | Platform maintenance burden; security surface; version compatibility; JS sandbox in a native app is complexity overhead; PRD already calls this out of scope | Stay out of scope; Boop exists for the scripting use case |
| **Collaboration / share transforms** | CyberChef recipe sharing model; users occasionally want to share a chain | Requires network, server, account; violates the core privacy guarantee | Stays out of scope per PRD |
| **Password generator** | Ships in DevToys; common request | Security-sensitive; entropy display, character set options, clipboard handling of secrets — all create scope; SecRandomCopyBytes makes it easy technically but the UX/trust surface is distinct from encoding tools | Low priority; if added, it's a 1-screen generator after core tools validated |

---

## Feature Dependencies

```
[Clipboard Auto-Detection]
    └──requires──> [Tool registration system] (each tool declares what patterns it accepts)
    └──enhances──> [History] (auto-detect events should log to history)

[History]
    └──requires──> [SQLite store / GRDB]
    └──enhances──> [Search] (history items are searchable)

[Search]
    └──requires──> [Tool registration system] (to query tool names + descriptions)
    └──enhances──> [Favorites] (pinned tools surface first in results)

[JWT HMAC Verify]
    └──requires──> [JWT Decode] (verify is a sub-mode of decode, not standalone)
    └──requires──> [CryptoKit HMAC] (available natively; no external dep)

[JSONPath Query]
    └──requires──> [JSON Formatter] (operates on already-parsed JSON)
    └──requires──> [Sextant or SwiftPath package]

[UUID v7 Generation]
    └──requires──> [Third-party Swift package] (Foundation UUID only generates v4)
    └──requires──> [UUID v7 inspect] ← deserves linked implementation

[UUID v5 Generation]
    └──requires──> [Namespace input field]
    └──requires──> [CryptoKit SHA-1]

[OKLCH Output]
    └──requires──> [Color Converter] (it's an output format, not standalone)
    └──requires──> [Manual OKLAB ↔ sRGB math] (no native Apple API)

[Screen Color Picker]
    └──requires──> [NSColorSampler] (available macOS 10.15+; no entitlement)
    └──enhances──> [Color Converter] (feeds picked color as input)

[Markdown PDF Export]
    └──requires──> [Markdown Preview / WKWebView rendering]
    └──requires──> [WKWebView.createPDF()] (macOS 14+ async API)

[WCAG Contrast Checker]
    └──requires──> [Color Converter] (two colors as input)

[Word-level Diff]
    └──requires──> [Line-level Diff] (word diff runs within changed lines only)
    └──requires──> [SwiftDiff or equivalent word tokenizer]

[Bulk UUID Export (CSV/JSON)]
    └──requires──> [UUID Generation]
    └──requires──> [File save panel] (NSSavePanel)

[History Panel]
    └──enhances──> [All tools] (every tool writes to history on transform)
    └──requires──> [SQLite / GRDB]

[Favorites / Pinning]
    └──requires──> [Tool registration system]
    └──enhances──> [Popover quick-launch grid]
```

### Dependency Notes

- **JSONPath requires Sextant/SwiftPath:** No native Foundation API exists for JSONPath queries. Sextant is the highest-performance Swift option (HIGH confidence from GitHub). This is the one external dep that isn't covered by CryptoKit/Foundation/AppKit.
- **UUID v7 requires external package:** Foundation `UUID()` only generates v4. The Swift Forums pitch for v7 in Foundation (May 2024) has not shipped. `nthState/UUIDV7` or `leodabus/UUIDv7` from Swift Package Index are available. LOW risk dependency.
- **OKLCH has no Apple-native path:** NSColor and CGColor have no OKLCH support. The conversion requires implementing the sRGB → linear sRGB → XYZ → OKLAB → OKLCH chain manually. This is ~100 lines of verified float math.
- **JWT HMAC verify is a sub-mode:** Do not build it as a separate tool. It sits inside the JWT decoder as an optional verification step. Secrets entered for verification should NOT be persisted to history.

---

## PRD Feature Assessment

Cross-checking every PRD tool against the competitor landscape and complexity estimate.

### Phase 1 — Core Tools

| PRD Feature | Competitive Baseline | Complexity | Flag |
|-------------|---------------------|------------|------|
| JSON Formatter: pretty/minify, validation, sort keys | Universal; all competitors | LOW | OK |
| JSON Formatter: JSONPath query | DevToys has standalone JSONPath tester; DevUtils has it | HIGH | **AMBITIOUS** — adds Sextant dependency; consider deferring to Phase 2 or making it a tab within the formatter |
| JSON Formatter: diff view (two JSON objects) | Rare in formatters specifically; usually a separate diff tool | HIGH | **AMBITIOUS** — building diff into the JSON formatter scope-inflates Phase 1; move diff to Text Diff tool or defer this variant |
| Base64: text encode/decode + URL-safe variant | Universal | LOW | OK |
| Base64: file mode (encode file → B64, decode B64 → file) | DevUtils has B64 image encode; file-arbitrary is less common | MEDIUM | OK — NSSavePanel + file drag; manageable |
| URL encode/decode | Universal | LOW | OK |
| URL parser with editable query-param table + rebuild | Rare (no competitor has editable rebuild) | MEDIUM | **DIFFERENTIATOR** — worth the medium cost |
| JWT decode: header/payload/signature display | Universal | LOW | OK |
| JWT decode: expiry countdown + warnings | Ships in DevUtils, Wring | LOW | OK |
| JWT decode: HMAC signature verification | Wring ships HS256; DevUtils does NOT | MEDIUM | **DIFFERENTIATOR** but flag: never persist the HMAC secret to history |
| Unix Timestamp: multi-timezone simultaneous display | DevUtils ships with additional timezone support | MEDIUM | OK |
| Unix Timestamp: ISO 8601 output | Common; ships in most competitors | LOW | OK |
| Hash: MD5/SHA-1/256/384/512 + CRC32 | Universal; CryptoKit covers SHA variants natively | LOW | OK — CRC32 requires manual or a small helper; not in CryptoKit |
| Hash: HMAC mode | Ships in Wring, DevUtils | MEDIUM | OK |
| Hash: file hashing | DevUtils ships file hash | MEDIUM | OK — requires non-sandboxed file access (already planned) |
| UUID: v4 generation | Universal | LOW | OK |
| UUID: v1 (time-based) | Ships in DevUtils | MEDIUM | OK — node identifier randomization per-session |
| UUID: v5 (namespace+SHA-1) | Ships in DevUtils | MEDIUM | OK — CryptoKit SHA-1 |
| UUID: v7 (time-ordered, sortable) | NOT in any current competitor | HIGH | **DIFFERENTIATOR + AMBITIOUS** — requires external Swift package; RFC 9562 is 2024; genuinely forward-looking but adds package dependency and v7 timestamp inspection logic |
| UUID: bulk to 1000 + CSV/JSON export | DevToys ships bulk; CSV/JSON export is rarer | MEDIUM | OK — NSSavePanel; manageable scope |

### Phase 2 — Extended Tools

| PRD Feature | Competitive Baseline | Complexity | Flag |
|-------------|---------------------|------------|------|
| Regex: pattern + flags + live highlight | Universal | MEDIUM | OK |
| Regex: capture groups + named groups | Ships in DevUtils, DevToys | MEDIUM | OK |
| Regex: replace mode | Ships in DevUtils | MEDIUM | OK |
| Regex: pattern library (email, URL, phone, etc.) | Partial in DevUtils | LOW | OK — static list |
| Color: HEX/RGB/HSL/HSV conversion | Universal | MEDIUM | OK |
| Color: OKLCH output | NO competitor ships OKLCH | HIGH | **DIFFERENTIATOR + AMBITIOUS** — manual conversion chain required |
| Color: NSColorSampler screen picker | Wring and DevUtils lack this | LOW | **DIFFERENTIATOR** — NSColorSampler is a 5-line integration; genuinely easy win |
| Color: WCAG AA/AAA contrast checker | NO competitor ships this inline | MEDIUM | **DIFFERENTIATOR** — worth doing; pure math |
| Markdown: split live preview (GFM) | DevUtils ships Markdown Preview | MEDIUM | OK |
| Markdown: syntax highlight in editor | Partial in DevUtils | MEDIUM | OK — NSTextView + Highlightr |
| Markdown: export HTML | DevUtils ships HTML export | LOW | OK |
| Markdown: export PDF via WKWebView | NO competitor ships Markdown→PDF | HIGH | **DIFFERENTIATOR + AMBITIOUS** — WKWebView.createPDF() works but styling parity between preview and PDF is non-trivial; print margins, font rendering differ |
| Number Base: bin/oct/dec/hex simultaneous | DevUtils, DevToys ship this | LOW | OK |
| Number Base: bit-width selector + signed/unsigned | Partial in DevToys | MEDIUM | OK |
| Number Base: bit-field visual (clickable 8-bit toggles) | NO competitor ships interactive bit toggles | MEDIUM | **DIFFERENTIATOR** — pure SwiftUI state; no dep |
| Text Diff: side-by-side + unified toggle | All competitors ship line diff | MEDIUM | OK |
| Text Diff: word-level highlight within changed lines | Rare at this fidelity | MEDIUM | **DIFFERENTIATOR** — SwiftDiff handles line; word tokenization within lines is additional work |
| Text Diff: patch export | Partial in some tools | LOW | OK |

### Infrastructure

| PRD Feature | Competitive Baseline | Complexity | Flag |
|-------------|---------------------|------------|------|
| MenuBarExtra popover + detachable window | Standard macOS 13+ pattern | MEDIUM | OK |
| Global hotkey (KeyboardShortcuts package) | Universal in menubar dev tools | LOW | OK |
| Clipboard auto-detect + banner | DevUtils, DevToys, Wring all ship this | MEDIUM | OK — NSPasteboard polling + content classifiers |
| History 100 items, SQLite, per-tool + global | DevUtils ships history | MEDIUM | OK — GRDB is the right choice |
| Fuzzy search across tools + history | DevUtils ships global search | MEDIUM | OK |
| Favorites (up to 6, drag reorder) | DevUtils ships pinning | LOW | OK |
| Preferences (general/appearance/history/per-tool) | Standard | MEDIUM | OK |
| Light/Dark mode + accessibility | System requirement | LOW | OK |

---

## MVP Definition

### Launch With — Phase 1 (MVP)

Core 7 tools + infrastructure. This is what makes the app useful for the daily API/backend developer.

- [x] JSON Formatter: pretty/minify/validate/sort — **without JSONPath and diff view in v1**
- [x] Base64: text + URL-safe + file encode/decode
- [x] URL: encode/decode + parser with editable query-param table
- [x] JWT Decoder: header/payload/expiry/warnings + HMAC verify (but never persist the secret)
- [x] Unix Timestamp: multi-timezone + ISO 8601 + relative display
- [x] Hash Generator: all CryptoKit algorithms + CRC32 + HMAC + file hashing
- [x] UUID Generator: v1/v4/v5/v7 + bulk + inspect (v7 requires external package — evaluate at sprint start)
- [x] Infrastructure: popover/window, hotkey, clipboard auto-detect, history, search, favorites, preferences

**Cut from Phase 1 to reduce scope risk:**
- JSONPath query (move to Phase 2 as an enhancement to the JSON tool)
- JSON diff view embedded in formatter (covered by standalone Text Diff in Phase 2)

### Add After Validation — Phase 2

- [x] Regex Tester (full: flags, live highlight, capture groups, replace, pattern library)
- [x] Color Converter (HEX/RGB/HSL/HSV/OKLCH + screen picker + contrast checker)
- [x] Markdown Previewer (split view + GFM + export HTML; defer PDF to Phase 2.1)
- [x] Number Base Converter (all representations + bit-width + signed + bit-field UI)
- [x] Text Diff (line + word-level + unified/side-by-side + patch export)
- [x] JSONPath query tab within JSON formatter (using Sextant; moved from Phase 1)

### Future Consideration — v2+

- [ ] YAML↔JSON converter — add once user demand confirmed; needs Yams package
- [ ] Cron expression parser — confirmed user demand via DevUtils/Wring; add in v2
- [ ] String case converter — low effort; bundle into "Text Utilities" catch-all
- [ ] QR Code generator/reader — Vision + CoreImage; discrete feature not core to identity
- [ ] HTML entity encoder — add to URL tool or Text Utilities bundle
- [ ] Password generator — after core tools validated; separate UX concern
- [ ] Markdown → PDF export — Phase 2.1 (WKWebView PDF is well-defined but polish-intensive)

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| JSON Formatter (core) | HIGH | LOW | P1 |
| Base64 | HIGH | LOW | P1 |
| URL Encode/Decode | HIGH | LOW | P1 |
| JWT Decoder | HIGH | LOW | P1 |
| Unix Timestamp | HIGH | LOW | P1 |
| Hash Generator | HIGH | LOW | P1 |
| UUID v4 + bulk | HIGH | LOW | P1 |
| Clipboard auto-detect | HIGH | MEDIUM | P1 |
| History + search | HIGH | MEDIUM | P1 |
| Global hotkey + popover | HIGH | LOW | P1 |
| Regex Tester | HIGH | MEDIUM | P1 |
| Text Diff | HIGH | MEDIUM | P1 |
| Color Converter (HEX/RGB/HSL) | MEDIUM | MEDIUM | P1 |
| Markdown Previewer | MEDIUM | MEDIUM | P2 |
| Number Base Converter | MEDIUM | MEDIUM | P2 |
| UUID v7 (+ package dep) | MEDIUM | HIGH | P2 |
| URL param editor (editable table) | HIGH | MEDIUM | P2 |
| OKLCH color output | LOW | HIGH | P2 |
| Screen color picker (NSColorSampler) | MEDIUM | LOW | P2 |
| WCAG contrast checker | MEDIUM | MEDIUM | P2 |
| JWT HMAC signature verify | MEDIUM | MEDIUM | P2 |
| Bit-field visual (8-bit toggle) | LOW | MEDIUM | P2 |
| Word-level diff | MEDIUM | MEDIUM | P2 |
| JSONPath query (Phase 2 tab) | MEDIUM | HIGH | P2 |
| Markdown → PDF export | LOW | HIGH | P3 |
| YAML↔JSON | MEDIUM | MEDIUM | P3 |
| Cron parser | MEDIUM | MEDIUM | P3 |
| String case converter | LOW | LOW | P3 |
| QR Code generator | LOW | MEDIUM | P3 |
| Lorem Ipsum | LOW | LOW | — omit |
| SQL formatter | LOW | HIGH | — omit |
| Plugin marketplace | LOW | HIGH | — omit |

---

## Competitor Feature Analysis

| Feature | DevToys v2 | DevUtils.app | Wring | Flint PRD |
|---------|------------|--------------|-------|-----------|
| JSON format/validate | YES | YES | YES | YES |
| JSONPath query | YES (standalone) | NO | NO | Phase 2 tab |
| JSON diff | Via Text Comparer | Via Text Diff | YES | Phase 2 standalone |
| Base64 | YES | YES | YES | YES |
| URL encode/decode | YES | YES | YES | YES |
| URL param editor | NO | YES | NO | YES (differentiator) |
| JWT decode | YES | YES | YES | YES |
| JWT HMAC verify | NO | NO | YES (HS256 only) | YES (HS256/384/512) |
| Unix Timestamp | YES | YES | YES | YES |
| Hash generator | YES | YES (incl. Keccak-256) | YES | YES |
| UUID v4 | YES | YES (+ ULID) | YES | YES |
| UUID v7 | NO | NO | NO | YES (differentiator) |
| Regex tester | YES (via JSONPath Tester) | YES | YES | YES |
| Color convert HEX/RGB/HSL | YES | YES | YES | YES |
| OKLCH color | NO | NO | NO | YES (differentiator) |
| Screen color picker | NO | NO | NO | YES (differentiator) |
| WCAG contrast checker | NO | NO | NO | YES (differentiator) |
| Markdown preview | YES | YES | NO | YES |
| Markdown → PDF | NO | NO | NO | Phase 2.1 |
| Number base converter | YES | YES | NO | YES |
| Bit-field visual UI | NO | NO | NO | YES (differentiator) |
| Text diff | YES | YES | YES | YES |
| Word-level diff | NO | NO | NO | YES (differentiator) |
| Cron parser | YES (ext.) | YES | YES | NOT in v1 (v2) |
| YAML↔JSON | YES | YES | NO | NOT in v1 (v2) |
| String case converter | NO | YES | YES | NOT in v1 (v2) |
| QR Code | YES | YES | NO | NOT in v1 (v2) |
| Lorem Ipsum | YES | YES | NO | Omit |
| SQL formatter | YES | YES | NO | Omit |

---

## PRD Ambition Flags (Summary)

Items in the PRD that are unusually ambitious relative to the competitive baseline or carry hidden implementation risk:

**HIGH concern — consider scoping or sequencing carefully:**

1. **UUID v7 in Phase 1** — RFC 9562 shipped May 2024; no Foundation support; requires external package; v7 inspect (extract embedded Unix ms timestamp) is additional logic. No competitor ships this. Recommend: keep it as a differentiator but validate the Swift package choice before committing. Move to Phase 2 if package vetting delays Phase 1.

2. **JSONPath inside the JSON formatter (Phase 1)** — This is a second tool embedded inside the JSON tool. Sextant/SwiftPath are mature but untested in this project. Adds a significant tab of UI and a package dependency. Recommend: extract to Phase 2 as a tab within the existing formatter view.

3. **JSON diff embedded in the JSON formatter (Phase 1)** — Having a diff mode inside the formatter duplicates what the Phase 2 Text Diff tool already covers. Two-pane diff inside the formatter is complex to build separately from the standalone diff. Recommend: remove from Phase 1 formatter spec; point users to the standalone Text Diff in Phase 2.

4. **OKLCH color conversion** — No native Apple API exists for OKLAB. The conversion chain (sRGB → linearRGB → XYZ D65 → OKLAB → OKLCH) must be implemented in float arithmetic. The math is correct and ~100 lines but has no test oracle in the OS. Recommend: include in Phase 2 but flag for correctness testing against a reference implementation (e.g., Evil Martians OKLCH picker outputs).

5. **Markdown → PDF export** — WKWebView.createPDF() is the right API and it works. The complexity is styling: the rendered preview and the exported PDF use different rendering paths, and fonts/margins/code block styling require explicit CSS in the WKWebView HTML template to look correct. This is a polish-intensive feature, not a logic-intensive one. Recommend: include in Phase 2 as a deferred task (Phase 2.1) after the HTML export is working.

**MEDIUM concern — manageable but worth noting:**

6. **JWT HMAC verification** — The HMAC math is CryptoKit and straightforward. The risk is UX: the user enters a production JWT secret into a text field. The history system MUST NOT persist the secret. The HMAC key input needs an explicit "not saved" notice. Wring ships this correctly (Keychain-backed .env manager kept separate from JWT tool).

7. **CRC32 hashing** — CryptoKit does NOT include CRC32. It requires zlib's `crc32()` via `import zlib` or a manual table-driven implementation. Small scope gap; easy to resolve with `import Darwin.zlib` on macOS.

8. **UUID v1 (time-based with random node)** — UUID v1 traditionally includes the MAC address as node; exposing MAC address is a privacy concern. Correct implementation generates a random node per session (no MAC address). This is the right approach but must be deliberate.

**PRD features correctly out of scope (confirmed):**
- Cloud sync, plugin marketplace, collaboration: confirmed correct by competitive analysis
- App Store sandboxing in v1: correct; clipboard + arbitrary file access require non-sandboxed entitlements
- No analytics/telemetry: consistent with Wring and the privacy positioning; users cite this as a reason to prefer these tools

**Expected-but-missing features confirmed as correctly deferred:**
- Cron parser: in competitors but v1 scope is right; add in v2 with high confidence it will be requested
- YAML↔JSON: in all major competitors; notable absence but correct to defer given no native YAML parser in Foundation
- String case converter: low complexity but low daily utility for API-focused devs; v2 is correct
- QR Code: in DevToys and DevUtils; not daily-use enough to merit Phase 1

---

## Sources

- [DevToys v2 GitHub repository](https://github.com/DevToys-app/DevToys) — built-in tool list verified
- [DevUtils.app official site](https://devutils.com/) — 47+ tools list verified live
- [Wring macOS app](https://getwring.app/) — 12 tools list verified live
- [Boop GitHub repository](https://github.com/IvanMathy/Boop) — features confirmed
- [DevUtils vs DevToys vs OpenDev comparison](https://dev.to/jamalianpour/devutils-vs-devtoys-vs-opendev-which-developer-utility-tool-is-right-for-you-a4j)
- [RFC 9562 UUID v7 (May 2024)](https://www.rfc-editor.org/rfc/rfc9562) — UUID v7 standard confirmed
- [Swift Forums UUID v7 pitch](https://forums.swift.org/t/pitch-uuid-v7-other-improvements/85427) — Foundation support status confirmed absent
- [NSColorSampler — DSFColorSampler reference](https://github.com/dagronf/DSFColorSampler) — no entitlement requirement confirmed
- [OKLCH in CSS — Evil Martians](https://evilmartians.com/chronicles/oklch-in-css-why-quit-rgb-hsl) — OKLCH conversion complexity confirmed
- [Sextant — high-performance JSONPath for Swift](https://github.com/KittyMac/Sextant) — JSONPath package option confirmed
- [WKWebView PDF creation on macOS](https://digitalbunker.dev/how-to-create-pdf-from-wkwebview/) — PDF export approach confirmed

---
*Feature research for: macOS Developer Utility Menubar App (Flint)*
*Researched: 2026-06-25*
