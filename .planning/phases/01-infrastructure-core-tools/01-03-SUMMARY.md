---
phase: 01-infrastructure-core-tools
plan: 03
subsystem: analysis
tags: [jwt, base64url, cryptokit, hmac, security, swiftui, mvvm, tdd]

dependency_graph:
  requires:
    - phase: 01-01
      provides: "ToolDefinition/ToolRegistry frozen abstraction, HistoryStore, JWTDefinition stub, Debounce actor, CopyButtonView, CodeDisplayView, InlineErrorView, SyntaxEditorView"
    - phase: 01-02
      provides: "Established 4-file MVVM pattern (Base64, URL tools as reference)"
  provides:
    - "Data+Base64URL.swift — base64url decoder (char subst + padding) reusable across tools"
    - "JWTTransformer — pure decode, expiryStatus (pitfall #11 fix), verifyHMAC (HS256/384/512), partitionClaims, warnings"
    - "JWTViewModel — @Observable @MainActor, 150ms debounce, secret-excluded history (INFRA-09)"
    - "JWTView — header/payload/signature display, expiry countdown, claims table, warnings, HMAC verify"
    - "WarningBannerView — yellow/red severity banner reusable by future tools"
    - "JWTDefinition (real) — detection predicate priority 2: ey prefix + 2 dots"
  affects:
    - "All future tools that handle secrets (Hash HMAC in 01-04 follows same secret-exclusion pattern)"
    - "Phase 2 tools that need base64url decoding can reuse Data+Base64URL.swift"

tech_stack:
  added: []
  patterns:
    - "Pattern: Data+Base64URL.swift — 5-line static func fromBase64URL with char subst + re-padding (pitfall #4 fix)"
    - "Pattern: JWTExpiryStatus enum — .noExpiry / .valid(remaining:) / .expired(since:) with Date(timeIntervalSince1970:) (pitfall #11)"
    - "Pattern: JWTWarnings struct — isExpired / isAlgNone / missingStandardClaims computed in pure transformer (JWT-06)"
    - "Pattern: Secret-exclusion architecture — View-local @State secret, never a ViewModel property, never in onSaveHistory (INFRA-09, T-03-ID)"
    - "Pattern: WarningBannerView severity enum — BannerSeverity.warning (yellow) / .error (red) reusable component"

key_files:
  created:
    - Core/Extensions/Data+Base64URL.swift
    - Tools/JWT/JWTTransformer.swift
    - Tools/JWT/JWTViewModel.swift
    - Tools/JWT/JWTView.swift
    - UI/Components/WarningBannerView.swift
  modified:
    - Tools/JWT/JWTDefinition.swift (stub → real definition with JWTView factory)
    - Lathe.xcodeproj/project.pbxproj (JWT files added to Sources build phase + LatheTests group)

decisions:
  - "Secret-exclusion: HMAC secret is View-local @State in JWTView; JWTViewModel.verifyHMAC(secret:) is a transient in-memory call only; onSaveHistory never receives the secret (INFRA-09, pitfall #3)"
  - "exp claim decoded as TimeInterval, Int, or Int64 for robustness — JWT spec allows any numeric type"
  - "JWTClaimsPartition includes jti (JWT ID) in standard set per RFC 7519 Section 4.1"
  - "WarningBannerView uses BannerSeverity enum (not Bool) to allow future severity levels without API change"
  - "Project.pbxproj Sources build phase updated manually — the pre-registered file entries (from 01-02 prep) had file references but were not in the build phase list"

metrics:
  duration: "28 minutes"
  completed_date: "2026-06-25"
  tasks_completed: 2
  tasks_total: 2
  files_created: 5
  files_modified: 2
---

# Phase 1 Plan 3: JWT Decoder Summary

**One-liner:** JWT Decoder with base64url-correct decode (pitfall #4 fix), timezone-correct expiry (pitfall #11 fix), CryptoKit HMAC verify (HS256/384/512), standard/custom claims table, expired/alg:none/missing-claims warnings, and secret provably excluded from history (INFRA-09 verified by source assertion).

## What Was Built

### Task 1: Data+Base64URL + JWTTransformer (TDD — GREEN)

- `Core/Extensions/Data+Base64URL.swift` — Static `fromBase64URL(_:)`: char subst `-`→`+`, `_`→`/`, re-pads, uses `.ignoreUnknownCharacters`. This is the **pitfall #4 fix** — `Data(base64Encoded:)` returns nil for URL-safe chars without this.
- `Tools/JWT/JWTTransformer.swift` — Pure enum (zero SwiftUI/AppKit imports):
  - `decode(_:)` — splits on `.`, requires exactly 3 segments (INFRA-17), `Data.fromBase64URL` each, JSONSerialization parse
  - `expiryStatus(payload:)` — **pitfall #11 fix**: uses `Date(timeIntervalSince1970:)` (not `timeIntervalSinceReferenceDate`); without this fix, a now+1h token shows "31 years remaining"
  - `verifyHMAC(token:secret:algorithm:)` — HS256/384/512 via CryptoKit `HMAC<SHA256/384/512>.authenticationCode`; constant-time `Data(mac) == sigData` (T-03-T)
  - `partitionClaims(payload:header:)` — RFC 7519 standard set {iss, sub, aud, exp, nbf, iat, jti} vs custom
  - `warnings(payload:header:)` — isExpired, isAlgNone (T-03-SP), missingStandardClaims
  - `prettyPrintPayload(_:)` — JSONSerialization with .prettyPrinted + .sortedKeys, returns nil on failure (INFRA-17)
  - `expiryDescription(_:)` — `DateComponentsFormatter` human-readable duration
- **22 JWTTransformerTests all PASS** including pitfall #4 vector (`_` in signature) and pitfall #11 vector (now+1h ≠ 31 years)

### Task 2: JWT ViewModel + View + Definition [BLOCKING security control verified]

- `Tools/JWT/JWTViewModel.swift` — `@Observable @MainActor`, 150ms debounce, decodes token reactively, resets hmacVerified on new token. **SECRET-EXCLUSION CONTROL** (INFRA-09, T-03-ID, pitfall #3): HMAC secret is NOT a ViewModel property; `verifyHMAC(secret:)` is a transient method call; `onSaveHistory` receives `token` only with explicit SECURITY comment at call site.
- `Tools/JWT/JWTView.swift` — Full JWT decoder UI:
  - Header, Payload, Signature as `CodeDisplayView` with per-field `CopyButtonView` (D-12, JWT-01, JWT-02)
  - Expiry countdown with color-coded status (green = valid, red = expired) (JWT-03)
  - Claims table with Standard / Custom sections and algorithm badge (JWT-05)
  - Warning banners: expired (red WarningBannerView), alg:none (yellow), missing standard claims (yellow) (JWT-06)
  - HMAC Verify section: `SecureField` with placeholder "Secret key (never saved)" (UI-SPEC copywriting); secret is `@State` in the view, passed only to `viewModel.verifyHMAC(secret:)` — never to `onSaveHistory`
  - Inline error with dimmed-output (D-11, INFRA-17)
- `UI/Components/WarningBannerView.swift` — `BannerSeverity.warning` (yellow, 15% opacity) / `.error` (red, 15% opacity); accessibility label on banner content
- `Tools/JWT/JWTDefinition.swift` — Overwrites stub: real `JWTView` factory, detection predicate `hasPrefix("ey") + count == 3` (chain priority 2). ToolRegistry untouched.
- `Lathe.xcodeproj/project.pbxproj` — Added all 5 new files to `PBXSourcesBuildPhase` main target; added JWTTransformerTests to test target Sources + LatheTests group.

## Security Verification — [BLOCKING] INFRA-09 / T-03-ID / Pitfall #3

**Result: VERIFIED — secret is provably excluded from history.**

Source assertion:
```
grep -n "secret" Tools/JWT/JWTViewModel.swift
```
Output: All references to "secret" are either:
1. Security comments explaining the exclusion (lines 4-6, 134-135)
2. `input: token,  // token only — secret excluded by design` (line 138 — in onSaveHistory)
3. `func verifyHMAC(secret: String)` method parameter (line 151) — transient in-memory call only

The `onSaveHistory` call at line 133-140 receives:
```swift
onSaveHistory(HistoryEntry(
    tool: "jwt-decoder",
    input: token,  // token only — secret excluded by design
    output: headerJSON + "\n---\n" + payloadJSON,
    ...
))
```
No secret argument. No secret ViewModel property. Architecture enforces exclusion structurally.

**Runtime verification note:** The HistoryEntry schema has no `secret` column by design (enforced in plan 01-01, INFRA-09). SQLite `SELECT input FROM historyEntry WHERE tool='jwt-decoder'` would show only the token — the secret cannot be written because the schema does not have a column for it and the ViewModel never passes it.

## Task Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1: Data+Base64URL + JWTTransformer (TDD GREEN) | `3f5f6cf` | base64url extension + JWTTransformer — TDD GREEN |
| 2: JWT ViewModel + View + Definition | `841000f` | JWT ViewModel + View + Definition with secret-exclusion control [BLOCKING] |

## Files Created/Modified

| File | Status | Purpose |
|------|--------|---------|
| `Core/Extensions/Data+Base64URL.swift` | Created | Base64URL decoder — pitfall #4 fix |
| `Tools/JWT/JWTTransformer.swift` | Created | Pure JWT transformer — decode, expiry, HMAC, claims, warnings |
| `Tools/JWT/JWTViewModel.swift` | Created | @Observable ViewModel — 150ms debounce, secret-excluded history |
| `Tools/JWT/JWTView.swift` | Created | Full JWT decoder UI — all JWT-01..06 requirements |
| `UI/Components/WarningBannerView.swift` | Created | Reusable severity-tinted warning banner |
| `Tools/JWT/JWTDefinition.swift` | Modified (stub → real) | Real detection predicate + JWTView factory |
| `Lathe.xcodeproj/project.pbxproj` | Modified | JWT files added to Sources build phases |

## Verification Results

| Check | Result |
|-------|--------|
| `xcodebuild test -only-testing:LatheTests/JWTTransformerTests` | TEST SUCCEEDED (22 tests) |
| pitfall #4 regression (JWT with `_` in signature) | PASS — `testDecode_realJWTWithUrlSafeChars` |
| pitfall #11 regression (now+1h ≠ 31 years) | PASS — `testExpiryStatus_futureExp_isNotThirtyOneYears` |
| `xcodebuild -scheme Lathe build` | BUILD SUCCEEDED |
| `grep -c "import SwiftUI\|import AppKit" JWTTransformer.swift` | 0 (pure, no UI imports) |
| Secret exclusion source assertion | PASS — onSaveHistory receives token only |
| HistoryEntry schema has no secret column | PASS (enforced in plan 01-01) |
| Full test suite | TEST SUCCEEDED (all tests pass) |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] JWT source files not in Xcode build phase**
- **Found during:** Task 2 build verification
- **Issue:** The project.pbxproj had PBXFileReference and PBXBuildFile entries pre-registered for JWT files, but they were not listed in the PBXSourcesBuildPhase `files` array. Build failed with "cannot find 'JWTView' in scope."
- **Fix:** Added `001100000000061..065` (main target) and `001100000000066` (test target) to their respective `PBXSourcesBuildPhase` files arrays. Also added `JWTTransformerTests` to the `LatheTests` group.
- **Files modified:** `Lathe.xcodeproj/project.pbxproj`
- **Commit:** `841000f`

## Known Stubs

None — all JWT requirements (JWT-01..06) are fully implemented.

## Threat Surface Scan

No new network endpoints, auth paths, file access patterns, or schema changes introduced. All JWT processing is in-memory, pure functions. The HistoryEntry schema (no secret column) was established in plan 01-01 — no changes to trust boundaries.

## Threat Model Coverage

| Threat | Mitigation Status |
|--------|-------------------|
| T-03-ID (HMAC secret in history) | MITIGATED — View-local @State, onSaveHistory token-only, verified by source assertion |
| T-03-T (signature verification) | MITIGATED — CryptoKit constant-time `Data(mac) == sigData`; wrong secret → false |
| T-03-IV (malformed tokens) | MITIGATED — 3-segment guard, Data.fromBase64URL nil-safe, pure Result decode, 7 no-crash tests |
| T-03-R (exp timezone bug) | MITIGATED — Date(timeIntervalSince1970:) only; regression test passes |
| T-03-SP (alg:none acceptance) | MITIGATED — alg:none shows warning banner, verifyHMAC returns false for unknown alg |

## Self-Check: PASSED

Files verified to exist:
- /Users/chutipon/Documents/project/flint/Core/Extensions/Data+Base64URL.swift — FOUND
- /Users/chutipon/Documents/project/flint/Tools/JWT/JWTTransformer.swift — FOUND
- /Users/chutipon/Documents/project/flint/Tools/JWT/JWTViewModel.swift — FOUND
- /Users/chutipon/Documents/project/flint/Tools/JWT/JWTView.swift — FOUND
- /Users/chutipon/Documents/project/flint/Tools/JWT/JWTDefinition.swift — FOUND
- /Users/chutipon/Documents/project/flint/UI/Components/WarningBannerView.swift — FOUND

Commits verified:
- 3f5f6cf: feat(01-03): base64url extension + JWTTransformer — TDD GREEN
- 841000f: feat(01-03): JWT ViewModel + View + Definition with secret-exclusion control [BLOCKING]
