---
phase: 03-polish-distribution
plan: 02b
type: execute
wave: 3
depends_on: ["03-02a"]
files_modified:
  - Tools/JSONFormatter/JSONFormatterView.swift
  - Tools/JWT/JWTView.swift
  - Tools/URLEncoder/URLView.swift
  - Tools/Timestamp/TimestampView.swift
  - Tools/Markdown/MarkdownView.swift
  - Tools/NumberBase/NumberBaseView.swift
  - Tools/Regex/RegexView.swift
  - Tools/Color/ColorView.swift
  - Tools/TextDiff/TextDiffView.swift
autonomous: false
requirements: [DIST-02]
must_haves:
  truths:
    - "User drags a text file onto an open text tool and its contents load into that tool's input"
    - "User drags a binary/non-UTF-8 file onto a text-only tool and gets an inline WarningBannerView, not a crash"
    - "Every one of the 9 text-tool views carries the shared .fileDrop modifier and a DropOverlayView overlay"
    - "Implements D-04 (text-tool side): a file dropped on an open text tool loads into THAT tool's input — open-tool-only routing never yanks the user out of the tool they deliberately opened"
    - "Implements D-06 (text-tool side): a binary/oversized/non-UTF-8 file dropped on a text tool is rejected via the shared handler with an inline WarningBannerView post-drop, never a crash"
  artifacts:
    - path: "Tools/JSONFormatter/JSONFormatterView.swift"
      provides: "Representative text-tool view with .fileDrop + DropOverlayView wired to viewModel.input/errorMessage"
      contains: "fileDrop"
  key_links:
    - from: "Tools/*/*View.swift (9 text tools)"
      to: "viewModel input / errorMessage"
      via: "FileDropHandler.fileDrop success → viewModel.input ; failure → viewModel.errorMessage"
      pattern: "fileDrop"
---

<objective>
Deliver the text-tool half of DIST-02: apply the shared `.fileDrop` modifier (from plan 03-02a) and a `DropOverlayView` overlay to the 9 remaining text-tool views so each loads dropped UTF-8 text into its primary input and rejects binary/oversized files via its existing error surface. This is the mechanical boilerplate slice the checker split out of the original 03-02 (BLOCKER 2): same two-line modifier per view, no new components.

This plan also carries the end-to-end drag-and-drop human verification (covering both binary tools/launcher from 03-02a and the text tools wired here), since the full drop surface only exists once both 03-02a and 03-02b have shipped.

Purpose: Complete the file-content input path across every tool without introducing new abstractions — the heavy lifting (handler, overlay, routing) is already done in 03-02a.
Output: `.fileDrop` + overlay on all 9 text-tool views, and a passed end-to-end drag-and-drop checkpoint.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/phases/03-polish-distribution/03-CONTEXT.md
@.planning/phases/03-polish-distribution/03-PATTERNS.md
@.planning/phases/03-polish-distribution/03-UI-SPEC.md
@.planning/phases/03-polish-distribution/03-02a-SUMMARY.md

<interfaces>
From Core/Services/FileDropHandler.swift (plan 03-02a output — the shared helper to apply):
- `func fileDrop(isTargeted: Binding<Bool>, onText: @escaping (String) -> Void, onError: @escaping (String) -> Void) -> some View` — decodes dropped file UTF-8 off-main, dispatches onText/onError on @MainActor, applies 5MB text guard + binary rejection copy.

From UI/Components/DropOverlayView.swift (plan 03-02a output):
- `struct DropOverlayView: View { var label: String }` — single valid drag-over state; no isRejected (rejection is post-drop via WarningBannerView).

From UI/Components/WarningBannerView.swift:
- `struct WarningBannerView { let message: String; let severity: BannerSeverity }` — the only sanctioned drop-error surface; do not invent a new banner.

From all Tools/*/*ViewModel.swift:
- Each exposes `var input: String` (setting it triggers the existing didSet→transform) and `var errorMessage: String?` rendered via WarningBannerView/InlineErrorView. TextDiff has two inputs — load into the primary/left input.
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Apply .fileDrop + DropOverlayView to the 9 text-tool views</name>
  <read_first>
    - Tools/JSONFormatter/JSONFormatterView.swift, Tools/JWT/JWTView.swift, Tools/URLEncoder/URLView.swift, Tools/Timestamp/TimestampView.swift, Tools/Markdown/MarkdownView.swift, Tools/NumberBase/NumberBaseView.swift, Tools/Regex/RegexView.swift, Tools/Color/ColorView.swift, Tools/TextDiff/TextDiffView.swift (read each root view body to find the ViewModel reference and `input` property; TextDiff has two inputs — load into the primary/left input)
    - Core/Services/FileDropHandler.swift + UI/Components/DropOverlayView.swift (03-02a outputs)
    - .planning/phases/03-polish-distribution/03-PATTERNS.md (".onDrop additions to tool views" — the exact modifier placement)
  </read_first>
  <action>
    For each of the 9 text tool views (JSONFormatter, JWT, URLEncoder, Timestamp, Markdown, NumberBase, Regex, Color, TextDiff), add `@State private var isDragTargeted = false` and apply the shared `.fileDrop(isTargeted: $isDragTargeted, onText: { viewModel.input = $0 }, onError: { viewModel.errorMessage = $0 })` on the root view. Where a tool's input property is named differently (e.g. test string, left/right text), set the primary input that drives that tool's transform and surface errors via its existing `errorMessage` (or equivalent error state already rendered by WarningBannerView/InlineErrorView). For TextDiff, load into the primary/left input. Add `.overlay { if isDragTargeted { DropOverlayView(label: "Drop to load") .transition(.opacity.animation(.easeOut(duration: 0.15))) } }`.

    For any tool whose ViewModel lacks an `errorMessage: String?`, route the drop error to the nearest existing inline error surface; if none exists, add a minimal `@State private var dropError: String?` in the view and render a `WarningBannerView(message: dropError!, severity: .warning)` at the top of the body when non-nil (do NOT invent new error UI styles — reuse WarningBannerView only). This is the mechanical boilerplate slice: no new components, no routing logic — just the shared modifier + overlay per view.
  </action>
  <verify>
    <automated>cd /Users/chutipon/Documents/project/flint && for f in Tools/JSONFormatter/JSONFormatterView.swift Tools/JWT/JWTView.swift Tools/URLEncoder/URLView.swift Tools/Timestamp/TimestampView.swift Tools/Markdown/MarkdownView.swift Tools/NumberBase/NumberBaseView.swift Tools/Regex/RegexView.swift Tools/Color/ColorView.swift Tools/TextDiff/TextDiffView.swift; do grep -q "fileDrop" "$f" && grep -q "DropOverlayView" "$f" || { echo "MISSING in $f"; exit 1; }; done && echo PASS</automated>
  </verify>
  <acceptance_criteria>
    - Each of the 9 text tool views contains a `.fileDrop(...)` modifier and a `DropOverlayView` overlay gated by an `isDragTargeted` @State (the programmatic loop above asserts every view individually).
    - `onText` sets the tool's primary input property (driving its existing transform); `onError` routes to an existing or WarningBannerView-based error surface.
    - No new error-banner component is introduced (grep finds only `WarningBannerView`/`InlineErrorView` for drop errors, not a new struct).
    - `Core/Services/ToolRegistry.swift` unmodified.
  </acceptance_criteria>
  <done>All 9 text tools load dropped UTF-8 text into their input and reject binary/oversized files via the shared handler and existing error banners.</done>
</task>

<task type="checkpoint:human-verify" gate="blocking">
  <name>Task 2: Verify drag-and-drop end-to-end (binary + launcher + text tools)</name>
  <action>This is a checkpoint task — the executor performs the verification described below (what-built / how-to-verify) and pauses for the human resume-signal. No code is written in this task.</action>
  <what-built>The complete DIST-02 drop surface: a whole-surface drag-over overlay and shared text-file drop handler (03-02a), permissive any-file drops on Base64/Hash via the chunked pipeline (03-02a), launcher-routed drops through detect() (03-02a), and the shared .fileDrop wired across all 9 text-tool views (this plan).</what-built>
  <how-to-verify>
    1. Run Flint. Open the JSON Formatter tool. Drag a `.json` text file onto the tool surface — the overlay "Drop to load" appears while dragging; on drop the file contents populate the input and format.
    2. Drag a binary file (e.g. an image or `.zip`) onto the JSON Formatter — EXPECTED: a WarningBannerView appears ("non-text data… Try Base64 or Hash") AFTER the drop, no crash, and the overlay itself stays the normal valid style during drag (rejection is post-drop, per the WARNING-5 design).
    3. Repeat the text-drop on at least 3 more text tools (e.g. JWT, Regex, Text Diff — TextDiff loads into its primary/left input) — confirm content loads and the overlay appears.
    4. Open the Hash tool. Drag a large binary file onto it — EXPECTED: it hashes off-main with progress (ProgressHashView), UI stays responsive, large file path still works (no size cap regression).
    5. Open Base64. Drag any file — EXPECTED: it encodes off-main without blocking.
    6. Open the launcher (root popover). Drag a text file containing a JWT — EXPECTED: detect() routes it to the JWT Decoder pre-filled. Drag a text file with non-matching content — EXPECTED: text is staged in the search field. Drag a binary file — EXPECTED: WarningBannerView rejection post-drop.
    7. Confirm the overlay fades in/out smoothly (easeOut 0.15).
  </how-to-verify>
  <resume-signal>Type "approved" or describe failures (overlay missing, UI froze on large file, wrong routing, crash on binary, a text tool not accepting drops).</resume-signal>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Filesystem → Flint via drop (text tools) | Arbitrary file (binary, oversized, non-UTF-8, alias URL) crosses into a text tool's input |
| NSItemProvider internal queue → @MainActor | Drop completion runs off-main (handled by the shared 03-02a handler); state mutation hops to MainActor |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-03-04b | Tampering | Binary file dropped into a text tool | mitigate | Reuses the 03-02a shared handler: UTF-8 decode attempt → throw → WarningBannerView rejection post-drop; content read, never executed. |
| T-03-05b | Denial of Service | Oversized file dropped into a text tool | mitigate | Reuses the 03-02a 5MB text guard via fileSizeKey → reject with "too large" copy. |
| T-03-SC | Tampering | npm/pip/cargo installs | mitigate | No package installs in this plan. N/A. |
</threat_model>

<verification>
- All 9 text-tool views carry the shared `.fileDrop` + `DropOverlayView` (programmatic per-file loop passes).
- No new error-banner component; ToolRegistry.swift unmodified.
- Human checkpoint confirms the full drop surface (text tools + binary tools + launcher) with no UI freeze on large files and correct routing.
</verification>

<success_criteria>
- DIST-02 fully met across 03-02a + 03-02b: all tools accept dropped text files; Base64/Hash accept any file; nothing crashes or freezes; launcher drops route via detect().
</success_criteria>

<output>
Create `.planning/phases/03-polish-distribution/03-02b-SUMMARY.md` when done.
</output>
