# Phase 4: UX Improvement - Discussion Log

**Date:** 2026-06-29
**Mode:** discuss (default)

Human-reference record of the discussion. Not consumed by downstream agents — see `04-CONTEXT.md` for the canonical decisions.

## Areas Discussed

### 1. Tool browsing & back navigation
- **Options:** Grid of all 12 + back button / Scrollable list / Keep pinned + 'All tools' expander
- **Selected:** Grid of all 12 + back button → D-01, D-02

### 2. Update-checker exposure
- **Root cause surfaced during scout:** `SparkleUpdaterService.checkForUpdates()` exists but is never called by any UI; Info.plist has placeholder EdDSA key + localhost feed URL.
- **Options:** Preferences button / Launcher footer / Both
- **Selected:** Preferences button → D-03 (+ D-04 release-gated config note)

### 3. Visual polish depth
- **Options:** Consistency pass / Light redesign / Defer to UI-SPEC step
- **Selected:** Consistency pass → D-05

### 4. Flow-speed (multi-select)
- **Options presented:** Auto-copy result / Faster tool switching / Surface clipboard suggestion / Keyboard nav in grid
- **User response (freeform):** Described a full keyboard-only loop — `⌘C` → `⌘⇧Space` → suggested helper → `⌘1/2/3/4` to pick a copy result (e.g. Color Converter) or paste, never leaving the keyboard. Also: arrow-down navigation in search results is currently missing.
- **Captured as:** D-07 (arrow nav in search results), D-08 (⌘N selects/copies output row), D-09 (configurable copy-and-paste).

### 5. ⌘N action (follow-up)
- **Options:** Copy that result / Copy + auto-close / Copy with separate paste action
- **Selected:** Copy, with a separate paste action → D-08 + D-09

### 6. Paste-back permission (follow-up)
- **Options:** Copy-only no auto-paste / Auto-paste via synthetic ⌘V / Decide during research
- **Selected:** "Make this configurable in setting" → D-09 (default-off Preferences toggle; synthetic ⌘V behind opt-in)

### 7. Arrow nav scope (follow-up)
- **Options:** Unified arrow+Return everywhere / Search results only
- **Selected:** Search results only → D-07 (grid stays mouse/tab-driven; deferred)

### 8. Toggle enable behavior (follow-up)
- **Options:** Prompt on enable / Toggle on, prompt on first use / Let researcher recommend
- **Selected:** Prompt on enable → D-09 (Accessibility request on toggle-on; revert + explain on denial)

## Deferred Ideas Noted
- Keyboard nav in the all-tools grid (chose search-results-only this phase)
- UI-SPEC-driven designed visual system (chose lighter consistency pass)
- Quick-switcher overlay / more visible ⌘]/⌘[ affordance

## Claude's Discretion
- Grid grouping/layout, back-affordance glyph, number-badge style, exact ⌘N vs copy-and-paste bindings, onboarding copy/layout, all spacing/type/color tokens, and whether to substitute real Sparkle credentials now vs at release.

## Open Question for Research
- OQ-01: macOS 14 synthetic-paste API + Accessibility request/observe path + previously-focused-app capture (D-09).
