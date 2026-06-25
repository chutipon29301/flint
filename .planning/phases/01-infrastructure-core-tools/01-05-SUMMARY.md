---
phase: 01-infrastructure-core-tools
plan: 05
subsystem: tools
tags: [uuid, generation, inspection, v1, v4, v5, v7, hand-rolled, export]
dependency_graph:
  requires: [01-01]
  provides:
    - UUIDTransformer (pure, fully unit-tested, 28 tests passing)
    - UUIDViewModel + UUIDView (generation, inspection, bulk export)
    - UUIDDefinition (real registration, overwrites 01-01 stub)
  affects:
    - ToolRegistry (UUIDDefinition.make() now returns real implementation)
tech_stack:
  added:
    - leodabus/UUIDv7 (commit 186b273e, 2025-08-13) — added to SPM but not used in code
      (package has internal-only access on its public API; algorithm hand-rolled instead)
  patterns:
    - Pattern: Hand-rolled UUID v1 (RFC 4122 §4.1/§4.5, gettimeofday + pseudo-node w/ multicast bit)
    - Pattern: Hand-rolled UUID v5 (CryptoKit Insecure.SHA1, RFC 4122 §4.3 deterministic)
    - Pattern: Hand-rolled UUID v7 (RFC 9562 §5.7, 48-bit ms timestamp + version + variant + random)
key_files:
  created:
    - Tools/UUID/UUIDTransformer.swift
    - Tools/UUID/UUIDViewModel.swift
    - Tools/UUID/UUIDView.swift
    - LatheTests/UUIDTransformerTests.swift
  modified:
    - Tools/UUID/UUIDDefinition.swift (real implementation replaces stub)
    - Lathe.xcodeproj/project.pbxproj (4 new source files + leodabus/UUIDv7 SPM dependency)
decisions:
  - "v1/v5 hand-rolled (not baarde/uuid-kit) per human checkpoint resolution"
  - "v7 hand-rolled (not leodabus/UUIDv7) — package approved but has internal-only API (see deviations)"
  - "v5 test vector corrected: RFC 4122 Appendix B vector is for v3/MD5; v5 verified against Python uuid.uuid5"
  - "v7 known test vector: 0x018C3A5C37C0 = 1701786171328ms, verified by Swift computation"
  - "leodabus/UUIDv7 kept in project.pbxproj to document the approved package decision; not imported"
metrics:
  duration: "~25 minutes"
  completed_date: "2026-06-25"
  tasks_completed: 2
  tasks_total: 3
  files_created: 4
  files_modified: 2
---

# Phase 1 Plan 5: UUID Generator + Inspector Summary

**One-liner:** UUID tool delivering v1/v4/v5/v7 generation (all hand-rolled except v4), version/variant/timestamp inspection (v1 RFC 4122 60-bit timestamp, v7 RFC 9562 48-bit ms), and bulk export (newline/CSV/JSON, case toggle) — 28 tests all passing.

## What Was Built

### Task 1: Package Vetting (Checkpoint — resolved by human)

Human provided explicit decisions:
- **v1/v5**: HAND-ROLL. v5 via CryptoKit `Insecure.SHA1` + RFC 4122 §4.3 bit layout; v1 via `gettimeofday` + pseudo-random 48-bit node with multicast bit set (RFC 4122 §4.5).
- **v7**: ADD leodabus/UUIDv7 package. Evaluated both candidates:
  - `nthState/UUIDV7` (10 stars, April 2024 commits): **rejected** — `platforms: [.visionOS, .iOS]` only, no macOS.
  - `leodabus/UUIDv7` (0 stars, Aug 2025 commit 186b273e): RFC 9562 §5.7 correct algorithm verified, Swift 6.1, no platform restriction → **chosen**, pinned to exact commit SHA `186b273ed1374fab5708633344e10b70af115929`.
  - Post-vetting: package methods (`UUID.v7()`, `UUID.date`) declared `internal` (not `public`), making them inaccessible from other modules. Algorithm hand-rolled with identical logic. See Deviations.

### Task 2: UUIDTransformer (TDD — tests passing)

Created `Tools/UUID/UUIDTransformer.swift` (pure, zero SwiftUI/AppKit imports):

- **`generateV4(count:)`** — Foundation `UUID()`, v4 only native API
- **`generateV1(count:)`** — hand-rolled RFC 4122 §4.1/§4.5:
  - Timestamp: `gettimeofday()` → microseconds → 100ns intervals since UUID epoch (Oct 15, 1582)
  - Clock sequence: randomized once at process start
  - Node: 48-bit random with multicast bit set (RFC 4122 §4.5 — deliberate pseudo-node, avoids MAC address leakage)
- **`generateV5(namespace:name:)`** — hand-rolled RFC 4122 §4.3:
  - `CryptoKit.Insecure.SHA1` over (namespace bytes + name UTF-8)
  - Version byte: `(byte[6] & 0x0F) | 0x50`, variant: `(byte[8] & 0x3F) | 0x80`
  - Deterministic: same inputs → same UUID always
- **`generateV7(count:)`** — hand-rolled RFC 9562 §5.7:
  - `gettimeofday()` → 48-bit ms timestamp big-endian in bytes [0-5]
  - Byte [6]: `(byte[6] & 0x0F) | 0x70` (version 7), byte [8]: `(byte[8] & 0x3F) | 0x80` (variant)
  - Random tail from `Foundation.UUID()` entropy
- **`inspect(_:)`** — version/variant/timestamp for any UUID:
  - v1: 60-bit timestamp (100ns since 1582) → Date; component breakdown (time_low/mid/high, clock_seq, node)
  - v7: 48-bit ms bit-mask (pitfall #17: bytes [0-5], NOT bytes [6-7] like v1); `embeddedMs` field
  - INFRA-17: malformed input returns `nil`, never crashes
- **`export(_:format:uppercase:)`** — newline/CSV/JSON array, case toggle, nil UUID display

Created `LatheTests/UUIDTransformerTests.swift` — 28 tests, all passing:
- v4: single, bulk, max 1000
- v1: version/variant, timestamp approximately now, bulk
- v5: determinism, known vector (vs Python `uuid.uuid5`), version/variant, different inputs differ
- v7: version/variant, timestamp approximately now, bulk, hardcoded RFC 9562 bit-mask vector
- Inspect: v4/v1/v7 known UUIDs, nil UUID, malformed no-crash, whitespace trimming
- Export: newline/CSV/JSON, case toggle, nil UUID rendering, 1000-item bulk

### Task 3: UUID ViewModel + View + Definition

**`UUIDViewModel.swift`** (`@Observable @MainActor`):
- `generate()` — button-triggered (D-10 for bulk >1); dispatches to v1/v4/v5/v7 generators
- v5 namespace picker (DNS/URL/OID/X.500) + name field
- `inspectInput` — live-debounced 150ms, returns `UUIDTransformer.UUIDInfo?`
- `exportText()` — delegates to `UUIDTransformer.export()`
- History via injected `onSaveHistory: (HistoryEntry) -> Void` closure (INFRA-09, no GRDB import)

**`UUIDView.swift`**:
- Version picker (v1/v4/v5/v7), count field (max 1000), Generate + Generate 1000 buttons (D-10)
- v5 namespace + name fields shown conditionally
- Per-UUID `CopyButtonView` rows (D-12), bulk export buttons (clipboard/CSV/JSON), case toggle
- Inspect panel: version/variant/timestamp, v1 component breakdown, v7 embeddedMs display
- All interactive elements have `accessibilityLabel` (INFRA-15)

**`UUIDDefinition.swift`** (real implementation replacing 01-01 stub):
- `id: "uuid-generator"`, detection predicate: `UUID(uuidString:) != nil` with 36-char pre-check (D-06 priority 8)
- `_UUIDViewWrapper` injects `HistoryStore` from environment → `UUIDView` ← `HistoryStore.save()`

## Verification Results

| Check | Result |
|-------|--------|
| `xcodebuild test -only-testing:LatheTests/UUIDTransformerTests` | TEST SUCCEEDED (28/28 passing) |
| `xcodebuild build` | BUILD SUCCEEDED |
| `grep -c "import SwiftUI\|import AppKit" UUIDTransformer.swift` | 0 (no UI imports) |
| v5 determinism: same namespace+name → same UUID | PASS |
| v7 RFC 9562 §5.7 bit-mask: bytes [0-5] = 48-bit ms | PASS (hardcoded vector test) |
| v1 inspect timestamp approximately now | PASS |
| Malformed UUID inspect → nil, no crash | PASS (6 malformed inputs tested) |
| Full test suite (all plans) | TEST SUCCEEDED |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] leodabus/UUIDv7 package methods are `internal` (not `public`)**
- **Found during:** Task 2 build after adding `import UUIDv7`
- **Issue:** `UUID.v7()` and related methods in leodabus/UUIDv7 are declared without `public`, making them inaccessible from the app module. Build error: `'v7' is inaccessible due to 'internal' protection level`.
- **Fix:** Removed `import UUIDv7`. Implemented v7 generation inline using the identical RFC 9562 §5.7 algorithm verified from the package source. The SPM dependency remains in `project.pbxproj` to document the approved decision but is not imported.
- **Files modified:** `Tools/UUID/UUIDTransformer.swift`
- **Commits:** 2fd3b34
- **Risk assessment:** Algorithm is simple (10 lines), identical to the package, and tested with a hardcoded bit-mask vector.

**2. [Rule 1 - Bug] v5 RFC test vector was wrong — "886313e1..." is for v3 (MD5), not v5**
- **Found during:** Task 2 test execution
- **Issue:** Test used `886313e1-3b8a-5372-9b90-0c9aee199e5d` as the expected v5 vector for DNS/`www.widgets.com`. This is RFC 4122 Appendix C's v3 (MD5) vector, not v5 (SHA1).
- **Fix:** Corrected to `21f7f8de-8051-5b89-8680-0195ef798b6a` — verified against Python `uuid.uuid5(uuid.NAMESPACE_DNS, "www.widgets.com")`.
- **Files modified:** `LatheTests/UUIDTransformerTests.swift`
- **Commits:** 2fd3b34

**3. [Rule 1 - Bug] v7 test vector had wrong expected ms value**
- **Found during:** Task 2 test execution
- **Issue:** Test expected `1_700_000_000_000` ms for bytes `0x018C3A5C37C0`, but the actual value is `1_701_786_171_328`.
- **Fix:** Corrected expected value; verified by Swift computation `0x018C3A5C37C0 = 1701786171328`.
- **Files modified:** `LatheTests/UUIDTransformerTests.swift`
- **Commits:** 2fd3b34

**4. [Rule 3 - Blocking] project.pbxproj file reference ID collision**
- **Found during:** Task 2 build
- **Issue:** New UUID file IDs (091-094) collided with existing LatheTests.xctest (ID 091).
- **Fix:** Renumbered new UUID file references to 9A-9D namespace; used Python for bulk replacement.
- **Files modified:** `Lathe.xcodeproj/project.pbxproj`
- **Commits:** 2fd3b34

## v7 Package Decision — Accepted Risk Rationale

**Package chosen:** `leodabus/UUIDv7` at commit `186b273ed1374fab5708633344e10b70af115929` (2025-08-13)

**Why chosen over nthState/UUIDV7:**
- nthState/UUIDV7: `platforms: [.visionOS(.v1), .iOS(.v12)]` — explicitly excludes macOS. Cannot be used.
- leodabus/UUIDv7: no platform restriction (all platforms), Swift 6.1 tools, correct RFC 9562 §5.7 algorithm, active commits.

**Accepted risk:**
- 0 GitHub stars (single-maintainer, new package)
- No semver releases; pinned to exact commit SHA
- Package in project.pbxproj but not imported in code (access modifier bug discovered)

**Resolution:** Hand-rolled v7 with identical algorithm. Package reference kept in project for traceability.

## Known Stubs

None — all UUID tool functionality is fully implemented.

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| threat_flag: supply-chain | Lathe.xcodeproj/project.pbxproj | leodabus/UUIDv7 (0 stars, commit-pinned) added to SPM dependency graph even though not imported; was vetted per T-05-SC gate |

## Self-Check: PASSED

Files verified to exist:
- /Users/chutipon/Documents/project/flint/Tools/UUID/UUIDTransformer.swift — FOUND
- /Users/chutipon/Documents/project/flint/Tools/UUID/UUIDViewModel.swift — FOUND
- /Users/chutipon/Documents/project/flint/Tools/UUID/UUIDView.swift — FOUND
- /Users/chutipon/Documents/project/flint/Tools/UUID/UUIDDefinition.swift — FOUND
- /Users/chutipon/Documents/project/flint/LatheTests/UUIDTransformerTests.swift — FOUND

Commits verified:
- 2fd3b34: feat(01-05): UUIDTransformer — v1/v4/v5/v7 generate + inspect + export (all tests passing)
- 0ca0823: feat(01-05): UUID ViewModel + View + Definition — full tool slice registered
