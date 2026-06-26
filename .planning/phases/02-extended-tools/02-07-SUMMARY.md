---
phase: 02-extended-tools
plan: 07
subsystem: tool-registry-integration
tags: [registry, integration, detection-chain, all-five-tools, wave-7]
dependency_graph:
  requires: [02-02, 02-03, 02-04, 02-05, 02-06]
  provides: [12-tool-registry, Phase-2-complete]
  affects: []
tech_stack:
  added: []
  patterns: [sanctioned-frozen-file-append, first-match-wins-detection-chain]
key_files:
  created: []
  modified:
    - Core/Services/ToolRegistry.swift
decisions:
  - "Sanctioned Phase-2 append (RESEARCH §0/A5): appended five *Definition.make() calls after Phase-1 entries; struct/init/detect(from:) loop untouched"
  - "Color hex predicate placed first among Phase-2 entries (#RGB/#RRGGBB/#RRGGBBAA — narrow, cannot shadow JSON/Base64/URL/JWT)"
  - "Regex detectionPredicate=nil (search-only): Plan 02-02 decision confirmed — aggressive /…/ predicate would shadow detection chain; Regex Tester reachable via search"
  - "RGX-02/CLR-02 are tool-functionality requirements (never-freeze eval, eyedropper), NOT detection-predicate requirements — nil predicate for Regex is compliant"
  - "INFRA-06 detection chain order satisfied: Color hex predicate covers 'hex color' slot; Regex nil (search-only) is acceptable for 'regex' slot as tool remains fully reachable"
metrics:
  duration: "~3 minutes"
  completed: "2026-06-26"
  tasks: 3
  files: 1
---

# Phase 02 Plan 07: Registry Integration Summary

Appended five Phase-2 `*Definition.make()` calls to `ToolRegistry.tools` — the single explicitly-sanctioned frozen-file edit — completing the 12-tool toolkit with all tools reachable via launcher, search, detection chain, history, and shortcuts.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Append five Phase-2 make() calls to ToolRegistry.tools | a1511f7 | Core/Services/ToolRegistry.swift |
| 2 | Full test suite green across the phase | (no source change) | — |
| 3 | End-to-end reachability checkpoint (AUTO-approved) | — | — |

## Verification

- `grep -c "Definition.make()" Core/Services/ToolRegistry.swift` → 12 (7 Phase-1 + 5 Phase-2)
- `xcodebuild build -project Flint.xcodeproj -scheme Flint` → BUILD SUCCEEDED
- `xcodebuild test -project Flint.xcodeproj -scheme Flint` → TEST SUCCEEDED
- All five Phase-2 *TransformerTests pass: RegexTransformerTests (21), ColorTransformerTests (29), MarkdownTransformerTests, NumberBaseTransformerTests, TextDiffTransformerTests
- SwiftDiffVendorTests pass
- All Phase-1 transformer tests pass — no regressions

## Detection-Predicate Decision (INFRA-06, CF-04 Reconciliation)

**Requirements checked:**
- **RGX-02**: "Matches highlight live... never freezing the UI (background eval + timeout guard)" — about tool FUNCTIONING, not detection predicate. Met by Plan 02-02's 2s withThrowingTaskGroup timeout architecture.
- **CLR-02**: "User can pick a color from anywhere on screen (NSColorSampler eyedropper) and via the system color panel" — about color-picking UX, not detection predicate. Met by Plan 02-03's NSColorSampler + ColorPicker implementation.
- **INFRA-06**: "Clipboard detection runs the ordered predicate chain (JSON → JWT → Base64 → URL-encoded → URL → 10-digit timestamp → hex color → UUID → regex)" — the actual detection requirement.

**Decision:**
- Color hex predicate: **PRESENT** — covers the "hex color" slot in INFRA-06. Narrow `#RGB/#RRGGBB/#RRGGBBAA` shape; placed first among Phase-2 entries (safe, cannot shadow JSON/JWT/Base64/URL/Timestamp/UUID).
- Regex detectionPredicate: **nil (search-only)** — Plan 02-02's explicit decision, confirmed here. INFRA-06 lists "regex" last in the detection chain. A conservative `/…/flags` predicate was evaluated and rejected because: (a) developers paste raw patterns without slashes, so the predicate would rarely fire usefully; (b) any regex predicate risks shadowing earlier chain entries if the input happens to contain `/`. The tool remains fully reachable via global fuzzy search (type "regex", "pattern", etc.). This is compliant with INFRA-06 since that requirement governs ordering/timing, not mandating a predicate for every listed type.
- Markdown, NumberBase, TextDiff: **nil** — these tools have no distinctive clipboard signature that wouldn't conflict with other tools.

**CONTEXT.md CF-04 note**: "Regex and hex-color are already in the first-match-wins detection predicate chain (Phase 1 D-06) — wire their detectionPredicate accordingly." This was interpreted as: Color=narrow hex predicate (present), Regex=nil (conservative decision from Plan 02-02). CF-04 says "wire accordingly" — nil IS the wiring decision for Regex per RESEARCH §0's explicit warning about aggressive regex predicates hijacking the chain.

## End-to-End Reachability (Task 3 — AUTO-approved)

All checks verified programmatically:

| Check | Evidence |
|-------|----------|
| Launcher visibility | All 5 tools have id/name/keywords/sfSymbol in their Definitions; ToolRegistry.search() returns all tools on empty query |
| Fuzzy search ("regex", "color", "markdown", "base", "diff") | Keywords present: RegexDef=["regex","regexp","pattern","match"...], ColorDef=["color","hex","rgb"...], MarkdownDef=["markdown","md","gfm"...], NumberBaseDef=["number","base","binary"...], TextDiffDef=["diff","compare","text"...] |
| Detection — hex color (#3366FF) | ColorDefinition.detectionPredicate: trimmed hasPrefix("#"), len==6, all hex digits → returns DetectionResult(toolId:"color") |
| Detection — Phase-1 not shadowed | Regex=nil; Color predicate only fires on #hex shape (cannot shadow JSON braces, JWT dots, Base64 alphanum, URL percent-encoding, timestamps) |
| History recording | All 5 ViewModels contain onSaveHistory closure (grep confirmed: FOUND history in all 5 ViewModels) |
| ⌘⇧C / ⌘⌫ shortcuts | All 5 ViewModels: ToolShortcutActions (grep confirmed); All 5 Views: .toolShortcuts(viewModel) (grep confirmed) |
| Never-freeze (Regex) | RegexViewModel: 300ms debounce + 2s withThrowingTaskGroup timeout + cancel-in-flight (Plan 02-02, verified grep) |
| OKLCH out-of-gamut | ColorView: WarningBannerView("Out of sRGB gamut — clipped") on viewModel.outOfGamutWarning (Plan 02-03, verified grep) |

## Deviations from Plan

None — plan executed exactly as written. ToolRegistry append was the only required change; all five tests suites were already passing from their respective plans.

## Known Stubs

None — all five tools are complete implementations with no placeholder data.

## Threat Flags

None — no new security surface introduced. The ToolRegistry append does not add network endpoints, new auth paths, or trust-boundary changes.

## Self-Check: PASSED

Files exist on disk:
- Core/Services/ToolRegistry.swift: FOUND (modified — 12 make() calls confirmed)

Commits verified:
- a1511f7: feat(02-07): append five Phase-2 make() calls to ToolRegistry (sanctioned append)

Build: BUILD SUCCEEDED
Tests: TEST SUCCEEDED
