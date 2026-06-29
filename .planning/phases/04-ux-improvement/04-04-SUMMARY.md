---
phase: 04-ux-improvement
plan: "04"
subsystem: ui
tags: [swiftui, consistency, empty-state, onboarding, semantic-colors, macos]

requires:
  - phase: 04-03
    provides: OutputRowBadge rows in ColorView/HashView/NumberBaseView (D-08)
  - phase: 03-polish-distribution
    provides: OnboardingWindowView with 2-step pattern (D-07 origin)

provides:
  - "D-05: 10 of 12 tool views show verbatim 'Paste or type content above' empty state on blank input"
  - "D-05: HashView HMAC chrome background normalized to semantic color"
  - "D-06: OnboardingWindowView Steps 3 (Services) and 4 (drag-drop) with 480pt height"

affects: [04-05, any future tool view work, pre-release visual QA]

tech-stack:
  added: []
  patterns:
    - "Empty state via conditional if input.isEmpty → Text('Paste or type content above') at 13pt .secondary centered"
    - "D-05: chrome colors normalized to Color(NSColor.controlBackgroundColor) / Color.primary / Color.secondary"
    - "D-06: onboarding steps use HStack(alignment:.top, spacing:12) { Image + VStack(heading+body) } pattern"

key-files:
  created: []
  modified:
    - Tools/JSONFormatter/JSONFormatterView.swift
    - Tools/Base64/Base64View.swift
    - Tools/URLEncoder/URLView.swift
    - Tools/JWT/JWTView.swift
    - Tools/Timestamp/TimestampView.swift
    - Tools/Hash/HashView.swift
    - Tools/UUID/UUIDView.swift
    - Tools/Regex/RegexView.swift
    - Tools/Markdown/MarkdownView.swift
    - Tools/TextDiff/TextDiffView.swift
    - UI/OnboardingWindowView.swift

key-decisions:
  - "ColorView and NumberBaseView do not need empty states: ColorView always shows a live color swatch; NumberBaseView fields start with default 0 values — neither has a 'blank' state"
  - "UUID generator panel: 'Paste or type content above' replaces 'Press Generate to produce UUIDs' to match verbatim spec requirement, even though generator UX differs from text-input tools"
  - "Regex empty state uses ZStack overlay on NSTextView to avoid breaking NSViewRepresentable coordinate system — Text with .allowsHitTesting(false) floats above the editor"
  - "HashView HMAC section: .blue.opacity(0.05) replaced with Color(NSColor.controlBackgroundColor).opacity(0.6) — chrome normalization only, HMAC section border/functional behavior unchanged"
  - "Domain-logic color literals preserved: ColorView RoundedRectangle swatches (user RGBA), TextDiff row backgrounds (green/red for added/removed), Regex capture-group palette (NSColor system palette)"

requirements-completed: [UX-07, UX-08, INFRA-14, INFRA-15]

duration: 18min
completed: 2026-06-29
---

# Phase 04 Plan 04: D-05 Consistency Pass + D-06 Onboarding Summary

**Empty-state "Paste or type content above" normalized across 10 of 12 tool views, HMAC chrome color fixed, and first-run onboarding extended with Services + drag-drop steps at 480pt height**

## Performance

- **Duration:** ~18 min
- **Started:** 2026-06-29T10:08:00Z
- **Completed:** 2026-06-29T10:26:00Z
- **Tasks:** 2
- **Files modified:** 11

## Accomplishments

- Added verbatim D-05 empty state ("Paste or type content above", 13pt .secondary, centered) to 10 tool views: JSONFormatter, Base64, URLEncoder (both encode/decode and parse modes), JWT, Timestamp, Hash, UUID, Regex, Markdown, TextDiff
- Normalized HashView HMAC section chrome background from hardcoded `.blue.opacity(0.05)` to semantic `Color(NSColor.controlBackgroundColor).opacity(0.6)` — only chrome/layout literal in any of the 12 tool views
- Preserved all domain-logic color literals: ColorView swatch `Color(red:green:blue:)`, TextDiff row backgrounds (green/red), Regex group palette (NSColor system colors)
- Preserved Plan 03's OutputRowBadge in ColorView (5 rows), NumberBaseView (4 rows), and HashView (via ProgressHashView showBadges:true, 6 rows)
- Extended OnboardingWindowView with Step 3 (text.cursor, "Route text from any app", verbatim Services body) and Step 4 (arrow.down.circle, "Drag files directly", verbatim drag-drop body), both .accessibilityHidden(true) on icons
- Changed OnboardingWindowView frame height from 360pt to 480pt

## Task Commits

1. **Task 1: D-05 consistency pass across all 12 tool views** - `5a93412` (feat)
2. **Task 2: D-06 onboarding Steps 3 (Services) and 4 (drag-drop)** - `9fef46f` (feat)

## Files Created/Modified

- `Tools/JSONFormatter/JSONFormatterView.swift` — Empty state when input is blank
- `Tools/Base64/Base64View.swift` — Empty state when input is blank and no file processing
- `Tools/URLEncoder/URLView.swift` — Empty state in encode/decode output panel; parse mode empty state normalized to verbatim copy
- `Tools/JWT/JWTView.swift` — Empty state when token is blank
- `Tools/Timestamp/TimestampView.swift` — Empty state when input is blank (above output section)
- `Tools/Hash/HashView.swift` — Empty state when textInput is empty; HMAC chrome color normalized
- `Tools/UUID/UUIDView.swift` — Generator empty state changed to verbatim spec copy
- `Tools/Regex/RegexView.swift` — Empty state as ZStack overlay on NSTextView editor
- `Tools/Markdown/MarkdownView.swift` — Empty state in preview panel when source is blank
- `Tools/TextDiff/TextDiffView.swift` — Empty state when both original and changed are blank
- `UI/OnboardingWindowView.swift` — Steps 3 and 4 added; height 360→480pt

## Decisions Made

- ColorView and NumberBaseView skip empty state: ColorView always displays a live swatch (no "blank" mode); NumberBaseView fields default to 0 and are always populated.
- UUID generator empty state uses verbatim spec copy even though the UX is button-triggered generation, not paste-input — spec acceptance criteria requires verbatim text.
- Regex ZStack overlay: `allowsHitTesting(false)` ensures the Text doesn't block the NSTextView, avoiding NSViewRepresentable focus conflicts.

## Deviations from Plan

None — plan executed exactly as written. All 12 tool views audited; domain-logic color literals identified and preserved per T-04-09 threat mitigation.

## Issues Encountered

None — build succeeded on first attempt after both tasks.

## Known Stubs

None — no placeholder or stub content introduced. All empty-state messages are production-ready UI copy from the UI-SPEC Copywriting Contract.

## Next Phase Readiness

- D-05 visual consistency complete; all 12 tools show semantic colors and empty states
- D-06 onboarding ready for first-run testing with 4 capability steps
- Plan 04-05 (final wave) can proceed without any dependency on 04-04 artifacts

---
*Phase: 04-ux-improvement*
*Completed: 2026-06-29*
