# Phase 1: Infrastructure + Core Tools - Context

**Gathered:** 2026-06-25
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 1 delivers the complete menubar app skeleton plus the seven core tools, proving the full `clipboard-detect → transform → history → search` pipeline end-to-end. Infrastructure (ToolRegistry, HistoryStore, ClipboardDetector, HotkeyManager, WindowCoordinator, PreferencesStore) is built and frozen first; JSON Formatter is the integration test; then Base64, URL, JWT, Timestamp, Hash, and UUID. All offline, under the performance targets, never crashing on bad input.

This discussion clarified **HOW** the UX behaves. The package stack, architecture layering, and the 11 critical pitfalls are already locked by `.planning/research/SUMMARY.md` and are NOT re-decided here.

</domain>

<decisions>
## Implementation Decisions

### Popover Layout & Navigation
- **D-01:** Search-first launcher. The popover (~480×600) opens with an **autofocused search field at the top**, a row of **6 pinned tools** below it, and **recent history** filling the body when the search field is empty. (Raycast/Spotlight feel.)
- **D-02:** The **search bar stays pinned at the top even inside a tool view** — typing there filters/switches tools. There is **no explicit back button**; navigation is search-driven.
- **D-03:** **Esc is two-stage:** first Esc returns from a tool to the launcher (empty search + pinned + recent); second Esc closes the popover. (Wire via MenuBarExtraAccess `isPresented` per the research pitfall #1 — `@Environment(\.dismiss)` does not work for MenuBarExtra.)

### Detection Banner UX
- **D-04:** Detection surfaces as a **non-destructive banner** ("Detected: JWT — Open JWT Decoder?") with **manual Accept/Dismiss**. It does **NOT** auto-open the tool — the user stays on the search-first launcher until they accept. Banner sits between the search bar and the pinned row.
- **D-05:** **Always re-show** the banner on focus when the clipboard matches, even after a prior dismissal. No per-value dismissal tracking (keeps state minimal).
- **D-06:** **Single best match only.** The ordered predicate chain (JSON → JWT → Base64 → URL-encoded → URL → timestamp → hex color → UUID → regex) is first-match-wins; the banner shows just that one suggestion. No alternate-match chips. If wrong, the user dismisses and searches manually.

### History Panel UX
- **D-07:** Full history is a **first-class view reachable through the same navigation model as tools** — via search ("history") or a pinned/quick slot. It opens a dedicated full-list view (last 100) with its own filter/search, pins, and delete. (Recent history on the launcher empty-state is the lightweight peek; this is the full surface.)
- **D-08:** **Clicking a history item restores the saved input into the matched tool and re-runs the transform live.** The saved output stored in the row is preview-only — output is always recomputed so it stays correct even if transform logic changed.
- **D-09:** **Pinned history items are exempt from the 100-item eviction cap and sort to the top.** Unpinned items roll off at 100. **"Clear" removes unpinned items only** (pins survive). Individual delete still works on any item.

### Tool I/O Interaction
- **D-10:** **Live, debounced transform** (~150ms) for the lightweight tools (JSON, Base64, URL, JWT, Timestamp, UUID-inspect). Output updates as the user types/pastes — matches the "under a second" core value. **Heavy operations stay button-triggered:** file hashing (HASH-02), bulk UUID generation up to 1000 (UUID-01), and file Base64 (B64-04).
- **D-11:** **Graceful inline errors that never blank the output.** On malformed input mid-typing, show a subtle inline error (with line:column for JSON per JSON-03) while keeping the **last valid output visible but dimmed**. No flicker-to-empty while typing.
- **D-12:** **Per-field copy buttons** on every output field/row (e.g. each of the 6 hashes, each timezone, each URL component, each generated UUID) — satisfies HASH-04 "copy any individual hash" and URL-04 "copy individual components" — **plus a primary "Copy output" / "Copy all"** for the main result.
- **D-13:** **Default pinned tools (6):** JSON, Base64, JWT, URL, Timestamp, UUID. **Hash is unpinned by default** (still searchable) as the most occasional of the seven. User can reorder/repin later (INFRA-11).

### Claude's Discretion
- Exact debounce timing, banner animation/transition style, icon choices (SF Symbols per ToolDefinition), spacing, and the visual treatment of "dimmed last-good output" are left to the builder, consistent with macOS HIG and Light/Dark/accent support (INFRA-14).
- Whether the History first-class view occupies a default pinned slot or is search-only is a builder call (D-13 already fills the 6 pins with tools; History is reachable via search regardless).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements & Roadmap
- `.planning/REQUIREMENTS.md` — INFRA-01..18, JSON-01..06, B64-01..05, URL-01..04, JWT-01..06, TS-01..05, HASH-01..04, UUID-01..04 (the 52 Phase-1 requirement IDs and their exact acceptance wording).
- `.planning/ROADMAP.md` § "Phase 1: Infrastructure + Core Tools" — goal and 5 success criteria.

### Architecture, Stack & Pitfalls (authoritative — locked before this discussion)
- `.planning/research/SUMMARY.md` — recommended stack (GRDB 7.11.1, KeyboardShortcuts 3.0.1, HighlightSwift 1.1.0, swift-markdown 0.8.0, MenuBarExtraAccess, CryptoKit+CommonCrypto+zlib), the layered architecture (App / Core Services / Tools / Infrastructure), the `ToolDefinition`/`ToolRegistry` central abstraction, the strict infra-first build order, and the **11 critical pitfalls** (esp. #1 MenuBarExtra dismiss, #2 activation-policy dance, #3 secrets-excluded-by-schema, #4 base64url JWT decode, #5 NSTextView re-render guard, #6 cold-start budget, #7 clipboard polling).
- `requirement.md` (repo root) — full PRD, the authoritative feature reference.

### Project-Level Decisions
- `.planning/PROJECT.md` § "Key Decisions" and § "Constraints" — performance targets (cold start <500ms, hotkey-to-popover <200ms, clipboard detect <100ms), not-sandboxed-in-v1, native-frameworks-first, GRDB-for-history.
- `CLAUDE.md` (repo root) — Technology Stack tables, native-vs-package decisions, "What NOT to Use".

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- None yet — greenfield. No Swift sources, no Xcode project exists at discussion time.

### Established Patterns
- The `ToolDefinition`/`ToolRegistry` abstraction (per SUMMARY.md) is the pattern every tool, the launcher search (D-01/D-02), clipboard detection (D-04..D-06), and history restore (D-08) must route through. Freeze its shape before tool work.
- Per-tool MVVM triad: pure `*Transformer` (no UI imports, testable) + `@Observable *ViewModel` + `*View`. Live-vs-button transform (D-10) and inline-error/last-good-output (D-11) are ViewModel concerns; per-field copy (D-12) is a View concern.

### Integration Points
- `MenuBarExtra` + `MenuBarExtraAccess` `isPresented` binding drives the two-stage Esc (D-03) and banner dismissal.
- `HistoryStore` (GRDB) schema must encode the pin flag and exempt-from-cap logic (D-09) and the secrets-exclusion (pitfall #3) from day one.

</code_context>

<specifics>
## Specific Ideas

- The launcher model is explicitly **Raycast/Spotlight-like**: persistent top search bar, search drives all navigation, no chrome-heavy back buttons.
- History is treated as a **first-class, re-runnable feature**, not a passive log — restore re-computes output (D-08), pins are durable (D-09).

</specifics>

<deferred>
## Deferred Ideas

- None new from this discussion — it stayed within Phase-1 scope. (Pre-existing deferrals already tracked in `.planning/STATE.md`: JSONPath tab → v2, JSON semantic diff → v2, UUID v7 gated on package vetting, App Store sandboxing → v2.)

</deferred>

---

*Phase: 1-Infrastructure + Core Tools*
*Context gathered: 2026-06-25*
