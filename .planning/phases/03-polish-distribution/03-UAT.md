---
status: diagnosed
phase: 03-polish-distribution
source: [03-01-SUMMARY.md, 03-02a-SUMMARY.md, 03-02b-SUMMARY.md, 03-03-SUMMARY.md, 03-04-SUMMARY.md, 03-05-SUMMARY.md]
started: 2026-06-26T17:42:36Z
updated: 2026-06-29T00:00:00Z
---

## Current Test

[testing complete]

## Automated Pre-Pass (2026-06-26)

Run before manual UAT, on the assumption "automate what's automatable first."

- `xcodebuild -scheme Flint -configuration Debug build` → **BUILD SUCCEEDED** (app target; the test-target XCTest failure noted in every SUMMARY is the *scheme* build only and does not affect the app target).
- Built `Flint.app` launched, stayed alive 4s, no crash report → cold start clean.
- Source gates: NSServices entry + NSMessage/`@objc func openInFlint` parity OK; all 9 text tools carry `fileDrop`+`DropOverlayView`; Base64/Hash any-file `onDrop` OK; onboarding pref+window+coordinator present; SparkleUpdaterService wraps `SPUStandardUpdaterController` with lazy init (the lone FlintApp hit is a comment); both distribution scripts `bash -n` clean.
- SUPublicEDKey still placeholder, SUFeedURL still `http://localhost:8000/appcast.xml` (expected — credential-gated, Test 11).

Tests 1 and 9 marked **pass** from this pass (build+launch+link verified). Tests 2–8 and 10 are GUI/system behaviors with no headless harness on native macOS — they need a human. Test 11 is credential-blocked.

## Tests

### 1. Cold Start Smoke Test
expected: Quit any running Flint. In Xcode, Product → Run a clean build of the Flint app scheme. App cold-starts — menubar wrench icon appears, popover opens to the launcher, no crash/hang. Time-to-popover feels instant (<500ms).
result: pass
note: Auto-verified — app target BUILD SUCCEEDED, built Flint.app launched and survived 4s with no crash report. Visual confirmation of menubar icon + <500ms feel still benefits from a human glance but the crash-on-cold-start risk is cleared.

### 2. First-Run Onboarding Window
expected: Reset state (`defaults delete com.flint.app lathe.hasSeenOnboarding`), then run. A "Welcome to Flint" window (480×360, not resizable) appears ABOVE the frontmost app, showing the menubar-icon callout + ⌘⇧Space hotkey instruction + a Launch-at-Login CTA. Clicking "Enable Launch at Login" enables it (Flint appears in System Settings → General → Login Items) and dismisses the window. Quit & relaunch — onboarding does NOT reappear. Reset flag, relaunch, click "Skip" — dismisses and stays gone.
result: pass

### 3. "Open in Flint" Services Routing — Match
expected: In TextEdit/Safari, select a JSON string like `{"a":1}`, right-click → Services → "Open in Flint" appears. Clicking it opens Flint IN FRONT of the source app, directly into the JSON Formatter, pre-filled with `{"a":1}` — no detection banner, no confirm step. Repeat with a JWT and a Base64 blob — each opens its matched tool pre-filled, in front.
result: superseded
note: "Open in Flint" did not appear in the Services submenu (would have been an issue). User decided to REMOVE the Services feature entirely rather than fix it. Removal routed through /gsd-quick. Tests 3 and 4 are void once removal lands; DIST-01 to be marked cut.

### 4. "Open in Flint" Services Routing — No Match
expected: Select a non-matching string like `just some words here` and invoke "Open in Flint". The launcher opens (in front) with the text staged in the search field — not an error or dead end.
result: superseded
note: Void — user is removing the Services feature (see Test 3). DIST-01 to be marked cut.

### 5. Drag Text File onto a Tool
expected: Open JSON Formatter, drag a `.json` text file over it — a "Drop to load" overlay appears during drag. On drop, the file contents populate the input and format. Repeat on ≥3 other text tools (e.g. JWT, Regex, Text Diff — TextDiff loads into its left "Original" input) — content loads, overlay appears each time.
result: pass
note: "Re-tested against the workspace window after gap-closure plan 03-07 (drag-drop routed to the resizable WindowGroup, which does not dismiss on resign-key). User verified: contents load with overlay across tools."

### 6. Drag Binary onto a Text Tool (graceful reject)
expected: Drag an image or `.zip` onto JSON Formatter. The drag-over overlay stays the normal valid style; AFTER the drop a warning banner appears ("non-text data… Try Base64 or Hash"). No crash.
result: pass
note: "Re-tested in the workspace window (plan 03-07). Post-drop warning banner appears with a dismiss button; no crash."

### 7. Drag Any File onto Binary Tools (Base64 / Hash)
expected: Open Hash, drag a large binary file — it hashes off-main with progress, the UI stays responsive, no size-cap regression. Open Base64, drag any file — it encodes off-main without blocking the UI.
result: pass
note: "Re-tested in the workspace window (plan 03-07). Off-main processing, UI responsive."

### 8. Launcher File Drop Routing
expected: Open the launcher (root popover). Drag a text file containing a JWT — detect() routes to the JWT Decoder pre-filled. Drag a text file with non-matching content — text staged in the search field. Drag a binary file — warning banner rejection appears post-drop.
result: pass
note: "Re-tested against the WORKSPACE window (plan 03-07) — the popover NSPanel cannot host Finder drags. Chrome drop → detect() selects + pre-fills the matched tool (pre-fill wired by plan 03-06). No-match shows a dismissible post-drop notice (D-03 analog: workspace has no search field to stage into — confirmed acceptable by user). Binary → post-drop warning banner. An always-visible 'Open in Window' button in the popover search bar provides the discoverable entry point."

### 9. Sparkle Auto-Update Readiness
expected: The app compiles with Sparkle linked and launches normally. On first launch NO Sparkle update sheet appears (Sparkle skips the first-launch check — correct). Cold start is unaffected by Sparkle (service starts in popover .onAppear, not at app init). NOTE: SUPublicEDKey is a known placeholder — full update flow is credential-gated (Test 11).
result: pass
note: Auto-verified — Sparkle 2.9.3 resolved and linked, app builds+launches with it. SparkleUpdaterService wraps SPUStandardUpdaterController; FlintApp constructs no controller at init (lazy via popover .onAppear) — confirmed the lone grep hit is a comment. "No update sheet on first launch" is Sparkle default behavior, not separately observable headlessly but follows from lazy wiring + first-launch skip.

### 10. Full-App VoiceOver Audit (INFRA-15)
expected: Enable VoiceOver (⌘F5). Tab the launcher (search field, pinned/tool rows, history) — each announces a meaningful label. Tab each of the 12 tools (JSON, Base64, URL, JWT, Timestamp, Hash, UUID, Regex, Color, Markdown, Number Base, Text Diff) — every Button/TextField/editor announces a meaningful label, logical focus order, no focus trap. Tab the onboarding window (headline → steps → CTA → Skip) and the drag overlay ("Drop to load…") — all announced.
result: skipped
reason: "Live VoiceOver audit (focus order, no focus trap, spoken announcements) requires a human at the machine — no headless harness on macOS. Source-level accessibility-label coverage was auto-audited instead: 47/48 surfaces GOOD. All 12 tools, launcher, onboarding, drag overlay, history panel, and preferences have explicit .accessibilityLabel on interactive controls; decorative SF Symbols are .accessibilityHidden(true). One PARTIAL: SearchView 'Show full history…' button relies on its implicit Text label (still announces, just not explicit). Labels are present; live focus-order/trap verification still owed by a human."

### 11. Signed/Notarized DMG + Update Dry-Run (credential-gated)
expected: With Apple Developer cert, notarytool profile, create-dmg, real EdDSA key, and teamID in place: `bash scripts/release.sh 0.0.1` produces a notarized+stapled `dist/Flint 0.0.1.dmg` that installs with NO Gatekeeper warning (`spctl` → "accepted, source=Notarized Developer ID"). `bash scripts/dry-run-update.sh` drives a v0.0.1→v0.0.2 Sparkle update that installs and relaunches at 0.0.2. NOTE: blocked if Apple Developer credentials are not yet set up.
result: blocked
blocked_by: third-party
reason: "Requires Apple Developer cert, notarytool keychain profile, real EdDSA signing key, and teamID — credentials not yet set up. SUPublicEDKey/SUFeedURL still placeholders per the automated pre-pass."

## Summary

total: 11
passed: 7
issues: 0
pending: 0
skipped: 1
blocked: 1
superseded: 2

## Gaps

- truth: "Dragging a text file onto a tool (or the launcher) loads its contents"
  status: resolved
  resolved_by: "plan 03-07 (gap closure) — drag-drop routed to the resizable workspace window; verified at human checkpoint. Tests 5, 6, 7, 8 all pass."
  reason: "User reported: it is impossible to drag the file in. the problem is when i open the menu the menu open but when i click on the file the menu disappear"
  severity: blocker
  test: 5
  also_blocks: [6, 7, 8]
  root_cause: "MenuBarExtra + .menuBarExtraStyle(.window) backs the popover with an NSPanel that SwiftUI auto-dismisses on resign-key (any outside click). Starting a Finder drag requires clicking a file in Finder first, which makes Finder key, resigns the panel, and SwiftUI tears down the popover — destroying the .onDrop target before the drag can land. The drop code (FileDropHandler) is correct and simply never runs. SwiftUI exposes no API to disable this dismissal (Apple FB11984872)."
  artifacts:
    - path: "App/FlintApp.swift"
      issue: "MenuBarExtra + .menuBarExtraStyle(.window) at lines 39-61 — the dismiss-on-resign-key behavior lives here; this is where the fix must go"
    - path: "App/WindowCoordinator.swift"
      issue: "Window/activation orchestration — would own a custom NSPanel under the fix"
    - path: "UI/MenuBarPopoverView.swift"
      issue: "Drop target (.fileDrop, lines 129-151) is correct but unreachable; unchanged by fix"
    - path: "Core/Services/FileDropHandler.swift"
      issue: ".onDrop logic (lines 28-72) is sound; unchanged by fix"
  missing:
    - "Window must survive resign-key so the drop target persists during a cross-app Finder drag"
    - "Option 1: replace MenuBarExtra(.window) with NSStatusItem + custom NSPanel (.nonactivatingPanel, hidesOnDeactivate=false), dismiss via global mouse-down monitor suspended while an NSDraggingSession is active"
    - "Option 2 (low-risk): route file drops to the existing WindowGroup workspace / MainWindowView (a normal window that does not dismiss on resign-key) instead of the menubar popover"
  debug_session: ".planning/debug/popover-dismiss-blocks-drag.md"
