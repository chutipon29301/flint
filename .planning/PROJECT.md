# Lathe — macOS Developer Toolkit (Menubar)

## What This Is

Lathe is a native SwiftUI menubar application for macOS that gives developers instant, offline access to common encoding, formatting, and transformation utilities (JSON, Base64, JWT, hashing, UUIDs, regex, color, markdown, diffing, and more). It lives in the menubar, opens in under a second via global hotkey, and works entirely on-device with no network, no account, and no subscription.

## Core Value

A developer can paste content and get the right transformation in under a second — fully offline, from anywhere on the system. If everything else fails, the core tools must be instant, correct, and never crash on bad input.

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

(None yet — ship to validate)

### Active

<!-- Current scope. Building toward these. v1 hypotheses until shipped. -->

**Infrastructure**
- [ ] Menubar app skeleton (MenuBarExtra) with popover + detachable window modes
- [ ] Global hotkey (`⌘⇧Space`, configurable) to open/focus from any app
- [ ] Clipboard auto-detection with non-destructive suggestion banner
- [ ] Persistent history (last 100 transformations, searchable, re-openable, SQLite)
- [ ] Global fuzzy search across tools + history, keyboard navigable
- [ ] Favorites/pinning (up to 6 tools in quick-access)
- [ ] Preferences (general, appearance, history, per-tool defaults)
- [ ] Full Light/Dark mode + accessibility (VoiceOver, Dynamic Type)

**Phase 1 Core Tools (MVP)**
- [ ] JSON Formatter & Validator (pretty/minify, validation, JSONPath, sort keys, diff)
- [ ] Base64 Encoder/Decoder (text + file, URL-safe variant, auto-direction)
- [ ] URL Encoder/Decoder + URL parser with editable query-param table
- [ ] JWT Decoder (header/payload/signature, expiry countdown, HMAC verify, claims table, warnings)
- [ ] Unix Timestamp Converter (multi-timezone, reverse, "now", relative, ISO 8601)
- [ ] Hash Generator (MD5/SHA-1/256/384/512/CRC32, HMAC, text + file)
- [ ] UUID Generator & Inspector (v1/v4/v5/v7, bulk to 1000, parse/inspect)

**Phase 2 Extended Tools**
- [ ] Regex Tester (flags, live highlight, capture groups, replace, pattern library)
- [ ] Color Converter (HEX/RGB/HSL/HSV/OKLCH, screen picker, contrast checker)
- [ ] Markdown Previewer (split live preview, GFM, export HTML/PDF)
- [ ] Number Base Converter (bin/oct/dec/hex, bit-width, signed, bit-field UI)
- [ ] Text Diff Viewer (side-by-side/unified, word-level, patch export)

**Phase 3 Polish & Distribution**
- [ ] macOS Services menu integration (right-click text → route to best tool)
- [ ] Drag & drop of text/binary files into all tools
- [ ] .dmg distribution + onboarding flow
- [ ] Auto-update (Sparkle)

### Out of Scope

<!-- Explicit boundaries with reasoning. -->

- Cloud sync / account system — v1 is local-first and offline by design
- Mobile / iOS version — desktop-only product focus
- Plugin marketplace — adds platform/maintenance burden not justified for v1
- Collaboration features — single-user tool, no multiplayer need
- Analytics / telemetry / crash reporting — privacy stance; opt-in Sentry deferred to v2
- App Store sandboxing in v1 — not sandboxed v1 to allow clipboard/file access; sandboxed App Store build is a v2 target
- Network entitlement — no tool requires the network; none will be requested

## Context

- **Source spec:** Full PRD lives in `requirement.md` at repo root — the authoritative feature reference.
- **Platform:** macOS 14.0 (Sonoma)+, Swift 5.9+, SwiftUI, MVVM.
- **Distribution:** Direct `.dmg` download first; Mac App Store as v2.
- **Footprint targets:** < 20 MB bundle, < 50 MB idle RAM, < 100 MB under load.
- **Suggested packages:** KeyboardShortcuts (global hotkey), Highlightr (NSTextView syntax highlighting), SwiftDiff (diffing), Ink (markdown), GRDB (SQLite history). To be validated during research — prefer native APIs where they suffice (ponytail: don't pull a dependency for what Foundation/CryptoKit/NSColorSampler already do).
- **Workflow:** Some crypto (MD5/SHA via CryptoKit/CommonCrypto), color (NSColorSampler eyedropper), markdown export (WKWebView → PDF) lean on native macOS frameworks.

## Constraints

- **Tech stack**: SwiftUI + MVVM, Swift 5.9+ — native macOS requirement, no cross-platform/web stack.
- **Platform**: macOS 14.0+ — uses MenuBarExtra and modern SwiftUI APIs that require Sonoma.
- **Offline**: Zero network dependency for any core tool — privacy and instant-availability guarantee.
- **Performance**: Cold start < 500ms, hotkey-to-popover < 200ms, clipboard detect < 100ms — "zero friction" is the core value.
- **Robustness**: No tool may crash on malformed input — all inputs validated gracefully.
- **Sandboxing**: v1 NOT sandboxed (needs clipboard + arbitrary file access); App Store v2 will sandbox.
- **Accessibility**: VoiceOver labels on all interactive elements, Dynamic Type scaling — system convention compliance.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Coarse phase granularity (~3 phases) | PRD already defines a clean 3-phase delivery plan (Core/Extended/Polish) | — Pending |
| SQLite (GRDB) for history, UserDefaults for prefs | 100-item searchable history needs queryable store; prefs are simple key-values | — Pending |
| Not sandboxed in v1 | Clipboard auto-detect + arbitrary file hashing/encoding need broad access | — Pending |
| Native frameworks before packages | CryptoKit, NSColorSampler, WKWebView, Foundation cover much of the spec | — Pending |
| Direct .dmg distribution first | Faster to ship than App Store review; sandboxing deferred to v2 | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-06-25 after initialization*
