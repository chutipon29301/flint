# Phase 4: UX Improvement - Research

**Researched:** 2026-06-29
**Domain:** SwiftUI macOS navigation patterns, Accessibility framework, Sparkle delegate API, keyboard event synthesis
**Confidence:** HIGH (core APIs verified) / MEDIUM (Sparkle delegate edge behavior) / LOW (polling timeout interval)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **CF-01:** Never crash / never freeze on bad input; cold start < 500ms, hotkey-to-popover < 200ms. No new work may regress the cold-start budget.
- **CF-02:** Zero-friction core value — no Accessibility permission prompt at install / hotkey-use. The only sanctioned exception is behind an explicit, default-off opt-in (D-09).
- **CF-03:** Reuse existing substrate — `ToolRegistry` (FROZEN), `ToolSeed`, `WarningBannerView`, `WindowCoordinator`, `DetectionBannerView`. Do not rebuild.
- **D-01:** Grid of all 12 tools + back button at root launcher. Keep existing 6-pinned row and recent history. Grouping vs flat is Claude's discretion.
- **D-02:** Consistent back-to-picker affordance inside every tool. One-action return to tool-selection screen from any of the 12 tools.
- **D-03:** Wire a "Check for Updates…" button in Preferences that calls `sparkle.checkForUpdates()`. This is the actual fix — method exists and works, just never surfaced.
- **D-04:** Credential/config tasks are release-gated. Phase 4 verifies the check completes and reports correctly (up-to-date / update available / clear error). Placeholder feed must surface as a clear error, never silent failure.
- **D-05:** Consistency pass, not a redesign — spacing, type scale, color, iconography, empty/loading states, Light/Dark across existing layouts.
- **D-06:** Refine existing `OnboardingWindowView` (Phase 3 D-07) — do not rebuild. Surface: global hotkey (⌘⇧Space), Services menu, drag-and-drop, clipboard auto-detect.
- **D-07:** Arrow-key navigation in search results only. ↑/↓ highlight, Return opens. Scope: search results only (grid stays mouse/tab-driven this phase).
- **D-08:** ⌘1…⌘9 select a numbered output row. Shows a small number badge next to each copyable output. ⌘N copies output row N to clipboard. Tools with single output: ⌘1 copies it.
- **D-09:** Separate copy-and-paste action, default-off Preferences toggle. Enable UX: prompt-on-enable. Toggle ON → synthetic ⌘V paste-back requiring Accessibility permission. If denied, toggle reverts.

### Claude's Discretion
- Grid grouping vs flat layout, exact back-affordance glyph/placement, number-badge visual style, exact key bindings for copy (⌘N) vs copy-and-paste (⌘⇧N / Return), onboarding copy/layout/illustration, all spacing/type/color tokens, whether to substitute real Sparkle key + production feed URL in this phase or keep as pre-release task.

### Deferred Ideas (OUT OF SCOPE)
- Arrow/keyboard navigation in the all-tools grid (D-01) — search results only for D-07.
- `/gsd:ui-phase` designed visual system — consistency pass chosen instead.
- Quick-switcher overlay / more visible ⌘]/⌘[ affordance.
</user_constraints>

---

## Summary

Phase 4 has five threads: (1) navigation defect — expose all 12 tools + back affordance; (2) update-checker defect — wire the already-implemented `checkForUpdates()` and surface result states; (3) visual consistency pass; (4) onboarding refinement; (5) keyboard-only loop (the headline: ⌘1…⌘9 copy output rows, optional paste-back via D-09).

The dominant technical question is **OQ-01**: whether a synthetic-paste path exists without Accessibility permission. Research confirms definitively: **no**. All paths that synthesize `⌘V` into another process — `CGEvent.post()`, AppleScript `keystroke`, or any event-injection mechanism — require macOS Accessibility permission (`kTCCServicePostEvent`). This is enforced by TCC on macOS 14 for non-sandboxed and sandboxed apps alike. D-09's default-off + opt-in + prompt-on-enable design is therefore confirmed correct and necessary.

The secondary finding on Sparkle (D-03/D-04) is that with a `localhost` feed URL the check will abort via `updater:didAbortWithError:` (network/connection error) and additionally (or alternatively) `updater:didFinishUpdateCycleForUpdateCheck:error:` with a non-nil error. The implementation must wire `updaterDelegate` on `SPUStandardUpdaterController` and translate these callbacks into a clear status message in PreferencesView.

The keyboard flow (D-07/D-08) extends the existing `NotificationCenter` broadcast pattern: a new `.selectOutputRow(index:)` notification carries the row index (1-9); tool views observe it and copy the indexed output. The existing `escMonitor` (local NSEvent monitor) and `SearchView.onKeyPress` coexist cleanly because `.onKeyPress` fires on the focused SwiftUI subtree while the local NSEvent monitor covers global popover-level events.

**Primary recommendation:** Implement in wave order — navigation + Sparkle status wiring first (highest defect value), then ⌘N row-copy infrastructure, then polish/onboarding, then D-09 paste-back as the last, most isolated opt-in feature.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| All-tools grid (D-01) | Frontend / SwiftUI popover | — | Pure UI: iterates `toolRegistry.tools`, sets `navigationState`. No data layer. |
| Back-to-picker (D-02) | Frontend / SwiftUI popover | — | `navigationState = .root` is a popover-level state mutation; can wrap `tool.makeView()` in a common header. |
| Update check button (D-03) | Frontend / PreferencesView + SparkleUpdaterService | — | `SparkleUpdaterService.checkForUpdates()` already exists; Preferences calls it and observes delegate callbacks. |
| Update result reporting (D-04) | SparkleUpdaterService (delegate callbacks) | PreferencesView (status display) | Sparkle delegate is service-layer; status string is surfaced in UI via `@Observable` published state. |
| Keyboard ⌘1–⌘9 row copy (D-08) | Frontend / MenuBarPopoverView (shortcut) → Tool views (observer) | — | Hidden button in `.background()` broadcasts `.selectOutputRow(index:)`; tool view observes and copies. Mirrors existing `.copyOutput` pattern. |
| Paste-back toggle + permission (D-09) | PreferencesStore (pref) + PreferencesView (toggle UX) + tool copy path (action) | macOS Accessibility (TCC) | Permission gate belongs in the preference-enable flow; the paste action belongs in the output-copy path when pref is enabled. |
| Arrow nav in search (D-07) | SearchView (`@State selectedIndex` + `.onKeyPress`) | — | Already partially implemented; `selectedIndex` and `.onKeyPress` are already in `SearchView.swift`. |
| Visual consistency (D-05) | All tool views + launcher | — | CSS-analog: spacing, typography, color tokens as constants. No logic change. |
| Onboarding refinement (D-06) | OnboardingWindowView | — | Extend existing view; adds Service / drag-drop / clipboard-detect callout blocks. |
| Previously-focused app capture (D-09) | SparkleUpdaterService / new PasteBackService | NSWorkspace | Must capture `NSWorkspace.shared.frontmostApplication` BEFORE the popover opens (in HotkeyManager) and store for use after dismiss. |

---

## Standard Stack

No new packages are required for this phase. All implementation uses existing dependencies and system frameworks.

### System Frameworks Used This Phase

| Framework | Version | Purpose | Source |
|-----------|---------|---------|--------|
| ApplicationServices / AXUIElement | macOS 14.0+ | `AXIsProcessTrustedWithOptions` — Accessibility permission check + prompt (D-09) | [CITED: developer.apple.com/documentation/applicationservices] |
| CoreGraphics / CGEvent | macOS 14.0+ | `CGEvent(keyboardEventSource:virtualKey:keyDown:)` + `.post(tap:)` — synthetic ⌘V (D-09, when Accessibility granted) | [CITED: developer.apple.com/documentation/coregraphics/cgevent] |
| AppKit / NSWorkspace | macOS 14.0+ | `NSWorkspace.shared.frontmostApplication` — capture previously-focused app before popover (D-09) | [CITED: developer.apple.com/documentation/appkit/nsworkspace/frontmostapplication] |
| AppKit / NSRunningApplication | macOS 14.0+ | `.activate(options:)` — re-activate previously-focused app before synthetic paste (D-09) | [CITED: Apple developer docs] |
| Sparkle 2.9.3 (existing) | 2.9.3 | `SPUUpdaterDelegate` callbacks for result reporting (D-03/D-04) | [CITED: sparkle-project.org/documentation/api-reference] |
| SwiftUI (existing) | macOS 14.0+ | `LazyVGrid`, `.onKeyPress`, `@State`, `NavigationStack` (not used) | [ASSUMED — based on existing codebase patterns] |
| NotificationCenter (existing) | Foundation | `.selectOutputRow(index:)` new notification; mirrors `.copyOutput` pattern | [VERIFIED: existing codebase] |

### No New SPM Packages

The Package Legitimacy Audit is **SKIPPED** — no new external packages are added in this phase. All capabilities use system frameworks or existing packages (Sparkle 2.9.3, KeyboardShortcuts 3.0.1, GRDB 7.11.1).

---

## OQ-01 Research: Synthetic Paste and Accessibility Permission

This is the critical research question from CONTEXT.md. All three sub-questions answered definitively.

### OQ-01(a): Is there ANY synthetic-paste path that does NOT require Accessibility permission?

**Verdict: NO. All synthetic-paste paths require Accessibility permission.** [VERIFIED: multiple Apple Developer Forum sources + TCC documentation]

The complete list of approaches and their permission requirements:

| Approach | Permission Required | Notes |
|----------|-------------------|-------|
| `CGEvent.post(tap: .cgSessionEventTap)` with keyboard events | **Accessibility (kTCCServicePostEvent)** | Confirmed on macOS 14. TCC enforces this for non-sandboxed apps too. |
| `CGEvent.postToPid(_:)` targeting a specific PID | **Accessibility (kTCCServicePostEvent)** | Same TCC gate as `.post()`. |
| AppleScript `tell application X` / `keystroke "v" using command down` | **Accessibility** | Requires app in Accessibility list. |
| NSAppleScript + keystrokes | **Accessibility** | Same as AppleScript path. |
| Writing to NSPasteboard then calling the paste action | Only clipboard access — BUT CANNOT TRIGGER THE PASTE | Writing to the pasteboard is permission-free; the user still has to press ⌘V. Not a synthetic-paste path. |
| `NSPasteboard.general.setString(...)` | No permission | This writes the value to the clipboard, which is what copy-only (D-09 default OFF) already does. The user then presses ⌘V manually. |

**Why it crosses the line:** On macOS 14, `CGEvent` event posting requires that the sending process have the Accessibility access listed under System Settings > Privacy & Security > Accessibility. macOS enforces this via TCC (`kTCCServicePostEvent`). This applies to non-sandboxed apps. The Console will show "Sender is prohibited from synthesizing events" if tried without permission.

**Implication for D-09:** The default-off design is mandatory. The copy-only path (toggle OFF) uses only `NSPasteboard.general.setString(...)` — zero permissions required. The paste-back path (toggle ON) synthesizes `⌘V` via `CGEvent` and MUST be gated behind Accessibility permission. D-09's design is confirmed correct. [VERIFIED: Apple Developer Forums thread/724603, blog.kulman.sk/implementing-auto-type-on-macos/]

### OQ-01(b): Exact API to request Accessibility permission on demand and observe if granted

**Step 1 — Check current status (no prompt):**

```swift
// Source: Apple ApplicationServices framework [CITED: developer.apple.com]
import ApplicationServices

func isAccessibilityGranted() -> Bool {
    return AXIsProcessTrusted()
}
```

**Step 2 — Request permission with prompt (prompt-on-enable UX):**

```swift
// Source: Apple ApplicationServices framework [CITED: developer.apple.com]
// AXIsProcessTrustedWithOptions returns Bool AND triggers the System Settings prompt.
@discardableResult
func requestAccessibilityPermission() -> Bool {
    let options: NSDictionary = [
        kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
    ]
    return AXIsProcessTrustedWithOptions(options)
}
```

Calling this opens "System Settings > Privacy & Security > Accessibility" and shows the app in the list. It does NOT block — it returns immediately (usually `false` on first call). The user must manually flip the toggle.

**Step 3 — Observe whether permission was granted (polling):**

macOS does not provide a callback or notification when TCC Accessibility status changes. The only reliable method is polling. [ASSUMED — based on developer community consensus; no official Apple API for TCC change observation]

```swift
// Pattern used by established macOS apps (e.g. Lasso, Raycast equivalents)
// Source: [ASSUMED] — no authoritative Apple doc for polling interval
private var accessibilityPollTimer: Timer?

func startPollingForAccessibility(onChange: @escaping (Bool) -> Void) {
    accessibilityPollTimer?.invalidate()
    // Poll every 0.5s for up to ~30s (60 polls), then give up
    var pollCount = 0
    accessibilityPollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
        pollCount += 1
        let granted = AXIsProcessTrusted()
        if granted || pollCount >= 60 {
            timer.invalidate()
            self?.accessibilityPollTimer = nil
            onChange(granted)
        }
    }
}
```

**Revert-on-denial pattern (D-09 toggle):**

```swift
// In PreferencesView: when toggle flips to ON
func enablePasteBack() {
    if AXIsProcessTrusted() {
        // Already granted — arm immediately
        prefs.pasteBackEnabled = true
    } else {
        // Not granted — show prompt, poll, revert if denied
        requestAccessibilityPermission()
        startPollingForAccessibility { [weak self] granted in
            DispatchQueue.main.async {
                if granted {
                    self?.prefs.pasteBackEnabled = true
                } else {
                    // Revert the toggle
                    self?.prefs.pasteBackEnabled = false
                    // Show explanatory message (D-09: "Accessibility permission is required...")
                }
            }
        }
    }
}
```

**Key caveat:** The system prompt can only be shown once per app launch in certain macOS versions. If the user dismisses the dialog without granting, the polling timer fires after 30s, detects `AXIsProcessTrusted() == false`, and reverts the toggle. [ASSUMED — polling timeout value; calibrate during implementation]

### OQ-01(c): Synthesizing ⌘V + capturing/restoring the previously-focused app

**Capturing the previously-focused app:**

The critical constraint: `NSWorkspace.shared.frontmostApplication` must be captured BEFORE the popover opens (before Flint takes focus), because once the `NSStatusItem` menu is clicked, Flint becomes the frontmost app.

```swift
// Source: HotkeyManager.swift — capture BEFORE activating popover [ASSUMED pattern]
// In HotkeyManager, when the hotkey fires (before showing the popover):
private var previousFrontmostApp: NSRunningApplication?

func hotkeyFired() {
    // Capture BEFORE showing the popover
    previousFrontmostApp = NSWorkspace.shared.frontmostApplication
    // Then show the popover
    clipboardDetector.isPopoverPresented = true
}
```

[VERIFIED: `NSWorkspace.shared.frontmostApplication` exists and returns the app that receives key events — developer.apple.com/documentation/appkit/nsworkspace/frontmostapplication]

**Synthesizing ⌘V after popover dismisses:**

The key code for `v` is `9` (virtual key code 9 on standard US keyboard). [ASSUMED — verify with key code map; this is training knowledge]

```swift
// Source: CoreGraphics CGEvent API [CITED: developer.apple.com/documentation/coregraphics/cgevent]
// Must be called AFTER the popover dismisses and the previous app is re-focused.
func synthesizePasteIntoApp(_ app: NSRunningApplication) {
    guard AXIsProcessTrusted() else { return }

    // Step 1: Activate the previous app
    app.activate(options: [.activateIgnoringOtherApps])

    // Step 2: Small delay to let the app take focus (AppKit activation is async)
    // [ASSUMED: 50-100ms is typical; tune during implementation]
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
        let vKeyCode: CGKeyCode = 9  // 'v' virtual key code
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: true),
              let keyUp   = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: false) else { return }

        let cmdFlag: CGEventFlags = .maskCommand
        keyDown.flags = cmdFlag
        keyUp.flags   = cmdFlag

        // Post to the session event tap (requires Accessibility)
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
    }
}
```

**WindowCoordinator interaction:** The popover dismissal (setting `clipboard.isPopoverPresented = false`) triggers the `NSPanel` to resign key. The previously-captured `NSRunningApplication` reference remains valid. Call `synthesizePaste` from the action that sets the output row AND triggers popover close, AFTER `isPopoverPresented = false`.

**Activation ordering pitfall:** `NSRunningApplication.activate(options:)` is not guaranteed to bring the window to front before the CGEvent fires. The `asyncAfter` delay handles this. Alternatively, observe `NSWorkspace.didActivateApplicationNotification` to fire the CGEvent once the target app is confirmed active. [ASSUMED — the notification approach is more robust but more complex]

---

## Architecture Patterns

### System Architecture Diagram

```
User (keyboard)
     │
     ▼
HotkeyManager (Carbon, no Accessibility)
  ├── [CAPTURE] NSWorkspace.frontmostApplication → previousApp
  └── shows popover → MenuBarPopoverView
          │
          ├── [D-01] AllToolsGridView (LazyVGrid 3-col, 12 tools)
          │         └── tap → navigationState = .tool(id)
          │
          ├── [D-02] ToolHeaderView (back button) wraps tool.makeView()
          │         └── tap back → navigationState = .root
          │
          ├── [D-07] SearchView (existing, already has onKeyPress ↑↓↩)
          │
          ├── [D-08] Hidden buttons in .background()
          │         ⌘1…⌘9 → post .selectOutputRow(index: N)
          │                    └── active tool observes → copies row N to NSPasteboard
          │
          └── [D-09] if pasteBackEnabled && AXIsProcessTrusted()
                        → synthesize ⌘V into previousApp
                        (popover dismissed first)

PreferencesView
  ├── [D-03] "Check for Updates…" button → sparkle.checkForUpdates()
  │         SparkleUpdaterService (SPUUpdaterDelegate) → @Published status
  │         └── PreferencesView shows: "Up to date" / "Update available" / error
  └── [D-09] Toggle "Auto-paste result" (default OFF)
            └── ON: requestAccessibilityPermission() → poll → revert if denied
```

### Recommended File Changes

```
UI/
├── MenuBarPopoverView.swift          # D-01 grid section, D-02 back header, D-08 ⌘N buttons
├── SearchView.swift                  # D-07 (already partially done — verify selectedIndex highlight)
├── AllToolsGridView.swift            # NEW — 12-tool grid (D-01)
├── ToolHeaderView.swift              # NEW — shared back affordance wrapper (D-02)
├── OnboardingWindowView.swift        # D-06 refinement
├── PreferencesView.swift             # D-03 button + D-09 toggle
Core/
├── Services/SparkleUpdaterService.swift  # D-03/D-04: add SPUUpdaterDelegate + @Published status
├── Services/PreferencesStore.swift       # D-09: add pasteBackEnabled bool
├── Services/HotkeyManager.swift          # D-09: capture previousFrontmostApp
├── Services/PasteBackService.swift       # NEW (optional) — isolate CGEvent paste logic (D-09)
Tools/
├── Color/ColorView.swift             # D-08: add row indices 1-5 (HEX/RGB/HSL/HSV/OKLCH)
├── Hash/HashView.swift               # D-08: add row indices 1-6 (MD5/SHA1/SHA256/SHA384/SHA512/CRC32)
├── NumberBase/NumberBaseView.swift   # D-08: add row indices 1-4 (BIN/OCT/DEC/HEX)
├── ... (all 12 tools)                # D-05 consistency pass; D-08 single-output tools get ⌘1
```

### Pattern 1: All-Tools Grid (D-01)

**What:** `LazyVGrid` with 3 adaptive columns showing all 12 tools as icon + name tiles.
**When to use:** Root navigation state, shown below (or instead of) the empty-state placeholder.
**Performance:** 12 items in a `LazyVGrid` is trivially small — no lazy loading needed, no performance concern against the 200ms budget. [VERIFIED: LazyVGrid renders lazily, 12 items instantaneous]

```swift
// Source: SwiftUI LazyVGrid [ASSUMED pattern — verified LazyVGrid API exists]
private let columns = [
    GridItem(.adaptive(minimum: 100, maximum: 140), spacing: 8)
]

var allToolsGrid: some View {
    LazyVGrid(columns: columns, spacing: 8) {
        ForEach(toolRegistry.tools) { tool in
            Button {
                navigationState = .tool(toolId: tool.id)
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: tool.sfSymbol)
                        .font(.system(size: 22))
                        .foregroundColor(.accentColor)
                    Text(tool.name)
                        .font(.system(size: 11, weight: .medium))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(.quaternary.opacity(0.5))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tool.name)
        }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
}
```

### Pattern 2: ⌘N Row Copy via Notification (D-08)

**What:** New `.selectOutputRow(index:)` notification carrying an `Int` row index (1-9), broadcast from hidden buttons in `MenuBarPopoverView.body` `.background()`. Tool views observe it and copy the indexed output.

```swift
// In MenuBarPopoverView.swift — new notification name
extension Notification.Name {
    static let selectOutputRow = Notification.Name("lathe.selectOutputRow")
}

// Hidden buttons in .background() (add to existing group):
// ⌘1 … ⌘9 — select output row N
ForEach(1...9, id: \.self) { index in
    Button("Copy Output \(index)") {
        NotificationCenter.default.post(
            name: .selectOutputRow,
            object: nil,
            userInfo: ["index": index]
        )
    }
    .keyboardShortcut(KeyEquivalent(Character(String(index))), modifiers: .command)
    .accessibilityHidden(true)
    .hidden()
}

// In a tool view (e.g. ColorContentView):
.onReceive(NotificationCenter.default.publisher(for: .selectOutputRow)) { note in
    guard let index = note.userInfo?["index"] as? Int else { return }
    let output = viewModel.outputForRow(index)   // tool-specific method
    guard let text = output, !text.isEmpty else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    // If paste-back enabled:
    // pasteBackService.pasteIntoPreviousApp()
}
```

**Conflict check:** ⌘1 in a macOS `List` navigates items; in a `TextField` it is unused. The hidden button in `.background()` takes precedence over `List` internal key handling because SwiftUI button keyboard shortcuts are first-responder-independent (they work via the responder chain at the window level). [ASSUMED — verify during implementation that ⌘1 doesn't conflict with text fields or List; if conflict arises, consider ⌘⌥1 instead. Claude's discretion on exact binding per CONTEXT.md]

### Pattern 3: Sparkle Result Reporting (D-03/D-04)

**What:** `SparkleUpdaterService` adopts `SPUUpdaterDelegate`. Three delegate callbacks map to an `@Published` (or `@Observable`) `updateStatus` enum.

```swift
// In SparkleUpdaterService.swift
enum UpdateStatus: Equatable {
    case idle
    case checking
    case upToDate
    case updateAvailable(version: String)
    case error(message: String)
}

extension SparkleUpdaterService: SPUUpdaterDelegate {

    // Called when no update found (user-initiated or background)
    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        let isUserInitiated = (error as NSError).userInfo[SPUNoUpdateFoundUserInitiatedKey] as? Bool ?? false
        if isUserInitiated {
            updateStatus = .upToDate
        }
        // Background checks: silently ignore (don't change status from .idle)
    }

    // Called when a valid update is found
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        updateStatus = .updateAvailable(version: item.displayVersionString)
    }

    // Called when Sparkle aborts (network error, bad feed URL, etc.)
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        updateStatus = .error(message: error.localizedDescription)
    }

    // Called at end of every cycle — catch-all
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        if let error {
            // Only update status if still .checking (don't overwrite specific states)
            if case .checking = updateStatus {
                updateStatus = .error(message: error.localizedDescription)
            }
        }
    }
}

func checkForUpdates() {
    updateStatus = .checking
    controller?.updater.checkForUpdates()
}
```

[CITED: sparkle-project.org/documentation/api-reference/Protocols/SPUUpdaterDelegate.html]

**CRITICAL wiring detail:** `SPUStandardUpdaterController` must be initialized with a delegate reference. The current code passes `updaterDelegate: nil`. Fix:

```swift
// In start():
controller = SPUStandardUpdaterController(
    startingUpdater: true,
    updaterDelegate: self,    // was nil
    userDriverDelegate: nil
)
```

The delegate is `weak` in Sparkle 2.x, so `SparkleUpdaterService` must be held alive by the app environment (it already is, via `@Environment(SparkleUpdaterService.self)`). [ASSUMED — Sparkle's delegate retention policy; verify against Sparkle 2.9.3 headers if needed]

**Localhost feed behavior:** With `SUFeedURL = http://localhost:8000/appcast.xml` and no server running, Sparkle will:
1. Call `checkForUpdates()` → sets status to `.checking`
2. Attempt network connection → connection refused after a timeout
3. Call `updater:didAbortWithError:` with `NSURLError` domain, code `-1004` (connection refused) or `-1009` (no internet connection) — the exact error code depends on OS networking, but the message will be "Could not connect to the server" / "The connection was refused"
4. Result: `updateStatus = .error("Could not connect to the server.")`

This is surfaced as a clear error in PreferencesView — exactly what D-04 requires. [ASSUMED: specific NSURLError codes; verified pattern from Sparkle network issue discussions]

**Sparkle start() guard:** `SparkleUpdaterService.start()` is called from `MenuBarPopoverView.onAppear`. If the user opens Preferences via the Dock (⌘, shortcut) without the popover having appeared, `controller` is nil and `checkForUpdates()` is a no-op. Fix: call `sparkle.start()` defensively at the beginning of `checkForUpdates()`:

```swift
func checkForUpdates() {
    start()  // idempotent — no-op if already started
    updateStatus = .checking
    controller?.updater.checkForUpdates()
}
```

### Pattern 4: D-07 Arrow Navigation — Current State vs Requirements

**Current state in `SearchView.swift`:** `@State private var selectedIndex: Int = 0` exists. `.onKeyPress(.upArrow)`, `.onKeyPress(.downArrow)`, `.onKeyPress(.return)` are already implemented. The visual highlight (`isSelected: selectedIndex == idx`) is already rendered. [VERIFIED: codebase read]

**What's already done vs what's missing:**

| Feature | Status | Notes |
|---------|--------|-------|
| `selectedIndex` state | DONE | Exists in SearchView |
| `.onKeyPress(.upArrow/.downArrow)` | DONE | In SearchView body |
| `.onKeyPress(.return)` | DONE | Calls `activateSelected()` |
| Visual highlight on selected row | DONE | `isSelected` prop on SearchToolRow |
| Reset selectedIndex on query change | DONE | `.onChange(of: query)` |
| Ensure search TextField focus doesn't block arrow keys | NEEDS VERIFICATION | `.onKeyPress` fires on the view that has focus; if `searchFocused` is true, the TextField may consume arrow keys before SearchView sees them |

**Key question for D-07:** The `TextField` in the search bar has `@FocusState` bound to `searchFocused`. On macOS, a focused `TextField` typically does NOT consume `.upArrow`/`.downArrow` (those are not text-editing keys in a single-line text field). `.onKeyPress` on the parent `SearchView` should fire correctly. [ASSUMED — verify during implementation; if TextField swallows arrows, escalate to adding an `NSEvent.addLocalMonitorForEvents` monitor for the arrow keys in the search state, similar to the existing `escMonitor`]

**Coexistence with `escMonitor`:** The existing `escMonitor` (local NSEvent monitor, keyCode 53) returns `nil` to consume Esc. Arrow keys have keyCodes 125 (down), 126 (up) — not 53. The monitor passes non-Esc events through unchanged (`return event`). No conflict. [VERIFIED: codebase read of `installEscMonitor()`]

### Pattern 5: D-09 Previously-Focused App — Timing and Storage

The previously-focused app must be captured at the moment the hotkey fires, before the popover steals focus. The right place is in `HotkeyManager.swift`, in the hotkey callback that posts `.showPopover`.

```swift
// HotkeyManager.swift — in the Carbon hotkey callback
// Capture frontmost app BEFORE posting .showPopover
// (NSWorkspace.shared.frontmostApplication reflects the app BEFORE Flint takes focus
// because the popover hasn't opened yet at this point)
@Observable
@MainActor
final class HotkeyManager {
    // New property for D-09
    private(set) var previousFrontmostApp: NSRunningApplication?

    // In the hotkey action:
    // previousFrontmostApp = NSWorkspace.shared.frontmostApplication
    // NotificationCenter.default.post(name: .showPopover, object: nil)
}
```

`NSRunningApplication` objects become invalid when the app quits, but the app we're pasting into is presumably still running. Store as `weak var` is not possible (no `weak` for `NSRunningApplication`); store as regular optionally-nilled reference.

**Activate + paste sequence:**

```swift
// After popover dismiss, inside the ⌘N action when pasteBackEnabled:
if prefs.pasteBackEnabled, AXIsProcessTrusted(),
   let app = hotkeyManager.previousFrontmostApp {
    // 1. Dismiss popover
    clipboard.isPopoverPresented = false
    // 2. Activate the previous app (async)
    app.activate(options: [.activateIgnoringOtherApps])
    // 3. Wait for app to be frontmost, then send ⌘V
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
        let v: CGKeyCode = 9
        if let kd = CGEvent(keyboardEventSource: nil, virtualKey: v, keyDown: true),
           let ku = CGEvent(keyboardEventSource: nil, virtualKey: v, keyDown: false) {
            kd.flags = .maskCommand
            ku.flags = .maskCommand
            kd.post(tap: .cgSessionEventTap)
            ku.post(tap: .cgSessionEventTap)
        }
    }
}
```

[CITED: developer.apple.com/documentation/coregraphics/cgevent]
[ASSUMED: 80ms activation delay — calibrate during implementation; apps like Raycast typically use 50-100ms]

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| EdDSA-signed auto-update | Custom update mechanism | Sparkle 2.9.3 (already integrated) | Security complexity; Sparkle handles signature verification, delta updates, XPC installer. |
| Global hotkey without Accessibility | CGEventTap | KeyboardShortcuts 3.0.1 (already integrated) | CGEventTap requires Accessibility prompt — exactly what CF-02 forbids. |
| OKLCH color conversion | Custom CSS L4 math | ChromaKit 0.1.1 (already integrated) | Already shipped in Phase 2. |
| Word-level diff | Custom diff algorithm | SwiftDiff (already integrated) | Google Diff Match and Patch algorithm. |
| Fuzzy search over tools | Custom string matching | `ToolRegistry.search()` (already built) | Already implements keyword + name search. |
| Permission status notification | Custom TCC observer | Poll `AXIsProcessTrusted()` on a Timer | macOS has no public API for TCC change callbacks. Polling is the standard pattern. |

---

## Common Pitfalls

### Pitfall 1: Wiring SPUUpdaterDelegate as `nil` (D-03 — existing bug)
**What goes wrong:** `SparkleUpdaterService` passes `updaterDelegate: nil` to `SPUStandardUpdaterController`. No delegate callbacks ever fire. Result status can never update.
**Why it happens:** The service was originally designed as fire-and-forget (background check, Sparkle owns the UI). D-03 requires programmatic status observation.
**How to avoid:** Pass `self` as `updaterDelegate` when constructing the controller. Store the delegate reference strongly (Sparkle holds it weakly).
**Warning signs:** `updateStatus` stays `.checking` indefinitely after calling `checkForUpdates()`.

### Pitfall 2: Capturing frontmostApplication Too Late (D-09)
**What goes wrong:** `NSWorkspace.shared.frontmostApplication` is read AFTER the popover is shown. At that point, Flint is the frontmost app. You capture Flint itself.
**Why it happens:** Natural place to put it is in `onAppear` or the copy action — both run after the popover is already on screen.
**How to avoid:** Capture in `HotkeyManager`'s Carbon callback, before posting `.showPopover`. This fires before the popover panel appears.
**Warning signs:** `previousFrontmostApp.bundleIdentifier == "com.yourcompany.flint"`.

### Pitfall 3: Accessibility Permission Request Can Only Show Once Per Launch
**What goes wrong:** On some macOS versions, if the user dismisses the Accessibility permission dialog without granting, subsequent calls to `AXIsProcessTrustedWithOptions` with `kAXTrustedCheckOptionPrompt: true` do NOT re-show the dialog in the same process lifetime. The polling timer runs out, the toggle reverts, but the user has no obvious path to try again without restarting.
**Why it happens:** TCC caches the "asked this session" state.
**How to avoid:** On toggle-ON when AXIsProcessTrusted is false: show prompt once, poll for 30s. If denied, revert toggle AND show a message: "Accessibility permission was denied. To enable paste-back, go to System Settings > Privacy & Security > Accessibility and add Flint." Provide a button: `Button("Open System Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) }`. [ASSUMED: exact behavior — calibrate during implementation]
**Warning signs:** User re-enables toggle; dialog doesn't appear; toggle reverts silently.

### Pitfall 4: ⌘N Conflicts with "New Window" (Existing Shortcut)
**What goes wrong:** `⌘N` is already wired in `MenuBarPopoverView.background()` as "Open workspace window" (INFRA-02). Adding `⌘1`…`⌘9` via D-08 is fine (1-9 are unused), but ⌘N literally conflicts with the existing `⌘N` binding.
**Why it happens:** D-08 uses ⌘1…⌘9 notation for "row N" — where N is the digit (1-9), not the letter N. There is NO conflict if the shortcut is `⌘` + digit key, not `⌘N` (letter).
**How to avoid:** Confirm the binding is `KeyboardShortcut(KeyEquivalent("1"), modifiers: .command)` through `KeyboardShortcut(KeyEquivalent("9"), modifiers: .command)` — digit keys 1-9, not the letter N. The existing `⌘N` → workspace window remains untouched.
**Warning signs:** Pressing ⌘1 opens the workspace window or has no effect.

### Pitfall 5: Sparkle First-Launch Check Suppression
**What goes wrong:** Sparkle 2.x intentionally does NOT check for updates on the very first launch (even if `checkForUpdates()` is called). `updaterDidNotFindUpdate` may not fire, or fires with a "first launch" suppression reason.
**Why it happens:** Sparkle has a built-in first-launch grace period (default: ~1 day check interval, not at t=0).
**How to avoid:** Do NOT override this. The "Check for Updates…" button calls `.checkForUpdates()` which bypasses the interval and forces an immediate check even on first run. Background auto-checks (Sparkle's own timer) correctly suppress on first launch. Manual button should always work.
**Warning signs:** `updateStatus` stays `.idle` after clicking the button (controller not armed because `start()` wasn't called).

### Pitfall 6: WindowCoordinator dance for Preferences already handles the Sparkle button
**What goes wrong:** The "Check for Updates…" button must call `sparkle.start()` before `checkForUpdates()` because Preferences can open without the popover appearing first (via ⌘, from an already-open Preferences window). If the popover `.onAppear` path is the only `start()` caller, `controller` may be nil.
**Why it happens:** `SparkleUpdaterService.start()` is idempotent but only called from the popover. Preferences opens via WindowCoordinator.
**How to avoid:** Make `checkForUpdates()` defensively call `start()` before checking. This is safe because `start()` is guarded: `guard controller == nil else { return }`.

### Pitfall 7: .onKeyPress Focus Requirement
**What goes wrong:** D-07 arrow navigation in `SearchView` may silently fail if the `SearchView` or its containing `VStack` doesn't hold key focus. The focused `TextField` may not propagate `.upArrow`/`.downArrow` events up to the containing view.
**Why it happens:** SwiftUI's `.onKeyPress` fires only on the focused view and its focused descendants. On macOS, a `TextField` with `@FocusState = true` may swallow certain keypresses.
**How to avoid:** Test empirically — if arrows don't work with TextField focused, add an `NSEvent.addLocalMonitorForEvents` monitor for keyCodes 125 (↓) and 126 (↑) in the search state, similar to the `escMonitor` pattern already used. Return `nil` to consume (handled), pass through otherwise.
**Warning signs:** Pressing ↑↓ produces a system "ding" sound instead of moving the selection.

### Pitfall 8: CGEvent Virtual Key Code for 'v'
**What goes wrong:** Using the wrong virtual key code for `v` in `CGEvent` synthesis produces the wrong keystroke.
**Why it happens:** CGEvent virtual key codes are hardware-layout codes, not ASCII values. On US keyboard, `v` = 9. But this varies by keyboard layout.
**How to avoid:** Use `CGEventCreateKeyboardEvent` with the character, or use a `CGEventSource` with the current keyboard layout. Alternatively, verify against `IOHIDKeyboardModifierMappingDst` constants. The well-known US key code for `v` is 9. [ASSUMED — verify with `IOHIDUsageTables.h` or a key code test during implementation]
**Warning signs:** Wrong character is typed, or nothing appears in the target app.

---

## Code Examples

### Sparkle Status Display in PreferencesView

```swift
// Source: pattern derived from SPUUpdaterDelegate docs [CITED: sparkle-project.org]
Section("Updates") {
    Button("Check for Updates…") {
        sparkle.checkForUpdates()
    }
    .disabled(sparkle.updateStatus == .checking)
    .accessibilityLabel("Check for updates")

    // Status display
    switch sparkle.updateStatus {
    case .idle:
        EmptyView()
    case .checking:
        HStack(spacing: 6) {
            ProgressView().scaleEffect(0.7)
            Text("Checking…").foregroundStyle(.secondary).font(.caption)
        }
    case .upToDate:
        Label("Flint is up to date.", systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green).font(.caption)
    case .updateAvailable(let version):
        Label("Update available: v\(version)", systemImage: "arrow.down.circle.fill")
            .foregroundStyle(.accentColor).font(.caption)
    case .error(let message):
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange).font(.caption)
            .lineLimit(3)
    }
}
```

### Number Badge for Output Rows (D-08)

```swift
// Source: [ASSUMED] — pattern adapted from existing CopyButtonView
// Applied to each output row in ColorView, HashView, NumberBaseView:
HStack(alignment: .center, spacing: 8) {
    // Row index badge
    Text("\(rowIndex)")
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .foregroundStyle(.secondary)
        .frame(width: 16, height: 16)
        .background(.quaternary.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .accessibilityLabel("⌘\(rowIndex) to copy")
        .help("Press ⌘\(rowIndex) to copy this value")

    // Existing format label and fields...
    Text(label).font(.system(size: 11, weight: .semibold)).frame(width: 42, alignment: .leading)
    content()
    Spacer()
    CopyButtonView(getText: copyText)
}
```

### Accessibility Permission Toggle (D-09)

```swift
// Source: AXIsProcessTrustedWithOptions [CITED: developer.apple.com/documentation/applicationservices]
Section("Keyboard Flow") {
    @Bindable var prefs = prefs
    Toggle("Auto-paste result after copying (requires Accessibility permission)",
           isOn: Binding(
               get: { prefs.pasteBackEnabled },
               set: { newValue in
                   if newValue {
                       handlePasteBackToggleOn()
                   } else {
                       prefs.pasteBackEnabled = false
                   }
               }
           ))
    .accessibilityLabel("Enable automatic paste-back after copying a result")
    .help("When enabled, pressing ⌘1–⌘9 copies the result AND pastes it into the previously-focused app. Requires Accessibility permission.")

    if prefs.pasteBackEnabled {
        Text("Accessibility permission granted. Press ⌘⇧1–9 to copy and paste.")
            .font(.caption).foregroundStyle(.secondary)
    }
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Highlightr for syntax highlighting | HighlightSwift 1.1.0 | 2026 (deprecated) | Already resolved in Phase 2 |
| AXObserver for TCC changes | Timer polling on `AXIsProcessTrusted()` | Always — no AXObserver API for TCC | No change needed; polling is the standard |
| altool for notarization | `xcrun notarytool` | Nov 2023 | Already resolved in Phase 3 |
| `openSettings()` on macOS 14 + .accessory | `WindowCoordinator` activation dance | Phase 1 | Already resolved; Preferences opens via WindowCoordinator |

**Deprecated/outdated in this phase:**
- `updaterDelegate: nil` in `SparkleUpdaterService.start()` — must change to `self` to get result callbacks.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The optimal accessibility polling interval is 0.5s for up to 30s | OQ-01(b) | Polling too fast wastes CPU; too slow makes the UX feel broken. Calibrate during implementation. |
| A2 | CGEvent activation delay of ~50-80ms is sufficient for `NSRunningApplication.activate` before key event | OQ-01(c) | Too short: keystroke fires before app is frontmost. Use `NSWorkspace.didActivateApplicationNotification` as a safer alternative if 80ms proves unreliable. |
| A3 | Virtual key code for 'v' on US keyboard is 9 | OQ-01(c) | Wrong key code would type wrong character. Verify with IOHIDUsageTables or a test during implementation. |
| A4 | Sparkle holds `updaterDelegate` weakly (requiring `SparkleUpdaterService` to be long-lived) | D-03/D-04 | If strongly held, a retain cycle forms. If weakly held and the service is deallocated, delegate callbacks stop. Verify against Sparkle 2.9.3 headers. |
| A5 | The localhost feed URL causes a connection-refused NSURLError (not a timeout hang) within a few seconds | D-04 | If Sparkle has a long timeout, the UI shows "Checking…" for too long. Sparkle timeout is ~30s per discussion #2674. If needed, use `SPUUpdaterDelegate.updater:mayPerformUpdateCheck:error:` to surface a cleaner error. |
| A6 | `⌘1`…`⌘9` (digit keys with Command) do not conflict with existing SwiftUI List or TextField behavior in the popover | D-08 | If conflict occurs, change to `⌘⌥1`…`⌘⌥9` (Command+Option+digit). Claude's discretion per CONTEXT.md. |
| A7 | `.onKeyPress(.upArrow/.downArrow)` fires on `SearchView` even when the `TextField` above it has `@FocusState = true` | D-07 | If TextField swallows arrows, escalate to a local NSEvent monitor for arrow keys (keyCodes 125/126) in the search state. |
| A8 | Sparkle delegate callbacks (`updaterDidNotFindUpdate`, `didFindValidUpdate`, `didAbortWithError`) are reliably called for both user-initiated and background checks | D-03/D-04 | If only called for background checks, user-initiated status won't update. The `SPUNoUpdateFoundUserInitiatedKey` userInfo key differentiates these. |
| A9 | `kAXTrustedCheckOptionPrompt` shows the System Settings panel and adds Flint to the Accessibility list in System Settings on macOS 14 (even without sandboxing) | D-09 | If the prompt doesn't appear for non-sandboxed apps, users must navigate to System Settings manually. Provide the fallback URL button. |

---

## Open Questions

1. **Does `.onKeyPress(.upArrow)` on `SearchView` fire when the search `TextField` has focus?**
   - What we know: The existing `SearchView` has `.onKeyPress(.upArrow/.downArrow)` and `@State selectedIndex`. The `TextField` in `searchBar` has `@FocusState searchFocused = true`.
   - What's unclear: On macOS 14, does a focused single-line `TextField` swallow arrow keys before the parent view's `.onKeyPress` sees them?
   - Recommendation: Test empirically on the first D-07 implementation task. If it fails, fall back to the existing `escMonitor` pattern (local NSEvent monitor for keyCodes 125/126).

2. **Does the Accessibility permission dialog appear for non-sandboxed macOS 14 apps when `kAXTrustedCheckOptionPrompt: true`?**
   - What we know: The API is documented to open System Settings. In practice, some versions of macOS only add the app to the list without showing a dialog; others show a dialog.
   - What's unclear: macOS 14-specific behavior.
   - Recommendation: During D-09 implementation, test the UX flow and ensure the fallback (deep link to System Settings > Accessibility) is always available.

3. **What is the exact error code/message Sparkle emits for the localhost feed?**
   - What we know: It will be an NSURLError (network unreachable or connection refused). The message depends on whether `localhost:8000` is actively refused vs. not listening.
   - What's unclear: Whether it's `-1004` (connection refused — server not running) or `-1009` (no internet) — these give different user-facing messages.
   - Recommendation: Surface `error.localizedDescription` directly. It will be "A server with the specified hostname could not be found." or "The connection was refused." Either is a clear error per D-04 requirements.

---

## Environment Availability

This phase is code-only changes to existing source files. No new build tools, runtimes, or external services are required.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode 16.3+ | Build | ✓ (assumed — Phase 3 shipped) | 16.x | — |
| Sparkle 2.9.3 | D-03/D-04 (already integrated) | ✓ | 2.9.3 | — |
| KeyboardShortcuts 3.0.1 | CF-02, hotkey (already integrated) | ✓ | 3.0.1 | — |
| ApplicationServices / AXIsProcessTrustedWithOptions | D-09 | ✓ | macOS 10.0+ | — |
| CGEvent (CoreGraphics) | D-09 paste-back | ✓ | macOS 10.0+ | — |
| NSWorkspace.frontmostApplication | D-09 focus capture | ✓ | macOS 10.6+ | — |

**Missing dependencies with no fallback:** None.

---

## Validation Architecture

> `nyquist_validation` is explicitly `false` in `.planning/config.json`. This section is **SKIPPED**.

---

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | — |
| V3 Session Management | no | — |
| V4 Access Control | yes (D-09) | Default-off toggle; Accessibility permission gate; never request permission without explicit user opt-in |
| V5 Input Validation | yes | Row index 1-9 clamped in notification handler; never crash on out-of-range index (CF-01) |
| V6 Cryptography | no | — |

### Known Threat Patterns for This Phase

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Requesting Accessibility permission at startup or on hotkey | Elevation of privilege | Never. Only on explicit toggle-ON in Preferences (CF-02 sanctioned exception) |
| CGEvent paste injecting into wrong app | Tampering | Capture target app before popover opens; verify it's still running before activating |
| Accessibility permission toggle persisting across restart without re-verification | Elevation of privilege | `prefs.pasteBackEnabled` is a stored bool. On each paste action, verify `AXIsProcessTrusted()` at the moment of paste — don't rely solely on the stored preference. If permission was revoked, copy-only gracefully (do not paste). |
| History storing Accessibility status | Information disclosure | No — `pasteBackEnabled` is a safe, non-sensitive boolean preference. |

---

## Sources

### Primary (HIGH confidence)
- [CITED: developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions] — AXIsProcessTrustedWithOptions: function signature, kAXTrustedCheckOptionPrompt behavior
- [CITED: developer.apple.com/documentation/coregraphics/cgevent] — CGEvent keyboard event synthesis API
- [CITED: developer.apple.com/documentation/appkit/nsworkspace/frontmostapplication] — NSWorkspace.frontmostApplication
- [CITED: sparkle-project.org/documentation/api-reference/Protocols/SPUUpdaterDelegate.html] — SPUUpdaterDelegate method signatures, updaterDidNotFindUpdate:error: parameters, didFindValidUpdate:, didAbortWithError:, didFinishUpdateCycleForUpdateCheck:error:
- [VERIFIED: codebase] — MenuBarPopoverView.swift: `escMonitor` pattern, hidden button `.background()` pattern, `PopoverNavigationState`, `NotificationCenter` broadcast pattern
- [VERIFIED: codebase] — SearchView.swift: `@State selectedIndex`, `.onKeyPress(.upArrow/.downArrow/.return)` already implemented
- [VERIFIED: codebase] — SparkleUpdaterService.swift: `updaterDelegate: nil` is the current (unfixed) state
- [VERIFIED: codebase] — Info.plist: `SUFeedURL = http://localhost:8000/appcast.xml`, `SUPublicEDKey = PLACEHOLDER`
- [VERIFIED: codebase] — ToolRegistry.swift: `tools` array has 12 items, is frozen
- [VERIFIED: codebase] — ColorView.swift: 5 format rows (HEX/RGB/HSL/HSV/OKLCH) — natural D-08 row indices 1-5

### Secondary (MEDIUM confidence)
- blog.kulman.sk/implementing-auto-type-on-macos — CGEvent synthesis requires Accessibility (`kTCCServicePostEvent`); Apple Developer Forums thread/724603 confirms same
- Apple Developer Forums thread/724603 — CGEvent.post() to session event tap requires Accessibility on macOS 14
- Multiple web sources — No path to synthetic paste without Accessibility permission exists on macOS 14
- sparkle-project.org/documentation/api-reference/Protocols/SPUUpdaterDelegate.html — All four key delegate methods verified with signatures

### Tertiary (LOW confidence / ASSUMED)
- Polling interval for AXIsProcessTrusted changes — 0.5s interval, 30s total — community convention, no Apple spec
- CGEvent virtual key code `9` for letter 'v' on US keyboard — training knowledge; verify with IOHIDUsageTables
- Activation delay 50-80ms for NSRunningApplication.activate before CGEvent — community convention
- Sparkle network timeout ~30s for unreachable feed — from sparkle-project/Sparkle discussion #2674

---

## Metadata

**Confidence breakdown:**
- OQ-01 verdict (no permission-free paste path): HIGH — multiple authoritative sources confirm
- OQ-01(b) AXIsProcessTrustedWithOptions API: HIGH — cited Apple docs
- OQ-01(c) CGEvent synthesis API: HIGH — cited Apple docs; activation delay: LOW (ASSUMED)
- Sparkle delegate API (D-03/D-04): HIGH — cited sparkle-project.org official API docs
- D-07 arrow nav (current state): HIGH — verified codebase; TextField interaction: LOW (needs runtime test)
- D-08 notification pattern: HIGH — mirrors verified existing `.copyOutput` pattern
- D-01 LazyVGrid performance: HIGH — 12 items is trivially small for lazy grid

**Research date:** 2026-06-29
**Valid until:** 2026-08-01 (30 days; Sparkle API and macOS TCC behavior are stable)
