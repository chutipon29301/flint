# Phase 7: Keep menubar popover open after color picker use - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-08
**Phase:** 7-keep-menubar-popover-open-after-color-picker-use-after-choos
**Areas discussed:** Scope, Recovery strategy, Fallback, ColorPanel behavior

---

## Scope (which pickers)

| Option | Description | Selected |
|--------|-------------|----------|
| Both | Keep popover open/re-presented after either picker. Matches roadmap goal literally. | ✓ |
| Eyedropper only | Only NSColorSampler; defer ColorPanel. | |
| ColorPanel only | Only the system ColorPicker. | |

**User's choice:** Both
**Notes:** Eyedropper is a transient screen overlay; ColorPanel is a persistent floating window — handled separately.

---

## Recovery strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Never dismiss | Prevent dismissal — hold isPopoverPresented / suppress resign-key close while a picker is active. | ✓ |
| Re-present after pick | Let it dismiss, then reopen via isPopoverPresented once pick completes. | |
| Whichever the code allows | No preference; let planning pick. | |

**User's choice:** Never dismiss
**Notes:** Cleanest UX, no flicker.

---

## Fallback (if never-dismiss fails)

| Option | Description | Selected |
|--------|-------------|----------|
| Re-present as fallback | Try never-dismiss; if popover still closes, reopen once pick lands. Color never lost. | ✓ |
| Accept dismissal, keep color | Let popover close but still apply color; user reopens manually. | |
| Never-dismiss only | No fallback; risk color loss on uncontrollable paths. | |

**User's choice:** Re-present as fallback
**Notes:** Guarantees the picked color reaches the tool even on code paths MenuBarExtra doesn't fully control.

---

## ColorPanel behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Stay open while panel is open | Popover stays visible alongside floating ColorPanel; formats update live. | ✓ |
| Reopen only after panel closes | Popover dismisses while panel is up; re-present on panel close. | |

**User's choice:** Stay open while panel is open
**Notes:** Live preview of formats as the user adjusts the color in the panel.

---

## Claude's Discretion

- Exact mechanism for holding the popover open (suppress resign-key vs. window-level tweak vs. MenuBarExtraAccess binding management). Re-present is the locked safe fallback.

## Deferred Ideas

None — discussion stayed within phase scope.
