---
status: diagnosed
trigger: "when pressing esc sometimes it does not go back to launcher (UAT Test 16)"
created: 2026-06-26T00:00:00Z
updated: 2026-06-26T00:00:00Z
mode: find_root_cause_only
---

## Current Focus

hypothesis: Esc is consumed by the focused NSTextView (SyntaxEditorView) first responder before SwiftUI's `.onKeyPress(.escape)` on the parent popover view sees it.
test: Trace the responder chain — where Esc is captured (AppKit NSTextView) vs where stage-1 logic lives (SwiftUI `.onKeyPress` on MenuBarPopoverView).
expecting: NSTextView handles `keyDown:`/`cancelOperation:` for Esc and does not forward it up to SwiftUI → handleEscape() never runs when the editor is focused. Confirmed root cause.
next_action: Return ROOT CAUSE FOUND to caller. No fix applied (diagnose-only mode).

## Symptoms

expected: First Esc → navigationState = .root (back to launcher); second Esc → close popover. (Two-stage Esc, D-03)
actual: Sometimes Esc does NOT return to the launcher from a tool. Intermittent — sometimes works, sometimes doesn't.
errors: None reported.
reproduction: UAT Test 16 — open a tool in the popover, press Esc, observe whether it returns to the launcher.
started: Discovered during UAT (feature built in 01-01).

## Eliminated

- hypothesis: Stage 1 vs stage 2 branch logic in handleEscape() is wrong (e.g. always taking stage 2).
  evidence: handleEscape() (MenuBarPopoverView.swift:377-386) is correct. When in `.tool`, the `if case .root` guard is false, so it takes the else branch → `navigationState = .root`. The logic is sound; the problem is that handleEscape() is never *invoked* in the failing cases.
  timestamp: 2026-06-26T00:00:00Z

- hypothesis: The hidden cancel button is disabled/behind another view depending on focus.
  evidence: There is no hidden cancel/.cancelAction button. Esc is handled exclusively via `.onKeyPress(.escape)` (MenuBarPopoverView.swift:111-114), not a keyboardShortcut button. So a button z-order/disable race is not the mechanism.
  timestamp: 2026-06-26T00:00:00Z

## Evidence

- timestamp: 2026-06-26T00:00:00Z
  checked: MenuBarPopoverView.swift Esc wiring
  found: Esc is handled by `.onKeyPress(.escape) { handleEscape(); return .handled }` attached to the root VStack (lines 111-114). `.onKeyPress` only receives key events that propagate through the SwiftUI focus/responder chain to this view.
  implication: If a descendant first responder consumes Esc, this handler never fires.

- timestamp: 2026-06-26T00:00:00Z
  checked: handleEscape() implementation (lines 377-386)
  found: Branch logic is correct — in `.tool` state it sets `navigationState = .root`. Not the bug.
  implication: The failure is non-invocation, not wrong logic.

- timestamp: 2026-06-26T00:00:00Z
  checked: SyntaxEditorView.swift (the editable input embedded in tool views)
  found: It is an `NSViewRepresentable` wrapping a real AppKit `NSTextView` (NSTextView.scrollableTextView(), line 15-37). `isEditable = true`. There is NO key handling that intercepts Esc and forwards it to SwiftUI (no keyDown override, no NSResponder subclass, no doCommandBySelector). The NSTextView is a standard first responder.
  implication: When the NSTextView holds first-responder focus, AppKit routes the Esc keyDown to the text view's own `cancelOperation:` / completion handling. Standard NSTextView consumes Esc (field-editor completion/cancel semantics) and does NOT bubble it up to the SwiftUI host's `.onKeyPress`. handleEscape() never runs → user stays in the tool.

- timestamp: 2026-06-26T00:00:00Z
  checked: Which tool views embed SyntaxEditorView
  found: Base64View, JSONFormatterView, JWTView, HashView, URLView (and CodeDisplayView for output). Base64View.swift:151 puts `SyntaxEditorView(text: $viewModel.input, ...)` as the primary input. Most tools have a focusable NSTextView as their main interaction surface.
  implication: The common case in a tool is that the NSTextView IS focused (user just pasted/typed). That is exactly when Esc fails → matches "intermittent."

- timestamp: 2026-06-26T00:00:00Z
  checked: Intermittency mechanism (why "sometimes works")
  found: Esc works when no NSTextView is first responder — e.g. immediately after opening a tool before clicking into the editor, after clicking a button (which moves focus off the text view), or in tool/states with no editor focus. In those cases the event reaches the SwiftUI `.onKeyPress`. Esc fails whenever the SyntaxEditorView NSTextView has focus (typing/pasting/cursor in the input).
  implication: Intermittency correlates exactly with text-editor focus state — the tell-tale signature of hypothesis (a).

## Resolution

root_cause: |
  Stage-1 Esc (back-to-launcher) is wired only via SwiftUI `.onKeyPress(.escape)` on the
  MenuBarPopoverView root (MenuBarPopoverView.swift:111-114). The tool views' primary input is
  `SyntaxEditorView` — an AppKit `NSTextView` first responder (SyntaxEditorView.swift:15-37).
  When that NSTextView has focus (the normal case once the user types/pastes/clicks into the
  input), AppKit delivers the Esc keyDown to the text view, which consumes it via its built-in
  cancel/completion handling and does NOT propagate it up the responder chain to the SwiftUI
  `.onKeyPress` host. As a result handleEscape() is never invoked and navigationState stays at
  `.tool`. When the NSTextView is NOT focused, Esc reaches `.onKeyPress` and works correctly —
  producing the intermittent "sometimes it doesn't go back to launcher" behavior.
fix: "(not applied — diagnose-only mode)"
verification: "(not applied — diagnose-only mode)"
files_changed: []
