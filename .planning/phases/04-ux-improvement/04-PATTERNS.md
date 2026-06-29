# Phase 4: UX Improvement — Pattern Map

**Mapped:** 2026-06-29
**Files analyzed:** 14 (4 new + 10 extended)
**Analogs found:** 14 / 14

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `UI/AllToolsGridView.swift` | component | request-response | `UI/Components/PinnedToolBarView.swift` | role-match |
| `UI/ToolHeaderView.swift` | component | request-response | `UI/Components/DetectionBannerView.swift` | role-match |
| `UI/Components/OutputRowBadge.swift` | component | request-response | `UI/Components/CopyButtonView.swift` | exact |
| `Core/Services/PasteBackService.swift` | service | event-driven | `Core/Services/HotkeyManager.swift` | role-match |
| `UI/MenuBarPopoverView.swift` | component | event-driven | self (extension) | exact |
| `UI/PreferencesView.swift` | component | request-response | self (extension) | exact |
| `UI/OnboardingWindowView.swift` | component | request-response | self (extension) | exact |
| `Core/Services/SparkleUpdaterService.swift` | service | event-driven | self (extension) | exact |
| `Core/Services/PreferencesStore.swift` | service | CRUD | self (extension) | exact |
| `Core/Services/HotkeyManager.swift` | service | event-driven | self (extension) | exact |
| `Tools/Color/ColorView.swift` | component | CRUD | self (extension) | exact |
| `Tools/Hash/HashView.swift` | component | CRUD | self (extension) | exact |
| `Tools/NumberBase/NumberBaseView.swift` | component | CRUD | self (extension) | exact |
| `UI/SearchView.swift` | component | event-driven | self (verification) | exact |

---

## Pattern Assignments

### `UI/AllToolsGridView.swift` (NEW — component, request-response)

**Analog:** `UI/Components/PinnedToolBarView.swift`

**Imports pattern** (PinnedToolBarView.swift lines 1–10):
```swift
import SwiftUI

struct PinnedToolBarView: View {
    @Environment(PreferencesStore.self) private var prefs
    @Environment(ToolRegistry.self) private var toolRegistry

    let onSelectTool: (String) -> Void  // passes toolId
```

**Core tile pattern — PinnedToolButton** (PinnedToolBarView.swift lines 43–67):
```swift
private struct PinnedToolButton: View {
    let tool: ToolDefinition
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            Image(systemName: tool.sfSymbol)
                .font(.system(size: 22))
                .foregroundColor(isHovered ? .accentColor : .secondary)
                .frame(width: 40, height: 40)
                .background(isHovered ? Color.accentColor.opacity(0.08) : .clear)
                .cornerRadius(8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tool.name)
        .help(tool.name)
        .onHover { hovered in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovered
            }
        }
    }
}
```

**Iteration over registry pattern** (PinnedToolBarView.swift lines 18–37):
```swift
private var pinnedTools: [ToolDefinition] {
    prefs.pinnedToolIds.compactMap { id in
        toolRegistry.tools.first { $0.id == id }
    }
}

var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 4) {
            ForEach(pinnedTools) { tool in
                PinnedToolButton(tool: tool, action: { onSelectTool(tool.id) })
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    .accessibilityLabel("Pinned tools")
}
```

**How to adapt for AllToolsGridView:**
- Replace `HStack` + `ScrollView(.horizontal)` with `LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 140), spacing: 8)], spacing: 8)`.
- Replace `ForEach(pinnedTools)` with `ForEach(toolRegistry.tools)` (all 12, no filter).
- Tile `VStack(spacing: 8)`: icon (22pt accent) over name (13pt regular, `.lineLimit(2)`, `.multilineTextAlignment(.center)`).
- Tile background: `.quaternary.opacity(0.5)` fill, `cornerRadius(8)`, hover tints to `.quaternary.opacity(0.85)`.
- Add `.accessibilityHint("Open \(tool.name)")` — not on PinnedToolButton (which uses `.help()`).
- Props: `toolRegistry: ToolRegistry` from `@Environment`, `onSelect: (String) -> Void` callback.
- No `@State` in the grid view itself — navigation state stays in `MenuBarPopoverView`.
- Outer padding: 12pt horizontal, 8pt vertical.

---

### `UI/ToolHeaderView.swift` (NEW — component, request-response)

**Analog:** `UI/Components/DetectionBannerView.swift`

**Imports and props pattern** (DetectionBannerView.swift lines 1–13):
```swift
import SwiftUI

struct DetectionBannerView: View {
    let result: DetectionResult
    let onAccept: () -> Void
    let onDismiss: () -> Void
```

**HStack header layout pattern** (DetectionBannerView.swift lines 14–54):
```swift
var body: some View {
    HStack(spacing: 8) {
        VStack(alignment: .leading, spacing: 2) {
            Text("Detected: \(result.toolName)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
            Text("Open \(result.toolName)?")
                .font(.caption)
                .foregroundColor(.secondary)
        }

        Spacer()

        Button("Open \(result.toolName)") {
            onAccept()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .accessibilityLabel("Open \(result.toolName)")
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(...)
}
```

**VoiceOver trait pattern from OnboardingWindowView.swift** (line 37):
```swift
Text("Welcome to Flint")
    .accessibilityAddTraits(.isHeader)
```

**How to adapt for ToolHeaderView:**
- Props: `toolName: String`, `onBack: () -> Void`. Stateless — caller (`MenuBarPopoverView`) owns navigation state.
- Layout: `VStack(spacing: 0)` wrapping an `HStack` + `Divider()`.
- HStack content: `.plain` button (`Image(systemName: "chevron.left")` + `Text("All Tools")`) in `.accentColor` on the left; `Text(toolName)` in 15pt semibold `.primary` centered; a matching invisible spacer on the right to balance.
- Back button `.accessibilityLabel("Back to tool picker")`.
- Tool name `.accessibilityAddTraits(.isHeader)` (pattern from OnboardingWindowView.swift line 37).
- Minimum height 44pt. Horizontal padding 12pt.
- `Divider()` below the HStack.
- The header is NOT added inside tool views — `MenuBarPopoverView` wraps `tool.makeView()` with this at the `.tool(toolId:)` switch case.

---

### `UI/Components/OutputRowBadge.swift` (NEW — component, request-response)

**Analog:** `UI/Components/CopyButtonView.swift` (exact pattern match for a small reusable per-row component)

**Full analog** (CopyButtonView.swift lines 1–44):
```swift
// UI/Components/CopyButtonView.swift
import SwiftUI
import AppKit

struct CopyButtonView: View {
    let getText: () -> String
    @State private var copied = false

    init(text: String) {
        self.getText = { text }
    }

    init(getText: @escaping () -> String) {
        self.getText = getText
    }

    var body: some View {
        Button(action: performCopy) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .foregroundColor(.secondary)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(copied ? "Copied" : "Copy")
    }

    private func performCopy() {
        let text = getText()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copied = false
        }
    }
}
```

**How to adapt for OutputRowBadge:**
- Props: `index: Int`. Pure display component — no action (⌘N is wired at the popover level).
- No `@State`. Stateless.
- Body: `Text("\(index)")` at 11pt semibold monospaced `.foregroundStyle(.secondary)` inside a 16×16pt `RoundedRectangle(cornerRadius: 4)` with `.quaternary.opacity(0.6)` fill.
- `.accessibilityLabel("⌘\(index) to copy")`.
- `.help("Press ⌘\(index) to copy")`.
- No `import AppKit` needed — pure SwiftUI display.
- Placement in output rows: leading edge of the row HStack, before the format label. See the `formatRow` helper in `ColorView.swift` lines 223–240 for the HStack signature to insert it into.

---

### `Core/Services/PasteBackService.swift` (NEW — service, event-driven)

**Analog:** `Core/Services/HotkeyManager.swift`

**Full analog** (HotkeyManager.swift lines 1–31):
```swift
// Core/Services/HotkeyManager.swift
import KeyboardShortcuts
import Foundation
import Observation

@Observable
@MainActor
final class HotkeyManager {
    init() {
        KeyboardShortcuts.onKeyDown(for: .openFlint) {
            NotificationCenter.default.post(name: .showPopover, object: nil)
        }
    }
}
```

**@Observable @MainActor final class service triple** — this is the canonical service pattern in this codebase. Every service (`SparkleUpdaterService`, `PreferencesStore`, `HotkeyManager`) uses it.

**SparkleUpdaterService pattern for methods + guard** (SparkleUpdaterService.swift lines 33–47):
```swift
func start() {
    guard controller == nil else { return }
    controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
}

func checkForUpdates() {
    controller?.updater.checkForUpdates()
}
```

**How to implement PasteBackService:**
```swift
// Core/Services/PasteBackService.swift
import AppKit
import CoreGraphics
import ApplicationServices
import Observation

@Observable
@MainActor
final class PasteBackService {
    // Guard at call time — permission may be revoked after toggle-on
    func synthesizePaste(into app: NSRunningApplication) {
        guard AXIsProcessTrusted() else { return }
        app.activate(options: [.activateIgnoringOtherApps])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            let v: CGKeyCode = 9  // 'v' on US keyboard — verify with IOHIDUsageTables
            guard let kd = CGEvent(keyboardEventSource: nil, virtualKey: v, keyDown: true),
                  let ku = CGEvent(keyboardEventSource: nil, virtualKey: v, keyDown: false)
            else { return }
            kd.flags = .maskCommand
            ku.flags = .maskCommand
            kd.post(tap: .cgSessionEventTap)
            ku.post(tap: .cgSessionEventTap)
        }
    }
}
```

- Register in `FlintApp.swift` alongside `HotkeyManager` in the `.environment()` chain.
- `AXIsProcessTrusted()` check at call time (not stored bool) — permission may be revoked after `pasteBackEnabled = true` was set.

---

## Extended File Pattern Assignments

### `UI/MenuBarPopoverView.swift` — D-01 grid, D-02 back, D-08 ⌘N buttons

**Notification name extension pattern** (MenuBarPopoverView.swift lines 22–35):
```swift
extension Notification.Name {
    static let clearInput  = Notification.Name("lathe.clearInput")
    static let copyOutput  = Notification.Name("lathe.copyOutput")
    static let pasteAndDetect = Notification.Name("lathe.pasteAndDetect")
}
```
Add inside the same extension block:
```swift
static let selectOutputRow = Notification.Name("lathe.selectOutputRow")
```

**Hidden button pattern** (MenuBarPopoverView.swift lines 193–278):
```swift
.background(
    Group {
        Button("Focus Search") { focusSearch() }
            .keyboardShortcut("k", modifiers: .command)
            .accessibilityHidden(true)
            .hidden()
        // ... more hidden buttons
        Button("Copy Output") {
            NotificationCenter.default.post(name: .copyOutput, object: nil)
        }
        .keyboardShortcut("c", modifiers: [.command, .shift])
        .accessibilityHidden(true)
        .hidden()
    }
)
```
Add ⌘1…⌘9 buttons with the same `.accessibilityHidden(true).hidden()` pattern, posting `.selectOutputRow` with `userInfo: ["index": index]`:
```swift
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
```

**PopoverNavigationState + bodyContent switch pattern** (MenuBarPopoverView.swift lines 38–43, 377–415):
```swift
enum PopoverNavigationState: Equatable {
    case root
    case tool(toolId: String)
    case searchResults(query: String)
    case history
}

// In bodyContent:
case .tool(let toolId):
    if let tool = toolRegistry.tools.first(where: { $0.id == toolId }) {
        tool.makeView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
        ContentUnavailableView("Tool Not Found", systemImage: "questionmark")
    }
```
For D-02: wrap `tool.makeView()` call with `ToolHeaderView`:
```swift
case .tool(let toolId):
    if let tool = toolRegistry.tools.first(where: { $0.id == toolId }) {
        VStack(spacing: 0) {
            ToolHeaderView(toolName: tool.name, onBack: { navigationState = .root })
            tool.makeView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
```

For D-01: add `AllToolsGridView` to the `.root` case, below `recentHistoryView`:
```swift
case .root:
    ScrollView {
        VStack(spacing: 0) {
            AllToolsGridView(onSelect: { toolId in
                navigationState = .tool(toolId: toolId)
            })
            Divider()
            recentHistoryView
        }
    }
```

**escMonitor pattern for D-07 fallback** (MenuBarPopoverView.swift lines 474–490):
```swift
private func installEscMonitor() {
    guard escMonitor == nil else { return }
    escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
        if event.keyCode == 53 {
            handleEscape()
            return nil  // consume
        }
        return event    // pass through all other keys
    }
}
```
If D-07 `.onKeyPress` on SearchView fails with focused TextField, mirror this with keyCode 125 (↓) and 126 (↑) in the search-results state only.

---

### `Core/Services/SparkleUpdaterService.swift` — D-03/D-04 delegate + status

**Service class header and idempotent start guard** (SparkleUpdaterService.swift lines 24–47):
```swift
@Observable
@MainActor
final class SparkleUpdaterService {
    private(set) var controller: SPUStandardUpdaterController?

    func start() {
        guard controller == nil else { return }
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,  // CHANGE TO: updaterDelegate: self
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        controller?.updater.checkForUpdates()
    }
}
```

**Changes required:**
1. Add `@Observable var updateStatus: UpdateStatus = .idle` property. `UpdateStatus` is a new enum defined in this file.
2. Change `updaterDelegate: nil` to `updaterDelegate: self`.
3. Add `start()` call at the top of `checkForUpdates()` (defensive — Preferences may open before popover).
4. Add `extension SparkleUpdaterService: SPUUpdaterDelegate` conformance with 4 delegate methods.

**UpdateStatus enum to add:**
```swift
enum UpdateStatus: Equatable {
    case idle
    case checking
    case upToDate
    case updateAvailable(version: String)
    case error(message: String)
}
```

---

### `Core/Services/PreferencesStore.swift` — D-09 pasteBackEnabled

**Existing bool preference pattern** (PreferencesStore.swift lines 72–75):
```swift
var hasSeenOnboarding: Bool {
    get { defaults.object(forKey: Keys.hasSeenOnboarding) as? Bool ?? false }
    set { defaults.set(newValue, forKey: Keys.hasSeenOnboarding) }
}
```

**Add after existing properties:**
```swift
// MARK: - Paste Back (D-09)
// Default: false — no Accessibility permission prompt without explicit opt-in (CF-02).
var pasteBackEnabled: Bool {
    get { defaults.object(forKey: Keys.pasteBackEnabled) as? Bool ?? false }
    set { defaults.set(newValue, forKey: Keys.pasteBackEnabled) }
}
```

**Add to Keys enum** (PreferencesStore.swift lines 234–248):
```swift
private enum Keys {
    // ... existing keys ...
    static let pasteBackEnabled = "lathe.pasteBackEnabled"
}
```

---

### `Core/Services/HotkeyManager.swift` — D-09 previousFrontmostApp capture

**Existing class body** (HotkeyManager.swift lines 22–31):
```swift
@Observable
@MainActor
final class HotkeyManager {
    init() {
        KeyboardShortcuts.onKeyDown(for: .openFlint) {
            NotificationCenter.default.post(name: .showPopover, object: nil)
        }
    }
}
```

**Add property and capture before posting:**
```swift
@Observable
@MainActor
final class HotkeyManager {
    // D-09: capture BEFORE the popover opens (before Flint takes focus)
    private(set) var previousFrontmostApp: NSRunningApplication?

    init() {
        KeyboardShortcuts.onKeyDown(for: .openFlint) { [self] in
            // Capture now — NSWorkspace.frontmostApplication still reflects
            // the previous app because the popover hasn't appeared yet.
            previousFrontmostApp = NSWorkspace.shared.frontmostApplication
            NotificationCenter.default.post(name: .showPopover, object: nil)
        }
    }
}
```

Add `import AppKit` to the existing import block (currently has `KeyboardShortcuts`, `Foundation`, `Observation`).

---

### `UI/PreferencesView.swift` — D-03 Update button + D-09 paste-back toggle

**Existing Section pattern** (PreferencesView.swift lines 62–108):
```swift
Form {
    Section("Startup") {
        Toggle("Launch at login", isOn: $prefs.launchAtLogin)
            .accessibilityLabel("Launch Flint at login")
            .help("Automatically start Flint when you log in to your Mac.")
    }

    Section("Clipboard") {
        Toggle("Auto-detect clipboard content", isOn: $prefs.clipboardAutoDetect)
            .accessibilityLabel("Automatically detect clipboard content and suggest the best tool")
            .help("...")
    }
}
.formStyle(.grouped)
.padding()
.frame(minWidth: 420)
```

**Environment access pattern** (PreferencesView.swift lines 10–12):
```swift
@Environment(PreferencesStore.self) private var prefs
@Environment(HotkeyManager.self) private var hotkeyManager
@Environment(HistoryStore.self) private var historyStore
```

For D-03, add `@Environment(SparkleUpdaterService.self) private var sparkle` to `GeneralPreferencesTab` and inject via `.environment(sparkle)` in `PreferencesView.body` (mirror the existing pattern at line 39).

**Button pattern from PreferencesView** (line 224–230):
```swift
Button(role: .destructive) {
    showClearConfirmation = true
} label: {
    Label("Clear All History", systemImage: "trash")
        .foregroundColor(.red)
}
.accessibilityLabel("Clear all unpinned history items")
.help("Remove all unpinned history entries. Pinned items will be kept.")
```

For D-03:
```swift
Section("Updates") {
    Button("Check for Updates…") {
        sparkle.checkForUpdates()
    }
    .disabled(sparkle.updateStatus == .checking)
    .accessibilityLabel("Check for updates")

    switch sparkle.updateStatus {
    case .idle: EmptyView()
    case .checking:
        HStack(spacing: 6) {
            ProgressView().scaleEffect(0.7)
            Text("Checking for updates…").foregroundStyle(.secondary).font(.system(size: 13))
        }
    case .upToDate:
        Label("Flint is up to date.", systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green).font(.system(size: 13))
    case .updateAvailable(let version):
        Label("Update available: v\(version)", systemImage: "arrow.down.circle.fill")
            .foregroundStyle(.accentColor).font(.system(size: 13))
    case .error(let message):
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange).font(.system(size: 13))
            .lineLimit(3)
    }
}
```

**`@Bindable` pattern** (PreferencesView.swift line 58):
```swift
@Bindable var prefs = prefs
```
Use the same `@Bindable var prefs = prefs` inside `GeneralPreferencesTab.body` when adding the D-09 Toggle.

For D-09 toggle, `Binding` with custom setter:
```swift
Section("Keyboard Flow") {
    Toggle(
        "Auto-paste result after copying",
        isOn: Binding(
            get: { prefs.pasteBackEnabled },
            set: { newValue in
                if newValue { handlePasteBackToggleOn() }
                else { prefs.pasteBackEnabled = false }
            }
        )
    )
    .accessibilityLabel("Enable automatic paste-back after copying a result")
    .help("When enabled, pressing ⌘1–⌘9 copies the result AND pastes it into the previously-focused app. Requires Accessibility permission.")
}
```

---

### `UI/OnboardingWindowView.swift` — D-06 Steps 3 and 4

**Existing step pattern** (OnboardingWindowView.swift lines 39–75):
```swift
// Step 1: menubar callout
HStack(alignment: .top, spacing: 12) {
    Image(systemName: "wrench.and.screwdriver")
        .font(.system(size: 22))
        .foregroundColor(.accentColor)
        .frame(width: 28)
        .accessibilityHidden(true)

    VStack(alignment: .leading, spacing: 4) {
        Text("Flint lives in your menubar")
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.primary)
        Text("Look for the wrench icon in the menu bar at the top of your screen...")
            .font(.system(size: 13))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
```

**Frame declaration** (OnboardingWindowView.swift line 116):
```swift
.frame(width: 480, height: 360)
```

**Changes required:**
1. Add Step 3 (Services) using the exact HStack pattern with `Image(systemName: "text.cursor")`.
2. Add Step 4 (Drag-and-drop) using the exact HStack pattern with `Image(systemName: "arrow.down.circle")`.
3. Change `.frame(width: 480, height: 360)` to `.frame(width: 480, height: 480)`.

Add Steps 3 and 4 after Step 2, before `Spacer(minLength: 0)`:
```swift
// Step 3: Services menu
HStack(alignment: .top, spacing: 12) {
    Image(systemName: "text.cursor")
        .font(.system(size: 22))
        .foregroundColor(.accentColor)
        .frame(width: 28)
        .accessibilityHidden(true)

    VStack(alignment: .leading, spacing: 4) {
        Text("Route text from any app")
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.primary)
        Text("Select text anywhere, right-click, and choose Services > Open in Flint to process it instantly.")
            .font(.system(size: 13))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// Step 4: Drag-and-drop
HStack(alignment: .top, spacing: 12) {
    Image(systemName: "arrow.down.circle")
        .font(.system(size: 22))
        .foregroundColor(.accentColor)
        .frame(width: 28)
        .accessibilityHidden(true)

    VStack(alignment: .leading, spacing: 4) {
        Text("Drag files directly")
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.primary)
        Text("Drop a text or binary file onto any tool — Base64 and Hash accept any file type.")
            .font(.system(size: 13))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
```

---

### `Tools/Color/ColorView.swift`, `Tools/Hash/HashView.swift`, `Tools/NumberBase/NumberBaseView.swift` — D-08 OutputRowBadge + `.selectOutputRow` observer

**Existing formatRow helper in ColorView.swift** (lines 223–240):
```swift
@ViewBuilder
private func formatRow<Content: View>(
    label: String,
    copyTooltip: String,
    copyText: @escaping () -> String,
    @ViewBuilder content: () -> Content
) -> some View {
    HStack(alignment: .center, spacing: 8) {
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .frame(width: 42, alignment: .leading)
        content()
        Spacer()
        CopyButtonView(getText: copyText)
            .help(copyTooltip)
            .accessibilityLabel(copyTooltip)
    }
    .padding(.vertical, 2)
}
```
Add `OutputRowBadge(index: rowIndex)` as the **first** element inside the `HStack`, before `Text(label)`:
```swift
HStack(alignment: .center, spacing: 8) {
    OutputRowBadge(index: rowIndex)      // D-08 — new
    Text(label)
        .font(.system(size: 11, weight: .semibold))
        .frame(width: 42, alignment: .leading)
    content()
    Spacer()
    CopyButtonView(getText: copyText)
        .help(copyTooltip)
        .accessibilityLabel(copyTooltip)
}
```

**Existing `.onReceive` notification pattern in ToolShortcutActions.swift** (lines 44–57):
```swift
.onReceive(NotificationCenter.default.publisher(for: .copyOutput)) { _ in
    guard let text = actions.primaryOutput(), !text.isEmpty else { return }
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(text, forType: .string)
}
.onReceive(NotificationCenter.default.publisher(for: .clearInput)) { _ in
    actions.clearInput()
}
```

Add a `.selectOutputRow` observer using the same `.onReceive` pattern in each multi-output tool's content view body:
```swift
.onReceive(NotificationCenter.default.publisher(for: .selectOutputRow)) { note in
    guard let index = note.userInfo?["index"] as? Int else { return }
    // Tool-specific: call viewModel.outputForRow(index)
    guard let text = viewModel.outputForRow(index), !text.isEmpty else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    // If pasteBackEnabled: pasteBackService.synthesizePaste(into: previousApp)
}
```

Each multi-output tool's ViewModel needs an `outputForRow(_ index: Int) -> String?` method:
- `ColorViewModel.outputForRow`: 1=HEX, 2=RGB, 3=HSL, 4=HSV, 5=OKLCH.
- `HashViewModel.outputForRow`: 1=MD5, 2=SHA-1, 3=SHA-256, 4=SHA-384, 5=SHA-512, 6=CRC32.
- `NumberBaseViewModel.outputForRow`: 1=BIN, 2=OCT, 3=DEC, 4=HEX.
- Single-output tools: row 1 = `primaryOutput()`, all others return nil (mirrors CF-01 never-crash rule).

**Existing baseRow in NumberBaseView.swift** (lines 157–210) shows the `HStack` structure to insert `OutputRowBadge` into for multi-row tools. The pattern is consistent: leading label frame → fields → CopyButtonView at trailing.

---

### `UI/SearchView.swift` — D-07 arrow-key navigation verification

**Current state already implemented** (SearchView.swift lines 46–57):
```swift
.onKeyPress(.upArrow) {
    if selectedIndex > 0 { selectedIndex -= 1 }
    return .handled
}
.onKeyPress(.downArrow) {
    if selectedIndex < flatResults.count - 1 { selectedIndex += 1 }
    return .handled
}
.onKeyPress(.return) {
    activateSelected()
    return .handled
}
```

**Existing `selectedIndex` reset** (SearchView.swift lines 43–45):
```swift
.onChange(of: query) { _, _ in
    selectedIndex = 0
}
```

**Visual highlight already applied** (SearchView.swift lines 88–93 for tool rows, lines 108–110 for history rows):
```swift
SearchToolRow(
    tool: tool,
    isSelected: selectedIndex == idx
)
// SearchToolRow body:
.background(isSelected ? Color.accentColor.opacity(0.1) : .clear)
.cornerRadius(4)
```

**D-07 task:** Empirically test whether `.onKeyPress(.upArrow/.downArrow)` fires when `searchFocused == true` (the `TextField` has focus). If the TextField swallows arrow keys, add a local NSEvent monitor in `MenuBarPopoverView` for keyCodes 125 (↓) and 126 (↑) that only fires in the `.searchResults` state, mirrors the existing `installEscMonitor()` pattern (MenuBarPopoverView.swift lines 474–490) with `return nil` to consume.

---

## Shared Patterns

### @Observable @MainActor final class (all services)
**Source:** `Core/Services/HotkeyManager.swift` lines 22–31, `Core/Services/SparkleUpdaterService.swift` lines 24–26
**Apply to:** `Core/Services/PasteBackService.swift`
```swift
@Observable
@MainActor
final class ServiceName {
    // properties + methods
}
```

### NotificationCenter broadcast + .onReceive observer
**Source:** `UI/MenuBarPopoverView.swift` lines 259–265 (broadcast) + `UI/Components/ToolShortcutActions.swift` lines 44–57 (observer)
**Apply to:** D-08 `selectOutputRow` notification, all multi-output tool views
```swift
// Broadcast (hidden button):
Button("...") {
    NotificationCenter.default.post(name: .selectOutputRow, object: nil, userInfo: ["index": index])
}
.keyboardShortcut(...).accessibilityHidden(true).hidden()

// Observer (tool view body):
.onReceive(NotificationCenter.default.publisher(for: .selectOutputRow)) { note in
    guard let index = note.userInfo?["index"] as? Int else { return }
    // ... handle
}
```

### NSPasteboard copy
**Source:** `UI/Components/CopyButtonView.swift` lines 31–35
**Apply to:** All `.selectOutputRow` observers, `PasteBackService`
```swift
NSPasteboard.general.clearContents()
NSPasteboard.general.setString(text, forType: .string)
```

### Semantic color + `.buttonStyle(.plain)` for nav buttons
**Source:** `UI/Components/PinnedToolBarView.swift` lines 49–65
**Apply to:** `ToolHeaderView` back button, `AllToolsGridView` tiles
```swift
.foregroundColor(isHovered ? .accentColor : .secondary)
.background(isHovered ? Color.accentColor.opacity(0.08) : .clear)
.cornerRadius(8)
// + .buttonStyle(.plain) + .onHover { }
```

### UserDefaults bool preference
**Source:** `Core/Services/PreferencesStore.swift` lines 72–75
**Apply to:** `pasteBackEnabled` in PreferencesStore
```swift
var boolPreference: Bool {
    get { defaults.object(forKey: Keys.key) as? Bool ?? false }
    set { defaults.set(newValue, forKey: Keys.key) }
}
```

### Form Section in Preferences
**Source:** `UI/PreferencesView.swift` lines 62–107
**Apply to:** D-03 "Updates" Section, D-09 "Keyboard Flow" Section in `GeneralPreferencesTab`
```swift
Section("Section Name") {
    Toggle("Label", isOn: $prefs.somePref)
        .accessibilityLabel("VoiceOver label")
        .help("Tooltip text.")
}
```

### WindowCoordinator.windowWillClose() on .onDisappear
**Source:** `UI/OnboardingWindowView.swift` line 118, `UI/PreferencesView.swift` line 47
**Apply to:** All modal windows (already applied; do not re-add to D-03/D-09 inline views)
```swift
.onDisappear {
    WindowCoordinator.shared.windowWillClose()
}
```

### fileDrop + DropOverlayView pattern (D-05 consistency)
**Source:** `UI/MenuBarPopoverView.swift` lines 127–150, `Tools/Color/ColorView.swift` lines 102–118
**Apply to:** Any tool view missing this during D-05 pass
```swift
.fileDrop(isTargeted: $isDragTargeted, onText: { ... }, onError: { ... })
.overlay { if isDragTargeted { DropOverlayView(label: "...").transition(...) } }
```

### accessibilityHidden + hidden() for shortcut buttons
**Source:** `UI/MenuBarPopoverView.swift` lines 197–199
**Apply to:** All new hidden ⌘1–⌘9 buttons in MenuBarPopoverView
```swift
.accessibilityHidden(true)
.hidden()
```

---

## No Analog Found

All files in Phase 4 have close analogs in the codebase. No file requires pure RESEARCH.md-only patterns.

| File | Note |
|------|------|
| `Core/Services/PasteBackService.swift` | CGEvent synthesis is new code with no codebase analog, but the service shell (`@Observable @MainActor final class`) is a direct match to `HotkeyManager`. The CGEvent implementation follows RESEARCH.md OQ-01(c) exactly. |

---

## Metadata

**Analog search scope:** `UI/`, `UI/Components/`, `Core/Services/`, `Core/Extensions/`, `Tools/Color/`, `Tools/Hash/`, `Tools/NumberBase/`
**Files scanned:** 17 source files read in full
**Pattern extraction date:** 2026-06-29
