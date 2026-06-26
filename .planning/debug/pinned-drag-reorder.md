---
status: diagnosed
trigger: "UAT Test 15 — draging does not works (pinned tool drag-to-reorder)"
created: 2026-06-26
updated: 2026-06-26
---

## Current Focus

hypothesis: CONFIRMED — multiple compounding defects in PinnedToolBarView.swift drag-to-reorder. Primary blocker is the `Button` swallowing the drag gesture; secondary defect is broken move-index math.
test: static code analysis of drag source, drop target, delegate, and persistence path; verified launcher instantiates the drag-enabled view.
expecting: identify which link in onDrag → onDrop → movePinnedTool chain prevents reorder.
next_action: return diagnosis (find_root_cause_only mode — no fix applied).

## Symptoms

expected: Launcher shows up to 6 pinned tool icons; dragging an icon reorders the bar; new order persists across relaunch.
actual: "draging does not works" — drag produces no reorder at all.
errors: None reported.
reproduction: Open Lathe menubar popover launcher, attempt to drag a pinned tool icon to a new position (UAT Test 15).
started: Discovered during UAT (INFRA-11 feature as built).

## Eliminated

- hypothesis: Launcher renders a non-drag variant (PinnedToolBarView without drop targets, vs DraggablePinnedToolBarView wrapper).
  evidence: MenuBarPopoverView.swift:84 instantiates `PinnedToolBarView(...)` directly. That view DOES wire onDrag (line 82-84) and onDrop (line 86-90) on each PinnedToolButton. The `DraggablePinnedToolBarView` wrapper (line 143) is unused and merely re-wraps PinnedToolBarView anyway. So the drop targets ARE wired. Not the cause.
  timestamp: 2026-06-26

- hypothesis: UTType identifier mismatch — onDrag registers NSString, onDrop accepts [.text].
  evidence: `NSItemProvider(object: tool.id as NSString)` (line 83) registers the string under `public.utf8-plain-text`. `UTType.text` (`public.text`) is a SUPERTYPE of `public.utf8-plain-text`, and SwiftUI's onDrop type matching accepts conforming subtypes. `info.itemProviders(for: [.text])` (line 112) and `loadObject(ofClass: NSString.self)` (line 115) will resolve the provider. This pairing is the standard working pattern, so the type wiring is not the primary blocker. (Kept as lower-probability contributor only.)
  timestamp: 2026-06-26

## Evidence

- timestamp: 2026-06-26
  checked: MenuBarPopoverView.swift:82-88 (which pinned view the launcher mounts)
  found: Root launcher mounts `PinnedToolBarView(onSelectTool:)` — the drag-enabled view. Drop targets are present.
  implication: Rules out "wrong view variant" hypothesis. The drag/drop chain exists; the defect is inside it.

- timestamp: 2026-06-26
  checked: PinnedToolBarView.swift:53-91 (PinnedToolButton structure — drag source layering)
  found: The icon is wrapped in `Button(action: action) { ... }` with `.buttonStyle(.plain)` (lines 62-73). The `.onDrag { ... }` (line 82) is attached to the Button itself. On macOS, a SwiftUI `Button`'s tap gesture competes with `.onDrag`; the Button's hit-testing/gesture recognizer typically wins on press, so the drag is never initiated. This is the well-documented "Button swallows onDrag on macOS" interaction.
  implication: PRIMARY ROOT CAUSE — the drag never starts because the drag source is a Button. No drag begin → no NSItemProvider delivered → performDrop never fires → no reorder. Matches the verbatim symptom "draging does not works" (no movement at all, not a wrong-position bug).

- timestamp: 2026-06-26
  checked: PinnedToolBarView.swift:111-130 (PinnedToolDropDelegate.performDrop) + PreferencesStore.swift:29-33 (movePinnedTool)
  found: performDrop reads draggedId, finds sourceIndex/destIndex in `prefs.pinnedToolIds`, then calls `movePinnedTool(from: IndexSet(integer: sourceIndex), to: destIndex > sourceIndex ? destIndex + 1 : destIndex)`. movePinnedTool uses `Array.move(fromOffsets:toOffset:)`. The `toOffset` semantics of `move(fromOffsets:toOffset:)` already expect the "insert before index" convention, and the `destIndex + 1` adjustment here is the SAME adjustment SwiftUI's List.onMove API expects callers to have NOT pre-applied. Applying `+1` on a raw firstIndex(of:) result double-compensates and lands the tool one slot past the intended drop target for forward moves.
  implication: SECONDARY DEFECT (latent) — even if the drag gesture were fixed, forward-direction reorders would land at the wrong index due to off-by-one in the destination math. Not the reason "draging does not works," but it would surface as "reorder lands in wrong spot" once the gesture is fixed.

- timestamp: 2026-06-26
  checked: PinnedToolBarView.swift:115-127 (async load + thread hop) and PreferencesStore.swift:17-20 (persistence)
  found: `loadObject` completion runs off the main actor, then dispatches `movePinnedTool` via `DispatchQueue.main.async`. movePinnedTool writes `pinnedToolIds` to UserDefaults (line 19) — persistence itself is correct and round-trips on relaunch. dropUpdated returns `.move` (line 135) so the cursor would show the move affordance IF a drag started.
  implication: Persistence (movePinnedTool → UserDefaults → pinnedToolIds getter) is sound. The failure is upstream at drag initiation, confirming the gesture-swallow diagnosis rather than a persistence problem.

## Resolution

root_cause: |
  The pinned tool drag-to-reorder never initiates because the drag source is a SwiftUI `Button`.
  In PinnedToolBarView.swift the entire icon (PinnedToolButton, lines 62-73) is a `Button(action:)`
  with `.buttonStyle(.plain)`, and `.onDrag { NSItemProvider(object: tool.id as NSString) }` (line 82-84)
  is attached to that Button. On macOS, a Button's tap/press gesture takes precedence over `.onDrag`,
  so a drag is never started — no NSItemProvider is ever vended, the PinnedToolDropDelegate.performDrop
  (line 111) never runs, and prefs.movePinnedTool is never called. Result: "draging does not works"
  (zero movement), exactly as reported.

  Secondary latent defect: even after the gesture is fixed, the destination index math in performDrop
  (line 126) `to: destIndex > sourceIndex ? destIndex + 1 : destIndex` over-adjusts for
  Array.move(fromOffsets:toOffset:), so forward moves would land one slot too far.

fix: (not applied — diagnosis-only mode)
verification: (not applied — diagnosis-only mode)
files_changed: []
