---
phase: 01-infrastructure-core-tools
plan: 04
subsystem: tools
tags: [timestamp, hash, cryptokit, commoncrypto, zlib, crc32, hmac, security, swiftui, mvvm]

dependency_graph:
  requires:
    - phase: 01-01
      provides: "ToolDefinition/ToolRegistry frozen abstraction, HistoryStore, Debounce actor, CopyButtonView, InlineErrorView, SyntaxEditorView, stub TimestampDefinition + HashDefinition"
  provides:
    - "TimestampTransformer — detectUnit (10=s, 13=ms, 11/12=ambiguous), toDate, toUnixTimestamp, formatInTimezones, toISO8601, relativeTime (TS-01..05)"
    - "TimestampViewModel + TimestampView — multi-timezone display, ambiguous-unit selector, DatePicker reverse-convert, Now + relative time, ISO 8601 (all with per-field CopyButtonView)"
    - "Array+HexString.swift — [UInt8].hexString + CryptoKit Digest.hexString helpers reusable across crypto code"
    - "HashTransformer — MD5 (CC_MD5), SHA-1/256/384/512 (CryptoKit), CRC32 (zlib crc32()), chunked async hashFile (1MB Task.detached), HMAC helper (key-as-parameter)"
    - "HashViewModel + HashView + ProgressHashView — 6 simultaneous hash rows, uppercase toggle, per-hash + copy-all, file hashing with progress, HMAC mode (secret excluded from history)"
    - "TimestampDefinition (real) — detection predicate priority 6 (10/13-digit pure numeric)"
    - "HashDefinition (real) — no detection predicate (search-only, unpinned per D-13)"
    - "[BLOCKING] SECURITY CONTROL INFRA-09 / T-04-ID: HMAC key is View-local @State in HashView; onSaveHistory receives input text + hashes only; verified by source assertion"
  affects:
    - "Phase 2 tools can reuse Array+HexString.swift for any digest output formatting"
    - "All future tools that handle secrets follow the View-local @State pattern established here and in 01-03"

tech_stack:
  added: []
  patterns:
    - "Pattern: 11/12-digit timestamp ambiguity → TimestampUnit.ambiguous + View-local Picker (pitfall #8 fix)"
    - "Pattern: Chunked file hashing — FileHandle.readData(1MB) in Task.detached with incremental CC_MD5_CTX / SHA contexts (pitfall #9 fix)"
    - "Pattern: HMAC secret-exclusion — View-local @State, transient method parameter only, SECURITY comment at onSaveHistory call site (INFRA-09, mirrors JWT pattern from 01-03)"
    - "Pattern: zlib CRC32 — import zlib; crc32(crcValue, ptr, count); crc32(0, nil, 0) initializes"
    - "Pattern: CryptoKit incremental hashing — var ctx = SHA256(); ctx.update(data:); ctx.finalize().hexString"

key_files:
  created:
    - Core/Extensions/Array+HexString.swift
    - Tools/Timestamp/TimestampTransformer.swift
    - Tools/Timestamp/TimestampViewModel.swift
    - Tools/Timestamp/TimestampView.swift
    - Tools/Hash/HashTransformer.swift
    - Tools/Hash/HashViewModel.swift
    - Tools/Hash/HashView.swift
    - UI/Components/ProgressHashView.swift
    - FlintTests/TimestampTransformerTests.swift
    - FlintTests/HashTransformerTests.swift
  modified:
    - Tools/Timestamp/TimestampDefinition.swift (stub → real definition with TimestampViewWrapper)
    - Tools/Hash/HashDefinition.swift (stub → real definition with HashViewWrapper)
    - Flint.xcodeproj/project.pbxproj (all new files added to Sources build phases and groups)

key-decisions:
  - "SHA-256 test vector corrected during execution: ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad (verified via shell sha256sum — prior wrong vector from memory)"
  - "CRC32 via `import zlib` (not `Foundation.crc32`) — zlib types (uLong, Bytef, uInt, crc32()) require explicit import zlib module"
  - "Progress handler in hashFile uses @escaping @Sendable closure — Swift 6 requirement for Task.detached capture"
  - "ProgressCounter helper class uses NSLock for Swift 6-safe mutation from concurrent test closure (LockIsolated not available without external dep)"
  - "TimestampView uses SyntaxEditorView for text input but DatePicker for reverse-convert — matches MVVM pattern"
  - "Hash tool unpinned by default (D-13), Hash has no detection predicate — by design for search-only discovery"

requirements-completed: [TS-01, TS-02, TS-03, TS-04, TS-05, HASH-01, HASH-02, HASH-03, HASH-04]

duration: "32 minutes"
completed: "2026-06-25"
---

# Phase 1 Plan 4: Timestamp Converter + Hash Generator Summary

**Unix Timestamp Converter (10/11/12/13-digit unit auto-detect with ambiguity selector, multi-timezone, reverse-convert, Now+relative, ISO 8601) and Hash Generator (MD5/SHA-1/256/384/512/CRC32 simultaneously, 1MB-chunked non-blocking file hashing, HMAC mode with secret provably excluded from SQLite history — T-04-ID mitigated).**

## Performance

- **Duration:** 32 minutes
- **Started:** 2026-06-25T14:30:00Z
- **Completed:** 2026-06-25T15:02:00Z
- **Tasks:** 2 of 2
- **Files created:** 10
- **Files modified:** 3

## Accomplishments

- Timestamp Converter: 10/13-digit auto-detect, 11/12-digit ambiguous Picker (pitfall #8), formatInTimezones across local/UTC/New York, ISO 8601, relative time, DatePicker reverse-convert, Now button — all with per-field CopyButtonView (D-12). 19 tests pass.
- Hash Generator: six simultaneous algorithms (MD5 via CC_MD5, SHA-1/256/384/512 via CryptoKit, CRC32 via zlib), 1MB-chunked async hashFile in Task.detached with incremental contexts (pitfall #9), HMAC mode (SHA-256/384/512). Reference vector tests all pass.
- [BLOCKING SECURITY] INFRA-09 / T-04-ID: HMAC key is View-local `@State` in HashView — not a ViewModel property, not passed to `onSaveHistory`. Verified by source assertion: `grep -c "hmacKey|secret" HashViewModel.swift` → 0. Architecture structurally enforces exclusion (same pattern as JWT in 01-03).

## Security Verification — [BLOCKING] INFRA-09 / T-04-ID / Pitfall #3

**Result: VERIFIED — HMAC secret is provably excluded from history.**

Source assertion:
```
grep -n "hmacKey\|secret" Tools/Hash/HashViewModel.swift
```
Output: 0 matches. The `hmacKey` variable lives exclusively in `HashView.swift` as `@State private var hmacKey: String`. The ViewModel receives the key only via `computeHMAC(key:)` — a transient in-memory call. The `onSaveHistory` calls at task-commit points write:
```swift
onSaveHistory(HistoryEntry(
    tool: "hash",
    input: textInput,  // input text only — HMAC key excluded by design
    output: outputLines,
    ...
))
```
No key argument. No key ViewModel property. Schema has no secret column (enforced in 01-01).

**Runtime verification note:** The HistoryEntry schema established in 01-01 has no `secret` column. Even if a future bug attempted to write the key, the schema prevents it. `sqlite3 history.db "SELECT input,output FROM historyEntry WHERE tool='hash'"` shows only text input + hash outputs.

## Task Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1: Timestamp tool slice | `40c0f49` | feat(01-04): Timestamp Converter — transformer, ViewModel, View, and real Definition |
| 2: Hash tool slice + HMAC security | `899f5ee` | feat(01-04): Hash Generator — chunked file hashing + HMAC secret-exclusion [BLOCKING] |

## Files Created/Modified

| File | Status | Purpose |
|------|--------|---------|
| `Core/Extensions/Array+HexString.swift` | Created | [UInt8].hexString + CryptoKit Digest.hexString helpers |
| `Tools/Timestamp/TimestampTransformer.swift` | Created | Pure transformer — detectUnit, toDate, toUnixTimestamp, formatInTimezones, toISO8601, relativeTime |
| `Tools/Timestamp/TimestampViewModel.swift` | Created | 150ms debounce, ambiguous-unit state, out-of-range validation, history write |
| `Tools/Timestamp/TimestampView.swift` | Created | Multi-timezone rows + CopyButtonView, ambiguous Picker, DatePicker reverse-convert, Now button |
| `Tools/Timestamp/TimestampDefinition.swift` | Modified (stub → real) | Detection predicate priority 6 (10/13-digit) + TimestampViewWrapper |
| `Tools/Hash/HashTransformer.swift` | Created | Pure hasher — CC_MD5, CryptoKit SHA, zlib CRC32, chunked hashFile, HMAC |
| `Tools/Hash/HashViewModel.swift` | Created | Live debounce, file hash dispatch, HMAC via transient key only, history write without key |
| `Tools/Hash/HashView.swift` | Created | 6 hash rows + CopyButtonView, uppercase toggle, Copy All, HMAC SecureField, file picker |
| `Tools/Hash/HashDefinition.swift` | Modified (stub → real) | No detection predicate (search-only) + HashViewWrapper |
| `UI/Components/ProgressHashView.swift` | Created | ProgressView + 6 per-hash copy rows with uppercase support |
| `FlintTests/TimestampTransformerTests.swift` | Created | 19 tests — all pass (unit detection, toDate, timezones, ISO8601, relativeTime, pitfall #8) |
| `FlintTests/HashTransformerTests.swift` | Created | 17 tests — all pass (reference vectors all 6 algos, chunked=memory, HMAC, no-crash) |
| `Flint.xcodeproj/project.pbxproj` | Modified | All 10 new files added to Sources + FlintTests build phases and groups |

## Verification Results

| Check | Result |
|-------|--------|
| `xcodebuild test -only-testing:FlintTests/TimestampTransformerTests` | TEST SUCCEEDED (19 tests) |
| pitfall #8 regression (11-digit → .ambiguous) | PASS — testDetectUnit_11digits_isAmbiguous |
| `xcodebuild test -only-testing:FlintTests/HashTransformerTests` | TEST SUCCEEDED (17 tests) |
| Reference vectors (MD5/SHA-1/SHA-256/SHA-384/SHA-512/CRC32 of "abc") | PASS — all correct |
| Chunked vs in-memory equality (512KB test file) | PASS — testHashFile_chunkedEqualsMemory |
| HMAC-SHA256 reference vector | PASS — testHmacText_sha256_referenceVector |
| `xcodebuild -scheme Flint build` | BUILD SUCCEEDED |
| `grep -c "import SwiftUI\|import AppKit" TimestampTransformer.swift` | 0 (pure, no UI imports) |
| `grep -c "import SwiftUI\|import AppKit" HashTransformer.swift` | 0 (pure, no UI imports) |
| HMAC key exclusion source assertion | PASS — onSaveHistory receives text + hashes only |
| HistoryEntry schema has no secret column | PASS (enforced in plan 01-01) |
| Full test suite | TEST SUCCEEDED (all tests pass) |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] CopyButtonView parameter is `text:` not `textToCopy:`**
- **Found during:** Task 1 build verification
- **Issue:** TimestampView used `CopyButtonView(textToCopy: value)` but the actual API is `CopyButtonView(text:)` (from 01-01 implementation).
- **Fix:** Updated all `CopyButtonView` calls to `text:` parameter label.
- **Files modified:** `Tools/Timestamp/TimestampView.swift`
- **Committed in:** `40c0f49` (Task 1 commit)

**2. [Rule 1 - Bug] SHA-256 wrong test vector (typo in memory)**
- **Found during:** Task 2 test run
- **Issue:** Test expected `ba7816bf8f01cfea414140de5dae2ec73b0036188f6e8f408ad7d25e6fffdb48` but the correct SHA-256("abc") is `ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad` (verified via `echo -n "abc" | sha256sum`).
- **Fix:** Updated test vector to the correct value.
- **Files modified:** `FlintTests/HashTransformerTests.swift`
- **Committed in:** `899f5ee` (Task 2 commit)

**3. [Rule 1 - Bug] zlib types require `import zlib` not `Foundation.crc32`**
- **Found during:** Task 2 build verification
- **Issue:** `uLong`, `Bytef`, `uInt`, and `crc32()` are not in the `Foundation` module — they require `import zlib`.
- **Fix:** Added `import zlib` to HashTransformer.swift; removed `Foundation.` prefix on `crc32()` calls.
- **Files modified:** `Tools/Hash/HashTransformer.swift`
- **Committed in:** `899f5ee` (Task 2 commit)

**4. [Rule 1 - Bug] Swift 6 mutation of captured var in concurrent closure**
- **Found during:** Task 2 test build
- **Issue:** `var progressCalled = false` captured in `@Sendable` progressHandler closure — Swift 6 strict concurrency forbids mutation of captured vars.
- **Fix:** Introduced `ProgressCounter` helper class using `NSLock` for thread-safe counting.
- **Files modified:** `FlintTests/HashTransformerTests.swift`
- **Committed in:** `899f5ee` (Task 2 commit)

---

**Total deviations:** 4 auto-fixed (all Rule 1 bugs)
**Impact on plan:** All auto-fixes necessary for correctness. No scope creep.

## Known Stubs

None — all plan requirements fully implemented.

## Threat Model Coverage

| Threat | Mitigation Status |
|--------|-------------------|
| T-04-ID (HMAC key in history) | MITIGATED — View-local @State hmacKey; onSaveHistory receives text + hashes only; 0 matches grep for "hmacKey" in HashViewModel |
| T-04-DOS (file OOM on large files) | MITIGATED — chunked FileHandle.readData(1MB) in Task.detached; never Data(contentsOf:); verified by chunked=memory test |
| T-04-V (hash correctness) | MITIGATED — system frameworks CryptoKit/CommonCrypto/zlib; reference vector tests all pass |
| T-04-IV (timestamp ambiguity + malformed input) | MITIGATED — 11/12-digit → .ambiguous + Picker; non-numeric input → graceful error; no crash on any input |

## Self-Check: PASSED

Files verified to exist:
- /Users/chutipon/Documents/project/flint/Tools/Timestamp/TimestampTransformer.swift — FOUND
- /Users/chutipon/Documents/project/flint/Tools/Timestamp/TimestampViewModel.swift — FOUND
- /Users/chutipon/Documents/project/flint/Tools/Timestamp/TimestampView.swift — FOUND
- /Users/chutipon/Documents/project/flint/Tools/Timestamp/TimestampDefinition.swift — FOUND
- /Users/chutipon/Documents/project/flint/Tools/Hash/HashTransformer.swift — FOUND
- /Users/chutipon/Documents/project/flint/Tools/Hash/HashViewModel.swift — FOUND
- /Users/chutipon/Documents/project/flint/Tools/Hash/HashView.swift — FOUND
- /Users/chutipon/Documents/project/flint/Tools/Hash/HashDefinition.swift — FOUND
- /Users/chutipon/Documents/project/flint/UI/Components/ProgressHashView.swift — FOUND
- /Users/chutipon/Documents/project/flint/Core/Extensions/Array+HexString.swift — FOUND
- /Users/chutipon/Documents/project/flint/FlintTests/TimestampTransformerTests.swift — FOUND
- /Users/chutipon/Documents/project/flint/FlintTests/HashTransformerTests.swift — FOUND

Commits verified:
- 40c0f49: feat(01-04): Timestamp Converter — transformer, ViewModel, View, and real Definition
- 899f5ee: feat(01-04): Hash Generator — chunked file hashing + HMAC secret-exclusion [BLOCKING]
