# Phase 4: UX Improvement - Context

**Gathered:** 2026-06-29
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 4 makes Flint feel effortless to navigate and trustworthy to keep. No new tools. Five threads, all clarifying HOW to improve what already ships:

1. **Defect — menu-landing navigation:** the launcher exposes only 6 pinned tools + recent history, with no way to browse all 12 and no back-to-picker affordance from inside a tool.
2. **Defect — update checker:** "Check for Updates" is failing. Root cause found during discussion (see code_context): `SparkleUpdaterService.checkForUpdates()` exists but **nothing in the UI ever calls it** — there is no Check-for-Updates affordance anywhere.
3. **Visual / aesthetic polish:** consistency pass across the 12 tools + launcher.
4. **Onboarding & discoverability:** refine the existing first-run flow + surface hidden capabilities.
5. **Interaction & flow speed:** a keyboard-only "paste → hotkey → suggested tool → pick a result → copy/paste" loop so the user never leaves the keyboard.

The keyboard flow (thread 5) is the dominant signal of this discussion and reshapes search-result navigation, every multi-output tool, and Preferences.
</domain>

<decisions>
## Implementation Decisions

### Carried Forward (apply across Phase 4)
- **CF-01:** Never crash / never freeze on bad input; cold start < 500ms, hotkey-to-popover < 200ms (PROJECT.md constraints) govern everything added here. No new work may regress the cold-start budget.
- **CF-02:** Zero-friction is the core value — **no Accessibility permission prompt at install / hotkey-use** (CLAUDE.md, why KeyboardShortcuts over CGEventTap). The only place an Accessibility prompt is acceptable is behind an explicit, default-off user opt-in (see D-09).
- **CF-03:** Reuse existing substrate — `ToolRegistry` (FROZEN tools array), `ToolSeed` one-shot pre-fill, `WarningBannerView`, the `WindowCoordinator` activation-policy dance, and the existing clipboard auto-detect banner (`DetectionBannerView`). Do not rebuild.

### Tool Browsing & Back Navigation (defect 1)
- **D-01:** **Grid of all 12 tools + back button.** Add a visible grid (icon + name) of all 12 tools reachable from the root launcher so a user with zero prior knowledge can see and open any tool. Keep the existing 6-pinned row and recent history; the grid is the "see everything" surface. Grouping vs flat is Claude's discretion.
- **D-02:** **Consistent back-to-picker affordance inside every tool.** A persistent, obvious control (e.g. a header back arrow) returns to the tool-selection screen in one action, from any of the 12 tools. This complements — does not replace — the existing two-stage Esc (stage 1 already returns to launcher).

### Update Checker (defect 2)
- **D-03:** **Wire a "Check for Updates…" button in Preferences** that calls `sparkle.checkForUpdates()`. This is the actual fix — the method already exists and works; it was simply never surfaced. Conventional macOS location; pairs with the existing Sparkle background auto-check (D-08 from Phase 3).
- **D-04:** **Credential/config tasks are release-gated, not Phase-4 wiring.** Info.plist still carries `PLACEHOLDER` `SUPublicEDKey` and a `localhost` `SUFeedURL` (deferred to plan 03-05, credential-gated). Phase 4 verifies the *check completes and reports correctly* (up-to-date / update available / clear error). Whether a real key + production feed URL are substituted now or remain a pre-release task is a planning call — but a failing check caused by the placeholder feed must be reported as a *clear error*, never a silent failure (CF-01).

### Visual / Aesthetic Polish (thread 3)
- **D-05:** **Consistency pass, not a redesign.** Audit and normalize spacing, type scale, color, iconography, empty/loading states, and Light/Dark across the existing layouts. No structural redesign. Directly satisfies success criterion 3. (User explicitly chose the consistency-pass depth over a redesign or a separate UI-SPEC step. If a designed visual system is wanted later, that's `/gsd:ui-phase` — deferred, not this phase.)

### Onboarding & Discoverability (thread 4)
- **D-06:** Refine the **existing** single first-run welcome window (`OnboardingWindowView`, Phase 3 D-07) — do not rebuild. Surface the hidden capabilities a fresh user won't discover: global hotkey (⌘⇧Space), Services menu, drag-and-drop, and clipboard auto-detect. Exact copy/layout is Claude's discretion within macOS HIG + Light/Dark + VoiceOver.

### Keyboard-Only Flow (thread 5 — PRIMARY)
The target loop, in the user's words: copy text → `⌘⇧Space` (open Flint) → suggested tool surfaces (existing clipboard auto-detect) → pick a result with `⌘1/2/3/4` → copy or paste — all without the hands leaving the keyboard.

- **D-07:** **Arrow-key navigation in search results.** `↑`/`↓` move a highlight through search results; `Return` opens the highlighted tool. Scope: **search results only** for now — the new all-tools grid (D-01) stays mouse/tab-driven this phase (user chose "search results only"). (Note: the existing `.onSubmit` already opens the first result on Return; D-07 generalizes this to an arrow-driven highlight.)
- **D-08:** **`⌘1`…`⌘9` select a numbered output row.** Tools with multiple copyable outputs (Color: HEX/RGB/HSL/HSV/OKLCH; Hash: MD5/SHA1/SHA256/…; Number Base: bin/oct/dec/hex; and any other multi-output tool) show a small number badge next to each copyable output. `⌘N` **copies** output row N to the clipboard. Tools with a single output: `⌘1` copies it.
- **D-09:** **Separate copy-and-paste action, gated by a default-off Preferences toggle.** A distinct key (e.g. `⌘⇧N` or `Return` on the selected row — exact binding is planning/Claude discretion) copies row N **and** pastes it into the previously-focused app.
  - **Default: OFF → copy-only, zero new permissions.** This preserves CF-02 / the no-Accessibility-prompt guarantee. With the toggle off, the flow is keyboard-only except the final `⌘V` the user presses in their own app.
  - **Toggle ON → synthetic `⌘V` paste-back**, which requires macOS Accessibility permission. This is the one sanctioned exception to CF-02, *only* by explicit user opt-in.
  - **Enable UX: prompt-on-enable.** Flipping the toggle on triggers the Accessibility permission request *then*; if denied, the toggle reverts and explains why. Permission is never requested except by this explicit opt-in.
  - **Researcher must confirm** the exact macOS 14 no-permission-vs-permission paste mechanism and the precise Accessibility request/observe API (see canonical_refs / open question OQ-01).

### Claude's Discretion
- Grid grouping vs flat layout, exact back-affordance glyph/placement, the number-badge visual style, exact key bindings for copy (`⌘N`) vs copy-and-paste (`⌘⇧N` / Return), onboarding copy/layout/illustration, and all spacing/type/color tokens in the consistency pass — left to the builder, consistent with macOS HIG, Light/Dark/accent, VoiceOver labels (INFRA-14/15), and never-crash/never-freeze.
- Whether to substitute a real Sparkle key + production feed URL in this phase or keep it as the pre-release task (D-04).

### Open Questions for Research
- **OQ-01:** On macOS 14, does a synthetic-paste path exist that does NOT require Accessibility permission? Confirm the exact API for (a) requesting Accessibility permission on demand (prompt-on-enable, D-09), (b) synthesizing `⌘V` into the previously-focused app after dismissing Flint, and (c) capturing/restoring "previously-focused app" focus. If no non-permission path exists, D-09's default-off + opt-in design stands as written.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements & Roadmap
- `.planning/ROADMAP.md` § "Phase 4: UX Improvement" — goal, 5-item scope, and 5 success criteria. New `UX-*` requirements are expected to be derived during planning (ROADMAP notes "to be derived").
- `.planning/REQUIREMENTS.md` — INFRA-14 (Light/Dark, no chrome violations), INFRA-15 (VoiceOver), INFRA-16 (global keyboard shortcuts) and the DIST-04 update-checker acceptance wording all bear on this phase.

### Stack, Tooling & Pitfalls (authoritative — locked)
- `CLAUDE.md` (repo root) — **KeyboardShortcuts 3.0.1** (Carbon RegisterEventHotKey, no Accessibility prompt — the reason CF-02 exists) and **Sparkle 2.9.3** wiring. The "What NOT to Use" table (no CGEventTap for global hotkey) is the constraint D-09's opt-in carves the single exception to.

### Code This Phase Edits
- `UI/MenuBarPopoverView.swift` — the launcher: `PopoverNavigationState` enum, search-results path (`.onSubmit` first-result open), pinned row, recent history, and the existing hidden-button keyboard-shortcut block. D-01 (grid), D-02 (back), D-07 (arrow nav), D-08/D-09 (⌘N bindings) all touch this file.
- `Core/Services/SparkleUpdaterService.swift` — `checkForUpdates()` already implemented; D-03 just calls it.
- `UI/PreferencesView.swift` — host for the D-03 "Check for Updates…" button and the D-09 paste-back toggle.
- `Core/Services/PreferencesStore.swift` — add the D-09 paste-back pref.
- `UI/OnboardingWindowView.swift` — D-06 refinement target.
- `Tools/*/...View.swift` (all 12) — D-05 consistency pass + D-08 numbered output badges (esp. multi-output: Color, Hash, NumberBase).

### Prior-Phase Decisions (carry forward)
- `.planning/phases/03-polish-distribution/03-CONTEXT.md` — Sparkle D-08/D-09 (background auto-check, single stable channel) that D-03 surfaces a manual trigger for; onboarding D-07 that D-06 refines; the lazy-start-from-popover rule for Sparkle.
- `.planning/phases/01-infrastructure-core-tools/01-CONTEXT.md` — D-04 clipboard detection banner (the "suggested tool" step of the keyboard flow), two-stage Esc, search-first launcher, and INFRA-16 keyboard-shortcut conventions.
- `.planning/phases/01-infrastructure-core-tools/01-UI-SPEC.md`, `02-UI-SPEC.md`, `03-UI-SPEC.md` — existing visual contracts; the D-05 consistency pass should reconcile to these, not invent a new system.

### Project-Level
- `.planning/PROJECT.md` § Constraints / Key Decisions — not-sandboxed-v1, performance targets, never-crash, the zero-friction core value behind CF-02.
- `requirement.md` (repo root) — full PRD; authoritative for the "paste → right transform in under a second" promise this phase makes obvious.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Core/Services/SparkleUpdaterService.swift` → `checkForUpdates()` — already correct; the update-checker "defect" is purely that no UI calls it (D-03). The fix is a button, not a service change.
- `UI/MenuBarPopoverView.swift` → `PopoverNavigationState` (`.root` / `.tool` / `.searchResults` / `.history`) + `bodyContent` switch — the navigation backbone; D-01 grid is a new root surface, D-02 back returns `navigationState = .root`.
- `UI/MenuBarPopoverView.swift` → the hidden `Button(...).keyboardShortcut(...)` block (⌘K/⌘H/⌘N/⌘]/⌘[/⌘,/⌘⇧C/⌘⇧V) — the established pattern D-08/D-09 (⌘N) extend; `.copyOutput` notification already broadcasts to tools for ⌘⇧C, a precedent for per-row copy.
- `Core/Extensions/View+CopyButton.swift` + `UI/Components/CopyButtonView.swift` + the existing `.copyOutput` notification — per-field copy already exists (Phase 2 CF-03); D-08 numbered rows build on this.
- `DetectionBannerView` + `ClipboardDetector` — the "suggested tool" step of the keyboard flow is already built; thread 5 makes the *rest* of the loop keyboard-driveable.
- `UI/OnboardingWindowView.swift`, `UI/PreferencesView.swift`, `Core/Services/PreferencesStore.swift` — refine/extend, don't rebuild.

### Established Patterns
- Keyboard shortcuts are wired as hidden `Button().keyboardShortcut()` views in `.background()` of the popover — D-07/D-08/D-09 follow this. Caveat: `⌘1`…`⌘9` must dispatch to the *active tool's* numbered output, so they likely broadcast a notification (like `.copyOutput`) carrying the row index, with each tool view observing it — mirror the `.clearInput`/`.copyOutput` pattern.
- Window surfacing (Preferences, onboarding) uses the `WindowCoordinator` activation-policy dance (Pitfall #2) — the D-03 button lives in the already-surfaced Preferences window, no new dance.
- Multi-output tools (Color, Hash, NumberBase) render each format as a labeled row — natural anchor points for D-08 number badges.

### Integration Points
- **Grid (D-01):** new case/surface in `MenuBarPopoverView.bodyContent` (or a sibling section at `.root`), iterating `toolRegistry.tools` (all 12).
- **Back (D-02):** a header control in each tool view (or wrapped once around `tool.makeView()` in `bodyContent`) that sets `navigationState = .root`.
- **Arrow nav (D-07):** a `@State` highlighted-index in the search-results path + `.onKeyPress`/local monitor; reconcile with the existing Esc local NSEvent monitor so they don't fight.
- **⌘N row select (D-08/D-09):** popover-level shortcut → `.selectOutputRow(index:)` notification → active tool copies (or copy-and-pastes if D-09 toggle on) that row.
- **Update button (D-03):** `PreferencesView` button → `sparkle.checkForUpdates()`. Note Sparkle is started lazily from popover `.onAppear`; if Preferences can open without the popover having appeared, planning must ensure `sparkle.start()` has run (or call it defensively) so the controller is armed.
- **Paste-back toggle (D-09):** `PreferencesStore` bool + a toggle in `PreferencesView`; enabling triggers the Accessibility permission request (prompt-on-enable), reverts on denial.

</code_context>

<specifics>
## Specific Ideas

- **The keyboard loop is the headline.** User's exact expected flow: `⌘C` → `⌘⇧Space` → suggested helper surfaces → `⌘1/2/3/4` to pick the right copy result (named the Color Converter explicitly) → copy or paste — "without hand off the keyboard." Every thread-5 decision (D-07/D-08/D-09) serves this single loop; downstream agents should treat it as one coherent feature, not three.
- **The update checker isn't broken — it's unwired.** Don't go hunting for a Sparkle bug. The method works; surface it (D-03). The placeholder feed URL is a separate, known, release-gated config item (D-04) — if it makes the check fail, that must surface as a *clear error*, never a hang or silent failure.
- **Paste-back is the one permission exception.** The whole product avoids Accessibility prompts on purpose. Auto-paste is the sole sanctioned exception, and only behind an explicit default-off opt-in with prompt-on-enable. Do not make it default, do not request the permission unprompted.

</specifics>

<deferred>
## Deferred Ideas

- **Arrow/keyboard navigation in the all-tools grid (D-01)** — user chose "search results only" for D-07 this phase. Grid keyboard-driveability is a natural follow-up, not this phase.
- **`/gsd:ui-phase` designed visual system** — considered as the polish approach; user chose the lighter consistency pass (D-05). A full UI-SPEC-driven redesign is a future option.
- **Quick-switcher overlay / more visible ⌘]/⌘[ affordance** — surfaced under flow-speed but not selected; the keyboard loop (D-07/08/09) is the chosen flow-speed work. Note for a future flow pass.

(Pre-existing deferrals tracked in `.planning/STATE.md` / REQUIREMENTS.md v2: cloud sync, App Store sandboxing, additional tools, UUID v7, beta update channel.)

</deferred>

---

*Phase: 4-UX Improvement*
*Context gathered: 2026-06-29*
