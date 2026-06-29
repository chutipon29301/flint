---
phase: 04-ux-improvement
plan: "01"
subsystem: ui-navigation
tags: [grid-nav, back-affordance, swiftui, accessibility, d-01, d-02]
completed: 2026-06-29
duration: "~7 minutes"

dependency_graph:
  requires: []
  provides:
    - AllToolsGridView — 12-tool adaptive grid mounted at root navigation state
    - ToolHeaderView — back-to-picker header wrapping every tool view
    - MenuBarPopoverView — D-01 grid + D-02 header wired at navigation switch site
  affects:
    - UI/MenuBarPopoverView.swift — bodyContent .root and .tool cases extended

tech_stack:
  added: []
  patterns:
    - LazyVGrid with GridItem(.adaptive) for responsive 3-column tool grid
    - Per-tile private subview to isolate @State hover from grid-level view
    - Invisible matching spacer for visually-centered title in header HStack
    - NSColor.quaternaryLabelColor via SwiftUI on macOS (no explicit AppKit import needed)

key_files:
  created:
    - UI/AllToolsGridView.swift
    - UI/ToolHeaderView.swift
  modified:
    - UI/MenuBarPopoverView.swift
    - Flint.xcodeproj/project.pbxproj

decisions:
  - AllToolsGridView uses ToolGridTile private subview to own @State isHovered, keeping the grid-level view state-free per plan requirement
  - Color.quaternary.opacity() produces a type error in Swift 6 (Color static member issue); replaced with Color(NSColor.quaternaryLabelColor).opacity() which is semantically equivalent and compiles correctly without an explicit AppKit import
  - .root bodyContent uses VStack (grid + Divider + recentHistoryView) rather than ScrollView wrapping, to avoid List-inside-ScrollView conflict that would break recentHistoryView's internal scrolling
  - ToolHeaderView uses a hidden clone of the back-button content as the trailing spacer to match width automatically, keeping the tool title visually centered without hardcoding widths

metrics:
  duration: "~7 minutes"
  completed: 2026-06-29
  tasks: 2
  files: 4
---

# Phase 04 Plan 01: Grid Navigation + Back Affordance Summary

**One-liner:** Added 12-tool adaptive LazyVGrid at root and a universal back-to-picker header wrapping every tool via ToolHeaderView, resolving the D-01 discoverability defect and D-02 navigation defect.

## What Was Built

**Task 1: AllToolsGridView (D-01) + ToolHeaderView (D-02)**

`AllToolsGridView.swift` — a stateless component that renders all 12 registered tools in a 3-column adaptive grid. Uses `@Environment(ToolRegistry.self)` for the tool list and an `onSelect: (String) -> Void` callback for navigation. Per-tile hover state is isolated in a private `ToolGridTile` subview so the grid view itself remains state-free. Each tile shows the SF Symbol icon at 22pt in `.accentColor` over the tool name at 13pt regular with 2-line limit. VoiceOver: `.accessibilityLabel(tool.name)` + `.accessibilityHint("Open \(tool.name)")` on each tile.

`ToolHeaderView.swift` — a stateless back-affordance header with `toolName: String` and `onBack: () -> Void` props. Layout: `VStack(spacing: 0)` wrapping an `HStack` (back button + centered title + invisible balancing spacer) then `Divider()`. Back button renders `chevron.left` + "All Tools" text in `.accentColor` at 13pt. Tool name at 15pt semibold with `.accessibilityAddTraits(.isHeader)`. Back button `.accessibilityLabel("Back to tool picker")`. Minimum header height 44pt.

**Task 2: MenuBarPopoverView wiring**

`.root` case in `bodyContent` now renders a `VStack(spacing: 0)` with `AllToolsGridView` on top (its `onSelect` closure sets `navigationState = .tool(toolId: toolId)`), a `Divider`, then the existing `recentHistoryView`. The pinned-bar (Zone 3) above `bodyContent` is unchanged.

`.tool` case now wraps `tool.makeView()` in a `VStack(spacing: 0)` whose first child is `ToolHeaderView(toolName: tool.name, onBack: { navigationState = .root })`. The `ToolHeaderView` is applied uniformly to all 12 tools at the switch site — no changes inside individual tool views.

Both new files were registered in `Flint.xcodeproj/project.pbxproj` (PBXFileReference, PBXBuildFile, UI group children, Sources build phase).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Color.quaternary.opacity() compile error**
- **Found during:** Task 1 (first build attempt)
- **Issue:** `Color.quaternary` is not a static `Color` property in Swift 6/SwiftUI — `.quaternary` is a `ShapeStyle`, not expressible as `Color.quaternary.opacity(...)`.
- **Fix:** Replaced with `Color(NSColor.quaternaryLabelColor).opacity(...)` — semantically equivalent, resolves to the system quaternary label color in both Light and Dark modes. No explicit `import AppKit` needed; `NSColor` is available via SwiftUI on macOS.
- **Files modified:** `UI/AllToolsGridView.swift`
- **Commit:** 01c1423

**2. [Rule 1 - Bug] New Swift files not in Xcode project target**
- **Found during:** Task 2 (build attempt after MenuBarPopoverView wiring)
- **Issue:** `AllToolsGridView` and `ToolHeaderView` were created as filesystem files but not added to `Flint.xcodeproj/project.pbxproj`, causing "cannot find type in scope" build errors.
- **Fix:** Added PBXFileReference entries, PBXBuildFile entries, UI group membership, and Sources build phase membership for both files using IDs `00120000000DD04`/`00110000000DD04` and `00120000000DD05`/`00110000000DD05`.
- **Files modified:** `Flint.xcodeproj/project.pbxproj`
- **Commit:** 01c1423

**3. [Rule 1 - Arch] VStack vs ScrollView for .root bodyContent**
- **Found during:** Task 2 implementation
- **Issue:** PATTERNS.md showed wrapping the .root body in a `ScrollView`, but the existing `recentHistoryView` uses a `List` with `.frame(maxWidth: .infinity, maxHeight: .infinity)`. Nesting a `List` inside a `ScrollView` disables the List's internal scroll, breaking its layout.
- **Fix:** Used a `VStack(spacing: 0)` instead of `ScrollView` as the outer container. The grid renders at its natural height, and the history List expands below it as before. Both remain within the 480×600 popover frame.
- **Impact:** The plan's "keep everything inside a ScrollView so the popover scrolls rather than clips" intent is achieved via the List's own scrolling rather than an outer ScrollView.
- **Files modified:** `UI/MenuBarPopoverView.swift`

## Known Stubs

None. All 12 grid tiles render live data from `toolRegistry.tools`. The back button is fully wired to `navigationState = .root`. No placeholder text or mock data.

## Threat Flags

None. Changes are limited to in-process UI navigation state (`PopoverNavigationState`). No new network endpoints, auth paths, file access patterns, or schema changes introduced.

## Self-Check: PASSED

- `UI/AllToolsGridView.swift` exists: FOUND
- `UI/ToolHeaderView.swift` exists: FOUND
- `UI/MenuBarPopoverView.swift` modified: FOUND
- Task 1 commit 40cc031: FOUND
- Task 2 commit 01c1423: FOUND
- Build: SUCCEEDED
