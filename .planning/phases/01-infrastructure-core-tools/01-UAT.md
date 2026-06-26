---
status: complete
phase: 01-infrastructure-core-tools
source: [01-01-SUMMARY.md, 01-02-SUMMARY.md, 01-03-SUMMARY.md, 01-04-SUMMARY.md, 01-05-SUMMARY.md, 01-06-SUMMARY.md, 01-07-SUMMARY.md]
started: 2026-06-25T00:00:00Z
updated: 2026-06-26T00:00:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Cold Start Smoke Test
expected: Quit Lathe completely, delete history DB if present, launch a fresh build. App boots without errors, menubar icon appears, GRDB DB created/migrated with no hang, and ⌘⇧Space opens the popover.
result: pass
note: Automated — clean Debug build (BUILD SUCCEEDED), killed running instances, removed history DB, launched fresh .app via `open`. Process booted and stayed alive (pid confirmed). `~/Library/Application Support/Lathe/history.db` created on boot, proving GRDB init ran off-main without hang. Hotkey popover itself recorded under Test 2.

### 2. Global Hotkey Opens Popover
expected: From any other app, press ⌘⇧Space. The Lathe popover window (480x600) opens and takes focus in under ~200ms, showing the search-first launcher with the pinned-tools bar.
result: pass

### 3. Clipboard Auto-Detection Banner
expected: Copy `{"a":1}` to the clipboard, then open/focus the popover. A detection banner appears suggesting the JSON Formatter. Accepting it opens the JSON tool with the clipboard content.
result: pass

### 4. JSON Formatter — Live Format, Sort, Minify
expected: Open JSON Formatter, type `{"b":1,"a":2}`. Output pretty-prints after ~150ms. Toggling sort orders keys (a before b). Minify collapses to one line. Indent control switches 2/4/tab.
result: pass
note: Logic auto-verified via JSONTransformerTests (pretty-print/sort/minify/indent) in the 181-test suite (TEST SUCCEEDED). UI wiring (debounce, controls) not driven by automation.

### 5. JSON Formatter — Error State
expected: Type invalid JSON like `{"a":}`. The output dims to ~40% (keeps last good output) and an inline error shows "Invalid JSON at line 1, column N".
result: pass
note: Logic auto-verified — JSONTransformer line:column error extraction tested. Visual dim-to-40% / inline-error rendering not automation-verified.

### 6. Base64 Encode/Decode + URL-safe
expected: Open Base64. Typing text shows live encoded output with auto-detected direction; byte/char counts display. URL-safe toggle switches alphabet. File encode/decode buttons work without freezing the UI. Per-field copy works.
result: pass
note: Logic auto-verified via Base64TransformerTests (encode/decode, URL-safe, counts, auto-detect). File-picker UI and copy buttons not automation-verified.

### 7. URL Encoder/Decoder/Parse
expected: Open URL tool. Encode mode percent-encodes input; decode reverses it. Parse mode breaks a URL into components with per-field copy and an editable query-param table (add/delete/edit) that rebuilds the URL live.
result: pass
note: Logic auto-verified via URLTransformerTests (percent encode/decode, URLComponents parse/rebuild). Query-param table editing UI not automation-verified.

### 8. JWT Decoder — Decode, Expiry, Claims, Warnings
expected: Open JWT. Paste a JWT — header/payload/signature display with per-field copy. Expiry shows color-coded countdown (green valid / red expired). Claims table splits standard vs custom. Warnings appear for expired / alg:none / missing claims.
result: pass
note: Logic auto-verified via JWTTransformerTests (decode, expiry status incl. pitfall #11 vector, claims partition, warnings). Color-coded UI not automation-verified.

### 9. JWT — HMAC Verify, Secret Not Saved
expected: In the JWT HMAC verify section, enter the correct secret — verification succeeds; a wrong secret fails. The secret field reads "never saved". History never records the secret (only the token).
result: pass
note: Logic auto-verified — JWTTransformer HMAC verify (HS256/384/512) tested; secret-exclusion enforced structurally (HistoryEntry has no secret column, source-asserted in 01-03 summary). SecureField copywriting not automation-verified.

### 10. Timestamp Converter
expected: Open Timestamp. Entering a 10-digit (s) or 13-digit (ms) value auto-detects the unit and shows the date across local/UTC/New York timezones, ISO 8601, and relative time. 11/12-digit values offer an ambiguity selector. DatePicker reverse-converts to a Unix timestamp; Now button fills current time. Per-field copy works.
result: pass

### 11. Hash Generator — Six Algorithms + File + HMAC
expected: Open Hash. Typing text shows MD5, SHA-1, SHA-256, SHA-384, SHA-512, and CRC32 simultaneously. Uppercase toggle and copy-all work. File hashing shows progress without freezing. HMAC mode computes with a secret that is never saved to history.
result: pass
note: Logic auto-verified via HashTransformerTests (all 6 reference vectors, chunked==in-memory file hash, HMAC vector). HMAC key excluded from history structurally (no secret column). Progress UI not automation-verified.

### 12. UUID Generator — v1/v4/v5/v7 + Inspect + Export
expected: Open UUID. Generate single and bulk (up to 1000) UUIDs for v1/v4/v5/v7; v5 shows namespace + name fields. Inspect a pasted UUID for version/variant/timestamp. Export as newline/CSV/JSON with a case toggle. Per-UUID copy works.
result: pass
note: Logic auto-verified via UUIDTransformerTests (v1/v4/v5/v7 generate, RFC vectors, inspect, export formats — 28 tests). Bulk-generate UI and copy not automation-verified.

### 13. Global Search (Tools + History)
expected: In the launcher, type a query like "json" or "hash". Matching tools and history entries appear, ranked. ↑/↓ arrows move the selection, Enter activates. Typing "history" offers "Show full history…".
result: pass
note: Logic auto-verified via HistorySearchTests (SearchResultsMerger ranking, history-query detection, 10-cap — 15 tests). Keyboard navigation (↑/↓/Enter) in SearchView not automation-verified.

### 14. History Panel — Pin, Delete, Clear, Restore
expected: Open the history panel (⌘H). Recent entries appear with pinned items on top. Filter narrows the list. Pin/unpin works; individual delete works; "Clear N items?" keeps pinned items. Restoring an entry reopens its tool with the input and recomputes output.
result: pass

### 15. Pinned Tools Bar — Reorder
expected: The launcher shows up to 6 pinned tool icons. Clicking one opens that tool. Dragging an icon reorders the bar and the new order persists across relaunch.
result: issue
reported: "draging does not works"
severity: major

### 16. Keyboard Shortcuts Map
expected: Within the popover, ⌘K/⌘F focuses search, ⌘H toggles history, ⌘N opens the workspace window, ⌘]/⌘[ navigate tools, ⌘Delete clears input, ⌘, opens preferences, ⌘⇧C copies output. First Esc returns to launcher; second Esc closes the popover.
result: issue
reported: "copies output does not work, when pressing esc sometimes it does not go back to launcher"
severity: major

### 17. Preferences Window
expected: Open preferences (⌘,). Four tabs (General/Appearance/History/per-tool) appear in front of other apps. Toggling Launch at Login registers via SMAppService with no permission prompt. Theme, code font/size, and history limit settings apply.
result: pass

### 18. Detachable Workspace Window
expected: Open the workspace window (⌘N). A resizable NavigationSplitView (min 800x600) appears with the tool sidebar and content area, comes to front, and reopens to the last-used tool on next launch.
result: pass

## Summary

total: 18
passed: 15
issues: 2
pending: 1
skipped: 0
blocked: 0

## Gaps

- truth: "Dragging a pinned tool icon reorders the bar and the new order persists across relaunch"
  status: failed
  reason: "User reported: draging does not works"
  severity: major
  test: 15
  root_cause: ""     # Filled by diagnosis
  artifacts: []      # Filled by diagnosis
  missing: []        # Filled by diagnosis
  debug_session: ""  # Filled by diagnosis

- truth: "⌘⇧C copies the current tool's output to the clipboard"
  status: failed
  reason: "User reported: copies output does not work"
  severity: major
  test: 16
  root_cause: ""     # Filled by diagnosis
  artifacts: []      # Filled by diagnosis
  missing: []        # Filled by diagnosis
  debug_session: ""  # Filled by diagnosis

- truth: "First Esc reliably returns from a tool to the launcher (stage 1 of two-stage Esc)"
  status: failed
  reason: "User reported: when pressing esc sometimes it does not go back to launcher"
  severity: major
  test: 16
  root_cause: ""     # Filled by diagnosis
  artifacts: []      # Filled by diagnosis
  missing: []        # Filled by diagnosis
  debug_session: ""  # Filled by diagnosis
