# Walking Skeleton — Flint

**Phase:** 1
**Generated:** 2026-06-25

## Capability Proven End-to-End

A developer presses ⌘⇧Space from any app, the Flint popover opens in under 200ms with no Accessibility prompt, they paste a JSON string, a non-destructive "Detected: JSON Formatter" banner appears, they open the JSON Formatter, it pretty-prints live with a 150ms debounce (keeping last-good output dimmed on malformed input), the successful transform writes one row to the GRDB history store, and searching "json" in the launcher finds that row.

## Architectural Decisions

| Decision | Choice | Rationale |
|---|---|---|
| UI framework | SwiftUI (macOS 14.0+) + `@Observable` macro | Native MenuBarExtra, property-level re-render, no ObservableObject cascade; CLAUDE.md constraint |
| Menubar surface | `MenuBarExtra` `.window` style + MenuBarExtraAccess 1.3.0 | `MenuBarExtra` has no 1st-party dismiss API (FB10185203); MenuBarExtraAccess `isPresented` binding is the only path for two-stage Esc (D-03, pitfall #1) |
| App lifecycle / service ownership | Services are `@State` in `FlintApp` struct, injected via `.environment()` | Only lifecycle-stable ownership point; tool ViewModels created on-demand per navigation (RESEARCH Pattern 1) |
| Tool abstraction | `ToolDefinition` struct + `ToolRegistry` (`@Observable`) | Single source for launcher, search, detection, services routing; frozen before tool work (INFRA-03, D-pre-Phase-1). Registry pre-registers all 7 `*Definition.make()` calls so tool plans never touch ToolRegistry.swift |
| Per-tool architecture | MVVM triad: pure `*Transformer` (no UI imports) + `@Observable @MainActor *ViewModel` + `*View`, plus a `*Definition` | Transformer fully unit-testable; ViewModel owns debounce + last-good-output; View owns per-field copy (RESEARCH Responsibility Map) |
| History store | GRDB 7.11.1 `DatabaseQueue` at `~/Library/Application Support/Flint/history.db`, opened off-main via `Task.detached(.utility)`, reactive via `ValueObservation` | SwiftData has critical macOS 14 bugs; GRDB gives typed records + migrations + reactive reads; off-main open protects the <500ms cold-start budget (pitfall #6) |
| Secrets handling | HMAC/JWT secret keys NEVER enter `HistoryEntry`; excluded by schema design + ViewModel serialization contract | Information-disclosure mitigation (INFRA-09, pitfall #3); secret is a View-local `@State` that never reaches the history closure |
| Preferences store | `@Observable` UserDefaults wrapper (`PreferencesStore`); secrets NEVER stored here | Simple key-value; no SQL needed; UserDefaults is iCloud-backed so secrets are forbidden |
| Global hotkey | KeyboardShortcuts 3.0.1 (Carbon `RegisterEventHotKey`) | Zero Accessibility permission prompt — required for zero-friction UX (INFRA-04) |
| Clipboard detection | `ClipboardDetector` `@Observable @MainActor`, `NSPasteboardDidChangeNotification` + popover-visibility gate; ordered first-match-wins predicate chain on `ToolRegistry` | 0% idle CPU (pitfall #7); detection fires within 100ms of focus (INFRA-06); single best match (D-06) |
| Window mode | `WindowCoordinator` toggling `NSApp.setActivationPolicy(.regular/.accessory)` around every window open/close | `.accessory` hides Dock icon but also hides windows behind frontmost app; the activation dance fixes it (pitfall #2, INFRA-02/INFRA-12) |
| Editable syntax highlight | Custom `NSTextStorage` subclass via `NSTextStorageDelegate`, wrapped in `SyntaxEditorView` (NSViewRepresentable) with `guard textView.string != text` re-render guard | No package works for editable NSTextView; guard prevents the infinite re-render loop (pitfall #5). HighlightSwift used display-only |
| Build configs | Dual entitlements: `Flint-debug.entitlements` (has `get-task-allow`) + `Flint-release.entitlements` (NO `get-task-allow`, Hardened Runtime), `CODE_SIGN_ENTITLEMENTS` per config | `get-task-allow` in Release fails notarization + is an EoP risk; dual entitlements from day one (security gate) |
| Directory layout | `App/`, `Core/{Services,Models,Extensions}/`, `Tools/<ToolName>/` (4-file pattern), `UI/{,Components}/`, `Resources/` | RESEARCH "Recommended Project Structure"; each tool is a self-owned folder for parallel execution |
| Deployment | Local: `xcodebuild -scheme Flint -destination 'platform=macOS' build` + run `Flint.app`; signed/notarized DMG deferred to Phase 3 | v1 is not sandboxed (needs clipboard + arbitrary file access); DMG/Sparkle is Phase 3 |

## Stack Touched in Phase 1 (Skeleton slice)

- [x] Project scaffold — Xcode project, macOS 14.0 target, Swift 6 language mode, 4 SPM packages, dual entitlements, libz.tbd linked
- [x] Routing — `MenuBarExtra` popover + `WindowGroup` workspace + `Settings` scene; search-driven navigation
- [x] Database — real write (JSON transform inserts a `HistoryEntry`) AND real read (`ValueObservation` surfaces it; search "json" finds it)
- [x] UI — `SyntaxEditorView` (NSTextView) wired to `JSONFormatterViewModel` with live 150ms debounce
- [x] Deployment — documented local full-stack run: `xcodebuild build` then launch; hotkey opens popover end-to-end

## Out of Scope (Deferred to Later Slices in this phase or beyond)

- The remaining six tools (Base64, URL, JWT, Timestamp, Hash, UUID) — separate Wave-2 slices (plans 01-02..01-05)
- First-class History view, global fuzzy search across history, pin/reorder of pinned tools — plan 01-06
- Preferences window, launch-at-login, detachable workspace polish, full VoiceOver + Dynamic Type audit, final perf instrumentation — plan 01-07
- UUID v7 generation (UUID-02) — gated on package vetting; defaults to Phase 2 deferral with a documented stub
- Regex/Color/Markdown/Number/Diff tools — Phase 2
- Services menu, drag-and-drop, signed/notarized DMG, Sparkle auto-update — Phase 3
- App Store sandboxing — v2

## Subsequent Slice Plan

Each later plan/phase adds one vertical slice on top of this skeleton without altering its architectural decisions:

- **01-02..01-05** (this phase, Wave 2): each remaining core tool as an independent `Tools/<X>/` slice that registers via its pre-wired `*Definition.make()` slot.
- **01-06** (this phase, Wave 2): History first-class view + global fuzzy search + pinned-tool reorder.
- **01-07** (this phase, Wave 3): Preferences + launch-at-login + workspace window + accessibility/perf hardening.
- **Phase 2:** Regex, Color, Markdown, Number Base, Text Diff tools (append `*Definition.make()` to the frozen registry).
- **Phase 3:** Services menu, drag-and-drop, signed/notarized DMG, Sparkle auto-update, VoiceOver audit.
