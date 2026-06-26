---
phase: 03-polish-distribution
plan: 02a
type: execute
wave: 2
depends_on: ["03-01"]
files_modified:
  - UI/Components/DropOverlayView.swift
  - Core/Services/FileDropHandler.swift
  - UI/MenuBarPopoverView.swift
  - Tools/Base64/Base64View.swift
  - Tools/Base64/Base64ViewModel.swift
  - Tools/Hash/HashView.swift
autonomous: true
requirements: [DIST-02]
must_haves:
  truths:
    - "User drags a binary file onto Base64 or Hash and it is processed off-main via the existing chunked pipeline without freezing the UI"
    - "User drags a text file onto the launcher and detect() routes it to the best-matched tool pre-filled (or stages it in the search field on no match)"
    - "A drag-over overlay covers the whole surface while dragging and disappears on drop/exit"
    - "A binary/non-UTF-8 file dropped on the launcher (text path) surfaces an inline WarningBannerView after the drop, never a crash"
    - "Dropping a binary or oversized file on a text tool shows a WarningBannerView AFTER the drop completes — not during drag — because binary vs text is determined by UTF-8 decode (post-drop); the drag-over overlay remains the single valid-state accent style throughout"
  artifacts:
    - path: "UI/Components/DropOverlayView.swift"
      provides: "Stateless full-surface drag-over overlay (single valid state) with VoiceOver label and contextual label text"
      min_lines: 20
    - path: "Core/Services/FileDropHandler.swift"
      provides: "Shared onText/onError onDrop helper: resolves fileURL from NSItemProvider off-main, UTF-8 decode with binary rejection (post-drop), size guard"
      contains: "loadItem"
  key_links:
    - from: "UI/MenuBarPopoverView.swift"
      to: "ToolRegistry.detect + ToolSeed + navigationState"
      via: "launcher drop reads text, runs detect(), stages seed or search text; binary/oversized → WarningBannerView"
      pattern: "detect\\(from"
    - from: "Tools/Base64,Hash *View.swift"
      to: "viewModel.loadFile(url:) / viewModel.startFileHash(url:)"
      via: "permissive any-file .onDrop calls the existing off-main chunked entry point"
      pattern: "startFileHash\\(url:"
---

<objective>
Deliver the foundation + binary half of DIST-02: the shared `DropOverlayView` and `FileDropHandler` drop primitives, the any-file drop on the two binary tools (Base64, Hash) via the existing off-main chunked pipeline, and the launcher drop that reads file text, runs `detect()`, and routes to the best tool (mirrors Services D-02, reusing `openLauncherWithStagedText` semantics from plan 03-01 for no-match staging). Text-only tools are wired in plan 03-02b (this plan ships the reusable handler they consume).

This plan was split from the original 03-02 (checker BLOCKER 2): the foundation, binary wiring, and launcher routing live here (Wave 2); the mechanical `.fileDrop` boilerplate across the 9 text-tool views moved to plan 03-02b (Wave 3, depends_on 03-02a).

Purpose: Make file content a first-class input path alongside paste and Services, without regressing the shipped large-file-hash capability (no blanket size cap — D-06).
Output: `DropOverlayView`, a shared `FileDropHandler`, any-file `.onDrop` + overlay on Base64/Hash, the launcher drop routing, and a `loadFile(url:)` entry point added to Base64ViewModel.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/phases/03-polish-distribution/03-CONTEXT.md
@.planning/phases/03-polish-distribution/03-RESEARCH.md
@.planning/phases/03-polish-distribution/03-PATTERNS.md
@.planning/phases/03-polish-distribution/03-UI-SPEC.md
@.planning/phases/03-polish-distribution/03-01-SUMMARY.md

<interfaces>
From UI/Components/WarningBannerView.swift (analog for DropOverlayView; also the rejection surface):
- `struct WarningBannerView { let message: String; let severity: BannerSeverity }` — `.warning`/`.error`; uses system semantic colors, `.accessibilityElement(children: .combine)` + `.accessibilityLabel`.

From Tools/Hash/HashViewModel.swift:
- `func startFileHash(url: URL)` (line 105) — existing off-main chunked file-hash entry point. Call directly for Hash drops.

From Tools/Base64/Base64ViewModel.swift:
- `var isProcessingFile: Bool` (line 45), `var errorMessage: String?` (line 29), `func encodeFile()` (line 176, opens NSOpenPanel), `static func encodeFileChunked(url:urlSafe:) async throws -> String` (line 208). The Task.detached + `await MainActor.run` off-main pattern lives at lines 188-205. Add a `loadFile(url:)` that resolves a dropped URL and runs that same chunked pipeline (no NSOpenPanel).

From App/WindowCoordinator.swift (added in plan 03-01):
- `func openLauncherWithStagedText(_ text: String)` — staging semantics to mirror for the launcher no-match drop (the popover is already the active surface, so the in-popover drop sets `searchText` + `.searchResults` directly rather than re-running the activation dance).

From Core/Services/ToolRegistry.swift (FROZEN):
- `func detect(from string: String) -> DetectionResult?`; `ToolSeed.set(toolId:value:)`.

From UI/MenuBarPopoverView.swift:
- `enum PopoverNavigationState` with `.root`, `.tool(toolId:)`, `.history`, `.searchResults(query:)`; `@State private var navigationState`, `@State private var searchText`. The clipboard-accept path (~line 83) sets `navigationState = .tool(toolId:)`.
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: DropOverlayView + shared FileDropHandler</name>
  <read_first>
    - UI/Components/WarningBannerView.swift (full — copy stateless-struct + semantic color + accessibility shape)
    - .planning/phases/03-polish-distribution/03-UI-SPEC.md (Color section "Phase 3 new semantic" — overlay fill Color.accentColor.opacity(0.08), 2pt accent border, cornerRadius 8; Copywriting "Drag-and-Drop" labels; Interaction "Drag-and-Drop" → easeOut 0.15)
    - .planning/phases/03-polish-distribution/03-PATTERNS.md (sections "DropOverlayView.swift" and ".onDrop additions" — exact shells; Shared Patterns → Task.detached for File I/O Off-Main)
    - .planning/phases/03-polish-distribution/03-RESEARCH.md (Pattern 2 — onDrop/NSItemProvider; Pitfall #4 — file-reference URL; A3/A4 risks)
  </read_first>
  <action>
    Create `UI/Components/DropOverlayView.swift`: a stateless `struct DropOverlayView: View` exposing a single injected `var label: String`. Body is a ZStack: fill = `Color.accentColor.opacity(0.08)`, with a 2pt rounded border (`RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: 2)`), centered VStack(spacing: 8) of an SF Symbol `doc.fill.badge.plus` (32pt, accentColor, `.accessibilityHidden(true)`) and `label` at 15pt semibold. Add `.accessibilityElement(children: .combine)` + `.accessibilityLabel(label)`.

    Do NOT add an `isRejected` / rejected visual state to DropOverlayView (checker WARNING 5). `.onDrop(of: [.fileURL])` accepts all file URLs during drag; whether a file is text vs binary is only known AFTER the drop completes (post-decode). Drag-time rejection styling would be dead code with no wiring. Rejection feedback is therefore shown POST-DROP via `WarningBannerView` (D-06), not via the overlay. Document this in the view's doc comment ("overlay shows the valid drag-over affordance only; binary/oversized rejection is surfaced post-drop through WarningBannerView"). CONTEXT.md scopes drag-over styling to Claude's Discretion — the simpler single-state overlay is the correct, internally-consistent choice.

    Create `Core/Services/FileDropHandler.swift`: a `View` extension `func fileDrop(isTargeted: Binding<Bool>, onText: @escaping (String) -> Void, onError: @escaping (String) -> Void) -> some View` that applies `.onDrop(of: [.fileURL], isTargeted: isTargeted)`. In the perform closure: take `providers.first`, call `loadItem(forTypeIdentifier: UTType.fileURL.identifier)`; in its completion (off-main, so wrap UI in `Task { @MainActor in ... }`), build `URL(dataRepresentation: data, relativeTo: nil)`, then in a `Task` attempt `String(contentsOf: url, encoding: .utf8)`. On success call `onText(text)`; on throw call `onError` with the UI-SPEC copy "File contains non-text data and can't be loaded here. Try Base64 or Hash." Add a size guard: if the file's resource size (`url.resourceValues(forKeys: [.fileSizeKey])`) exceeds a text threshold (use 5MB — builder discretion per D-06 Claude's Discretion, this is the text-tool threshold only, NOT a universal cap), call `onError` with "File is too large to load as text. Try dropping into Hash for checksums." Import SwiftUI + UniformTypeIdentifiers. Use `url.lastPathComponent` (never `url.path`) if displaying a name (Pitfall #4).
  </action>
  <verify>
    <automated>cd /Users/chutipon/Documents/project/flint && grep -q "struct DropOverlayView" UI/Components/DropOverlayView.swift && grep -q "accessibilityLabel" UI/Components/DropOverlayView.swift && ! grep -q "isRejected" UI/Components/DropOverlayView.swift && grep -q "func fileDrop" Core/Services/FileDropHandler.swift && grep -q "loadItem" Core/Services/FileDropHandler.swift && grep -q "String(contentsOf" Core/Services/FileDropHandler.swift && grep -q "fileSizeKey" Core/Services/FileDropHandler.swift && echo PASS</automated>
  </verify>
  <acceptance_criteria>
    - `DropOverlayView` is a stateless struct (no @State), exposes a single `label` (NO `isRejected`), uses `Color.accentColor` semantic color only (no hex), and has an `.accessibilityLabel`.
    - A doc comment states rejection is surfaced post-drop via WarningBannerView, not via the overlay.
    - `FileDropHandler.swift` defines `func fileDrop(isTargeted:onText:onError:)` using `.onDrop(of: [.fileURL])`, resolves URL via `URL(dataRepresentation:relativeTo:)`, decodes UTF-8 inside a `Task`, and dispatches both `onText`/`onError` on `@MainActor`.
    - A text-size threshold guard exists using `fileSizeKey`; binary/UTF-8 failure routes to `onError` with the exact UI-SPEC rejection copy.
    - No `url.path` is used for display (grep `url.path` returns nothing in FileDropHandler.swift, or only in non-display context).
  </acceptance_criteria>
  <done>A reusable single-state overlay component and a single drop-handling extension exist; text-tool drops decode UTF-8 off-main and reject binary/oversized gracefully (post-drop, via WarningBannerView). No dead rejected-overlay code.</done>
</task>

<task type="auto">
  <name>Task 2: Wire drop into binary tools (Base64, Hash) + launcher</name>
  <read_first>
    - Tools/Hash/HashView.swift and Tools/Hash/HashViewModel.swift (lines 105-136 startFileHash — the off-main entry to call directly)
    - Tools/Base64/Base64View.swift and Tools/Base64/Base64ViewModel.swift (lines 176-271 — encodeFile/encodeFileChunked; add loadFile(url:) mirroring lines 188-205)
    - UI/MenuBarPopoverView.swift (lines 67-140 — root VStack, navigationState/searchText, the existing clipboard-accept routing ~line 83; this is where the launcher drop attaches)
    - Core/Services/FileDropHandler.swift (Task 1 output)
    - UI/Components/DropOverlayView.swift (Task 1 output)
    - UI/Components/WarningBannerView.swift (the post-drop rejection surface)
  </read_first>
  <action>
    Add `func loadFile(url: URL)` to `Base64ViewModel`: set `isProcessingFile = true`, clear `errorMessage`, then run the existing `Task.detached` → `encodeFileChunked(url:urlSafe:)` → `await MainActor.run` pipeline (copy lines 188-205; use the current `urlSafe` mode state). This gives Base64 a drop entry point parallel to Hash's `startFileHash(url:)`.

    In `Tools/Base64/Base64View.swift` and `Tools/Hash/HashView.swift`: add `@State private var isDragTargeted = false`, apply `.onDrop(of: [.fileURL], isTargeted: $isDragTargeted)` directly on the root view (NOT the shared text `fileDrop` helper — binary tools accept ANY file). In the perform closure, resolve the URL via `URL(dataRepresentation:relativeTo:)` and call the existing off-main entry (`viewModel.startFileHash(url:)` for Hash, `viewModel.loadFile(url:)` for Base64) inside `Task { @MainActor in }`. Add `.overlay { if isDragTargeted { DropOverlayView(label: "Drop to load file") .transition(.opacity.animation(.easeOut(duration: 0.15))) } }`.

    In `UI/MenuBarPopoverView.swift`: add `@State private var isDragTargeted = false` and apply `.fileDrop(isTargeted: $isDragTargeted, onText:, onError:)` on the root VStack. In `onText`: run `toolRegistry.detect(from: text)`; if matched, `toolSeed.set(toolId: result.toolId, value: text)` and `navigationState = .tool(toolId: result.toolId)`; else set `searchText = text` and `navigationState = .searchResults(query: text)` (mirrors the Services no-match staging; the WindowCoordinator dance is not needed here since the popover is already the active surface). In `onError`: surface via an inline `WarningBannerView` (add a `@State private var dropError: String?` rendered at the top of the popover body when non-nil — this is the post-drop rejection surface for the WARNING-5 design). Add `.overlay { if isDragTargeted { DropOverlayView(label: "Drop to open in best tool") ... } }`.
  </action>
  <verify>
    <automated>cd /Users/chutipon/Documents/project/flint && grep -q "func loadFile(url: URL)" Tools/Base64/Base64ViewModel.swift && grep -q "DropOverlayView" Tools/Hash/HashView.swift && grep -q "startFileHash(url:" Tools/Hash/HashView.swift && grep -q "loadFile(url:" Tools/Base64/Base64View.swift && grep -q "fileDrop" UI/MenuBarPopoverView.swift && grep -q "detect(from" UI/MenuBarPopoverView.swift && grep -q "WarningBannerView" UI/MenuBarPopoverView.swift && echo PASS</automated>
  </verify>
  <acceptance_criteria>
    - `Base64ViewModel.loadFile(url:)` exists and runs the chunked pipeline off-main (`Task.detached` + `encodeFileChunked` + `await MainActor.run` present in its body).
    - Hash and Base64 views use a permissive `.onDrop(of: [.fileURL])` (any file) calling their existing off-main entry points, each with a `DropOverlayView` overlay.
    - The launcher (`MenuBarPopoverView`) uses the shared `fileDrop` helper, routes matched text via `detect()`+`ToolSeed`+navigation and no-match text via `searchText`+`.searchResults`, and renders a drop error via a `WarningBannerView` driven by a `dropError` state (post-drop rejection).
    - No edit to `Core/Services/ToolRegistry.swift`.
  </acceptance_criteria>
  <done>Binary tools accept any dropped file via the existing chunked pipeline; the launcher routes a dropped text file through detect() to the best tool or the staged search field, and surfaces binary/oversized rejection through WarningBannerView post-drop.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Filesystem → Flint via drop | Arbitrary file (binary, oversized, non-UTF-8, alias URL) crosses into tool input or the file pipeline |
| NSItemProvider internal queue → @MainActor | Drop completion runs off-main; state mutation must hop to MainActor |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-03-04 | Tampering | Binary file dropped into text path (launcher) | mitigate | UTF-8 decode attempt; throw → WarningBannerView rejection post-drop; file content is read, never executed. |
| T-03-05 | Denial of Service | Oversized file dropped into text path | mitigate | 5MB text threshold guard via fileSizeKey → reject with "too large" copy; binary tools intentionally uncapped (use existing streaming pipeline, off-main). |
| T-03-06 | Denial of Service | UI freeze on large binary drop | mitigate | Binary drops call existing off-main chunked pipeline (startFileHash/encodeFileChunked); never read on @MainActor. |
| T-03-07 | Information Disclosure | file-reference/alias URL leaks real path | accept | url.lastPathComponent used for display only; Foundation resolves alias URLs for read; low risk, non-sandboxed local app. |
| T-03-SC | Tampering | npm/pip/cargo installs | mitigate | No package installs in this plan. N/A. |
</threat_model>

<verification>
- DropOverlayView (single state, no isRejected) + FileDropHandler compile and are stateless/reusable.
- Base64/Hash + the launcher have drop wiring; binary tools route to the existing off-main pipeline; launcher rejects binary/oversized via WarningBannerView post-drop.
- ToolRegistry.swift unmodified.
</verification>

<success_criteria>
- The DIST-02 foundation + binary half is met: shared overlay/handler exist, Base64/Hash accept any file off-main, and launcher drops route via detect(). Text-tool wiring (the remaining 9 views) completes in plan 03-02b.
</success_criteria>

<output>
Create `.planning/phases/03-polish-distribution/03-02a-SUMMARY.md` when done.
</output>
</content>
</invoke>
