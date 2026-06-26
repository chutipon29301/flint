---
phase: 03-polish-distribution
plan: 02a
subsystem: ui-input
tags: [drag-and-drop, ondrop, nsitemprovider, file-io, off-main, overlay, detect-routing, warningbanner]

# Dependency graph
requires:
  - phase: 03-polish-distribution
    plan: 01
    provides: "openLauncherWithStagedText staging semantics + ToolRegistry.detect/ToolSeed routing reused for the launcher no-match drop"
  - phase: 01-infrastructure-core-tools
    provides: "ToolRegistry.detect(from:) + ToolSeed (FROZEN), HashViewModel.startFileHash off-main pipeline, Base64ViewModel.encodeFileChunked off-main pipeline, PopoverNavigationState, WarningBannerView"
provides:
  - "DropOverlayView — stateless full-surface drag-over overlay (single valid state, no rejected style) reused by all drop targets"
  - "View.fileDrop(isTargeted:onText:onError:) — shared text-tool drop helper (off-main URL resolve + UTF-8 decode + 5MB size guard + post-drop binary rejection) consumed by plan 03-02b's 9 text tools"
  - "Base64ViewModel.loadFile(url:) — off-main chunked drop entry point parallel to Hash startFileHash"
  - "Any-file .onDrop + DropOverlayView on Base64 and Hash (binary tools, uncapped, off-main)"
  - "Launcher (MenuBarPopoverView) file drop: detect()-routes a dropped text file to the best tool (D-04) or stages it in search on no-match; binary/oversized rejected post-drop via WarningBannerView"
affects: [03-02b-text-tool-drops]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Binary tools use a permissive `.onDrop(of: [.fileURL])` (any file) calling their existing off-main chunked pipeline directly — no UTF-8 gate, no size cap (D-06)"
    - "Text path / launcher use the shared `View.fileDrop` helper: off-main URL resolve via URL(dataRepresentation:relativeTo:), UTF-8 decode, fileSizeKey size guard, both callbacks hopped to @MainActor"
    - "Single-state drag-over overlay (DropOverlayView) — binary-vs-text is only known post-decode, so rejection is surfaced POST-DROP via WarningBannerView, never via a drag-time rejected overlay (checker WARNING 5)"
    - "Launcher drop reuses the Services D-02/D-03 routing (detect → ToolSeed + .tool navigation, or searchText + .searchResults) without the WindowCoordinator activation dance since the popover is already the active surface"

key-files:
  created:
    - "UI/Components/DropOverlayView.swift"
    - "Core/Services/FileDropHandler.swift"
  modified:
    - "Tools/Base64/Base64ViewModel.swift"
    - "Tools/Base64/Base64View.swift"
    - "Tools/Hash/HashView.swift"
    - "UI/MenuBarPopoverView.swift"
    - "Flint.xcodeproj/project.pbxproj"

key-decisions:
  - "DropOverlayView ships as a single-state overlay (label-only, no isRejected) — drag-time rejection styling would be dead code because text-vs-binary is undecidable until after the drop (post UTF-8 decode); rejection is shown post-drop via WarningBannerView (D-06, checker WARNING 5)"
  - "Binary tools (Base64, Hash) use their own inline permissive .onDrop rather than the shared fileDrop helper, because they accept ANY file and must NOT apply the helper's UTF-8 gate or 5MB cap (D-06 — preserve the uncapped large-file-hash path)"
  - "5MB chosen as the text-tool size threshold (D-06 Claude's Discretion) — applies only to the shared text fileDrop helper, never to the binary pipelines"
  - "Launcher no-match stages text directly into searchText + .searchResults in the .fileDrop onText closure (no WindowCoordinator dance) because the popover is already frontmost when an in-popover drop occurs"

patterns-established:
  - "Drop wiring split by tool class: binary = inline any-file .onDrop → existing off-main entry; text/launcher = shared View.fileDrop helper with post-drop validation"
  - "pbxproj registration for new Swift files: PBXBuildFile + PBXFileReference + group child + app-target Sources phase entry (test target left untouched)"

requirements-completed: [DIST-02]

# Metrics
duration: 5min
completed: 2026-06-26
---

# Phase 3 Plan 02a: Drag-and-Drop Foundation + Binary Tools + Launcher Routing Summary

**The DIST-02 foundation + binary half: a stateless `DropOverlayView`, a shared `View.fileDrop` text-drop helper (off-main UTF-8 decode + 5MB guard + post-drop binary rejection), any-file drops on Base64/Hash via their existing off-main chunked pipelines, and a launcher drop that reads file text, runs `detect()`, and routes to the best tool or the search-staged launcher on no match.**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-06-26T10:58:06Z
- **Completed:** 2026-06-26T11:03:39Z
- **Tasks:** 2 auto completed (0 checkpoints in this plan — the end-to-end drag-drop human-verify lives in plan 03-02b)
- **Files:** 7 (2 created, 5 modified — including the pbxproj registration)

## Accomplishments
- **Task 1** — Created `UI/Components/DropOverlayView.swift`: a stateless full-surface overlay (`Color.accentColor.opacity(0.08)` fill + 2pt `accentColor` rounded border, `doc.fill.badge.plus` SF Symbol + a `label` at 15pt semibold, combined accessibility element). Single valid drag-over state — no `isRejected` (documented in the doc comment as post-drop rejection via WarningBannerView per D-06 / checker WARNING 5). Created `Core/Services/FileDropHandler.swift`: a `View.fileDrop(isTargeted:onText:onError:)` extension that resolves the dropped URL off-main via `URL(dataRepresentation:relativeTo:)`, applies a 5MB `fileSizeKey` guard, decodes UTF-8 inside a `Task`, and dispatches both callbacks on `@MainActor` with the canonical UI-SPEC rejection copy. Registered both files in the app target (pbxproj; test target untouched).
- **Task 2** — Added `Base64ViewModel.loadFile(url:)` running the existing `Task.detached → encodeFileChunked → await MainActor.run` pipeline (parallel to Hash's `startFileHash`). Wired permissive any-file `.onDrop(of: [.fileURL])` + `DropOverlayView("Drop to load file")` onto Base64View and HashView (binary tools, uncapped, off-main). Wired the launcher: `MenuBarPopoverView` applies the shared `.fileDrop` on its root VStack — `onText` runs `detect()` and routes matched text via `ToolSeed` + `.tool(toolId:)` navigation, no-match text via `searchText` + `.searchResults`; `onError` drives a new `dropError` state rendered as a `WarningBannerView` (post-drop rejection surface), plus `DropOverlayView("Drop to open in best tool")`. Left `ToolRegistry.swift` untouched.

## Task Commits

1. **Task 1: DropOverlayView + shared FileDropHandler** — `04e8870` (feat)
2. **Task 2: Wire drop into binary tools (Base64, Hash) + launcher** — `854d516` (feat)

**Plan metadata:** _(this commit)_ (docs: complete plan)

## Files Created/Modified
- `UI/Components/DropOverlayView.swift` — **created**. Stateless single-state drag-over overlay with contextual label + VoiceOver label; doc-comment records that rejection is surfaced post-drop via WarningBannerView.
- `Core/Services/FileDropHandler.swift` — **created**. `View.fileDrop(isTargeted:onText:onError:)` — off-main URL resolution, 5MB text size guard via `fileSizeKey`, UTF-8 decode with binary→`onError` rejection, both callbacks on `@MainActor`. Imports SwiftUI + UniformTypeIdentifiers; uses `url.lastPathComponent` (never `url.path`, Pitfall #4).
- `Tools/Base64/Base64ViewModel.swift` — **modified**. Added `loadFile(url:)` running the chunked off-main pipeline using the current `urlSafe` mode.
- `Tools/Base64/Base64View.swift` — **modified**. Added `import UniformTypeIdentifiers`, `isDragTargeted` state, any-file `.onDrop` → `viewModel.loadFile(url:)`, and `DropOverlayView("Drop to load file")` overlay.
- `Tools/Hash/HashView.swift` — **modified**. Added `import UniformTypeIdentifiers`, `isDragTargeted` state, any-file `.onDrop` → `viewModel.startFileHash(url:)`, and `DropOverlayView("Drop to load file")` overlay.
- `UI/MenuBarPopoverView.swift` — **modified**. Added `isDragTargeted` + `dropError` state, a top-of-body `WarningBannerView` driven by `dropError`, the `.fileDrop` launcher routing (`detect()`+`ToolSeed`+navigation / search-staged no-match), and `DropOverlayView("Drop to open in best tool")` overlay.
- `Flint.xcodeproj/project.pbxproj` — **modified**. Registered the two new Swift files (PBXBuildFile + PBXFileReference + group child + app-target Sources phase) — DropOverlayView in UI/Components, FileDropHandler in Core/Services. Test target untouched. `plutil -lint` passes.

## Decisions Made
- **Single-state overlay (no `isRejected`):** drag-time rejection styling is dead code because text-vs-binary is only knowable post-decode; rejection is surfaced post-drop via WarningBannerView (D-06, checker WARNING 5).
- **Binary tools bypass the shared helper:** Base64/Hash use their own inline any-file `.onDrop` so they neither apply the UTF-8 gate nor the 5MB cap — preserving the uncapped large-file-hash capability (D-06).
- **5MB text threshold:** scoped to the shared `fileDrop` helper only (D-06 Claude's Discretion), never a universal cap.
- **No WindowCoordinator dance on the launcher drop:** the popover is already frontmost during an in-popover drop, so `onText` sets navigation/search state directly (mirrors the Services no-match staging without re-running the activation dance).

## Deviations from Plan

None - plan executed exactly as written.

The plan's Task 1 `<action>` instructed the DropOverlayView doc comment to mention `isRejected` while the same task's `<verify>` requires `! grep -q "isRejected"`. To satisfy both intents, the doc comment phrases the same rationale as "no rejected-style visual" (no literal `isRejected` token). This is a wording-only reconciliation of an internal plan tension, not a functional deviation — the design (single-state overlay, post-drop rejection) is exactly as specified.

**Total deviations:** 0 functional (1 wording reconciliation of a plan-internal verify/action mismatch).
**Impact on plan:** None — all task verifies and acceptance criteria pass.

## Issues Encountered

- **Headless `xcodebuild -scheme Flint` still fails only on the pre-existing test-target error** (`FlintTests/PinnedToolReorderTests.swift: import XCTest — "compilation search paths unable to resolve module dependency: 'XCTest'"`). This predates phase 03 (committed in the project-rename `5a4632c`), is out of scope (SCOPE BOUNDARY), and is already logged in `deferred-items.md` by plan 03-01. **None of this plan's new/modified files produce compile errors**: `swiftc -parse` on all six source files is clean, and the full scheme build emits no errors outside that one pre-existing test file (confirmed by filtering `error:` lines — only the two `PinnedToolReorderTests.swift` XCTest lines remain). The app target's own Swift sources compile.

## Deferred Manual Verification

None for this plan — 03-02a is autonomous with no human-verify checkpoint of its own. The end-to-end drag-and-drop functional verification (drag a real binary onto Base64/Hash, a real text/JWT file onto the launcher, confirm overlay appears/disappears, confirm binary/oversized rejection banner) lives in **plan 03-02b** after the 9 text tools are wired, and folds into the phase-end batched manual pass.

## Known Stubs

None — no placeholder/TODO/empty-data stubs introduced. All drop paths are wired to live off-main pipelines and live routing.

## Next Phase Readiness
- DIST-02 foundation + binary half complete and source-verified. The shared `View.fileDrop` helper and `DropOverlayView` are ready for plan 03-02b to wire across the remaining 9 text-tool views (Wave 3, depends_on 03-02a).
- `Base64ViewModel.loadFile(url:)` gives Base64 a drop entry point parallel to Hash's `startFileHash(url:)`.
- No blockers introduced. The one pre-existing, out-of-scope test-target build issue remains logged in `deferred-items.md`.

## Self-Check: PASSED

- Created files verified on disk: `UI/Components/DropOverlayView.swift`, `Core/Services/FileDropHandler.swift`.
- Task commits verified in git log: `04e8870`, `854d516`.
- pbxproj validity confirmed via `plutil -lint` (OK).
- Plan-level verification + both task `<verify>` blocks + all `<acceptance_criteria>` pass; ToolRegistry.swift unmodified.

---
*Phase: 03-polish-distribution*
*Completed: 2026-06-26*
