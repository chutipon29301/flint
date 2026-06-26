---
phase: 01-infrastructure-core-tools
reviewed: 2026-06-25T00:00:00Z
depth: standard
files_reviewed: 63
files_reviewed_list:
  - App/FlintApp.swift
  - App/WindowCoordinator.swift
  - Core/Extensions/Array+HexString.swift
  - Core/Extensions/Data+Base64URL.swift
  - Core/Extensions/View+CopyButton.swift
  - Core/Models/DetectionResult.swift
  - Core/Models/HistoryEntry.swift
  - Core/Models/ToolCategory.swift
  - Core/Models/ToolDefinition.swift
  - Core/Services/ClipboardDetector.swift
  - Core/Services/HistoryStore.swift
  - Core/Services/HotkeyManager.swift
  - Core/Services/PreferencesStore.swift
  - Core/Services/SearchResultsMerger.swift
  - Core/Services/ToolRegistry.swift
  - FlintTests/Base64TransformerTests.swift
  - FlintTests/HashTransformerTests.swift
  - FlintTests/HistorySearchTests.swift
  - FlintTests/JSONTransformerTests.swift
  - FlintTests/TimestampTransformerTests.swift
  - FlintTests/URLTransformerTests.swift
  - FlintTests/UUIDTransformerTests.swift
  - Tools/Base64/Base64Definition.swift
  - Tools/Base64/Base64Transformer.swift
  - Tools/Base64/Base64View.swift
  - Tools/Base64/Base64ViewModel.swift
  - Tools/Hash/HashDefinition.swift
  - Tools/Hash/HashTransformer.swift
  - Tools/Hash/HashView.swift
  - Tools/Hash/HashViewModel.swift
  - Tools/JSONFormatter/JSONFormatterDefinition.swift
  - Tools/JSONFormatter/JSONFormatterView.swift
  - Tools/JSONFormatter/JSONFormatterViewModel.swift
  - Tools/JSONFormatter/JSONTransformer.swift
  - Tools/JWT/JWTDefinition.swift
  - Tools/JWT/JWTTransformer.swift
  - Tools/JWT/JWTView.swift
  - Tools/JWT/JWTViewModel.swift
  - Tools/Timestamp/TimestampDefinition.swift
  - Tools/Timestamp/TimestampTransformer.swift
  - Tools/Timestamp/TimestampView.swift
  - Tools/Timestamp/TimestampViewModel.swift
  - Tools/URLEncoder/URLEncoderDefinition.swift
  - Tools/URLEncoder/URLTransformer.swift
  - Tools/URLEncoder/URLView.swift
  - Tools/URLEncoder/URLViewModel.swift
  - Tools/UUID/UUIDDefinition.swift
  - Tools/UUID/UUIDTransformer.swift
  - Tools/UUID/UUIDView.swift
  - Tools/UUID/UUIDViewModel.swift
  - UI/Components/CodeDisplayView.swift
  - UI/Components/CopyButtonView.swift
  - UI/Components/DetectionBannerView.swift
  - UI/Components/HistoryRowView.swift
  - UI/Components/InlineErrorView.swift
  - UI/Components/PinnedToolBarView.swift
  - UI/Components/ProgressHashView.swift
  - UI/Components/SyntaxEditorView.swift
  - UI/Components/WarningBannerView.swift
  - UI/HistoryPanelView.swift
  - UI/MainWindowView.swift
  - UI/MenuBarPopoverView.swift
  - UI/PreferencesView.swift
  - UI/SearchView.swift
findings:
  critical: 3
  warning: 6
  info: 0
  total: 9
status: clean
fixed_at: 2026-06-25T22:51:00Z
fixed_by: Claude (gsd-code-fixer)
fix_commits:
  CR-01: 1bac6e3
  CR-02: 9ca6af0
  CR-03: 58bc11e
  WR-01: ab9c802
  WR-02: 5378fe6
  WR-03: a127643
  WR-04: a127643
  WR-05: 7bfdda8
  WR-06: b00d248
---

# Phase 01: Code Review Report

**Reviewed:** 2026-06-25
**Depth:** standard
**Files Reviewed:** 63
**Status:** issues_found

## Summary

Phase 01 delivered all seven tools (JSON, Base64, JWT, URL, Timestamp, Hash, UUID), the HistoryStore/GRDB infrastructure, global search, history panel, pinned tool bar, preferences window, workspace window, and the core service layer. The two security-blocking controls — JWT HMAC secret exclusion from history and Hash HMAC key exclusion from history — are correctly implemented: both secrets are `@State` in their respective Views and never reach `onSaveHistory`. The GRDB parameterized query interface is used correctly for search (no SQL interpolation). Transformer purity is maintained: no SwiftUI/AppKit imports appear in any `*Transformer.swift` file or `SearchResultsMerger.swift`. SHA-384 and SHA-512 test vectors are correct. UUID v5 implementation matches the RFC 4122 Python reference vector.

Three blockers are present: a dead "Clear All History" button in Preferences, a multiplied-observer bug in `ClipboardDetector`, and a JSON output corruption bug in the 4-space/tab indent transformation. Six warnings cover a misleading constant-time comment on HMAC verification, an activation-policy leak when only Preferences is opened, an unbounded SQLite store, a disconnected `historyLimit` preference, unescaped LIKE wildcards in history search, and a dead variable in `allHashesText`.

## Critical Issues

### CR-01: "Clear All History" Button in Preferences is Completely Non-Functional

**File:** `UI/PreferencesView.swift:229`
**Issue:** `HistoryPreferencesTab` posts a `Notification.Name("lathe.clearAllHistory")` notification when the destructive button is confirmed. No code anywhere in the project registers an observer for this notification name. The button shows a confirmation dialog, the user confirms, and nothing happens — the history is not cleared. This is a silent data-loss-prevention failure in reverse: the advertised destructive action silently no-ops.

**Fix:** Wire the notification to `HistoryStore.clearUnpinned()`. The cleanest approach uses the injected environment object directly instead of a notification:

```swift
// In HistoryPreferencesTab — add @Environment
@Environment(HistoryStore.self) private var historyStore

// Replace the notification post with a direct call:
Button("Clear History", role: .destructive) {
    historyStore.clearUnpinned()
}
```

Alternatively, add an observer to `HistoryStore.init()` that calls `clearUnpinned()` when it receives `"lathe.clearAllHistory"`.

---

### CR-02: ClipboardDetector.start() Leaks NSNotification Observers on Every Popover Appearance

**File:** `Core/Services/ClipboardDetector.swift:33-48`
**Issue:** `start(registry:)` calls `NotificationCenter.default.addObserver(...)` and stores the token in `observerToken`. It does not remove the previous observer before registering a new one. `MenuBarPopoverView.onAppear` calls `clipboard.start(registry: toolRegistry)` every time the popover is shown. Because `MenuBarExtra(.window)` re-runs `onAppear` each time the popover opens, after `N` popover appearances there are `N` active observers. Each pasteboard change fires the handler `N` times, causing `checkPasteboard` to run redundantly. The old `observerToken` is silently overwritten without calling `NotificationCenter.default.removeObserver`, so those observers are never cleaned up.

**Fix:** Guard against re-registration and remove the previous observer:

```swift
func start(registry: ToolRegistry) {
    // Remove existing observer before re-registering
    if let token = observerToken {
        NotificationCenter.default.removeObserver(token)
        observerToken = nil
    }
    self.registry = registry
    let token = NotificationCenter.default.addObserver(
        forName: NSNotification.Name("NSPasteboardDidChangeNotification"),
        object: nil,
        queue: .main
    ) { [weak self] _ in
        Task { @MainActor [weak self] in
            self?.pasteboardDidChange()
        }
    }
    observerToken = token
}
```

---

### CR-03: JSONTransformer.applyIndent() Corrupts JSON String Values Containing Consecutive Spaces

**File:** `Tools/JSONFormatter/JSONTransformer.swift:96-108`
**Issue:** `applyIndent(_:indent:)` converts `JSONSerialization`'s 2-space indent to 4-space or tab by calling `str.replacingOccurrences(of: "  ", with: "    ")` (or `"\t"`). This is a global string substitution that matches every occurrence of two consecutive spaces — including inside JSON string values. A value like `"some  value"` becomes `"some    value"` in the output. This is a correctness bug: the pretty-printed JSON output is semantically different from the input.

Concrete example: `{"key": "some  double  spaces"}` formatted with 4-space indent produces:
```
{
    "key" : "some    double    spaces"
}
```
The value has been corrupted from `"some  double  spaces"` to `"some    double    spaces"`.

**Fix:** Instead of naive string replacement, reformat the output using a proper indent walk — process the string line-by-line, counting leading spaces and replacing only the leading whitespace prefix:

```swift
private static func applyIndent(_ str: String, indent: Int) -> String {
    guard indent != 2 else { return str }
    let lines = str.components(separatedBy: "\n")
    return lines.map { line in
        let leadingSpaces = line.prefix(while: { $0 == " " }).count
        // JSONSerialization uses exactly 2 spaces per level
        let level = leadingSpaces / 2
        let replacement: String
        switch indent {
        case 4: replacement = String(repeating: "    ", count: level)
        case 0: replacement = String(repeating: "\t", count: level)
        default: return line
        }
        return replacement + line.dropFirst(leadingSpaces)
    }.joined(separator: "\n")
}
```

## Warnings

### WR-01: JWT HMAC Comparison Is Not Constant-Time Despite Comment Claiming It Is

**File:** `Tools/JWT/JWTTransformer.swift:186-196`
**Issue:** The comment at line 186 reads `"CryptoKit constant-time comparison via Data(mac) == sigData"`. This is incorrect. `Data(mac) == sigData` uses Swift's `Data.==` operator, which performs a standard byte-by-byte comparison and returns early on the first mismatch — this is a timing side-channel. Although this is a local offline tool where remote timing attacks are not an immediate threat, the misleading comment could lead future maintainers to believe this code is safe in a higher-threat context. CryptoKit provides `HMAC<SHA256>.isValidAuthenticationCode(_:authenticating:using:)` specifically for constant-time comparison.

**Fix:** Replace `Data(mac) == sigData` with CryptoKit's constant-time API:

```swift
case "HS256":
    return HMAC<SHA256>.isValidAuthenticationCode(sigData, authenticating: messageData, using: key)
case "HS384":
    return HMAC<SHA384>.isValidAuthenticationCode(sigData, authenticating: messageData, using: key)
case "HS512":
    return HMAC<SHA512>.isValidAuthenticationCode(sigData, authenticating: messageData, using: key)
```

---

### WR-02: WindowCoordinator.windowCount Leaks When Only Preferences Is Opened

**File:** `App/WindowCoordinator.swift:31-38` / `UI/PreferencesView.swift`
**Issue:** `WindowCoordinator.openPreferences()` increments `windowCount` to 1. `windowWillClose()` (which decrements `windowCount` and restores `.accessory` activation policy when it hits 0) is called from `MainWindowView.onDisappear`. `PreferencesView` has no `.onDisappear` that calls `windowWillClose()`. After the user opens and then closes Preferences without ever opening the workspace window, `windowCount` stays at 1 and `NSApp.setActivationPolicy(.accessory)` is never restored. The app remains visible in the Dock after the Preferences window closes.

**Fix:** Add `.onDisappear` to `PreferencesView` (or its hosting `Settings` scene body):

```swift
// In PreferencesView.body:
.onDisappear {
    WindowCoordinator.shared.windowWillClose()
}
```

---

### WR-03: HistoryStore SQLite Database Grows Unbounded — No Row Eviction

**File:** `Core/Services/HistoryStore.swift:67-91`
**Issue:** `ValueObservation` fetches 200 rows and trims the in-memory `entries` array to 100 unpinned entries. However, no rows are ever deleted from the SQLite database. After extended use, the database accumulates every transformation the user has ever performed. The `HistoryStore.save()` method inserts without deleting old rows. The `limit(200)` in the query is a display cap only — older rows remain in the DB and will be fetched again if the cap is raised.

**Fix:** After each successful `save()`, trim the database by deleting rows beyond the configured limit. Using a subquery:

```swift
func save(_ entry: HistoryEntry) {
    guard let queue = dbQueue else { return }
    Task.detached(priority: .utility) {
        do {
            try await queue.write { db in
                try entry.insert(db)
                // Evict unpinned rows beyond the 100-item cap
                try db.execute(sql: """
                    DELETE FROM historyEntry
                    WHERE pinned = 0
                    AND id NOT IN (
                        SELECT id FROM historyEntry
                        WHERE pinned = 0
                        ORDER BY timestamp DESC
                        LIMIT 100
                    )
                """)
            }
        } catch {
            print("[HistoryStore] Save failed: \(error)")
        }
    }
}
```

---

### WR-04: historyLimit Preference Has No Effect — Eviction Hardcoded at 100

**File:** `Core/Services/HistoryStore.swift:83` / `Core/Services/PreferencesStore.swift:168-173`
**Issue:** `PreferencesStore.historyLimit` is a user-visible preference exposed in the History Preferences tab, allowing values from 10 to 100. However, `HistoryStore` hardcodes `prefix(100)` in the ValueObservation `onChange` handler and `LIMIT 100` in any eviction SQL. The preference value is stored in UserDefaults but never read by `HistoryStore`. The user sees a slider that appears to configure the history cap but has no observable effect.

**Fix:** Inject the preferences store into `HistoryStore` and read `historyLimit` in the eviction logic:

```swift
// In startObservation:
let unpinned = Array(allEntries.filter { !$0.pinned }.prefix(historyLimit))

// Where historyLimit is read from PreferencesStore or passed at init:
init(historyLimit: Int = 100) { ... }
```

---

### WR-05: GRDB LIKE Pattern Does Not Escape Underscore Wildcard — Search Widens Unexpectedly

**File:** `Core/Services/HistoryStore.swift:168`
**Issue:** `searchAsync(_:)` constructs the LIKE pattern as `"%\(query)%"`. LIKE has two metacharacters: `%` (any sequence) and `_` (any single character). When a user searches for a term containing `_` (e.g., `"base_64"`, `"jwt_token"`, or `"__init__"`), the `_` wildcards broaden the match to any single character at that position. A search for `"_"` matches every row. This is not SQL injection (the value is correctly parameterized), but it is a correctness bug where the search results are broader than expected.

**Fix:** Escape LIKE metacharacters before building the pattern:

```swift
let escaped = query
    .replacingOccurrences(of: "\\", with: "\\\\")
    .replacingOccurrences(of: "%", with: "\\%")
    .replacingOccurrences(of: "_", with: "\\_")
let pattern = "%\(escaped)%"

// And in the GRDB query, specify the escape character:
try HistoryEntry
    .filter(
        Column("tool").like(pattern, escape: "\\") ||
        Column("input").like(pattern, escape: "\\")
    )
```

---

### WR-06: HashViewModel.allHashesText() Contains Dead Code — prefix Variable Is Always Empty String

**File:** `Tools/Hash/HashViewModel.swift:147-156`
**Issue:** `allHashesText(from:)` computes `let prefix = uppercase ? "" : ""` — both branches of the ternary are identical empty strings. `prefix` is then suppressed with `_ = prefix`. The variable was clearly intended to prepend something (perhaps a header or label prefix) to differentiate cases, but the implementation was left with identical branches. This is dead code that silently fails to do what it appears to intend.

**Fix:** Either remove the unused variable entirely, or implement the intended behavior. If no prefix is wanted in either case, simply remove lines 147 and 156:

```swift
func allHashesText(from result: HashTransformer.HashResult) -> String {
    let lines = [
        "MD5:    \(uppercase ? result.md5.uppercased() : result.md5)",
        "SHA-1:  \(uppercase ? result.sha1.uppercased() : result.sha1)",
        "SHA-256:\(uppercase ? result.sha256.uppercased() : result.sha256)",
        "SHA-384:\(uppercase ? result.sha384.uppercased() : result.sha384)",
        "SHA-512:\(uppercase ? result.sha512.uppercased() : result.sha512)",
        "CRC32:  \(uppercase ? result.crc32.uppercased() : result.crc32)",
    ]
    return lines.joined(separator: "\n")
}
```

---

_Reviewed: 2026-06-25_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
