# 03-07 SUMMARY — Workspace-window drag-and-drop + discoverable entry point

**Plan:** 03-07 (gap closure, DIST-02)
**Status:** Complete — human checkpoint approved
**Tasks:** 4/4 (3 auto + 1 human-verify)

## What was built

File drag-and-drop is now reachable. Root cause (diagnosed in `.planning/debug/popover-dismiss-blocks-drag.md`): the `MenuBarExtra(.window)` popover is a non-activating NSPanel that dismisses on resign-key, so clicking Finder to grab a file tore the popover down before the drop landed (Apple FB11984872). Fix (user-chosen Option 2): route drops to the normal `WindowGroup("workspace")` → `MainWindowView`, which does NOT dismiss on resign-key.

- **`MainWindowView` is now a launcher-routing drop target** (mirrors `MenuBarPopoverView.fileDrop`): drop text on the workspace chrome → `toolRegistry.detect()` → on match, `toolSeed.set()` + `selectedToolId = result.toolId` (pre-fill wired by Plan 06); on no-match, a non-destructive post-drop notice (D-03 analog — workspace has no search field to stage into); binary/oversized → `onError` → `WarningBannerView`. `DropOverlayView` shows during drag.
- **Per-tool drops in the detail pane are unchanged** — each tool keeps its own `.fileDrop` (innermost target wins), so Tests 5/6/7 mechanics needed no change.
- **Always-visible "Open in Window" affordance** added to the popover's `searchBar` HStack (`macwindow` icon, `accessibilityLabel "Open Flint in a resizable window to drag and drop files"`). Lives in always-rendered chrome, so it survives history accumulation. Mirrors the existing hidden ⌘N handler (now ≥2 `openWorkspace()` call sites). The hidden ⌘N shortcut is retained.

## Deviations (during human checkpoint)

The plan specified `.safeAreaInset(edge: .top)` for the post-drop banner. In practice that floated the banner across the full window width, overlapping the sidebar and the tool's toolbar (two screenshots from the user). **Corrected:** the banner now renders inside the **detail pane's** content VStack, above the tool view — it stacks cleanly below the window toolbar and never touches the sidebar. Also added a **visible × dismiss button** (`accessibilityLabel "Dismiss notice"`) per user request, replacing a non-discoverable tap-to-dismiss.

## Verification

- OK_TASK1, OK_TASK2 grep gates: pass
- OK_BUILD: `xcodebuild -scheme Flint -configuration Debug build` → **BUILD SUCCEEDED**
- Human checkpoint: UAT Tests 5, 6, 7, 8 re-run against the workspace window — **all pass**. Window survives resign-key; Open-in-Window button stays visible with history present; no-match notice confirmed as the accepted D-03 substitute; banner layout clean with dismiss button.

## Key files

- `UI/MainWindowView.swift` — window-level launcher drop (detect → seed + select), post-drop banner (detail-pane VStack) with dismiss button, drag overlay.
- `UI/MenuBarPopoverView.swift` — always-visible Open-in-Window button in `searchBar`.

## Constraints honored

No new files. MenuBarExtra / MenuBarExtraAccess untouched. No custom NSPanel (Option 1 rejected). Reused existing `fileDrop`, `DropOverlayView`, `WarningBannerView`, `toolRegistry.detect`, `toolSeed.set`.

## Commits

- 5369e67 feat(03-07): make workspace window a launcher-routing file-drop target
- 4bfda79 feat(03-07): add always-visible open-in-window affordance to popover search bar
- 9fb10df fix(03-07): banner in detail pane (no sidebar/toolbar overlap) + dismiss button

## Self-Check: PASSED
