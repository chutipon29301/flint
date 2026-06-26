---
phase: 03-polish-distribution
verified: 2026-06-27T00:30:00Z
status: human_needed
score: 4/4 success-criteria source-verified (live execution + manual UX deferred by design)
overrides_applied: 0
re_verification:
  previous_status: none
  previous_score: n/a
human_verification:
  - test: "Services menu routing (DIST-01)"
    expected: "Select text in TextEdit/Safari → right-click → Services → 'Open in Flint' appears; JSON/JWT/Base64 selections open their matched tool pre-filled (D-02); non-matching text opens the launcher with text staged in search (D-03); window appears in front of the source app (activation dance)"
    why_human: "Requires running the app and invoking the real macOS Services menu from another app — not observable via grep"
  - test: "Drag-and-drop end-to-end (DIST-02)"
    expected: "Drop .json/.txt onto text tools → overlay shows during drag, content loads on drop; drop image/.zip onto a text tool → post-drop WarningBannerView rejection, no crash; drop large binary onto Hash/Base64 → off-main hashing/encoding, UI stays responsive; launcher drop routes via detect() or stages in search; overlay fades smoothly"
    why_human: "Real drag gestures, UI responsiveness on large files, and visual overlay behavior cannot be verified statically"
  - test: "First-run onboarding (DIST-03)"
    expected: "Reset hasSeenOnboarding → launch → 'Welcome to Flint' window (480×360, non-resizable) appears above frontmost app; 'Enable Launch at Login' enables SMAppService login item and dismisses; relaunch does not show onboarding again; 'Skip' path also persists"
    why_human: "First-run window appearance, login-item registration, and once-only persistence require running the app and checking System Settings"
  - test: "Signed/notarized DMG + Gatekeeper (DIST-03) — credential-gated"
    expected: "bash scripts/release.sh 0.0.1 archives, exports Developer ID, notarytool returns Accepted, staples app+DMG, spctl reports 'Notarized Developer ID', DMG mounts and installs without Gatekeeper warning"
    why_human: "Requires Apple Developer enrollment, Developer ID cert, and notarytool profile — credentials the user has explicitly deferred. Scripts are written and structurally verified; live run pending credentials"
  - test: "Sparkle v0.0.1→v0.0.2 update dry-run (DIST-04) — credential-gated"
    expected: "Generate real EdDSA key via generate_keys, replace SUPublicEDKey placeholder, run scripts/dry-run-update.sh → v0.0.1 sees the local appcast, Sparkle update sheet for v0.0.2 appears, installs, app relaunches at 0.0.2 with no EdDSA signature error"
    why_human: "Requires one-time EdDSA key generation (writes private key to login Keychain) and the credential-gated release pipeline — explicitly deferred. Wiring + scripts verified; live run pending credentials"
  - test: "Full-app VoiceOver audit (INFRA-15, BLOCKING)"
    expected: "VoiceOver announces a meaningful label for every interactive element across the launcher, all 12 tools, and the 3 Phase 3 surfaces (Services-routed open, drag overlay, onboarding window); logical focus order; no focus traps"
    why_human: "VoiceOver announcement quality and focus order require a live screen-reader session; source pre-check (labels present, semantic colors) is complete"
---

# Phase 3: Polish & Distribution Verification Report

**Phase Goal (User Story / mvp mode):** Flint is in users' hands — it passes Gatekeeper, auto-updates via Sparkle, accepts dragged files and selected text routed from the system Services menu, and every tool is accessible via VoiceOver.
**Verified:** 2026-06-27T00:30:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

All four phase success criteria (DIST-01..04) are implemented as real, substantive, wired source. Every file claimed in the six SUMMARYs exists on disk, contains the described implementation (not stubs), and is registered in the Xcode project so it compiles into the app target. The two deferred categories — batched manual UX verification and credential-gated live distribution — are expected by design and are the only reason status is `human_needed` rather than `passed`.

### Observable Truths (ROADMAP Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Services menu routes selected text to the best-matching tool pre-filled | ✓ VERIFIED (source) | `Info.plist` NSServices entry (NSMessage=openInFlint, NSSendTypes=public.plain-text); `FlintServiceProvider.openInFlint` off-main handler with 1MB DoS cap → posts `.serviceDidReceiveText`; `AppDelegate` registers provider + `NSUpdateDynamicServices()`; `FlintApp` receives on @MainActor → `toolRegistry.detect()` → `toolSeed.set` → `openToolViaService` (D-02) / `openLauncherWithStagedText` (D-03); `MenuBarPopoverView` consumes `.routeServiceMatch`/`.routeServiceNoMatch`. Selector parity confirmed: NSMessage `openInFlint` == `@objc func openInFlint`. Live invocation = human-verify item 1 |
| 2 | All tools accept dragged text files; Base64/Hash accept any binary file, off-main | ✓ VERIFIED (source) | Shared `View.fileDrop` (off-main URL resolve, 5MB text guard, UTF-8 decode, post-drop binary rejection, @MainActor callbacks) + stateless `DropOverlayView`; Base64View/HashView use permissive any-file `.onDrop` → existing off-main chunked pipeline (`loadFile`/`startFileHash`, uncapped); all 9 text-tool views carry `.fileDrop` + `DropOverlayView` (1 each, confirmed); launcher drop routes via `detect()`. Real gesture/large-file behavior = human-verify item 2 |
| 3 | Signed/notarized DMG passes Gatekeeper; first-run onboarding greets new users | ✓ VERIFIED (source) | Onboarding: `hasSeenOnboarding` UserDefaults bool (default false), `OnboardingWindowView` (480×360, menubar callout + ⌘⇧Space teach + conditional Launch-at-Login CTA reusing SMAppService, single `finish()` sets flag), `WindowCoordinator.openOnboarding()` activation dance, `WindowGroup(id:"onboarding")` + `.onReceive(.openOnboarding)→openWindow`, first-run gate in popover `.onAppear`. DMG: `scripts/release.sh` (Archive→Developer ID export→notarytool→staple→create-dmg→notarize+staple DMG, `bash -n` clean, placeholder guard present), `exportOptions.plist` (method=developer-id), `Flint-release.entitlements` (no get-task-allow). Live signing = human-verify item 4; onboarding UX = item 3 |
| 4 | Auto-updates via Sparkle (EdDSA-signed); v0.0.1→v0.0.2 validated; EdDSA key in Info.plist from first release | ✓ VERIFIED (source) | Sparkle 2.9.3 pinned in `Package.resolved` (rev d46d456); `SparkleUpdaterService` (@Observable @MainActor, lazy idempotent `start()` constructing SPUStandardUpdaterController, off cold-start path via popover `.onAppear`); `SUPublicEDKey`+`SUFeedURL` present in Info.plist from first build (clearly-marked placeholders per known deferral); `scripts/dry-run-update.sh` (generate_appcast + http.server + SULastCheckTime reset + CFBundleVersion 1→2, `bash -n` clean). Live dry-run = human-verify item 5 |

**Score:** 4/4 success criteria source-verified; live execution + manual UX intentionally deferred.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Info.plist` | NSServices + Sparkle keys, manual plist | ✓ VERIFIED | plutil OK; NSServices openInFlint entry; SUPublicEDKey/SUFeedURL present (intentional placeholders); GENERATE_INFOPLIST_FILE=NO for app target only |
| `Core/Services/FlintServiceProvider.swift` | Off-main Services handler | ✓ VERIFIED | 1MB cap, posts notification, no direct window/seed call; 4 pbxproj refs |
| `App/AppDelegate.swift` | Register provider + refresh cache | ✓ VERIFIED | servicesProvider + NSUpdateDynamicServices; 4 pbxproj refs |
| `Core/Services/FileDropHandler.swift` | Shared text drop helper | ✓ VERIFIED | off-main, 5MB guard, UTF-8 decode, post-drop rejection; 4 pbxproj refs |
| `UI/Components/DropOverlayView.swift` | Stateless overlay | ✓ VERIFIED | single-state, a11y label, semantic colors; 4 pbxproj refs |
| `Core/Services/SparkleUpdaterService.swift` | Lazy Sparkle wrapper | ✓ VERIFIED | @Observable @MainActor, guarded start(); 4 pbxproj refs |
| `UI/OnboardingWindowView.swift` | First-run welcome | ✓ VERIFIED | 480×360, conditional CTA, finish() flag funnel, full a11y; 4 pbxproj refs |
| `scripts/release.sh` | Notarized DMG pipeline | ✓ VERIFIED | bash -n clean, all 9 steps, placeholder guard, no codesign --deep / altool |
| `scripts/dry-run-update.sh` | Sparkle dry-run | ✓ VERIFIED | bash -n clean, generate_appcast + http.server + version bump |
| `scripts/exportOptions.plist` | Developer ID export config | ✓ VERIFIED | method=developer-id; teamID placeholder (documented) |
| `DISTRIBUTION.md` | Release checklist | ✓ VERIFIED | prerequisites, EdDSA key procedure, NEVER anti-patterns, version convention |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| Info.plist NSMessage | FlintServiceProvider | @objc selector name parity | ✓ WIRED | `openInFlint` matches both sides |
| FlintServiceProvider | FlintApp | NotificationCenter `.serviceDidReceiveText` | ✓ WIRED | posted off-main, received @MainActor |
| FlintApp | ToolRegistry/ToolSeed/WindowCoordinator | detect→set→open + route notifications | ✓ WIRED | match→openToolViaService+routeServiceMatch; no-match→openLauncherWithStagedText+routeServiceNoMatch |
| Text tool views | FileDropHandler | `.fileDrop(...)` | ✓ WIRED | all 9 views carry it |
| Base64/Hash views | ViewModel off-main pipeline | any-file `.onDrop`→loadFile/startFileHash | ✓ WIRED | uncapped, off-main |
| FlintApp | SparkleUpdaterService | `.environment(sparkle)` + `sparkle.start()` in popover .onAppear | ✓ WIRED | off cold-start path; no controller in FlintApp.init |
| Popover .onAppear | OnboardingWindowView | `!hasSeenOnboarding`→openOnboarding→WindowGroup(id:onboarding) | ✓ WIRED | once-only via finish() flag |
| release.sh | Info.plist SUPublicEDKey | PlistBuddy placeholder guard | ✓ WIRED | aborts if still placeholder |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| DIST-01 | 03-01 | Services menu routes selection to best tool pre-filled | ✓ SATISFIED (source) | Full Services chain wired end-to-end |
| DIST-02 | 03-02a/03-02b | All tools accept text drop; binary tools accept any file | ✓ SATISFIED (source) | 11 tools + launcher wired; off-main binary pipeline |
| DIST-03 | 03-04 / 03-05 | Signed notarized DMG + first-run onboarding | ✓ SATISFIED (source) | Onboarding wired; release.sh structurally complete (live run deferred) |
| DIST-04 | 03-03 / 03-05 | Sparkle EdDSA auto-update | ✓ SATISFIED (source) | Sparkle pinned + wired lazily; key present from first build; dry-run script ready |
| INFRA-15 | 03-04 | VoiceOver labels on all interactive elements | ✓ SATISFIED (source pre-check) | Phase 3 surfaces + 12 tools labeled; semantic colors; live VoiceOver audit = human item 6 |

No orphaned requirements — REQUIREMENTS.md maps DIST-01..04 to Phase 3 and all are claimed by plans.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Info.plist valid | `plutil -lint Info.plist` | OK | ✓ PASS |
| NSServices entry present | PlistBuddy Print :NSServices | openInFlint dict present | ✓ PASS |
| Sparkle keys present | PlistBuddy Print SUPublicEDKey/SUFeedURL | both present (placeholders) | ✓ PASS |
| release.sh syntax | `bash -n scripts/release.sh` | clean | ✓ PASS |
| dry-run-update.sh syntax | `bash -n scripts/dry-run-update.sh` | clean | ✓ PASS |
| codesign --deep absent | grep release.sh | absent | ✓ PASS |
| altool absent | grep release.sh | absent | ✓ PASS |
| Sparkle pinned 2.9.3 | grep Package.resolved | version 2.9.3 | ✓ PASS |
| New files registered | grep pbxproj (6 files) | 4 refs each | ✓ PASS |
| Full Xcode build | `xcodebuild -scheme Flint` | NOT RUN (pre-existing FlintTests/XCTest CLI failure, out of scope) | ? SKIP |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| Info.plist | SUPublicEDKey | Clearly-marked placeholder string | ℹ️ Info | Intentional, documented deferral (no Apple credentials yet); release.sh guards against shipping it |
| Info.plist | SUFeedURL | `http://localhost:8000/appcast.xml` placeholder | ℹ️ Info | Intentional local dry-run URL; DISTRIBUTION.md mandates HTTPS swap before v1.0 |
| scripts/exportOptions.plist | teamID | `REPLACE_WITH_YOUR_TEAM_ID` | ℹ️ Info | Intentional, documented; requires developer's Apple Team ID |

No debt markers (TBD/FIXME/XXX) in any phase-modified file. No unexpected stubs (`return null`/empty data/TODO) in the new source files. The three placeholders are the documented, credential-gated deferrals — not gaps.

### Human Verification Required

See frontmatter `human_verification` list. Six items, all expected:
1. Services menu routing (live invocation from another app)
2. Drag-and-drop end-to-end (gestures, large-file responsiveness, overlay)
3. First-run onboarding (window appearance + login-item + once-only persistence)
4. Signed/notarized DMG + Gatekeeper (credential-gated — needs Apple Developer enrollment)
5. Sparkle v0.0.1→v0.0.2 dry-run (credential-gated — needs EdDSA key generation)
6. Full-app VoiceOver audit (INFRA-15 blocking — live screen-reader session)

Items 1–3 and 6 are the batched manual-UX pass deferred via "code now, verify at the end". Items 4–5 are blocked on Apple Developer credentials the user has not yet obtained. All are deferred-by-design, not implementation gaps.

### Gaps Summary

No genuine implementation gaps found. Every code-level deliverable for DIST-01..04 (plus INFRA-15 source coverage) exists, is substantive, and is wired into the app target. The phase goal is achieved at the source level. The remaining work is exclusively (a) hands-on manual UX verification deliberately batched to this verification pass, and (b) live execution of the distribution pipeline, which is blocked on Apple Developer credentials the user has explicitly deferred. The Sparkle key/feed-URL/teamID placeholders are intentional, clearly marked, guarded, and documented — replacing them is the first step of the deferred credential-gated pass, not a defect.

One out-of-scope, pre-existing issue noted: headless `xcodebuild -scheme Flint` fails only on `FlintTests/PinnedToolReorderTests.swift` (`import XCTest` CLI module-search-path error) committed before Phase 03 (5a4632c). It does not affect any Phase 3 app-target source and is logged in `deferred-items.md`.

---

_Verified: 2026-06-27T00:30:00Z_
_Verifier: Claude (gsd-verifier)_
