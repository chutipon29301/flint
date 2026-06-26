---
phase: 03-polish-distribution
plan: 05
subsystem: distribution
tags: [release, notarization, gatekeeper, sparkle, appcast, eddsa, dmg, developer-id, credential-gated]

# Dependency graph
requires:
  - phase: 03-polish-distribution
    provides: "Sparkle 2.9.3 SPM wiring + SUPublicEDKey/SUFeedURL placeholders in Info.plist (03-03); Flint-release.entitlements (Hardened Runtime, no get-task-allow); onboarding wired (03-01, 03-04)"
provides:
  - "scripts/release.sh — repeatable Archive -> Developer ID export -> notarytool submit --wait -> stapler staple -> create-dmg -> notarize+staple DMG pipeline (no codesign deep re-sign, no altool)"
  - "scripts/exportOptions.plist — method=developer-id export config (teamID placeholder to fill in)"
  - "scripts/dry-run-update.sh — local v0.0.1 -> v0.0.2 Sparkle update dry-run (generate_appcast + local http.server host + SULastCheckTime reset)"
  - "DISTRIBUTION.md — release checklist: prerequisites, EdDSA key generate+backup, integer CFBundleVersion convention, SUFeedURL production-URL swap, NEVER anti-patterns"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Release pipeline as a guarded bash script (set -euo pipefail) that fails non-zero on any verification miss (spctl / stapler validate)"
    - "Signing exclusively via xcodebuild -exportArchive (method=developer-id) so Xcode re-signs Sparkle XPC services inside-out — never a manual recursive codesign deep re-sign"
    - "Notarization via xcrun notarytool submit --wait + stapler staple, applied to both the .app and the .dmg (altool is dead since Nov 2023)"
    - "Sparkle update validation via generate_appcast over an updates/ folder, served by python3 -m http.server to match the local SUFeedURL placeholder, with SULastCheckTime reset to force a check"
    - "release.sh self-guards: refuses to run while SUPublicEDKey is still the 03-03 placeholder"

key-files:
  created:
    - "scripts/release.sh"
    - "scripts/exportOptions.plist"
    - "scripts/dry-run-update.sh"
    - "DISTRIBUTION.md"
  modified: []

key-decisions:
  - "Wrote all three deliverable artifacts in full (runnable when credentials exist) but did NOT execute any signing/notarization/DMG/dry-run step — the user has deferred Apple Developer enrollment, Developer ID cert, notarytool profile, and EdDSA key generation. All execution steps are recorded under Deferred Manual Verification."
  - "Reworded in-script comments to avoid the literal string 'codesign --deep' so the plan's grep anti-pattern gate (! grep -q 'codesign --deep') passes while still loudly warning against recursive deep re-signing."
  - "Added a hard guard in release.sh that aborts if Info.plist SUPublicEDKey is still the placeholder, preventing an accidental keyless release (Sparkle cannot add the key later without locking users out)."
  - "release.sh notarizes BOTH the app and the DMG and staples both, matching RESEARCH Pattern 5 step 9 (recommended)."
  - "dry-run-update.sh locates generate_appcast under DerivedData (SPM artifacts path) at runtime rather than hardcoding a version-specific path."

requirements-completed: [DIST-03, DIST-04]

# Metrics
duration: 3 min
completed: 2026-06-26
---

# Phase 3 Plan 05: Distribution — Notarization & Appcast Dry-Run Summary

**Wrote the credential-gated distribution capstone as runnable artifacts — `release.sh` (Archive → Developer ID export → notarytool → staple → create-dmg → notarize+staple DMG), `exportOptions.plist`, `dry-run-update.sh` (local v0.0.1→v0.0.2 Sparkle dry-run via `generate_appcast` + local HTTP host + `SULastCheckTime` reset), and a full `DISTRIBUTION.md` checklist — without running any signing/notarization step, since Apple Developer credentials and the EdDSA key are deferred (all execution recorded for a single manual pass).**

## Performance

- **Duration:** 3 min
- **Started:** 2026-06-26T17:05:42Z
- **Completed:** 2026-06-26T17:09:12Z
- **Tasks:** 2 auto completed (Task 2, Task 3) + 2 credential-gated checkpoints (Task 1 human-action, Task 4 human-verify) recorded as deferred (NOT paused on, per code-only mode)
- **Files created:** 4 (`scripts/release.sh`, `scripts/exportOptions.plist`, `scripts/dry-run-update.sh`, `DISTRIBUTION.md`)

## Accomplishments

- **`scripts/release.sh`** — `set -euo pipefail` bash pipeline parameterized by version (`$1`), implementing RESEARCH Pattern 5 exactly:
  1. `xcodebuild -scheme Flint -configuration Release -archivePath build/Flint.xcarchive archive`
  2. `xcodebuild -exportArchive ... -exportOptionsPlist scripts/exportOptions.plist -exportPath build/export` (Developer ID — re-signs Sparkle XPC services in the correct inside-out order; **no** recursive deep re-sign anywhere)
  3. `ditto -c -k --keepParent build/export/Flint.app build/Flint.zip`
  4. `xcrun notarytool submit build/Flint.zip --keychain-profile NOTARYTOOL_PROFILE --wait`
  5. `xcrun stapler staple` + `stapler validate` on the app
  6. `spctl -a -t exec -vvv` Gatekeeper assessment
  7. `create-dmg build/export/Flint.app dist/`
  8. `xcrun notarytool submit "dist/Flint $1.dmg" --keychain-profile NOTARYTOOL_PROFILE --wait`
  9. `xcrun stapler staple` + `stapler validate` on the DMG.
  Every step `die`s with a clear message and non-zero exit on failure. A pre-flight guard aborts if `SUPublicEDKey` is still the 03-03 placeholder, and it checks for `xcodebuild`/`create-dmg` presence.
- **`scripts/exportOptions.plist`** — `method=developer-id`, `signingStyle=automatic`, `destination=export`, with a clearly-flagged `teamID` placeholder (`REPLACE_WITH_YOUR_TEAM_ID`) the developer must fill in.
- **`scripts/dry-run-update.sh`** — `set -euo pipefail` orchestration of the RESEARCH v0.0.1→v0.0.2 dry-run: builds v0.0.1 (`CFBundleVersion=1`) and v0.0.2 (`CFBundleVersion=2`) via `release.sh`, stages both DMGs into `updates/`, runs `generate_appcast updates/` (located dynamically under DerivedData; signs from the login Keychain), serves the folder with `python3 -m http.server 8000` to match the `http://localhost:8000/appcast.xml` placeholder SUFeedURL, resets `SULastCheckTime` (`defaults delete com.flint.app SULastCheckTime`) to force an immediate check, and prints the manual steps (install, launch, confirm the update sheet + relaunch at 0.0.2). Documents the HTTPS fallback (ngrok / staging) for Open Question #3.
- **`DISTRIBUTION.md`** — release checklist covering prerequisites (Developer ID cert, notarytool profile, create-dmg, Node 22, teamID), Sparkle EdDSA key generate-once + off-machine backup, integer `CFBundleVersion` (1→2→3) ↔ `sparkle:version` convention, the release procedure, appcast generation, the `SUFeedURL` production-HTTPS swap, the dry-run, and a final pre-release checklist. Explicit "NEVER" anti-pattern lines: no recursive deep re-sign, no altool, never lose the private key, `SUPublicEDKey` must ship from the first release, never commit the private key.

## Task Commits

1. **Task 2: release.sh + exportOptions.plist + DISTRIBUTION.md** — `78d511e` (feat)
2. **Task 3: dry-run-update.sh + mark scripts executable** — `ac6af15` (feat)

_Task 1 (checkpoint:human-action) and Task 4 (checkpoint:human-verify) write no code — recorded under Deferred Manual Verification below; not paused on, per code-only mode._

## Verification

All source-level acceptance criteria pass:

- **Task 2:** `bash -n scripts/release.sh` clean; contains `notarytool submit`, `stapler staple`, `exportArchive`; contains NO `codesign --deep` and NO `altool`; `DISTRIBUTION.md` exists and contains `SUPublicEDKey`; `exportOptions.plist` `method=developer-id`. → **PASS** (`TASK2-VERIFY: PASS`).
- **Task 3:** `bash -n scripts/dry-run-update.sh` clean; contains `generate_appcast`, `SULastCheckTime`, `http.server`; builds `CFBundleVersion=1` + `CFBundleVersion=2`; documents HTTPS fallback. → **PASS** (`TASK3-VERIFY: PASS`).

The runtime pipeline (actual archive/notarize/DMG/dry-run) was intentionally NOT executed — see below.

## Deviations from Plan

**1. [Code-only mode] Tasks 1 and 4 not paused on; recorded as deferred.**
- **Found during:** Tasks 1, 4 (both credential-gated checkpoints).
- **Issue:** The user has no Apple Developer enrollment, Developer ID cert, notarytool profile, or generated EdDSA key, and explicitly deferred all live signing/notarization/DMG/Sparkle-dry-run actions.
- **Fix:** Wrote the deliverable artifacts in full (runnable when credentials exist); did not run `xcodebuild archive/export`, `codesign`, `notarytool`, `stapler`, `create-dmg`, `spctl`, `generate_keys`, `generate_appcast`, or the dry-run server. Recorded exact run-instructions + expected-pass criteria under Deferred Manual Verification.
- **Files modified:** none beyond the four created artifacts.
- **Verification:** source-level acceptance criteria (Tasks 2, 3) all pass.

**2. [Rule 3 - Blocker] Reworded comments to satisfy the grep anti-pattern gate.**
- **Found during:** Task 2 verification.
- **Issue:** Warning comments literally containing `codesign --deep` tripped the plan's `! grep -q "codesign --deep"` gate.
- **Fix:** Reworded comments to "recursive deep re-sign" / "codesign deep flag" so the gate passes while the warning remains loud and clear. The legitimate verify command `codesign --verify --deep --strict` (integrity check, not re-signing) does not match the `codesign --deep` substring.
- **Files modified:** `scripts/release.sh`.
- **Verification:** `! grep -q "codesign --deep" scripts/release.sh` now returns clean; `TASK2-VERIFY: PASS`.

**3. [Rule 2 - Missing critical guard] release.sh aborts on placeholder SUPublicEDKey.**
- **Found during:** Task 2.
- **Issue:** Without a guard, `release.sh` could ship a build whose `SUPublicEDKey` is still the 03-03 placeholder — an unrecoverable field failure (Sparkle won't let you add the key later).
- **Fix:** Added a PlistBuddy pre-flight check that `die`s if `SUPublicEDKey` still contains "PLACEHOLDER".
- **Files modified:** `scripts/release.sh`.
- **Verification:** guard present; script still parses clean.

**Total deviations:** 3 (1 mode-driven deferral, 1 Rule 3 blocker, 1 Rule 2 guard). **Impact:** No functional drift from the plan; the artifacts implement Pattern 5 + the dry-run exactly, with one safety guard added and the live execution recorded for a manual pass.

## Authentication Gates

None hit during execution. The credentialed steps (Apple Developer login for notarization, Keychain access for `generate_appcast`) are part of the deferred manual pass, not attempted here.

## Known Stubs

| Stub | File | Reason |
|------|------|--------|
| `teamID` = `REPLACE_WITH_YOUR_TEAM_ID` | `scripts/exportOptions.plist` | Developer's real Apple Team ID; required before `-exportArchive` can sign. Documented in DISTRIBUTION.md prerequisites. |
| `SUPublicEDKey` placeholder (from 03-03) | `Info.plist` | Real EdDSA public key requires `generate_keys` (writes private key to login Keychain). `release.sh` refuses to run until replaced. Owned by the deferred manual pass below. |
| `SUFeedURL` = `http://localhost:8000/appcast.xml` (from 03-03) | `Info.plist` | Local dry-run URL. Swap to production HTTPS before v1.0 (documented in DISTRIBUTION.md + dry-run-update.sh). |

These are intentional and resolved by the Deferred Manual Verification pass — they cannot be satisfied without Apple Developer credentials and the one-time key generation.

## Deferred Manual Verification (credential-gated)

These are the live pipeline runs that this plan deliberately did NOT execute. Perform them once the prerequisites are in place. All scripts and the checklist are ready.

### Prerequisites to complete FIRST (Task 1 — checkpoint:human-action)

1. **Apple Developer Program** enrolled; **Developer ID Application** cert installed in the login Keychain.
   Verify: `security find-identity -v -p codesigning` lists a "Developer ID Application: … (TEAMID)" identity.
2. **notarytool profile** stored once:
   `xcrun notarytool store-credentials "NOTARYTOOL_PROFILE" --apple-id <id> --team-id <TEAMID> --password <app-specific-password>`
   (create the app-specific password at appleid.apple.com).
3. **create-dmg** installed: `brew install create-dmg` (or `npm install -g create-dmg`; Node 22 present). Verify `create-dmg --version`.
4. **EdDSA key generated + backed up:** run Sparkle 2.9.3's `bin/generate_keys` once (under `~/Library/Developer/Xcode/DerivedData/Flint-*/SourcePackages/artifacts/sparkle/Sparkle/bin/`). Copy the printed base64 public key into `Info.plist :SUPublicEDKey` (replacing the placeholder); confirm the private key is in the login Keychain and **backed up off-machine** (1Password / CI secret). Never commit it.
5. **Fill `teamID`** in `scripts/exportOptions.plist` (replace `REPLACE_WITH_YOUR_TEAM_ID`).

**Resume signal (original Task 1):** "ready" once the Developer ID cert, notarytool profile, create-dmg, and EdDSA key backup are all in place.

### Execute the signed DMG + update dry-run (Task 4 — checkpoint:human-verify, BLOCKING)

1. **Release run:** `bash scripts/release.sh 0.0.1`.
   **EXPECTED:** archives; exports with Developer ID; notarytool returns "Accepted"; stapler succeeds; `create-dmg` produces `dist/Flint 0.0.1.dmg`; DMG notarized + stapled. Script exits 0.
2. **Gatekeeper:** mount `dist/Flint 0.0.1.dmg`, drag Flint to Applications, launch.
   **EXPECTED:** opens with NO Gatekeeper warning. `spctl -a -t exec -vvv /Applications/Flint.app` → "accepted, source=Notarized Developer ID". `xcrun stapler validate /Applications/Flint.app` → "validate worked".
3. **Sparkle XPC integrity:** `codesign --verify --deep --strict --verbose=2 /Applications/Flint.app` → valid (confirms XPC services were NOT corrupted).
4. **Update dry-run:** `bash scripts/dry-run-update.sh`. Follow its prompts (set `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` per step: 0.0.1/1 then 0.0.2/2).
   **EXPECTED:** with v0.0.1 installed and the local appcast served, after the `SULastCheckTime` reset, launching v0.0.1 shows Sparkle's update sheet for v0.0.2, installs it, and the app relaunches reporting 0.0.2. If Sparkle rejects plain HTTP, use the documented ngrok/staging HTTPS fallback.
5. **Signature verification:** confirm Sparkle logs no EdDSA signature error (a mismatched key would be rejected).

**Resume signal (original Task 4):** "approved" once the DMG installs without a Gatekeeper warning AND the v0.0.1→v0.0.2 update completes; otherwise describe the failure.

### Before the real v1.0

- Replace `Info.plist :SUFeedURL` with the production **HTTPS** appcast URL (`/usr/libexec/PlistBuddy -c "Set :SUFeedURL https://your-host/appcast.xml" Info.plist`).
- Publish `appcast.xml`, the DMG(s), and `.delta` files to that HTTPS host.

## Issues Encountered

- **Pre-existing, out-of-scope:** headless `xcodebuild` full build fails on `FlintTests/PinnedToolReorderTests.swift` (`import XCTest` module-search-path error), predating phase 03 (logged in `deferred-items.md` by 03-01). Per orchestrator instruction this was NOT fixed and NOT used as a gate. It does not affect these artifacts — `release.sh` archives the app scheme (not the test target); the source-level acceptance criteria all pass.

## Next Phase Readiness

- **DIST-03** (signed/notarized DMG passing Gatekeeper) and **DIST-04** (validated EdDSA Sparkle update path) are implemented as runnable artifacts; their live execution is the single credential-gated manual pass recorded above.
- No code blockers introduced. The only outstanding work is credential-gated and human-only: Apple Developer enrollment, cert, notarytool profile, real EdDSA key generation+backup, teamID fill-in, then running `release.sh` + `dry-run-update.sh` and swapping `SUFeedURL` to production HTTPS before v1.0.

## Self-Check: PASSED

- Created files verified on disk: `scripts/release.sh`, `scripts/exportOptions.plist`, `scripts/dry-run-update.sh`, `DISTRIBUTION.md` (all present; both shell scripts executable).
- `bash -n` parses clean for both scripts; Task 2 and Task 3 acceptance grep gates return PASS.
- Task commits verified in git log: `78d511e`, `ac6af15`.
- No private key, app-specific password, or teamID secret written to the repo (only a clearly-marked placeholder).

---
*Phase: 03-polish-distribution*
*Completed: 2026-06-26*
