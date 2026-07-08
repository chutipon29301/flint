# Phase 7: Keep menubar popover open after color picker use - Context

**Gathered:** 2026-07-08
**Status:** Ready for planning

<domain>
## Phase Boundary

After the user picks a color via the eyedropper (`NSColorSampler`) or the system ColorPicker (`NSColorPanel`), the `.window`-style MenuBarExtra popover currently resigns key focus and dismisses. This phase keeps the popover usable so the picked color lands in the Color tool and the user can copy any format and keep working — for **both** pickers.

Scope is the popover-survival behavior only. Not touching color conversion, format output, or the Color tool's UI.

</domain>

<decisions>
## Implementation Decisions

### Which pickers
- **D-01:** Fix **both** the eyedropper (`NSColorSampler`) and the system ColorPicker (`NSColorPanel`). The roadmap goal is literal — the picked color must land in the tool and stay usable regardless of which picker was used.

### Recovery strategy
- **D-02:** Prefer **never-dismiss** — hold the popover open (keep `isPopoverPresented` true / suppress the resign-key close) while a picker is active. Cleanest UX, no flicker.
- **D-03:** **Re-present as fallback.** If the OS still force-closes the popover on a code path we can't control (MenuBarExtra `.window` dismissal is not fully controllable), re-open it via `isPopoverPresented` once the pick lands. The picked color must never be lost.

### ColorPanel behavior
- **D-04:** While the system ColorPanel is floating (open), the popover **stays open the whole time** so the user sees color formats update live as they adjust the color in the panel. Not "reopen only after panel closes."

### Claude's Discretion
- Exact mechanism for holding the popover open (suppressing resign-key vs. window-level tweak vs. MenuBarExtraAccess binding management) — research/planning picks whichever is reliable. Re-present (D-03) is the locked safe fallback.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Popover / picker integration (primary work sites)
- `Tools/Color/ColorView.swift` §124–162 — the `swatchSection` where `NSColorSampler().show { }` (eyedropper) and `ColorPicker` (NSColorPanel) live. This is where the picker is invoked.
- `App/FlintApp.swift` §51–73 — `MenuBarExtra` + `.menuBarExtraAccess(isPresented: $clipboard.isPopoverPresented)` + `.menuBarExtraStyle(.window)`. The popover presentation binding is here.
- `App/WindowCoordinator.swift` §68 — existing note about re-presenting the popover via the `isPopoverPresented` binding (Pitfall #3). Relevant prior art for the re-present fallback (D-03).
- `Tools/Color/ColorViewModel.swift` §85–178 — `swiftUIColor` binding (drives NSColorPanel) and `updateFromNSColor(_:)` (applies eyedropper/panel picks). Where the picked color lands.

### Reference
- `MenuBarExtraAccess` package — provides the `isPresented` binding used to programmatically show/dismiss the `.window` MenuBarExtra (SwiftUI has no native API for this; FB10185203).

No external ADRs/specs for this phase — behavior fully captured in decisions above.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `clipboard.isPopoverPresented` binding (via `.menuBarExtraAccess`): the existing programmatic show/dismiss lever. Both never-dismiss (hold true) and re-present (set true after pick) build on this — no new plumbing needed.
- `ColorViewModel.updateFromNSColor(_:)`: already applies a picked `NSColor` to canonical RGBA. The picker callbacks already call it; the color path works, only popover survival is broken.

### Established Patterns
- `.menuBarExtraStyle(.window)` popovers auto-dismiss on resigning key window. Both `NSColorSampler` (transient screen overlay) and `NSColorPanel` (persistent floating window) steal key status — this is the root cause.
- `WindowCoordinator` already documents re-presenting the popover after an activation-policy dance (Pitfall #3) — the re-present fallback (D-03) has precedent in this codebase.

### Integration Points
- Eyedropper: `NSColorSampler().show { }` completion in `ColorView.swift` — wrap/guard popover state around this call.
- ColorPanel: SwiftUI `ColorPicker` binding to `viewModel.swiftUIColor` — panel open/close is where popover survival must hold for the full panel lifetime (D-04).

</code_context>

<specifics>
## Specific Ideas

- Eyedropper and ColorPanel behave differently and must be reasoned about separately: eyedropper is a transient overlay (fix spans one pick), ColorPanel is a persistent floating window (fix must span the whole time the panel is open, D-04).

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 7-keep-menubar-popover-open-after-color-picker-use-after-choos*
*Context gathered: 2026-07-08*
