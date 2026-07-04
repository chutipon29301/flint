---
phase: quick-260704-mgn
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - Core/DesignSystem.swift
  - UI/AllToolsGridView.swift
  - UI/SearchView.swift
  - UI/MenuBarPopoverView.swift
  - UI/ToolHeaderView.swift
  - UI/Components/DetectionBannerView.swift
  - UI/Components/CodeDisplayView.swift
  - UI/Components/WarningBannerView.swift
  - UI/Components/InlineErrorView.swift
  - UI/Components/CopyButtonView.swift
  - Tools/JWT/JWTView.swift
autonomous: true
requirements: [UI-REDESIGN]
must_haves:
  truths:
    - "App background, cards, and text render in the graphite/ash/chalk palette (no system window-gray or system-blue)"
    - "The ember spark accent appears only at primary action, active/selected tool, detection banner, focus, and the top syntax token — never as large fills"
    - "Code blocks (JSON/JWT) use amber keys, jade strings, purple numbers, ash punctuation — not the default red-string/blue-number scheme"
    - "Error and warning banners use palette-harmonized rose-red / muted-gold tones, visually distinct from the ember accent"
    - "All 13 tool detail screens inherit the new look through the shared components (header, code display, banners, copy buttons, error labels)"
    - "The app builds green (xcodebuild) after each screen and each screen is an atomic commit"
  artifacts:
    - path: "Core/DesignSystem.swift"
      provides: "Single source of truth: Color/Font/spacing/radius tokens matching docs/index.html :root"
      contains: "graphite950"
      min_lines: 60
    - path: "UI/AllToolsGridView.swift"
      provides: "Launcher grid restyled with graphite cards + spark hover/selected"
    - path: "UI/Components/CodeDisplayView.swift"
      provides: "Graphite-inset code surface consumed by every tool's output view"
    - path: "UI/Components/WarningBannerView.swift"
      provides: "Rose-red error / muted-gold warning semantic banners consumed app-wide"
  key_links:
    - from: "all restyled views"
      to: "Core/DesignSystem.swift"
      via: "Color/Font token references"
      pattern: "Color\\.(graphite|ash|chalk|spark|code)"
    - from: "Tools/*/*.View.swift"
      to: "UI/Components (CodeDisplayView, WarningBannerView, CopyButtonView, InlineErrorView)"
      via: "shared component consumption"
      pattern: "CodeDisplayView|WarningBannerView"
---

<objective>
Port the landing page (`docs/index.html`) visual identity into the native SwiftUI app. Create a single `DesignSystem.swift` token file mirroring the site's CSS `:root` palette and type, then restyle the app screen-by-screen to consume those tokens. Visual layer ONLY — no tool logic, inputs/outputs, layout structure, or tool-set changes.

Purpose: A developer landing on the site, downloading, and opening the app should feel one continuous product — same graphite base, same ember accent used with the same restraint, same code-syntax colors, same type personality. The app currently reads as generic stock SwiftUI (system blue, default fonts, system red/yellow alerts).

Output: `Core/DesignSystem.swift` plus restyled launcher, detection banner, and detail-view components/screens. Dark-only for v1 (intentional — the popover is dark; light mode later is a token swap, not a rewrite).

**One rule above all: the ember `spark` accent is a scalpel, not a bucket.** It appears ONLY at primary action, active/selected tool, the detection banner, focus rings, and the single most important syntax token. If large areas turn orange, that is the failure mode — stop and revert.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/quick/260704-mgn-app-ui-redesign-port-landing-page-visual/260704-mgn-BRIEF.md
@./CLAUDE.md

<canonical_tokens>
<!-- Exact values from docs/index.html :root (lines 23-43). Mirror these; do NOT invent. -->
graphite950 #14171c   (app/popover background — NOT pure black)
graphite925 #171b21
graphite900 #1a1e24   (cards, raised surfaces, detail panels)
graphite850 #1f242b   (hover / pressed surface)
graphite800 #242a32   (borders, dividers)
graphite700 #333b45   (stronger borders, kbd chips)
ash         #8a94a2   (secondary/muted text, inactive icons)
ashDim      #626b78   (tertiary text, captions, placeholders)
chalk       #e8ebef   (primary text, cool white)
spark       #ff7a1a   (THE accent — primary action, active state, detect banner, focus)
sparkHot    #ffb347   (ember highlight / hover of accent, key syntax token)
sparkGlow   rgba(255,122,26,0.14)

<!-- Syntax tokens (JSON/JWT/code) -->
codeKey     #ffb347   (JSON keys, JWT claim names)  == sparkHot
codeString  #6fd3b8   (string values; also the site's --jade; reuse for success/valid)
codeNumber  #c9a8ff   (numbers, booleans, timestamps)
codePunct   #626b78   (braces, brackets, colons, commas)  == ashDim

<!-- Semantic states -->
error   text/icon #e5657f  fill rgba(229,101,127,0.10)  border rgba(229,101,127,0.28)
warning text/icon #d9a441  fill rgba(217,164,65,0.10)   border rgba(217,164,65,0.28)  (duller than spark on purpose)
success #6fd3b8 (== codeString jade)
</canonical_tokens>

<interfaces>
<!-- Existing view structure the executor restyles. Layout/logic stay identical — only colors/fonts/radii change. -->

Launcher container: UI/MenuBarPopoverView.swift
  - 480×600 popover. searchBar (HStack, line ~370), Divider, bodyContent switch (root grid / searchResults / tool).
  - Currently .background(Color(NSColor.windowBackgroundColor)) — replace with graphite950.
  - searchBar TextField "Search tools…" uses .system(size:15); magnifyingglass + clear + window + gear icons all .secondary.
  - WarningBannerView used for drop errors; DetectionBannerView used for detect banner.

Launcher grid: UI/AllToolsGridView.swift
  - ToolGridTile (private): Image(tool.sfSymbol) .foregroundColor(.accentColor); Text(tool.name) .primary.
  - background: isSelected ? Color.accentColor.opacity(0.20) : quaternaryLabelColor; cornerRadius(8); strokeBorder(.accentColor).
  - @State isHovered already wired.

Search results: UI/SearchView.swift — SearchToolRow: Image .accentColor, name .system(13,.semibold), category .caption .secondary, isSelected background accentColor.opacity(0.12).

Tool header: UI/ToolHeaderView.swift — back chevron+"All Tools" .accentColor; tool name .system(15,.semibold) .primary; Divider.

Detection banner: UI/Components/DetectionBannerView.swift — VStack title/subtitle, Button("Open …").borderedProminent, Button("Dismiss").plain; background controlBackgroundColor + separatorColor border.

Shared detail components (consumed by ALL 13 tools):
  - UI/Components/CodeDisplayView.swift — read-only HighlightSwift output; .background(Color(NSColor.textBackgroundColor)); empty-state "Output will appear here" .secondary.
  - UI/Components/WarningBannerView.swift — BannerSeverity {warning,error}; tintColor .yellow/.red; background tintColor.opacity(0.15).
  - UI/Components/InlineErrorView.swift — Text(message).caption.foregroundColor(.orange).
  - UI/Components/CopyButtonView.swift — doc.on.doc/checkmark icon .secondary.

JWT reference detail: Tools/JWT/JWTView.swift
  - SegmentSection labels .system(11,.semibold).secondary; CodeDisplayView(language:"json").
  - ExpirySection expiryColor: .secondary/.green/.red (line ~252).
  - HMACVerifySection result: .green/.red checkmark.shield/xmark.shield (line ~409).
  - navigationTitle("JWT Decoder") set inside; header chrome comes from ToolHeaderView wrapper.
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Create DesignSystem.swift token file</name>
  <files>Core/DesignSystem.swift</files>
  <action>
Create `Core/DesignSystem.swift` as the single source of truth for all visual tokens, mirroring the exact values in `docs/index.html` `:root` (see &lt;canonical_tokens&gt; above — confirm each hex against the file, do not invent).

Define, all as static extensions so views read `Color.spark`, `Font.monoLabel`, etc.:

1. `extension Color` — a hex initializer `init(hex: UInt, alpha: Double = 1)` (or reuse an existing one if present), then static tokens: `graphite950/925/900/850/800/700`, `ash`, `ashDim`, `chalk`, `spark`, `sparkHot`, `sparkGlow`; syntax tokens `codeKey`, `codeString`, `codeNumber`, `codePunct`; semantic `errorText`/`errorFill`/`errorBorder`, `warningText`/`warningFill`/`warningBorder`, `success` (== codeString). Fills/borders use the low-alpha rgba values from the brief.
2. `extension Font` — `monoLabel` (11–12 uppercase-intent, use `.system(size:11, weight:.semibold, design:.monospaced)`), `monoBody` (`.system(size:13, design:.monospaced)`), `monoSearch` (`.system(size:15, design:.monospaced)`), `bodyText` (`.system(size:13)`), `toolTitle` (`.system(size:14, weight:.semibold)`), `detailHeading` (`.system(size:16, weight:.semibold)`). Section labels are mono. Body prose is default design. Use SF Mono via `design:.monospaced` (zero-bundle) per brief — do NOT bundle a font.
3. An `enum Radius` (or static CGFloat tokens): `card = 11`, `control = 8`, `chip = 5`. An `enum Space` with the common paddings if helpful (optional — keep minimal).
4. A brief doc comment at top: dark-only v1 is an intentional choice; when light mode arrives, add a parallel light token set here so it becomes a token swap, not a rewrite. Never hard-code colors in views.

Add the file to the Flint target (it lives under Core/, which is already compiled). Do NOT modify any view yet — this task only creates the token file and confirms it compiles.
  </action>
  <verify>
    <automated>xcodebuild -project Flint.xcodeproj -scheme Flint -configuration Debug build 2>&1 | tail -5 | grep -q "BUILD SUCCEEDED" && grep -q "graphite950" Core/DesignSystem.swift && grep -q "codeString" Core/DesignSystem.swift && echo TOKENS_OK</automated>
  </verify>
  <done>Core/DesignSystem.swift exists with all color/syntax/semantic/font/radius tokens matching docs/index.html :root; project builds green; no view changed yet. Commit: "feat(ui): add DesignSystem.swift tokens ported from landing page".</done>
</task>

<task type="auto">
  <name>Task 2: Restyle launcher — grid, search field, and clipboard "Detected" banner</name>
  <files>UI/MenuBarPopoverView.swift, UI/AllToolsGridView.swift, UI/SearchView.swift, UI/Components/DetectionBannerView.swift</files>
  <action>
Restyle the launcher surfaces to consume `DesignSystem.swift` tokens. Keep the grid layout, all 13 tools, search logic, and navigation exactly as they are — visual layer only.

MenuBarPopoverView.swift:
  - Replace `.background(Color(NSColor.windowBackgroundColor))` (line ~132) with `Color.graphite950`.
  - searchBar (line ~370): TextField placeholder "Search tools…" → `.font(.monoSearch)`; make the field an inset — wrap the HStack content with `.graphite950` fill, 1px `.graphite800` border, `Radius.control` corners; placeholder/icons in `.ashDim`/`.ash`; add a `.spark` focus ring (1–2px `.spark` border when `searchFocused`). magnifyingglass/clear/window/gear icons → `.ash` (spark on hover is optional; keep it subtle). Do NOT change any button action or keyboard shortcut.

AllToolsGridView.swift (ToolGridTile):
  - Icon: `.ash` at rest, `.spark` when hovered OR selected (kill `.accentColor`/system-blue).
  - Label: `.chalk` primary text via `.font(.system(size:11))` (or a token); no change to lineLimit/frame.
  - Card background: `.graphite900` at rest, `.graphite850` on hover/selected; `Radius.card` corners.
  - Border: 1px `.graphite800` at rest, `.spark` on hover/selected; add a subtle 1–2pt lift on hover (small `.shadow` or offset — respect Reduce Motion: no-op the animation under `.accessibilityReduceMotion`).
  - No-match empty state text → `.ash`.

SearchView.swift (SearchToolRow + emptyState): icon `.ash`→`.spark` when selected; name `.chalk`; category `.ashDim`; selected row background `.graphite850` (or `spark.opacity(0.12)` only if it stays subtle). emptyState icon/text → `.ash`.

DetectionBannerView.swift — this is the app's signature "spark" moment (the ONE place the accent shines in the launcher):
  - Surface: `.spark`-tinted fill (`sparkGlow` or `spark.opacity(0.10-0.14)`), 1px `.spark` border, `Radius.control` corners.
  - "Detected: …" title in `.chalk` (mono label treatment), subtitle in `.ash`.
  - "Open …" primary button styled with `.spark` (spark fill, graphite950 text — matches the site's download button); keep `.borderedProminent` semantics but tint to spark, or replace with a custom spark-filled button. "Dismiss" stays quiet in `.ash`.
  - Preserve all accessibility labels and both button actions.

Preserve every keyboard/focus affordance and VoiceOver label. Test at the real 480×600 popover size — no layout overflow.
  </action>
  <verify>
    <automated>xcodebuild -project Flint.xcodeproj -scheme Flint -configuration Debug build 2>&1 | tail -5 | grep -q "BUILD SUCCEEDED" && ! grep -q "accentColor" UI/AllToolsGridView.swift && grep -Eq "Color\.(spark|graphite)" UI/Components/DetectionBannerView.swift && echo LAUNCHER_OK</automated>
  </verify>
  <done>Launcher renders graphite950 background, graphite900/850 tool cards with ash/spark icons and spark hover/selected borders, an inset mono search field with spark focus ring, and a spark-accented detection banner. No system-blue accentColor remains in the grid. Builds green. Commit: "feat(ui): restyle launcher grid, search, and detection banner".</done>
</task>

<task type="auto">
  <name>Task 3: Restyle detail views — shared components + JWT reference + per-tool token pass</name>
  <files>UI/ToolHeaderView.swift, UI/Components/CodeDisplayView.swift, UI/Components/WarningBannerView.swift, UI/Components/InlineErrorView.swift, UI/Components/CopyButtonView.swift, Tools/JWT/JWTView.swift</files>
  <action>
Apply the detail-view pattern from the brief. The shared components below are consumed by ALL 13 tool views, so restyling them once propagates the look consistently. Then apply the JWT-specific inline token pass to Tools/JWT/JWTView.swift as the reference detail screen. Visual layer only — no logic, inputs/outputs, or layout structure changes.

ToolHeaderView.swift: tool name → `.chalk` `.font(.detailHeading)` (16pt); "All Tools" back link chevron+text → `.spark` (kill `.accentColor`); Divider tint → `.graphite800`.

CodeDisplayView.swift (the code-block surface for every tool):
  - Background: `.graphite950` inset (replace `Color(NSColor.textBackgroundColor)`).
  - Empty-state "Output will appear here" → `.ashDim`, `.font(.monoBody)`.
  - Syntax colors: HighlightSwift outputs via highlight.js themes and cannot be re-tinted per-token cheaply here. To match the site palette without swapping the highlighter, replace the HighlightSwift theme with a token-mapped rendering: keep it minimal — set the base text to `.chalk` on `.graphite950`, and confirm the highlighted `AttributedString` reads on the dark inset. If HighlightSwift's default theme clashes badly on graphite950, pass an appropriate dark theme (e.g. `.dark(.xcode)` or nearest) via its API so keys/strings/numbers land close to codeKey amber / codeString jade / codeNumber purple. Do NOT rewrite the highlighter or add a dependency. Base/punctuation fallback to `.chalk`/`.codePunct`. Keep `.textSelection(.enabled)` and the plain-text fallback path.

WarningBannerView.swift (error/warning banners app-wide): replace stock `.yellow`/`.red`:
  - `.error`: text/icon `.errorText` (#e5657f) on `.errorFill` fill, 1px `.errorBorder` border, `Radius.control` corners.
  - `.warning`: text/icon `.warningText` (#d9a441, duller than spark) on `.warningFill`, 1px `.warningBorder` border.
  - Keep the icon+text pairing (do not rely on color alone — a11y). Message text stays `.chalk`.

InlineErrorView.swift: `.orange` → `.errorText` (#e5657f) to harmonize with the palette; keep caption size and transition.

CopyButtonView.swift: icon `.ash` at rest, `.spark` on hover; the copied checkmark confirmation in `.success` (codeString jade). Keep the 1.5s reset and accessibility labels.

Tools/JWT/JWTView.swift inline pass (per brief §"Tool detail view — JWT Decoder"):
  - SegmentSection labels ("JWT Token", "Header", "Payload", "Signature") → uppercase mono in `.ash` (`.font(.monoLabel)`).
  - ExpirySection expiryColor (line ~252): `.secondary`→`.ash`, `.green`→`.success`, `.red`→`.errorText`.
  - HMACVerifySection result (line ~409): valid `.green`→`.success`, invalid `.red`→`.errorText`.
  - ClaimsSection "alg:" chip background → `.graphite800`, text `.ash`; claim key `.ash` mono, value `.chalk`.
  - The JWT view's warning banners already route through WarningBannerView (restyled above) — no duplicate work.

Because the header, code display, banners, inline error, and copy button are shared, all 13 tools inherit the new look. Do NOT hand-edit the other 12 tool views in this quick task beyond what the shared components deliver; note in the SUMMARY that any tool with its OWN hardcoded colors (grep for `.green`/`.red`/`.blue`/`.orange`/`.accentColor` under Tools/) is a follow-up candidate, but JWT is the delivered reference.
  </action>
  <verify>
    <automated>xcodebuild -project Flint.xcodeproj -scheme Flint -configuration Debug build 2>&1 | tail -5 | grep -q "BUILD SUCCEEDED" && ! grep -Eq "\.yellow|\.red" UI/Components/WarningBannerView.swift && grep -q "errorText" UI/Components/InlineErrorView.swift && grep -Eq "Color\.(spark|ash|chalk)" Tools/JWT/JWTView.swift && echo DETAIL_OK</automated>
  </verify>
  <done>Shared detail components (header, code display, warning/error banners, inline error, copy button) consume DesignSystem tokens; the JWT screen shows chalk title, spark back link, ash mono section labels, graphite950 code inset, palette-harmonized rose-red/gold status banners, and jade "Copied"/valid states. All 13 tools inherit the shared look. Builds green. Commit: "feat(ui): restyle detail components and JWT reference screen".</done>
</task>

</tasks>

<verification>
- `xcodebuild -project Flint.xcodeproj -scheme Flint -configuration Debug build` succeeds after each task.
- `grep -rn "accentColor\|\.systemBlue" UI/AllToolsGridView.swift UI/ToolHeaderView.swift` returns nothing (system-blue killed in touched surfaces).
- `grep -rn "graphite950\|spark\|codeString" Core/DesignSystem.swift` confirms tokens exist and match docs/index.html.
- Manual (real popover size, human-verify at review): launcher cards graphite with ash/spark icons; detection banner is the single spark moment; JWT code blocks read amber/jade/purple; error/warning banners are rose-red/gold, NOT system red/yellow and NOT the ember accent; no large orange fills anywhere.
- Reduce Motion: hover lift/transition animations no-op.
</verification>

<success_criteria>
- `Core/DesignSystem.swift` is the single source of truth; no new hardcoded hex colors introduced in views (all reference tokens).
- Ember `spark` accent appears ONLY at: primary action, active/selected tool, detection banner, focus ring, top syntax token. No bucket-fill orange.
- Code syntax palette matches the site (amber keys, jade strings, purple numbers, ash punctuation).
- Semantic error/warning banners are palette-harmonized and distinct from the accent.
- All 13 tool screens inherit the look via shared components; JWT is the delivered reference detail screen.
- Dark-only v1 shipped intentionally; build green; three atomic commits (tokens / launcher / detail).
- Zero tool logic, inputs/outputs, layout structure, or tool-set changes.
</success_criteria>

<output>
Create `.planning/quick/260704-mgn-app-ui-redesign-port-landing-page-visual/260704-mgn-SUMMARY.md` when done.
</output>
