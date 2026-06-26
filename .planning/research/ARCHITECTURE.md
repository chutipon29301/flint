# Architecture Research

**Domain:** Native macOS menubar developer-utility app (SwiftUI + MVVM, macOS 14+)
**Researched:** 2026-06-25
**Confidence:** HIGH (all critical patterns verified against Apple official docs, Context7, and open-source macOS menubar apps)

---

## System Overview

```
┌──────────────────────────────────────────────────────────────────────┐
│                        FlintApp (@main)                              │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │  App-level state (owned here, injected into every scene)     │    │
│  │  @State historyStore | @State prefs | @State clipboard       │    │
│  │  @State hotkeyManager | @State toolRegistry                  │    │
│  └──────────────────────────────────────────────────────────────┘    │
│         │ .environment(...)            │ .environment(...)            │
│  ┌──────▼──────────────────┐  ┌───────▼──────────────────────────┐   │
│  │  MenuBarExtra (.window) │  │  WindowGroup (id: "workspace")   │   │
│  │  MenuBarPopoverView     │  │  MainWindowView                  │   │
│  │  • SearchBar            │  │  • Sidebar (categories/tools)    │   │
│  │  • ToolGrid             │  │  • ToolContentArea               │   │
│  │  • DetectionBanner      │  │  • HistoryPanel (right sidebar)  │   │
│  │  • RecentTools          │  │  • Tool workspace                │   │
│  └─────────────────────────┘  └──────────────────────────────────┘   │
│                     │                        │                       │
│  ┌──────────────────▼────────────────────────▼──────────────────┐    │
│  │                    Core Services Layer                        │    │
│  │  ToolRegistry  HistoryStore  ClipboardDetector               │    │
│  │  HotkeyManager  PreferencesStore                             │    │
│  └───────────────────────────────────────────────────────────────┘   │
│                                 │                                     │
│  ┌──────────────────────────────▼────────────────────────────────┐   │
│  │                      Tools Layer                              │    │
│  │  JSONFormatterTool  Base64Tool  URLEncoderTool  JWTTool       │    │
│  │  TimestampTool  HashTool  UUIDTool  (+ Phase 2 tools)        │    │
│  │  Each: ToolDefinition + ToolViewModel + ToolView             │    │
│  └───────────────────────────────────────────────────────────────┘   │
│                                 │                                     │
│  ┌──────────────────────────────▼────────────────────────────────┐   │
│  │                   Infrastructure Layer                        │    │
│  │   GRDB (SQLite)    UserDefaults    KeyboardShortcuts           │    │
│  │   NSPasteboard     CryptoKit/CommonCrypto  AppKit bridges     │    │
│  └───────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Component Boundaries

| Component | Responsibility | Communicates With | Never Touches |
|-----------|---------------|-------------------|---------------|
| `FlintApp` | Owns and instantiates all app-level services; injects them into scenes | All scenes via `.environment()` | Individual tool business logic |
| `ToolRegistry` | Immutable ordered list of `ToolDefinition` values; the single enumeration point for all tools | `MenuBarPopoverView`, `SidebarView`, `ClipboardDetector`, `HistoryStore` | UI rendering, transformation logic |
| `HistoryStore` | GRDB-backed write/read log of transformations (tool + input + output + timestamp + pinned) | `ToolViewModel` (writes), `HistoryPanelView` (reads), `SearchService` (queries) | Tool logic, UI layout |
| `PreferencesStore` | `UserDefaults`-backed observable model for all user settings | All views that present configurable behavior | History data, tool execution |
| `ClipboardDetector` | Polls `NSPasteboard.changeCount` on a background actor; runs predicate chain; publishes `DetectionResult?` | `MenuBarPopoverView` (shows banner), `ToolRegistry` (resolves tool match) | History, preferences persistence |
| `HotkeyManager` | Registers/re-registers global hotkey via `KeyboardShortcuts`; publishes activation events | `FlintApp` (owns), responds to `PreferencesStore` hotkey changes | Window layout |
| `ToolDefinition` | **Value type** (struct). Metadata + detection predicate + view factory closure for one tool | `ToolRegistry` (holds array), `ClipboardDetector` (runs predicates) | Services, database |
| `ToolViewModel` | Per-tool `@Observable` class. Owns input, output, transformation state; writes to `HistoryStore` via injected closure | Its paired `ToolView`, `HistoryStore` | Other tools, UI framework APIs |
| `ToolView` | SwiftUI view. Reads from ViewModel only; user actions call ViewModel methods | Its `ToolViewModel` | Core services directly |
| `MenuBarPopoverView` | Quick launcher and detection banner host | `ToolRegistry`, `ClipboardDetector`, `openWindow` action | `HistoryStore` writes |
| `MainWindowView` | Full workspace; hosts sidebar + active tool area + history panel | `ToolRegistry`, `HistoryStore`, `PreferencesStore` | Clipboard polling |
| `WindowCoordinator` | Manages `NSActivationPolicy` switching (accessory ↔ regular) when main window is shown/hidden | `NSApplication`, `NotificationCenter` for window lifecycle | Tool state |

---

## Recommended Project Structure

```
Flint/
├── App/
│   ├── FlintApp.swift              ← @main; owns @State services; .environment() injection
│   ├── WindowCoordinator.swift     ← NSActivationPolicy switching; bridges AppKit window lifecycle
│   └── AppDelegate.swift           ← @NSApplicationDelegateAdaptor; macOS Services handler
│
├── Core/
│   ├── Services/
│   │   ├── ToolRegistry.swift      ← Holds [ToolDefinition]; computed queries (search, byCategory)
│   │   ├── HistoryStore.swift      ← GRDB DatabaseQueue wrapper; ValueObservation → @Observable
│   │   ├── ClipboardDetector.swift ← @MainActor actor; DispatchSourceTimer polling; predicate chain
│   │   ├── HotkeyManager.swift     ← KeyboardShortcuts registration + callback
│   │   └── PreferencesStore.swift  ← @Observable wrapper around UserDefaults
│   │
│   ├── Models/
│   │   ├── ToolDefinition.swift    ← struct; id, name, category, keywords, detectionPredicate, viewFactory
│   │   ├── HistoryEntry.swift      ← struct; GRDB FetchableRecord + PersistableRecord
│   │   ├── DetectionResult.swift   ← struct; tool: ToolDefinition, confidence: Float, sample: String
│   │   └── ToolCategory.swift      ← enum; Encoding, Formatting, Conversion, Generation, Analysis
│   │
│   └── Extensions/
│       ├── String+Clipboard.swift  ← Clipboard read/write helpers
│       └── View+CopyButton.swift   ← Reusable copy-to-clipboard modifier
│
├── Tools/
│   ├── JSONFormatter/
│   │   ├── JSONFormatterDefinition.swift   ← ToolDefinition factory func; detection predicate
│   │   ├── JSONFormatterViewModel.swift    ← @Observable; pure transform via JSONTransformer
│   │   ├── JSONFormatterView.swift         ← SwiftUI view; reads ViewModel
│   │   └── JSONTransformer.swift           ← Pure struct/enum; all transformation logic; no UI deps
│   ├── Base64/
│   │   ├── Base64Definition.swift
│   │   ├── Base64ViewModel.swift
│   │   ├── Base64View.swift
│   │   └── Base64Transformer.swift
│   ├── URLEncoder/   (same pattern)
│   ├── JWT/          (same pattern)
│   ├── Timestamp/    (same pattern)
│   ├── Hash/         (same pattern)
│   └── UUID/         (same pattern)
│
├── UI/
│   ├── MenuBarPopoverView.swift    ← launcher grid + detection banner
│   ├── MainWindowView.swift        ← sidebar + content area + history panel (NavigationSplitView)
│   ├── SidebarView.swift
│   ├── HistoryPanelView.swift
│   ├── SearchView.swift            ← fuzzy search across tools + history
│   ├── PreferencesView.swift
│   └── Components/
│       ├── ToolGridItemView.swift
│       ├── DetectionBannerView.swift
│       ├── CopyButtonView.swift
│       ├── SyntaxHighlightedTextView.swift  ← NSViewRepresentable wrapping NSTextView
│       └── CodeDisplayView.swift           ← HighlightSwift display-only text
│
└── Resources/
    ├── Assets.xcassets
    ├── Flint.entitlements
    └── highlight.js                ← bundled for WKWebView Markdown preview
```

### Structure Rationale

- **Core/Services/ vs Tools/:** Services are long-lived app-level singletons injected from `FlintApp`. Tools are self-contained, stateless at the definition level; their ViewModels are created on demand per navigation.
- **`*Transformer.swift` alongside every ViewModel:** Pure transformation logic in a separate file with no imports of SwiftUI or AppKit. This boundary is the testability guarantee — `JSONTransformerTests.swift` tests the model layer with zero UI setup.
- **`*Definition.swift` per tool:** Centralizes all metadata (id, name, keywords, detection predicate, view factory) in one place. Adding a new tool means adding one `Definition` file and one line in `ToolRegistry`.
- **UI/ flat for shared chrome:** `MenuBarPopoverView`, `MainWindowView`, and `HistoryPanelView` are app shell — they don't belong in any one tool's folder.

---

## Architectural Patterns

### Pattern 1: App-Level Service Injection with @Observable

**What:** All shared services (`HistoryStore`, `PreferencesStore`, `ClipboardDetector`, `HotkeyManager`, `ToolRegistry`) are declared as `@State` properties in the `@main App` struct and injected into every scene via `.environment()`. This is the only safe ownership point — the `App` struct is never rebuilt by SwiftUI, unlike `View` structs.

**Why @Observable over ObservableObject:** The `@Observable` macro (macOS 14, Swift 5.9) provides property-level dependency tracking — a view only re-renders when a specific property it reads changes. `ObservableObject` + `@Published` triggers a full view refresh on any property change. For services like `HistoryStore` (frequent writes), `@Observable` prevents cascading re-renders across unrelated views.

**Why not static singletons:** Static singletons make testing impossible without global state reset. `@State` in `App` gives the same stable lifetime with injectable, replaceable instances.

```swift
@main
struct FlintApp: App {
    @State private var historyStore = HistoryStore()
    @State private var prefs = PreferencesStore()
    @State private var clipboard = ClipboardDetector()
    @State private var hotkeyManager = HotkeyManager()
    @State private var toolRegistry = ToolRegistry()

    var body: some Scene {
        MenuBarExtra("Flint", systemImage: "wrench.and.screwdriver") {
            MenuBarPopoverView()
        }
        .menuBarExtraStyle(.window)
        .environment(historyStore)
        .environment(prefs)
        .environment(clipboard)
        .environment(toolRegistry)

        WindowGroup(id: "workspace") {
            MainWindowView()
        }
        .environment(historyStore)
        .environment(prefs)
        .environment(clipboard)
        .environment(toolRegistry)

        Settings {
            PreferencesView()
        }
        .environment(prefs)
        .environment(hotkeyManager)
    }
}
```

Views read services via `@Environment(ServiceType.self)`. This is type-safe (crash at compile time if not injected) unlike the older `@EnvironmentObject` (crashes at runtime).

---

### Pattern 2: The ToolDefinition / ToolRegistry Pattern

**What:** Every tool is described by a `ToolDefinition` value type that contains all metadata the app needs to enumerate, search, route to, and detect clipboard matches for that tool. `ToolRegistry` holds an ordered array of definitions and provides query methods.

**Why value type for ToolDefinition:** Definitions are immutable at runtime — they describe a tool's metadata, not its state. A struct with a closure-based view factory is sufficient. No subclassing, no protocol boxing, no `AnyView` type erasure cascade.

```swift
// Core/Models/ToolDefinition.swift
struct ToolDefinition: Identifiable {
    let id: String                       // e.g. "json-formatter"
    let name: String                     // "JSON Formatter"
    let category: ToolCategory
    let keywords: [String]               // for fuzzy search
    let sfSymbol: String                 // icon name

    // Ordered predicate chain entry — nil means "never auto-detect"
    let detectionPredicate: ((String) -> DetectionResult?)?

    // View factory: creates the tool's SwiftUI root view on demand.
    // Returns AnyView to keep the array homogeneous. The actual view
    // is always a concrete type — AnyView used only at this boundary.
    @ViewBuilder
    let makeView: () -> AnyView
}

// Core/Services/ToolRegistry.swift
@Observable
final class ToolRegistry {
    let tools: [ToolDefinition]  // Ordered; defines launcher grid order

    init() {
        tools = [
            JSONFormatterDefinition.make(),
            Base64Definition.make(),
            URLEncoderDefinition.make(),
            JWTDefinition.make(),
            TimestampDefinition.make(),
            HashDefinition.make(),
            UUIDDefinition.make(),
            // Phase 2 tools appended here
        ]
    }

    // Fuzzy search across name + keywords
    func search(_ query: String) -> [ToolDefinition] { ... }

    // Clipboard predicate chain — runs in priority order, returns first match
    func detect(from string: String) -> DetectionResult? {
        for tool in tools {
            if let result = tool.detectionPredicate?(string) { return result }
        }
        return nil
    }
}
```

Adding a new tool in Phase 2: create `RegexDefinition.make()`, add one line to `ToolRegistry.init()`. No changes to any other file.

---

### Pattern 3: MVVM Boundaries — Three Distinct Layers

**Transformer (Model layer) — pure, no SwiftUI:**
```swift
// Tools/JSONFormatter/JSONTransformer.swift
enum JSONTransformer {
    static func prettyPrint(_ input: String, indent: Int) -> Result<String, JSONError> { ... }
    static func minify(_ input: String) -> Result<String, JSONError> { ... }
    static func validate(_ input: String) -> [JSONError] { ... }
}
```
No `import SwiftUI`. No `import AppKit`. Testable with `XCTest` in isolation. This is where correctness lives.

**ViewModel — @Observable, orchestrates state and side effects:**
```swift
// Tools/JSONFormatter/JSONFormatterViewModel.swift
@Observable
final class JSONFormatterViewModel {
    var input: String = ""
    var output: String = ""
    var errors: [JSONError] = []
    var indentSize: Int = 2

    // Injected at creation; avoids tight coupling to a singleton
    private let onSaveHistory: (HistoryEntry) -> Void

    func format() {
        switch JSONTransformer.prettyPrint(input, indent: indentSize) {
        case .success(let result):
            output = result
            errors = []
            onSaveHistory(HistoryEntry(tool: "json-formatter", input: input, output: result))
        case .failure(let error):
            errors = [error]
        }
    }
}
```
The ViewModel owns the "what is happening" state. It calls the Transformer for pure logic and invokes an injected closure to write history — never importing GRDB or touching `HistoryStore` directly.

**View — reads ViewModel, issues commands:**
```swift
// Tools/JSONFormatter/JSONFormatterView.swift
struct JSONFormatterView: View {
    @State private var viewModel = JSONFormatterViewModel(
        onSaveHistory: { /* injected from environment */ }
    )

    var body: some View {
        // Display only — no transformation logic here
    }
}
```

The rule: if a line of code would not change if the visual design changed, it belongs in Transformer or ViewModel.

---

### Pattern 4: Clipboard Auto-Detection Pipeline

**What:** A background actor polls `NSPasteboard.changeCount` every 100ms. On change, it extracts the string value and runs it through `ToolRegistry.detect()` which is the ordered predicate chain. The result is published as an `@Observable` property that `MenuBarPopoverView` observes.

```swift
// Core/Services/ClipboardDetector.swift
@Observable
@MainActor
final class ClipboardDetector {
    var detectionResult: DetectionResult? = nil
    var isEnabled: Bool = true

    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var timer: DispatchSourceTimer?
    private weak var registry: ToolRegistry?

    func start(registry: ToolRegistry) {
        self.registry = registry
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .background))
        t.schedule(deadline: .now(), repeating: .milliseconds(100))
        t.setEventHandler { [weak self] in
            self?.checkPasteboard()
        }
        t.resume()
        timer = t
    }

    private func checkPasteboard() {
        let current = NSPasteboard.general.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current

        guard isEnabled,
              let string = NSPasteboard.general.string(forType: .string),
              !string.isEmpty else {
            Task { @MainActor in self.detectionResult = nil }
            return
        }

        let result = registry?.detect(from: string)
        Task { @MainActor in self.detectionResult = result }
    }
}
```

Detection predicates in priority order (matches PRD section 4.1):
1. Valid JSON (`JSONSerialization.jsonObject` succeeds)
2. JWT pattern (`ey...` prefix + two `.` separators)
3. Base64 (`Data(base64Encoded:)` succeeds, decoded length reasonable)
4. URL-encoded characters (`%[0-9A-Fa-f]{2}` match)
5. Valid URL (`URL(string:)` with scheme succeeds)
6. Pure numeric 10-digit (Unix timestamp range check)
7. Hex color (`#` + 3 or 6 hex chars)
8. UUID pattern (regex `[0-9A-F]{8}-...`)
9. Regex pattern (`/pattern/flags` prefix/suffix)

Each predicate is a `(String) -> DetectionResult?` closure stored on `ToolDefinition`. First non-nil wins.

**The banner:** `MenuBarPopoverView` observes `ClipboardDetector.detectionResult`. When non-nil it shows `DetectionBannerView`. Accept triggers `openWindow(id: "workspace")` + sets the active tool. Dismiss sets `detectionResult = nil` (non-destructive — clipboard unchanged).

---

### Pattern 5: Popover + Window Mode with Activation Policy

**The core problem:** `MenuBarExtra` apps run with `NSApplication.ActivationPolicy.accessory` — no Dock icon, no app switcher entry. macOS will not reliably bring a `WindowGroup` window to the front from this policy. Opening the main workspace window requires temporarily switching to `.regular`, then back to `.accessory` when the window closes.

**Solution — WindowCoordinator:**

```swift
// App/WindowCoordinator.swift
final class WindowCoordinator: NSObject {
    static let shared = WindowCoordinator()

    func openWorkspace() {
        // 1. Switch to regular so the window can become key
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // 2. Open window via notification (cannot call openWindow from App struct directly)
        NotificationCenter.default.post(name: .openWorkspace, object: nil)
    }

    func workspaceDidClose() {
        // 3. Return to accessory after a brief delay (avoids visual flash)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
```

`MainWindowView` observes `NSWindow.willCloseNotification` to call `workspaceDidClose()`.

The `MenuBarPopoverView` Detach button calls `WindowCoordinator.shared.openWorkspace()` which posts the notification; `MainWindowView` listens via `onReceive` or the view uses `@Environment(\.openWindow)` directly if the hotkey flow is used instead.

**Shared state:** Both the popover and the workspace window receive identical service instances (same `@State` objects in `FlintApp`). There is one `HistoryStore`, one `ToolRegistry`, one `ClipboardDetector`. Each tool's `ToolViewModel` is created separately per navigation destination — ViewModels are not shared between windows (each window has its own navigation state and tool activation).

---

### Pattern 6: History Integration Without Tool Coupling

**The problem:** Every tool needs to write to `HistoryStore`, but tools should not import or reference `HistoryStore` directly — that creates a coupling that makes tools hard to test.

**Solution — closure injection:**

`ToolDefinition.makeView()` receives an `onSaveHistory` closure when it constructs the view:

```swift
// Tools/JSONFormatter/JSONFormatterDefinition.swift
enum JSONFormatterDefinition {
    static func make() -> ToolDefinition {
        ToolDefinition(
            id: "json-formatter",
            name: "JSON Formatter",
            category: .formatting,
            keywords: ["json", "format", "pretty", "minify", "validate"],
            sfSymbol: "curlybraces",
            detectionPredicate: { input in
                guard JSONSerialization.isValidJSONObject(
                    (try? JSONSerialization.jsonObject(with: Data(input.utf8))) ?? ""
                ) else { return nil }
                return DetectionResult(toolId: "json-formatter", confidence: 0.95, sample: input)
            },
            makeView: { AnyView(JSONFormatterView()) }
        )
    }
}
```

`JSONFormatterView` reads `HistoryStore` from `@Environment(HistoryStore.self)` and passes a save closure down to `JSONFormatterViewModel`. The ViewModel calls the closure — it never imports GRDB.

For global history (the history panel), `HistoryPanelView` queries `HistoryStore` with `GRDB.ValueObservation` — reactively updating when any tool writes. Per-tool history is a filtered query: `SELECT * FROM history WHERE tool = ? ORDER BY timestamp DESC LIMIT 20`.

---

## Data Flow

### Clipboard Detection → Suggestion Banner

```
NSPasteboard                  (system)
  ↓ changeCount poll (100ms, background queue)
ClipboardDetector.checkPasteboard()
  ↓ string extracted
ToolRegistry.detect(from: string)
  ↓ ordered predicate chain
DetectionResult? (first match wins)
  ↓ @MainActor publish to ClipboardDetector.detectionResult
MenuBarPopoverView (observes @Environment(ClipboardDetector.self))
  ↓ non-nil result
DetectionBannerView displayed
  ↓ user taps "Open Tool"
WindowCoordinator.openWorkspace() + set active tool
  ↓
MainWindowView navigates to matched tool, pre-fills input
```

### Tool Execution → History Write

```
User input → ToolView
  ↓ calls ViewModel.transform()
ToolViewModel (input, output state updated)
  ↓ calls JSONTransformer.prettyPrint() [pure, no UI]
Result<String, Error>
  ↓ ViewModel updates output property
ToolView re-renders (only properties read change, @Observable)
  ↓ ViewModel calls onSaveHistory(entry)
HistoryStore.save(entry) → GRDB INSERT
  ↓ GRDB ValueObservation fires
HistoryPanelView re-renders with new entry
```

### Window Detach Flow

```
User clicks "Open in Window" (popover)
  ↓
WindowCoordinator.openWorkspace()
  ↓ NSApp.setActivationPolicy(.regular)
  ↓ NSApp.activate(ignoringOtherApps: true)
  ↓ NotificationCenter.post(.openWorkspace)
MainWindowView onReceive → openWindow(id: "workspace")
  ↓ WindowGroup window appears (already has shared @State services)
User closes MainWindowView
  ↓ NSWindow.willCloseNotification
WindowCoordinator.workspaceDidClose()
  ↓ NSApp.setActivationPolicy(.accessory)
App returns to menubar-only mode
```

### Search Flow

```
User types in SearchBar (popover or main window)
  ↓ query string published
ToolRegistry.search(query) → [ToolDefinition] (name + keyword fuzzy match)
  ↓
HistoryStore.search(query) → [HistoryEntry] (SQLite LIKE query)
  ↓
SearchResultsView renders merged results, keyboard navigable
User selects result → navigate to tool (with history entry pre-loaded if history result)
```

---

## Build Order (Dependency Graph)

The infrastructure must exist before tools can be built. Within infrastructure, the ToolDefinition protocol/struct is the central dependency for both the registry and the clipboard detector.

```
Phase 1 — Week 1-2: Pure Infrastructure
  1. ToolDefinition + ToolCategory + DetectionResult structs  [no deps]
  2. HistoryEntry struct + GRDB schema + HistoryStore         [deps: GRDB]
  3. PreferencesStore                                         [deps: UserDefaults]
  4. ToolRegistry (stub — no tools registered yet)           [deps: ToolDefinition]
  5. ClipboardDetector                                        [deps: ToolRegistry]
  6. HotkeyManager                                           [deps: KeyboardShortcuts]
  7. WindowCoordinator                                        [deps: AppKit]
  8. FlintApp + scene wiring + .environment() injection      [deps: all above]
  9. MenuBarPopoverView (empty shell)                        [deps: ToolRegistry]
  10. MainWindowView (empty shell, NavigationSplitView)      [deps: ToolRegistry, HistoryStore]
  11. DetectionBannerView                                    [deps: ClipboardDetector, ToolRegistry]

Phase 1 — Week 3-4: First Tool (proves the pattern)
  12. JSONTransformer (pure)                                 [no deps]
  13. JSONFormatterViewModel                                 [deps: JSONTransformer]
  14. JSONFormatterView                                      [deps: JSONFormatterViewModel]
  15. JSONFormatterDefinition.make()                         [deps: JSONFormatterView, ToolDefinition]
  16. Register in ToolRegistry                               [deps: JSONFormatterDefinition]
  → Clipboard detection, history write, search all work for this one tool.
     Repeat steps 12-16 for each subsequent tool.

Phase 1 — Remaining tools (parallel if multiple developers, sequential otherwise)
  17-23. Base64, URLEncoder, JWT, Timestamp, Hash, UUID       [each: same 12-16 pattern]

Phase 2: Extended tools
  24-28. Regex, Color, Markdown, NumberBase, TextDiff         [same pattern; some add Phase 2 packages]

Phase 3: Polish
  29. SearchView refinement (history + tools merged)
  30. macOS Services (AppDelegate NSServicesProvider)
  31. Drag & drop universal handler
  32. Sparkle integration
  33. .dmg + notarization pipeline
```

**Key constraint:** Steps 1-11 must complete before any tool work starts. The `ToolDefinition` struct design is the highest-leverage early decision — changing it later requires touching every `*Definition.swift` file.

---

## Anti-Patterns

### Anti-Pattern 1: ViewModel imports GRDB or HistoryStore directly

**What people do:** `import GRDB` in `JSONFormatterViewModel.swift`, call `try historyStore.save(entry)` directly.

**Why it's wrong:** ViewModel becomes untestable without a real database. Tight coupling means changing the history schema requires touching every tool's ViewModel. History becomes an invisible side effect rather than an explicit contract.

**Do this instead:** Inject `onSaveHistory: (HistoryEntry) -> Void` at ViewModel init. Tests pass a no-op closure. Production passes `historyStore.save`.

---

### Anti-Pattern 2: Tool state shared between popover and workspace window

**What people do:** Create one `@StateObject JSONFormatterViewModel` in `FlintApp` and inject it into both scenes.

**Why it's wrong:** The popover is compact; the workspace is full-featured. They may want different tool-level state (different indent sizes, different mode toggles). Sharing state means actions in the popover silently mutate workspace state. It also means the popover can't close without destroying the workspace's active editing session.

**Do this instead:** Each navigation destination creates its own ViewModel instance. Shared state lives only in the four app-level services (HistoryStore, PreferencesStore, ClipboardDetector, ToolRegistry). Per-tool ViewModels are local to their view.

---

### Anti-Pattern 3: Transformation logic in ToolView or ToolViewModel

**What people do:** `let result = String(Data(base64Encoded: input)!)` inside a SwiftUI `Button` action or directly in ViewModel.

**Why it's wrong:** Untestable. Logic is buried in UI code. Error handling is ad-hoc. Adding a new mode (URL-safe Base64) requires editing the View or ViewModel.

**Do this instead:** All transformation logic lives in `*Transformer.swift` (pure enum/struct with static methods). ViewModels call Transformers. Views call ViewModels. Test coverage is purely at the Transformer layer.

---

### Anti-Pattern 4: Bypassing ToolRegistry for clipboard routing

**What people do:** Add a second `switch` statement in `MenuBarPopoverView` or `ClipboardDetector` that hard-codes tool IDs or types.

**Why it's wrong:** Every place that makes tool routing decisions must be kept in sync. When a Phase 2 tool is added, it won't be auto-detected.

**Do this instead:** The predicate chain in `ToolRegistry.detect()` is the single routing authority. Adding a new tool to the registry automatically makes it eligible for clipboard detection.

---

### Anti-Pattern 5: Polling clipboard on the main thread

**What people do:** Use a `Timer.scheduledTimer` in a View or on `DispatchQueue.main`.

**Why it's wrong:** 100ms polling intervals on the main thread introduce perceptible UI stutter. The main run loop is already busy with rendering.

**Do this instead:** `DispatchSource.makeTimerSource(queue: .global(qos: .background))` fires on a background queue. The result is published back to `@MainActor` via `Task { @MainActor in ... }`. UI updates remain on main thread; polling does not.

---

## Integration Points

### AppKit Bridges

| Bridge | Pattern | Notes |
|--------|---------|-------|
| `NSTextView` (editable syntax highlight) | `NSViewRepresentable` wrapping `NSTextView` with custom `NSTextStorage` subclass | Keep the representable thin — update methods should only set text, not perform highlighting |
| `NSColorSampler` (eyedropper) | Called directly in `ColorTool ViewModel`; result callback dispatched to `@MainActor` | Zero permissions required; works from `.accessory` activation policy |
| `NSColorPanel` | SwiftUI `ColorPicker` wraps it; drop to `NSColorPanel.shared` only for custom configuration | |
| `WKWebView` (Markdown preview + PDF) | `NSViewRepresentable`; `WKWebView.createPDF(configuration:completionHandler:)` | Load HTML string generated by `swift-markdown` visitor; inject highlight.js from bundle |
| macOS Services | `AppDelegate` implements `NSServicesProvider`; routes selected text to `ToolRegistry.detect()` | Registered in `Info.plist` under `NSServices` key |

### Scene Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| `MenuBarExtra` ↔ `WindowGroup` | Shared `@State` services from `FlintApp`; `NotificationCenter` for open-window trigger | `openWindow` environment action is NOT available inside `MenuBarExtra` views — use notification indirection |
| `ToolViewModel` ↔ `HistoryStore` | Injected closure (`onSaveHistory`) — never a direct reference | Keeps tools decoupled from storage layer |
| `ClipboardDetector` ↔ `ToolRegistry` | Direct reference (weak, set at `start(registry:)` time) | ToolRegistry is immutable after init; no cycle risk |
| `WindowCoordinator` ↔ `NSApp` | Direct `NSApp.setActivationPolicy()` calls | Must happen on main thread |

---

## Scaling Considerations

This is a single-user local app; scaling in the traditional sense is not applicable. The relevant scaling dimensions are:

| Concern | With 7 tools (MVP) | With 12 tools (Phase 2) | With 20+ tools (hypothetical) |
|---------|-------------------|------------------------|------------------------------|
| Tool registration | Trivial array append | No change needed | Consider lazy loading definitions if startup time affected |
| Clipboard predicate chain | < 1ms for 9 predicates | < 2ms for 15 predicates | Order matters; expensive predicates (JSON parse) should be short-circuited by cheap pre-checks |
| History search | Instant (100 rows, SQLite LIKE) | Instant | Add FTS5 virtual table if full-text search on large history becomes slow |
| Memory per tool | ViewModel created on navigation, released on back | Same | No accumulation — each navigation destination has independent ViewModel lifecycle |

---

## Sources

- Apple Developer Docs — `@Observable` macro, `.environment()` injection pattern: https://developer.apple.com/documentation/swiftui/model-data
- Apple Developer Docs — `MenuBarExtra` scene: https://developer.apple.com/documentation/SwiftUI/MenuBarExtra
- Apple Developer Docs — `openWindow` / `dismissWindow` environment actions: https://developer.apple.com/documentation/swiftui/environmentvalues/dismisswindow
- Context7 (HIGH confidence) — `.environment()` applied to scenes, `@State` in App struct for shared observable: https://developer.apple.com/documentation/swiftui/scene/environment
- Jesse Squires — `@Observable` vs `ObservableObject` initialization difference (MEDIUM confidence): https://www.jessesquires.com/blog/2024/09/09/swift-observable-macro/
- Peter Steinberger — Activation policy juggling, hidden window pattern for macOS menubar apps (HIGH confidence, 2025): https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items
- artlasovsky.com — `NSActivationPolicy` switching pattern, `NSPanel` nonactivating style (MEDIUM confidence): https://artlasovsky.com/fine-tuning-macos-app-activation-behavior
- PlainPasta/PasteboardMonitor.swift — `DispatchSourceTimer` 100ms polling on background queue (HIGH confidence, real macOS app): https://github.com/hisaac/PlainPasta/blob/main/PlainPasta/PasteboardMonitor.swift
- Apple Developer Docs — `NSPasteboard.changeCount`: https://developer.apple.com/documentation/appkit/nspasteboard/1533544-changecount
- Alexey Naumov — Clean Architecture for SwiftUI, service injection via environment, interactor pattern: https://nalexn.github.io/clean-architecture-swiftui/
- MenuBarExtraAccess (programmatic dismiss workaround, FB10185203): https://github.com/orchetect/MenuBarExtraAccess

---
*Architecture research for: Flint — native macOS menubar developer-utility app*
*Researched: 2026-06-25*
