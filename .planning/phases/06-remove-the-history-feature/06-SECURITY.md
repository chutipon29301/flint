---
phase: 06
slug: remove-the-history-feature
status: secured
threats_open: 0
asvs_level: 1
created: 2026-07-04
---

# Phase 06 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.
> Mode: **Retroactive STRIDE** — no `<threat_model>` block existed in any Phase 6 PLAN; the
> register was built post-hoc from ROADMAP.md rationale, implementation diffs (base `4704e27`
> → HEAD), and 06-REVIEW.md, then independently verified against the codebase by
> gsd-security-auditor.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| App ↔ local disk | UserDefaults preferences; (formerly) GRDB history.db in Application Support | Tool input/output — potentially secrets (JWTs, HMAC keys, arbitrary pastes) |
| App ↔ clipboard | Clipboard auto-detect, paste-back | Arbitrary user paste content |
| App ↔ dropped files | Base64 / ImageCompress file-drop and file-picker paths | Arbitrary file contents |

---

## Threat Register

| Threat ID | Category | Component | Disposition | Mitigation | Status |
|-----------|----------|-----------|-------------|------------|--------|
| T-01 | Information Disclosure | Future history persistence | mitigate | HistoryStore/HistoryEntry deleted (0b1e8cd); repo-wide grep zero matches — no code path writes tool input/output to any store | closed |
| T-02 | Information Disclosure | JWT secret / HMAC key | mitigate | Both remain View-local `@State` (JWTView, HashView); no UserDefaults/file-write sink in either ViewModel; no surviving capture closure | closed |
| T-03 | Information Disclosure | Residual `~/Library/Application Support/Flint/history.db` written by pre-Phase-6 builds | mitigate | Startup cleanup in `App/FlintApp.swift` `init()` deletes history.db + -wal/-shm sidecars (commit 6d31a09). Verified live: file present before launch, gone after | closed |
| T-04 | Information Disclosure | Preferences / UserDefaults | mitigate | `PreferencesStore.Keys` contains only non-secret keys; `historyLimit` key deleted (06-05); no secret ever written to UserDefaults | closed |
| T-05 | Tampering | Clipboard detection, file-drop paths | mitigate | Phase diff shows zero changes to clipboard detection; Base64/ImageCompress diffs are closure-removal only | closed |

*Status: open · closed*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

### Non-blocking flags

| ID | Category | Finding | Tracking |
|----|----------|---------|----------|
| T-06 | Dead surface area | `UI/SearchView.swift` + `Core/Services/SearchResultsMerger.swift` edited but unreachable (never instantiated); `.searchNavigate` declared/observed but never posted | 06-REVIEW.md WR-04 — delete or document in a future cleanup |
| T-07 | Functional (non-security) | Output-correctness regressions in ImageCompress/Base64 paths touched by the removal | 06-REVIEW.md WR-01/WR-02/WR-03 |

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|

*Accepted risks do not resurface in future audit runs.*

---

## Audit Trail

## Security Audit 2026-07-04

| Metric | Count |
|--------|-------|
| Threats found | 5 (+2 non-blocking flags) |
| Closed | 5 |
| Open | 0 |

- Retroactive-STRIDE audit by gsd-security-auditor (no plan-time threat model existed).
- T-03 found OPEN: removing history code left the data-at-rest file behind. User chose
  "add cleanup code" over accept-risk; fixed in `6d31a09` and verified end-to-end
  (history.db present before launch of the fixed build, deleted after).
- All other threats verified closed against the implementation, not just SUMMARY claims.
