# Pitfalls Research

**Domain:** Native macOS SwiftUI menubar developer-utility app (Flint)
**Researched:** 2026-06-25
**Confidence:** HIGH (all critical claims verified against official Apple docs, community post-mortems, or official package repos)

---

## Critical Pitfalls

### Pitfall 1: MenuBarExtra Has No Programmatic Dismiss API

**What goes wrong:**
SwiftUI's `MenuBarExtra` with `.window` style provides no 1st-party API to close the popover from within its own content. A tool's "Close" or "Esc" key handler calls something, nothing happens, and the popover stays open. Apple Feedback FB10185203 has been open since 2022 and remains unresolved as of macOS 15 Sequoia.

**Why it happens:**
`MenuBarExtra` is a thin SwiftUI scene wrapper around `NSStatusItem`. The underlying `NSWindow` is accessible only through AppKit introspection, which Apple has not surfaced as a public API in SwiftUI.

**How to avoid:**
Add `MenuBarExtraAccess` (orchetect/MenuBarExtraAccess) from day one. It exposes an `isPresented` `Binding<Bool>` and access to the underlying `NSStatusItem`. Wire `Esc` keypress and "Close window" toolbar button to set `isPresented = false`. Do not attempt to replicate this with `@Environment(\.dismiss)` — that modifier does not work for `MenuBarExtra` windows.

Alternative: wrap with `@NSApplicationDelegateAdaptor` and manage `NSStatusItem` + `NSPopover` directly if full control is needed, but this abandons SwiftUI lifecycle management entirely.

**Warning signs:**
- Pressing `Esc` inside the popover has no effect
- "Detach window" → closing the detached window → popover still shows menubar icon as "active"
- Testing on macOS 14 shows modal sheets inside `MenuBarExtra` block dismiss entirely

**Phase to address:** Phase 1 (infrastructure skeleton) — must be solved before any tool UI is built on top of it.

---

### Pitfall 2: Activation Policy Trap When Opening the Preferences / Detached Window

**What goes wrong:**
Menu bar apps run as `.accessory` activation policy — no Dock icon, no App Switcher presence. This means `NSWindow.makeKeyAndOrderFront(nil)` silently succeeds but the window appears *behind* whatever app is currently frontmost. Users see nothing. `SettingsLink` and `openSettings()` environment action fail silently or only work on macOS 15+ (broken on macOS 14, the minimum target).

**Why it happens:**
macOS reserves window elevation rights for apps in `.regular` activation policy. An `.accessory` app's windows are treated as background windows. `openSettings()` additionally requires the SwiftUI render tree to be active — which is not guaranteed in a menubar-only app.

**How to avoid:**
Implement a controlled activation dance when opening Preferences or detaching to a full window:
1. Store the desired operation in a deferred closure.
2. Call `NSApp.setActivationPolicy(.regular)`.
3. Call `NSApp.activate(ignoringOtherApps: true)`.
4. Wait ~100ms (use `DispatchQueue.main.asyncAfter`) for the policy change to propagate.
5. Call `openWindow(id:)` or present the settings window.
6. Register for `NSWindowWillCloseNotification` — when the last non-menubar window closes, restore `.accessory` policy.

Do NOT hardcode whether to show the Dock icon permanently — toggle it only for the duration of the detached window being open. This is the approach documented in steipete's post-mortem on this exact problem (5-hour debugging session).

**Warning signs:**
- Preferences window opens but is hidden under other apps
- `SettingsLink` does nothing when clicked
- `openSettings()` crashes or produces "no window for id" in logs
- Dock icon flashing on/off unpredictably

**Phase to address:** Phase 1 (infrastructure skeleton) — affects global hotkey "focus" behavior and the "open preferences" action.

---

### Pitfall 3: Global Hotkey via CGEventTap Triggers Accessibility Permission Dialog

**What goes wrong:**
Using `CGEventTap` for the global hotkey shows a system dialog: "Flint would like to control your computer using Accessibility features." For a tool with zero legitimate reason to request Accessibility access, this kills the zero-friction promise immediately on first launch.

**Why it happens:**
`CGEventTap` is a system-wide input monitoring mechanism used by screen readers, automation tools, and remote-control software. macOS correctly classifies it as a high-privilege operation requiring user consent under TCC (Transparency Consent and Control).

**How to avoid:**
Use `KeyboardShortcuts` 3.0.1 (sindresorhus/KeyboardShortcuts). It wraps Carbon's `RegisterEventHotKey`, which requires zero permissions, works in sandboxed apps, and is Mac App Store approved. It also ships a `KeyboardShortcuts.Recorder` SwiftUI component, so the configurable hotkey preference UI is effectively free.

Never add CGEventTap for hotkey registration. If a future feature genuinely needs Accessibility (e.g., Services menu input monitoring), request it only when that feature is activated, not on launch.

**Warning signs:**
- System Accessibility permission dialog appears on first launch
- Users report the app "asking for suspicious permissions"
- CI test runner refuses to grant permission → tests that rely on hotkey fail

**Phase to address:** Phase 1 (infrastructure skeleton) — `HotkeyManager.swift` is built here.

---

### Pitfall 4: Cold Start Exceeds 500ms Due to Eager Tool Initialization

**What goes wrong:**
All 12 tool ViewModels are allocated at app startup, the GRDB database is opened synchronously on the main thread, and `NSTextView`-backed editors for JSON and Regex initialize their `NSTextStorage` and `NSLayoutManager` stacks eagerly. Cold start blows past 500ms and the popover opens sluggishly.

**Why it happens:**
SwiftUI's `@StateObject` instantiates immediately when the view body is first evaluated. If the root view contains all tool entries (even hidden ones), every `@StateObject` ViewModel initializer runs synchronously during the first render pass. GRDB's `DatabaseQueue` initialization includes schema migration checks, which involve disk I/O.

**How to avoid:**
- Use lazy `@StateObject` instantiation: only initialize a tool's ViewModel when its view first appears (use `.onAppear` or `LazyVStack`/lazy navigation).
- Move GRDB `DatabaseQueue` open off the main thread: use `Task.detached(priority: .utility)` at app launch, store the queue in a shared actor, and show the popover immediately (history simply loads once ready).
- Avoid any `import WKWebView` at startup — `WKWebView` initialization is expensive (~30ms). Only instantiate it when the Markdown tool is actually opened.
- Profile with Xcode Instruments "App Launch" template before shipping Phase 1.

**Warning signs:**
- Xcode Instruments shows > 200ms of main-thread time during the first render pass
- The popover has a visible "blink" delay after the hotkey press
- `DYLD_PRINT_STATISTICS=1` output shows > 10 dynamic libraries outside the shared cache

**Phase to address:** Phase 1 (infrastructure skeleton) — architectural decision, hard to retrofit.

---

### Pitfall 5: NSViewRepresentable NSTextView Causes Infinite Re-render Loops

**What goes wrong:**
The `NSViewRepresentable` wrapping `NSTextView` (used for JSON editor and Regex tester input) triggers `updateNSView` on every keypress. Inside `updateNSView`, the naive implementation replaces the entire `NSTextAttributedString`, which triggers the text storage delegate, which fires a SwiftUI state update, which calls `updateNSView` again — an infinite loop that freezes the editor within seconds of typing.

**Why it happens:**
`NSViewRepresentable` is a value type. Every SwiftUI body re-evaluation creates a new representable value. The `updateNSView` method is called with the new value, and if it naively sets `textView.string = newValue` unconditionally, it resets cursor position, clears undo history, and triggers re-layout even when the content hasn't changed.

**How to avoid:**
Inside `updateNSView`:
1. Guard against redundant updates: `if textView.string == newValue { return }`.
2. Preserve selection: save `textView.selectedRanges` before the update, restore after.
3. Never set `textView.attributedString` from the update path — only apply syntax highlighting attributes via `NSTextStorageDelegate` on the AppKit side.
4. Post SwiftUI state changes asynchronously from the Coordinator: `DispatchQueue.main.async { self.binding.wrappedValue = newText }` to break the synchronous call cycle.

**Warning signs:**
- Typing in the JSON or Regex editor produces severe lag after a few dozen characters
- CPU pegs at 100% during active typing
- Xcode console shows rapid repeated calls to `updateNSView`
- Undo history randomly disappears

**Phase to address:** Phase 1 (JSON Formatter tool) and Phase 2 (Regex Tester) — critical for any editable `NSTextView`.

---

### Pitfall 6: JWT Segments Must Use Base64url, Not Standard Base64

**What goes wrong:**
Feeding a JWT segment directly to `Data(base64Encoded:)` returns `nil` or corrupted data. The tool shows "Invalid token" for perfectly valid JWTs.

**Why it happens:**
JWT uses base64url encoding (RFC 4648 §5): `+` → `-`, `/` → `_`, and padding (`=`) is stripped. Swift's `Data(base64Encoded:)` uses standard base64 (RFC 4648 §4) and will fail on base64url input containing `-` or `_` characters, or on unpadded strings.

**How to avoid:**
Write a dedicated JWT base64url decoder that:
1. Replaces `-` with `+` and `_` with `/`.
2. Pads the string to a multiple of 4: `let padded = segment + String(repeating: "=", count: (4 - segment.count % 4) % 4)`.
3. Then calls `Data(base64Encoded: padded)`.

Never call `Data(base64Encoded:)` directly on a JWT segment. Add a unit test with a known JWT from jwt.io that contains `-` and `_` in its payload.

**Warning signs:**
- Decoder works for simple JWTs but fails on tokens with non-ASCII claims or binary-adjacent payloads
- `Data(base64Encoded:)` returns `nil` for the header segment

**Phase to address:** Phase 1 (JWT Decoder tool).

---

### Pitfall 7: JWT `exp` Claim Compared in Wrong Timezone

**What goes wrong:**
The expiry countdown shows the wrong time. A token expiring "in 2 hours" is displayed as "already expired" or vice versa.

**Why it happens:**
JWT `exp` is always a Unix timestamp (seconds since 1970-01-01T00:00:00 UTC). If the comparison uses `Date()` but the display formatter is initialized with a local timezone — or if the developer compares `exp` against `Date().timeIntervalSinceReferenceDate` (seconds since 2001-01-01) instead of `timeIntervalSince1970` — the expiry calculation is wrong.

**How to avoid:**
- Always compare `exp` against `Date().timeIntervalSince1970` (not `timeIntervalSinceReferenceDate` — they differ by 978,307,200 seconds).
- Display the expiry date using the user's local timezone for human readability, but the comparison for "expired/valid" must use UTC-based Unix time.
- Add a unit test: create a token with `exp = Int(Date().timeIntervalSince1970) + 3600`, verify the tool shows "Expires in ~1h".

**Warning signs:**
- Expiry displayed as "in 31 years" or "expired 31 years ago" (symptom of `timeIntervalSinceReferenceDate` confusion)
- Expiry is correct in UTC but wrong in some non-UTC local timezones

**Phase to address:** Phase 1 (JWT Decoder tool).

---

### Pitfall 8: Timestamp Tool Auto-Detection Has an Ambiguous Zone

**What goes wrong:**
The "auto-detect seconds vs milliseconds" feature misclassifies some timestamps. A 10-digit number like `9999999999` (year 2286 in seconds) is treated as milliseconds (year 2001), and the user gets a confusing date.

**Why it happens:**
The common heuristic (10 digits = seconds, 13 digits = milliseconds) breaks at the edges: 10-digit values above ~2,000,000,000 (year 2033) or 13-digit values that happen to be small are technically ambiguous. Pydantic's numeric threshold (values outside ±2e10 are treated as ms) is more robust but still has edge cases near the boundary.

**How to avoid:**
- Use digit count as the primary heuristic: 10 digits → seconds, 13 digits → milliseconds.
- Add boundary validation: if 10-digit value > 2,147,483,647 (year 2038 overflow for 32-bit) or > 9,999,999,999 (year 2286), show an ambiguity warning instead of silently converting.
- Never auto-detect for 11 or 12 digit inputs — show a format selector and require explicit confirmation.
- Always show the detected format label (e.g., "Interpreted as: seconds") so the user can correct it.

**Warning signs:**
- 13-digit input shows a date in the 1970s (misclassified as seconds)
- Testing with `1700000000000` (Nov 2023 in ms) produces year 53858 (misclassified as seconds)

**Phase to address:** Phase 1 (Unix Timestamp Converter tool).

---

### Pitfall 9: Hash Generator Blocks the Main Thread on Large Files / Memory Blowup

**What goes wrong:**
Dropping a 500 MB ISO or video file into the Hash tool causes the UI to freeze for several seconds (or crash with OOM) while the app reads the entire file into memory for hashing.

**Why it happens:**
`Data(contentsOf:)` reads the entire file into RAM synchronously. On the main thread, this blocks SwiftUI rendering. CryptoKit's `SHA256.hash(data:)` also accepts `Data`, so the naive implementation is: read file → hash data → display. For a 500 MB file, this allocates 500 MB of heap on the main thread.

**How to avoid:**
- Use streaming hashes: `SHA256()` has an `update(data:)` method that accepts chunks. Read the file in 1 MB chunks using `FileHandle.readData(ofLength:)` in a `Task.detached(priority: .utility)`.
- For CRC32 (via zlib), use `crc32()` iteratively with the same chunked read pattern.
- Show progress: emit percentage complete to the ViewModel via `@Published` from the background task.
- Cap the UI-visible "all hashes simultaneously" feature for text input only; for file hashing, compute one algorithm at a time or in parallel Tasks.
- Display an activity indicator with a Cancel button — CryptoKit operations are not cancellation-aware, so use a `Task` + `task.cancel()` + cooperative `try Task.checkCancellation()` between chunks.

**Warning signs:**
- `Instruments → Allocations` shows a spike matching the file size during hashing
- The app becomes unresponsive (spinning beachball) for files > 50 MB
- Hashing a 1 GB file crashes with memory pressure (`EXC_RESOURCE RESOURCE_TYPE_MEMORY`)

**Phase to address:** Phase 1 (Hash Generator tool).

---

### Pitfall 10: Regex Live Tester Causes UI Hang via Catastrophic Backtracking

**What goes wrong:**
A user types `(a+)+` or `(\w+\s*)+` as a pattern and pastes a 200-character test string without a match. NSRegularExpression's NFA engine backtracks exponentially — the UI hangs for tens of seconds or minutes.

**Why it happens:**
NSRegularExpression uses an NFA (nondeterministic finite automaton) engine. Patterns with nested quantifiers over ambiguous inputs cause exponential backtracking. `(a+)+` against `"aaaaaaaaaaaaaaab"` requires 2^n attempts. The operation runs on the thread where it was invoked — if that is the main thread (or the cooperative thread pool via `Task`), it blocks everything.

**How to avoid:**
- Always run regex matching in a `Task.detached(priority: .userInitiated)` with a timeout: wrap the match call with Swift 6's `withTimeout(seconds: 2.0) { ... }`.
- Since NSRegularExpression does not respond to Swift cooperative cancellation, use a `DispatchWorkItem` with `DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) { workItem.cancel() }` as a hard timeout guard.
- Alternatively, use Swift 5.7+ `Regex` type with `.reluctant` quantifiers — the new Regex engine is a PEG-based engine that does not backtrack catastrophically.
- Display a "Running..." state and a Cancel button that cancels the outer Task.
- Debounce pattern evaluation: do not re-run on every keystroke. Use a 300ms debounce before evaluating.

**Warning signs:**
- Typing a pattern with `+` or `*` inside a group causes the UI to freeze
- Activity Monitor shows Flint pegged at 100% CPU during pattern entry
- No result appears for a valid pattern on a known string that should not match

**Phase to address:** Phase 2 (Regex Tester tool).

---

### Pitfall 11: HMAC / JWT Secret Keys Must Not Be Written to SQLite History

**What goes wrong:**
The history store saves `input` and `output` for every transformation. For the JWT tool, the user supplies an HMAC secret to verify the signature. If the history record's `input` field contains the raw JWT and the secret key, that secret is now persisted in a plaintext SQLite database at `~/Library/Application Support/Flint/history.db` — readable by any process with user-level access.

**Why it happens:**
Generic "save everything" history schema treats all tool inputs identically. A secret key is structurally identical to a string input from the ViewModel's perspective.

**How to avoid:**
Define per-tool history serialization. For the JWT tool and Hash tool (HMAC mode):
- The `HistoryRecord.input` field stores only the JWT string (for JWT) or the text/file path (for Hash).
- The secret key is **explicitly excluded** from the `input` field. Add a code comment in `JWTFormatterViewModel` marking this requirement.
- Never store secrets in `UserDefaults` either — they are world-readable in `~/Library/Preferences/`.
- If a "remember secret" feature is ever added, use the Keychain via `SecItemAdd`/`SecItemCopyMatching` — never SQLite or UserDefaults.

**Warning signs:**
- `sqlite3 ~/Library/Application\ Support/Flint/history.db "SELECT input FROM history WHERE tool='jwt' LIMIT 1"` returns a row containing a secret key
- History panel shows a "Verified with key: mysecret" label that includes the raw key

**Phase to address:** Phase 1 (History store schema design) — the exclusion must be designed into the schema before any tool writes history.

---

### Pitfall 12: Non-Sandboxed Hardened Runtime Notarization Fails Due to Debug Entitlement

**What goes wrong:**
`xcrun notarytool submit` returns: *"The binary is not eligible for notarization. The binary has the 'get-task-allow' entitlement set to true."* The app cannot be distributed.

**Why it happens:**
Xcode's debug configuration injects `com.apple.security.get-task-allow = true` into the entitlements for debugger attachment. This entitlement is incompatible with notarization. It is present in the default `Debug.xcconfig` and developers forget to strip it from the `Release` configuration.

**How to avoid:**
- Maintain two separate entitlements files: `Flint-debug.entitlements` (with `get-task-allow`) and `Flint-release.entitlements` (without it).
- In Xcode Build Settings, set `CODE_SIGN_ENTITLEMENTS` per configuration:
  - Debug → `Flint-debug.entitlements`
  - Release → `Flint-release.entitlements`
- Enable Hardened Runtime in the Release configuration: `ENABLE_HARDENED_RUNTIME = YES`.
- Add `--timestamp` to codesign options in Release: `OTHER_CODE_SIGN_FLAGS = --timestamp`.
- Test notarization on the first Release build of Phase 3, not as an afterthought.

**Warning signs:**
- `codesign -dvvv Flint.app` shows `get-task-allow=1` in the Release build
- `xcrun notarytool submit` returns error code `4000074`
- `spctl -a -v Flint.app` returns "rejected" after stapling

**Phase to address:** Phase 3 (Distribution) — set up the dual entitlements files and CI notarization pipeline.

---

### Pitfall 13: Sparkle EdDSA Key Mismatch Blocks All Future Updates

**What goes wrong:**
After shipping v1.0, an update to v1.1 silently fails. Sparkle logs: *"A public (Ed)DSA key was found in the old bundle but not in the new update."* All users on v1.0 are permanently stuck and cannot auto-update.

**Why it happens:**
Sparkle 2 requires the `SUPublicEDKey` in `Info.plist` to be present in the *new* app bundle, not just the *old* one. The key embedded in v1.0 must match the private key used to sign v1.1's appcast `sparkle:edSignature`. If the keys rotate, if the key is missing from the new bundle, or if `generate_appcast` is not re-run after editing the appcast XML, verification fails silently.

**How to avoid:**
- Generate the EdDSA keypair once via `./bin/generate_keys` (bundled with Sparkle). Store the private key in the CI Keychain or 1Password — **never in the repo**.
- Embed `SUPublicEDKey` in `Info.plist` before shipping v1.0. It must be present in every subsequent update bundle.
- Use `generate_appcast ./releases/` to produce the `appcast.xml` — never hand-edit the XML after running `generate_appcast`, or re-run `generate_appcast` to re-sign.
- Validate the update pipeline with a test v0.0.1 → v0.0.2 cycle locally before the real v1.0 release.

**Warning signs:**
- `appcast.xml` has no `sparkle:edSignature` attribute on the `<enclosure>` element
- Sparkle console log shows "EdDSA signature validation failed"
- `SUPublicEDKey` is absent from `Info.plist` in the Release archive

**Phase to address:** Phase 3 (Auto-update) — must be set up correctly on first Sparkle integration, before v1.0 ships.

---

### Pitfall 14: VoiceOver Cannot Read Custom NSViewRepresentable Controls

**What goes wrong:**
VoiceOver announces "group" or nothing for the `NSTextView`-backed JSON editor, the syntax-highlighted output panels, and the bit-field toggle buttons in the Number Base tool. The accessibility audit fails and the acceptance criterion ("VoiceOver labels on all interactive elements") is not met.

**Why it happens:**
When an AppKit control is wrapped in `NSViewRepresentable`, SwiftUI's automatic accessibility passthrough does not apply. The SwiftUI modifiers `.accessibilityLabel()` and `.accessibilityHint()` are applied to the *wrapper struct*, but the wrapped `NSView` needs its own `accessibilityLabel()` override or the `NSAccessibility` protocol implementation. Without explicit AppKit-side labels, VoiceOver reads the raw class name.

**How to avoid:**
For every `NSViewRepresentable`:
- In `makeNSView`, call `nsView.setAccessibilityLabel("JSON input editor")` and `nsView.setAccessibilityRole(.textArea)`.
- For `NSTextView` wrappers: also set `nsView.setAccessibilityPlaceholderValue("Paste JSON here")`.
- For custom bit-field buttons (Number Base tool): subclass `NSButton` and override `accessibilityLabel()` to return `"Bit \(position): \(isOn ? "1" : "0")"`.
- Do not rely solely on `.accessibilityLabel()` on the SwiftUI side of a `NSViewRepresentable` — it may not propagate into the NSView's accessibility tree on macOS 14.
- Run `Accessibility Inspector.app` (in Xcode's Developer Tools) against every `NSViewRepresentable` before marking it done.

**Warning signs:**
- VoiceOver announces "group" instead of the control's purpose
- `Accessibility Inspector` shows empty `AXLabel` or `AXDescription` for the text view
- `AXRole` shows "AXGroup" instead of "AXTextArea" or "AXButton"

**Phase to address:** Phase 1 for `NSTextView` wrappers; Phase 2 for bit-field buttons and Color swatch controls.

---

### Pitfall 15: OKLCH Values Outside sRGB Gamut Produce Invalid NSColor

**What goes wrong:**
User inputs an OKLCH color like `oklch(0.9 0.4 150)` (high chroma green). The converter shows a clipped or wrong HEX value. `NSColor` initialized with out-of-gamut values silently clamps components to 0–1 in sRGB, altering the displayed color without warning.

**Why it happens:**
OKLCH's chroma axis is not bounded by sRGB. Chroma values above ~0.37–0.4 (hue-dependent) exceed the sRGB gamut. ChromaKit performs the math correctly but the resulting `NSColor` in the sRGB colorspace will have its components clamped by Core Graphics.

**How to avoid:**
- After converting OKLCH → sRGB, check if any component exceeds [0, 1]: if `r > 1 || g > 1 || b > 1 || r < 0 || g < 0 || b < 0`, display an out-of-gamut warning badge ("Out of sRGB gamut — values clamped").
- Use `NSColor(colorSpace: NSColorSpace.extendedSRGB, components: [r, g, b, a], count: 4)` to preserve out-of-gamut values for display in P3 on capable screens.
- For the HEX output, clamp to sRGB and mark it as approximate.
- Round OKLCH output values to a reasonable precision (L: 3dp, C: 4dp, H: 2dp) to avoid floating-point noise like `oklch(0.8999999 0.37000001 149.99998)`.

**Warning signs:**
- HEX output for a wide-gamut input differs from reference tools like oklch.com by more than ±1 hex digit per channel
- Color swatch shows a visually different color from the input OKLCH value
- `NSColor` component values printed in the console show exactly 1.0 or 0.0 where a non-round value was expected

**Phase to address:** Phase 2 (Color Converter tool).

---

### Pitfall 16: Number Base Converter Two's Complement Overflow with Signed / Bit-Width Changes

**What goes wrong:**
User sets bit-width to 8, inputs decimal `200` in signed mode. The tool shows `-56` instead of an overflow error. When the user changes bit-width from 8 to 16 mid-edit, the binary representation silently changes without explanation.

**Why it happens:**
Swift's `Int8(bitPattern: UInt8(200))` produces `-56` via two's complement wrap, which is mathematically correct — but the UI should communicate that 200 exceeds the signed 8-bit range (127 max). Bit-width changes affect sign extension: an 8-bit `0xFF` (−1 in signed) becomes `0x00FF` (+255) in 16-bit unsigned, which is a semantic change.

**How to avoid:**
- Maintain a canonical `UInt64` internal representation and derive all display values from it.
- Before displaying signed interpretation: check if the value exceeds the signed maximum for the selected bit-width (`(1 << (width-1)) - 1`). If so, show an overflow indicator (red text, warning icon).
- When changing bit-width, truncate (drop high bits) for narrowing conversions and zero-extend for widening — document this behavior in the UI with a tooltip.
- Use `FixedWidthInteger.init(truncatingIfNeeded:)` for the truncation, not `Int(exactly:)` which throws.

**Warning signs:**
- `200` in 8-bit signed shows `-56` with no warning
- Switching from 8-bit to 16-bit changes the binary value displayed without any visual cue
- Hex input `0xFF` in 8-bit unsigned converts to a different value than expected in signed mode

**Phase to address:** Phase 2 (Number Base Converter tool).

---

### Pitfall 17: UUID v7 Timestamp Extraction Requires Exact Bit-Mask Logic

**What goes wrong:**
The UUID v7 inspector displays the wrong timestamp, off by a factor of ~1000 (seconds displayed instead of milliseconds) or shows an epoch date (1970-01-01) due to extracting the wrong bits.

**Why it happens:**
UUID v7 (RFC 9562) stores a 48-bit Unix timestamp in milliseconds in the most-significant 48 bits (bytes 0–5). Bytes 6–7 contain the 4-bit version (0x7) in the high nibble and a 12-bit random sequence. A common mistake is extracting all 64 bits of the first two 32-bit words and not masking off the version nibble. Another mistake is treating the timestamp as seconds rather than milliseconds.

**How to avoid:**
```
let uuid_bytes: [UInt8] = withUnsafeBytes(of: uuid.uuid) { Array($0) }
let ms: UInt64 = (UInt64(uuid_bytes[0]) << 40)
               | (UInt64(uuid_bytes[1]) << 32)
               | (UInt64(uuid_bytes[2]) << 24)
               | (UInt64(uuid_bytes[3]) << 16)
               | (UInt64(uuid_bytes[4]) << 8)
               | UInt64(uuid_bytes[5])
// ms is the millisecond-precision Unix timestamp
let date = Date(timeIntervalSince1970: Double(ms) / 1000.0)
```
- Add a unit test: generate a UUID v7 at a known time, extract the timestamp, verify it matches within 1ms.
- Reject extraction attempts on v1/v4/v5 UUIDs — only v1 and v7 embed timestamps, and v1's timestamp uses a different encoding (100ns intervals since Oct 15, 1582 Gregorian).

**Warning signs:**
- UUID v7 inspector shows year 1970 for a freshly generated UUID
- Timestamp is off by exactly 1000x (seconds/milliseconds confusion)
- UUID v1 and v7 produce identical extracted dates for different UUIDs generated milliseconds apart

**Phase to address:** Phase 1 (UUID Generator & Inspector tool).

---

### Pitfall 18: Clipboard Auto-Detection NSPasteboard Polling Drains Battery

**What goes wrong:**
The clipboard auto-detect feature polls `NSPasteboard.general.changeCount` every 200–500ms. On battery, this produces 3–7% sustained CPU load, prevents the CPU from entering low-power C-states, and drains the battery noticeably. Users running macOS Activity Monitor will see Flint listed as a top CPU consumer even when idle.

**Why it happens:**
macOS provides no native push notification for clipboard changes. The industry standard fallback is polling `changeCount`. At 500ms intervals, this adds CPU wakeups and prevents idle states.

**How to avoid:**
- Use event-driven detection instead of a polling timer: observe `NSNotification.Name("NSPasteboardDidChangeNotification")` — this is a private but stable notification that fires on clipboard change without polling overhead (verified: 0% CPU when idle).
- Alternatively, limit polling to only when the Flint popover is visible: start the polling timer in `onAppear` and stop it in `onDisappear`. This reduces the background overhead to zero when the app is not in use.
- The PRD's 100ms detection target is achievable with a 100ms polling interval only when the window is visible, or immediately via the NSNotification approach.

**Warning signs:**
- `top -l 1 -stats pid,cpu | grep Flint` shows > 1% CPU when Flint popover is closed
- Battery usage report in System Settings lists Flint as a significant consumer
- Instruments "Energy Log" shows high wake activity from Flint's background timer

**Phase to address:** Phase 1 (ClipboardDetector.swift) — the polling/notification strategy must be decided at implementation time.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| `Data(base64Encoded: segment)` directly on JWT segments | Saves 3 lines | Silently returns nil for valid tokens with URL-safe characters; user sees "Invalid token" | Never |
| Polling NSPasteboard at 500ms globally (not just when visible) | Simpler code | Sustained ~5% CPU on battery; bad App Store review for v2 | Never for a menubar app |
| `try! DatabaseMigrator().migrate(db)` on first launch | Saves error handling | Crash on first launch if DB is already open or disk is full | Never |
| Storing HMAC/JWT secret in history record | Consistent schema | Credential leak to disk | Never |
| `NSApp.setActivationPolicy(.regular)` permanently | No activation dance code | Permanent Dock icon defeats "quiet menubar" UX promise | Never (use transient toggle) |
| `NSRegularExpression` matching on main thread | Simpler code | Single catastrophic pattern hangs the entire app | Never for live testers |
| Instantiating all 12 ViewModels at startup | Simpler dependency graph | 200–400ms cold-start overhead | Never without lazy init |
| `WKWebView` instantiated at startup | Instant first render | ~30ms overhead on launch even before Markdown tool is used | Defer to first use |
| Hard-coded `com.apple.security.get-task-allow` in a single entitlements file | Simpler config | Notarization fails for Release builds | Never |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Sparkle appcast | Hand-editing `appcast.xml` to add release notes after `generate_appcast` ran | Always re-run `generate_appcast` after any XML edits — it re-signs the file |
| GRDB with Swift 6 | Accessing `DatabaseQueue` from `@MainActor` functions with `.write { }` calls on the main thread | Use `try await dbQueue.write { db in ... }` from async contexts; mark record types `Sendable` |
| MenuBarExtraAccess | Adding it after building all tool views | Evaluate before building tool UIs — it affects the `isPresented` binding available to all child views |
| NSColorSampler + popover | Calling `NSColorSampler().show()` while the MenuBarExtra popover is key window | `NSColorSampler` dismisses the calling window; dismiss the popover first, then show the sampler |
| WKWebView + PDF export | Using `print(info:)` instead of `createPDF(configuration:)` | `print()` opens a system dialog; `createPDF(configuration:completionHandler:)` produces data silently |
| CryptoKit HMAC | Using `HMAC<SHA256>.authenticationCode(for: Data(key.utf8), using: SymmetricKey(data: ...))` with key as Data | SymmetricKey must wrap the raw key bytes, not the Data representation of the key string |
| KeyboardShortcuts + Settings | Registering the shortcut name in `KeyboardShortcuts.Name` at module level | Must call `.onKeyDown(for:)` only after the app is fully initialized, not in `init()` |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Synchronous GRDB open on main thread | Launch stutter; history loads 200ms after popover appears | Open `DatabaseQueue` in `Task.detached(priority: .utility)` at app init | Day 1 if not addressed |
| Naive NSTextView `updateNSView` | Typing lag after ~50 characters; CPU 100% | Guard with `if textView.string == newValue { return }` | With any non-trivial JSON or Regex input |
| `Data(contentsOf: largeFile)` on main thread | Beachball on files > 50 MB | Chunked async read via `FileHandle` in `Task.detached` | Any file > ~20 MB |
| Regex NFA catastrophic backtracking | UI hang lasting seconds to minutes | Background Task with 2s timeout; use Swift `Regex` for new patterns | Any ambiguous nested-quantifier pattern |
| WKWebView cold init | +30ms on Markdown tool first open | Lazy-init on first view appearance, not at app start | At app startup if eagerly allocated |
| Syntax highlighting entire document on each keypress | Keypress lag in large JSON documents | Highlight only dirty range via `NSTextStorageDelegate.textStorage(_:didProcessEditing:range:changeInLength:)` | Documents > ~5 KB |
| SwiftDiff on full document (not per-line) | Diff tab hangs on texts > 10 KB | Use `CollectionDifference` for line-level; SwiftDiff only within single changed lines | Texts > ~2000 characters |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Persisting HMAC/JWT secrets to SQLite history | Secret keys readable by any process with user access; leaks credentials if DB is shared/backed up | Exclude secret fields from history serialization at the ViewModel layer |
| Storing secrets in `UserDefaults` "for convenience" | Same risk as SQLite but plist format means it may be uploaded to iCloud backup automatically | Use macOS Keychain (`SecItemAdd`) for any secret the user opts to save |
| `get-task-allow` entitlement in Release build | Notarization rejected; if somehow distributed, allows debugger attach from other processes | Dual entitlements files per build configuration |
| Loading a `WKWebView` with user-supplied HTML without sanitization | If Markdown tool outputs unsanitized user HTML via `<script>` tags, XSS in the web view | Use `swift-markdown`'s AST → controlled HTML emission; do not pass raw user input as HTML. Disable JavaScript in the `WKWebViewConfiguration` unless required |
| Regex pattern from clipboard auto-detect executed without sandboxing | Malformed clipboard content could trigger a ReDoS in auto-detection heuristics | The clipboard detection heuristics must use simple, safe patterns (anchored prefix checks, not greedy) |

---

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| History stores secret keys alongside tool input | User shares history export and leaks credentials | Strip secrets from history records by design (see Pitfall 11) |
| Auto-detecting "Base64" for too many inputs (e.g., short strings) | Wrong tool suggested constantly; users disable the feature | Require minimum length (> 12 chars) and proper character-set validation before suggesting Base64 |
| Clipboard detection banner interrupts typing | User is in the middle of typing, banner steals focus | Show banner as non-interactive overlay only; never steal key focus |
| Esc closes popover when the user intended to dismiss a modal sheet | Unexpected behavior; partial work lost | Capture Esc in child sheets first; propagate to popover dismiss only if no sheet is active |
| Regex tester shows no feedback during long match | User thinks app is broken; forcequits | Show "Matching..." spinner immediately on pattern change; show Cancel button after 500ms |
| OKLCH values silently clamped with no warning | Designer uses tool, copies "wrong" HEX, ships broken colors | Show out-of-gamut badge on the color swatch |

---

## "Looks Done But Isn't" Checklist

- [ ] **JWT Decoder:** Uses base64url decoding (not standard base64) for all three segments — verify with a token containing `-` or `_`
- [ ] **JWT Decoder:** `exp` comparison uses `Date().timeIntervalSince1970` (not `timeIntervalSinceReferenceDate`) — unit test with known token
- [ ] **History store:** JWT HMAC key and Hash HMAC key are NOT present in any `HistoryRecord.input` field — check via `sqlite3` CLI
- [ ] **Hardened Runtime:** Release build entitlements do NOT contain `com.apple.security.get-task-allow` — verify with `codesign -dvvv`
- [ ] **MenuBarExtra dismiss:** Pressing `Esc` inside the popover closes it — manual test
- [ ] **Preferences window:** Opens in front of other apps on macOS 14 (not just 15) — test with `.accessory` activation policy active
- [ ] **Hash Generator:** Hashing a 200 MB file does not freeze the UI or crash — test with `dd if=/dev/urandom of=/tmp/test.bin bs=1m count=200`
- [ ] **Regex Tester:** Entering `(a+)+` with `"aaaaaaaaab"` does not hang the app for more than 2s — test immediately
- [ ] **Sparkle appcast:** `sparkle:edSignature` present in `appcast.xml` `<enclosure>` — inspect XML before releasing
- [ ] **UUID v7 inspector:** Extracted timestamp matches the generation time within 1ms — unit test
- [ ] **OKLCH converter:** Out-of-gamut values show a warning badge — test with `oklch(0.9 0.4 150)`
- [ ] **VoiceOver:** All NSViewRepresentable wrappers have non-empty AXLabel in Accessibility Inspector

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| MenuBarExtra no-dismiss API | LOW (add dep early) | Add `MenuBarExtraAccess` package; wire `isPresented` binding; 1-2 hours |
| Activation policy window ordering | MEDIUM (timing-sensitive) | Implement activation dance (policy toggle + delayed window open); test on macOS 14 specifically; 4-8 hours |
| JWT base64url bug shipped | LOW | Fix 3-line decoder, ship patch; no data migration needed |
| Secrets persisted in history DB | HIGH | Requires DB migration to drop/redact affected rows; user communication required |
| Notarization fails (get-task-allow) | LOW (if caught in CI) | Add dual entitlements; rebuild Release; resubmit; 2-4 hours |
| Notarization fails (shipped v1.0 missing SUPublicEDKey) | CRITICAL | All v1.0 users cannot auto-update ever; must ship v1.1 as manual download with correct key |
| NSTextView re-render loop | MEDIUM | Add guard to `updateNSView`; test with large inputs; 2-4 hours |
| Hash file OOM crash | MEDIUM | Replace `Data(contentsOf:)` with chunked `FileHandle` reader; refactor ViewModel to publish progress |
| Regex hang shipped | HIGH | Hot-patch with background task + 2s timeout; interim: disable live-update for complex patterns |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| MenuBarExtra no-dismiss API | Phase 1 (skeleton) | Manual Esc key test in popover |
| Activation policy / window ordering | Phase 1 (skeleton) | Open Preferences on macOS 14 VM with other app frontmost |
| CGEventTap Accessibility dialog | Phase 1 (HotkeyManager) | First launch: no permission dialog appears |
| Cold start > 500ms | Phase 1 (skeleton + lazy init) | Instruments App Launch template; measure 10 cold starts |
| NSTextView re-render loops | Phase 1 (JSON Formatter) | Type 200 chars; CPU must stay < 10% |
| JWT base64url / exp timezone | Phase 1 (JWT Decoder) | Unit tests with known token vectors |
| Timestamp seconds/ms ambiguity | Phase 1 (Timestamp Converter) | Test 10-digit, 13-digit, 11-digit boundary inputs |
| Hash file blocking + OOM | Phase 1 (Hash Generator) | Hash a 200 MB file; UI must remain responsive |
| History secret key leakage | Phase 1 (HistoryStore schema) | `sqlite3` query after JWT verification session |
| Clipboard battery drain | Phase 1 (ClipboardDetector) | Instruments Energy log; idle Flint must show < 1% CPU |
| NSViewRepresentable VoiceOver gaps | Phase 1 + Phase 2 | Accessibility Inspector AXLabel check on each wrapper |
| Regex catastrophic backtracking | Phase 2 (Regex Tester) | `(a+)+` against non-matching string must timeout, not hang |
| OKLCH gamut clipping | Phase 2 (Color Converter) | High-chroma OKLCH input shows gamut warning |
| Number base two's complement overflow | Phase 2 (Number Base Converter) | `200` in 8-bit signed must show overflow indicator |
| UUID v7 timestamp extraction | Phase 1 (UUID Inspector) | Unit test: generate + extract within 1ms tolerance |
| Notarization get-task-allow | Phase 3 (Distribution) | `codesign -dvvv` on Release archive; `notarytool submit` passes |
| Sparkle EdDSA key mismatch | Phase 3 (Auto-update) | Test v0.0.1 → v0.0.2 update locally before v1.0 |
| WKWebView XSS in Markdown | Phase 2 (Markdown Previewer) | Paste `<script>alert(1)</script>` in Markdown input; no alert fires |

---

## Sources

- Apple Feedback FB10185203 (MenuBarExtra no dismiss API): https://github.com/feedback-assistant/reports/issues/383
- MenuBarExtraAccess (orchetect): https://github.com/orchetect/MenuBarExtraAccess
- Peter Steinberger — "Showing Settings from macOS Menu Bar Items: A 5-Hour Journey" (2025): https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items
- Michael Tsai — Settings from Menu Bar Items (commentary): https://mjtsai.com/blog/2025/06/18/showing-settings-from-macos-menu-bar-items/
- Swift Forums — Pitch: base64 urlencoding options (confirms Data(base64Encoded:) does not handle base64url natively): https://forums.swift.org/t/pitch-adding-base64-urlencoding-and-omitting-padding-options-to-base64-encoding-and-decoding/77659
- Pydantic Issue #7940 — timestamp seconds vs milliseconds ambiguity: https://github.com/pydantic/pydantic/issues/7940
- Apple Developer Forums — NSViewRepresentable NSTextView state update loops: https://developer.apple.com/forums/thread/749620
- Snyk — ReDoS and Catastrophic Backtracking: https://snyk.io/blog/redos-and-catastrophic-backtracking/
- rexegg.com — Catastrophic Backtracking (NFA engine behavior): https://www.rexegg.com/regex-explosive-quantifiers.php
- Sparkle documentation — EdDSA signing: https://sparkle-project.org/documentation/
- Sparkle Discussion #2597 — EdDSA DMG signing pitfalls: https://github.com/sparkle-project/Sparkle/discussions/2597
- Apple — Reducing App Launch Time: https://developer.apple.com/documentation/xcode/reducing-your-app-s-launch-time
- NSPasteboard polling vs NSNotification CPU comparison: https://discussions.apple.com/thread/2661580
- OKLCH gamut mapping (CSS Color Level 4): https://colorjs.io/docs/gamut-mapping
- Evil Martians — OKLCH in CSS (gamut behavior): https://evilmartians.com/chronicles/oklch-in-css-why-quit-rgb-hsl
- Nathan Dudfield — UUID v7 in Swift: https://nathandud.github.io/2024/08/22/uuidv7-swift/
- Apple — Hardened Runtime and Notarization: https://eclecticlight.co/2021/01/07/notarization-the-hardened-runtime/
- Apple — Customizing the Notarization Workflow (notarytool): https://developer.apple.com/documentation/security/customizing-the-notarization-workflow
- objc.io — String to Data and Back (force-unwrap UTF-8 risk): https://www.objc.io/blog/2018/02/13/string-to-data-and-back/
- GRDB concurrency (Swift 6 discussion): https://github.com/groue/GRDB.swift/discussions/1509
- Multi.app — Pushing the limits of NSStatusItem (MenuBarExtra sizing): https://multi.app/blog/pushing-the-limits-nsstatusitem

---
*Pitfalls research for: Flint — native macOS SwiftUI menubar developer-utility app*
*Researched: 2026-06-25*
