---
status: diagnosed
trigger: "UAT Test 16 — ⌘⇧C copies the current tool's output to the clipboard; user report: 'copies output does not work'"
created: 2026-06-26
updated: 2026-06-26
---

## Current Focus

hypothesis: No tool view subscribes to `.copyOutput`, so the notification is posted but nothing copies. — CONFIRMED
test: grep entire project for any observer of `.copyOutput` (`.onReceive`, `addObserver`, `publisher(for:)`)
expecting: zero observers → notification fires into the void
next_action: investigation complete; return diagnosis (find_root_cause_only)

## Symptoms

expected: Pressing ⌘⇧C in the popover copies the active tool's primary output to the clipboard.
actual: "copies output does not work" — nothing is copied; pasting elsewhere yields prior clipboard contents.
errors: None reported.
reproduction: Open a tool (e.g. JSON Formatter) in the popover, produce output, press ⌘⇧C, paste elsewhere.
started: Discovered during UAT (Test 16). Search/history/preferences shortcuts work; copy-output and Esc-to-launcher fail.

## Eliminated

- hypothesis: The keyboard shortcut is wrong (not ⌘⇧C) or the post never fires.
  evidence: MenuBarPopoverView.swift:191-197 — hidden Button "Copy Output" with `.keyboardShortcut("c", modifiers: [.command, .shift])` correctly posts `NotificationCenter.default.post(name: .copyOutput, object: nil)`. Producer side is correct.
  timestamp: 2026-06-26

- hypothesis: An observer exists but writes to the wrong pasteboard / active view isn't mounted.
  evidence: There is NO observer at all (see Evidence). The pasteboard-writing code in tool views lives inside their own per-tool copy *buttons*, not in any notification handler.
  timestamp: 2026-06-26

## Evidence

- timestamp: 2026-06-26
  checked: `grep -rn "copyOutput" Tools UI`
  found: Only two hits, both in UI/MenuBarPopoverView.swift — line 27 (declaration) and line 193 (post). Zero hits under Tools/.
  implication: No tool view references `.copyOutput` in any form.

- timestamp: 2026-06-26
  checked: MenuBarPopoverView.swift:191-197 (producer)
  found: |
    // ⌘⇧C — copy output (broadcast; system ⌘C handles text fields)
    Button("Copy Output") {
        NotificationCenter.default.post(name: .copyOutput, object: nil)
    }
    .keyboardShortcut("c", modifiers: [.command, .shift])
  implication: The producer side is fully wired and correct — shortcut and post both fire.

- timestamp: 2026-06-26
  checked: `grep -rn "onReceive" --include=*.swift` across the whole project
  found: Exactly two `onReceive` usages exist — MenuBarPopoverView.swift:121 (`.showPopover`) and MainWindowView.swift:67 (`.openWorkspace`). Neither observes `.copyOutput`.
  implication: No SwiftUI consumer subscribes to `.copyOutput`. The notification is posted into the void.

- timestamp: 2026-06-26
  checked: `grep -rn "addObserver\|publisher(for: .copyOutput\|.copyOutput)" --include=*.swift` across whole project
  found: No `addObserver`-based or Combine `publisher(for:)` observer for `.copyOutput` anywhere.
  implication: Confirms zero consumers via any mechanism (NotificationCenter token or Combine).

- timestamp: 2026-06-26
  checked: NSPasteboard usage in Tools (grep)
  found: Tool views (Hash, JSONFormatter, Base64, UUID, URLEncoder) write to NSPasteboard.general ONLY inside their own visible per-tool "copy" buttons (e.g. JSONFormatterView.swift:68, Base64View.swift:74, URLView.swift:60, HashView.swift:64-65, UUIDView.swift:145-152). None of this code is reachable from the `.copyOutput` notification.
  implication: The plumbing to copy exists per-tool, but it is never invoked by the global ⌘⇧C path.

- timestamp: 2026-06-26
  checked: `.clearInput` (sibling notification) for the same pattern
  found: clearInput.swift declared (line 24) and posted (line 173) but has ZERO observers — identical gap.
  implication: This is a systemic pattern: broadcast notifications were defined and posted in INFRA-16 but the tool-view observer side was never implemented. ⌘⇧C and ⌘Delete both no-op.

## Resolution

root_cause: |
  The ⌘⇧C copy-output feature has no consumer. MenuBarPopoverView.swift declares
  `Notification.Name.copyOutput` (line 27) and a hidden overlay Button posts it on ⌘⇧C
  (lines 192-195), but NOT A SINGLE tool view (none of the 7: Base64, Hash, JSONFormatter,
  JWT, Timestamp, URLEncoder, UUID) registers an observer for `.copyOutput`. The whole
  project contains only two `onReceive` calls (`.showPopover`, `.openWorkspace`) and no
  `addObserver`/`publisher(for:)` for `.copyOutput`. The notification is posted into the
  void, so nothing ever writes the active tool's output to NSPasteboard. The per-tool
  NSPasteboard copy code exists only inside each tool's own visible copy button and is
  never reached by the global shortcut. The identical defect affects `.clearInput` (⌘Delete).
fix: (not applied — diagnosis only)
verification: (n/a — find_root_cause_only)
files_changed: []
