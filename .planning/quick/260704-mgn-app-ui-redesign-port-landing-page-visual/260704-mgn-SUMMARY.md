---
phase: quick-260704-mgn
plan: 01
subsystem: ui
tags: [design-system, swiftui, visual-refactor]
dependency-graph:
  requires: []
  provides:
    - Core/DesignSystem.swift (Color/Font/Radius/Space token single source of truth)
  affects:
    - UI/MenuBarPopoverView.swift
    - UI/AllToolsGridView.swift
    - UI/SearchView.swift
    - UI/ToolHeaderView.swift
    - UI/Components/DetectionBannerView.swift
    - UI/Components/CodeDisplayView.swift
    - UI/Components/WarningBannerView.swift
    - UI/Components/InlineErrorView.swift
    - UI/Components/CopyButtonView.swift
    - Tools/JWT/JWTView.swift
tech-stack:
  added: []
  patterns:
    - "DesignSystem.swift Color/Font/Radius token extensions — no hardcoded hex in views"
    - "HighlightSwift .custom(css:background:) CSS mapping for exact syntax-token parity"
key-files:
  created:
    - Core/DesignSystem.swift
  modified:
    - Flint.xcodeproj/project.pbxproj
    - UI/MenuBarPopoverView.swift
    - UI/AllToolsGridView.swift
    - UI/SearchView.swift
    - UI/Components/DetectionBannerView.swift
    - UI/ToolHeaderView.swift
    - UI/Components/CodeDisplayView.swift
    - UI/Components/WarningBannerView.swift
    - UI/Components/InlineErrorView.swift
    - UI/Components/CopyButtonView.swift
    - Tools/JWT/JWTView.swift
decisions:
  - "docs/index.html does not exist in this worktree/repo; canonical hex values were taken verbatim from the plan's <canonical_tokens> block (itself sourced from the brief), not re-derived from the site file."
  - "HighlightSwift theme: used HighlightColors.custom(css:background:) with a hand-written CSS mapping (hljs-attr/string/number/literal/punctuation) instead of a bundled .dark(theme:) preset, so JSON/JWT syntax colors land on exact codeKey/codeString/codeNumber/codePunct hex values rather than an approximate theme."
  - "Divider tint applied via .overlay(Color.graphite800) — SwiftUI's Divider has no direct color modifier; overlay is the standard workaround."
  - "Xcode project uses a traditional (non-file-system-synchronized) pbxproj; DesignSystem.swift required explicit PBXFileReference/PBXBuildFile/group/Sources-phase entries, added by hand alongside the file."
metrics:
  duration: ~35 minutes
  completed: 2026-07-04
---

# Phase quick-260704-mgn Plan 01: App UI Redesign — Port Landing Page Visual Summary

Ported the landing page's graphite/ember visual identity into the native SwiftUI app via a single `Core/DesignSystem.swift` token file, then restyled the launcher (grid, search, detection banner) and the shared detail-view components (header, code display, warning/error banners, copy button) plus the JWT Decoder as the reference detail screen — three atomic commits, build green after each.

## What Was Built

**Task 1 — `Core/DesignSystem.swift`:** Single source of truth for all visual tokens: `Color(hex:)` initializer; graphite950/925/900/850/800/700 scale; ash/ashDim/chalk text tokens; spark/sparkHot/sparkGlow accent tokens; codeKey/codeString/codeNumber/codePunct syntax tokens; errorText/errorFill/errorBorder, warningText/warningFill/warningBorder, and success semantic tokens; `Font` tokens (monoLabel/monoBody/monoSearch/bodyText/toolTitle/detailHeading); `Radius` (card/control/chip) and `Space` enums. Registered in `Flint.xcodeproj` (traditional pbxproj — required manual PBXFileReference/PBXBuildFile/Sources-phase entries since the project does not use file-system-synchronized groups).

**Task 2 — Launcher restyle:** `MenuBarPopoverView` background → graphite950; search field is now a graphite950 inset with a 1px graphite800 border that brightens to a 2px spark ring on focus, mono font, ash icons. `AllToolsGridView` tool tiles: ash icons at rest → spark on hover/selected, graphite900 → graphite850 background, graphite800 → spark border, subtle 1.5pt lift on hover/selected (no-ops under Reduce Motion). `SearchView` rows: chalk name, ashDim category, spark-selected icon, graphite850 selected background. `DetectionBannerView` — the one signature spark moment — now uses a sparkGlow-tinted surface with a spark border, a spark-filled primary "Open" button (graphite950 text), and ash "Dismiss".

**Task 3 — Detail components + JWT reference:** `ToolHeaderView` — chalk detailHeading title, spark back link, graphite800 divider. `CodeDisplayView` — graphite950 inset background, ashDim mono empty state, and a custom HighlightSwift CSS mapping (`HighlightColors.custom`) that maps `hljs-attr`→codeKey amber, `hljs-string`→codeString jade, `hljs-number`/`hljs-literal`→codeNumber purple, base text→chalk — giving exact site-palette parity in code blocks rather than an approximate bundled theme. `WarningBannerView` — rose-red `.error` / muted-gold `.warning` tokens with low-alpha tinted fill + 1px border, replacing stock yellow/red. `InlineErrorView` — errorText instead of stock orange. `CopyButtonView` — ash→spark hover, jade "Copied" state. `Tools/JWT/JWTView.swift` (reference detail screen) — uppercase mono ash section labels ("JWT Token", "Header", "Payload", "Signature", "Expiry", "Claims", "Verify Signature"), success/errorText expiry and HMAC verify states, graphite800 "alg:" chip, ash/chalk claim key/value text.

## Verification

- `xcodebuild -project Flint.xcodeproj -scheme Flint -configuration Debug build` → **BUILD SUCCEEDED** after each of the three commits.
- `grep -q "graphite950" Core/DesignSystem.swift && grep -q "codeString" Core/DesignSystem.swift` → pass.
- `! grep -q "accentColor" UI/AllToolsGridView.swift` (comment updated to reference DesignSystem instead) → pass.
- `grep -Eq "Color\.(spark|graphite)" UI/Components/DetectionBannerView.swift` → pass.
- `! grep -Eq "\.yellow|\.red" UI/Components/WarningBannerView.swift` → pass.
- `grep -q "errorText" UI/Components/InlineErrorView.swift` → pass.
- `grep -Eq "Color\.(spark|ash|chalk)" Tools/JWT/JWTView.swift` → pass.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `docs/index.html` does not exist in this worktree**
- **Found during:** Pre-Task-1 context gathering.
- **Issue:** The plan's action text says "confirm each hex against the file" (`docs/index.html`), but neither the worktree nor the main repo (per `git status`) contains that file — it appears to be an artifact referenced in planning docs but not yet committed to this checkout.
- **Fix:** Used the exact hex values already transcribed into the plan's `<canonical_tokens>` block (which states it mirrors `docs/index.html` lines 23-43) as the source of truth. No values were invented; all match the brief's color table verbatim.
- **Files affected:** Core/DesignSystem.swift.
- **Commit:** 10a8725.

**2. [Rule 3 - Blocking] DesignSystem.swift not auto-discovered by Xcode project**
- **Found during:** Task 1 build verification.
- **Issue:** `Flint.xcodeproj` uses a traditional (non-file-system-synchronized) `PBXGroup` structure — new files are not picked up automatically; the build would silently omit the new file with no error (link-only failure once views started referencing it).
- **Fix:** Added explicit `PBXFileReference`, `PBXBuildFile`, group child entry, and Sources build-phase entry for `Core/DesignSystem.swift`, mirroring the existing `Array+HexString.swift` pattern.
- **Files affected:** Flint.xcodeproj/project.pbxproj.
- **Commit:** 10a8725.

**3. [Rule 1 - Bug] `.foregroundStyle(.ash)` failed to compile**
- **Found during:** Task 3 build verification.
- **Issue:** `Text.foregroundStyle(_:)` expects a `ShapeStyle`; `.ash` resolves via `ShapeStyle` static-member lookup, which doesn't see the `Color` extension token (no `ShapeStyle.ash` exists). Compile error: "type 'ShapeStyle' has no member 'ash'".
- **Fix:** Qualified as `Color.ash` at that single call site (JWTView's "Paste or type content above" empty-state text). All other usages in this plan use `.foregroundColor(...)` which resolves correctly against the `Color` extension.
- **Files affected:** Tools/JWT/JWTView.swift.
- **Commit:** 394907c.

## Known Stubs

None. No new stub/placeholder data paths were introduced — this is a pure visual-layer refactor of existing wired views.

## Threat Flags

None. No new network endpoints, auth paths, file access patterns, or schema changes were introduced — visual/styling changes only.

## Follow-up Candidates (Not Touched This Task)

Per the plan's explicit scope ("Do NOT hand-edit the other 12 tool views... note in the SUMMARY that any tool with its OWN hardcoded colors is a follow-up candidate"), the following files still reference stock `.green`/`.red`/`.blue`/`.orange`/`.accentColor`/`.yellow` outside the shared components restyled in this plan:

- Tools/Base64/Base64View.swift
- Tools/Color/ColorTransformer.swift
- Tools/Color/ColorView.swift
- Tools/Color/ColorViewModel.swift
- Tools/Hash/HashView.swift
- Tools/ImageCompress/ImageCompressView.swift
- Tools/JSONFormatter/JSONFormatterView.swift
- Tools/TextDiff/TextDiffView.swift
- Tools/Timestamp/TimestampView.swift
- Tools/URLEncoder/URLView.swift

These 10 tools still inherit the new look through `ToolHeaderView`, `CodeDisplayView`, `WarningBannerView`, `InlineErrorView`, and `CopyButtonView` (all restyled in Task 3), but any color literals local to their own view bodies (e.g. status icons, valid/invalid indicators specific to that tool) were intentionally left untouched per plan scope. A future quick task or plan should sweep these with the same token substitutions applied to `JWTView.swift` in this plan.

## Self-Check: PASSED

All 11 created/modified source files confirmed present on disk; all 3 task commit hashes (`10a8725`, `63172cb`, `394907c`) confirmed present in `git log`.
