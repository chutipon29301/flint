# Phase 3: Polish & Distribution — Research

**Researched:** 2026-06-26
**Domain:** macOS Services, SwiftUI drag-and-drop, Sparkle auto-update, Developer ID notarization pipeline
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Carried Forward (apply across Phase 3)**
- CF-01: Reuse `ToolRegistry.detect(from:)` (first-match-wins chain) + `ToolSeed.set/consume` for BOTH Services routing and launcher-routed drops. No new detection abstraction.
- CF-02: Never crash / never freeze the UI on bad input — oversized/binary/invalid-UTF-8 handled gracefully, heavy work off-main.
- CF-03: Not sandboxed in v1 — Services, arbitrary-file drop, and SMAppService all rely on this. Hardened Runtime is ON.

**Services Menu Routing (DIST-01)**
- D-01: One smart entry in the system Services menu ("Open in Flint") — not per-tool entries.
- D-02: Auto-open the best-matched tool, pre-filled via ToolSeed — skip the detection banner. This is an intentional divergence from Phase 1 D-04 (passive clipboard banner).
- D-03: No-match fallback → open the search-first launcher with the text staged in the search/input area. Never a dead end.

**Drag-and-Drop (DIST-02)**
- D-04: Open-tool-only routing. Drop onto open tool loads into THAT tool. Drop onto launcher reads text, runs `detect()`, routes to best tool.
- D-05: Whole-surface drop target with a drag-over overlay — no permanent dedicated drop zone.
- D-06: Graceful, async, validated. Text tools reject binary/oversized with `WarningBannerView`. Binary tools (Base64, Hash) process any file off-main via existing chunked pipeline.

**Onboarding (DIST-03)**
- D-07: One focused welcome window on first run — shows menubar icon location, teaches `⌘⇧Space` hotkey, single CTA to enable Launch at Login (SMAppService). No carousel.

**Auto-Update (DIST-04)**
- D-08: Auto-check in background, prompt to install (Sparkle default). Not silent auto-install.
- D-09: Single stable channel only — no beta opt-in in v1.

### Claude's Discretion
- Exact Services entry label/glyph, no-match staging affordance, drag-over overlay styling/animation, file-size threshold for progress UI, welcome window exact copy/layout/illustration, all codesign/notarytool/create-dmg/appcast plumbing mechanics — consistent with macOS HIG, Light/Dark/accent, VoiceOver labels.
- Whether the welcome window surfaces "Check for Updates" or Preferences link is a builder call.

### Deferred Ideas (OUT OF SCOPE)
- Stable + beta update channels — add only when a beta audience exists.
- Per-tool Services entries — rejected for v1; single smart entry covers the need.

</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| DIST-01 | macOS Services menu lets a user select text anywhere, route it to the best-matching tool pre-filled | NSServices Info.plist declaration, `FlintServiceProvider` service handler, `ToolSeed` + `ToolRegistry.detect()` routing, `WindowCoordinator` activation dance |
| DIST-02 | All tools accept drag-and-drop of text files; binary tools (Base64, Hash) accept any file | SwiftUI `.onDrop(of:isTargeted:perform:)` with `UTType.fileURL`, `NSItemProvider` async URL loading, binary detection, `WarningBannerView` rejection, existing chunked pipeline |
| DIST-03 | App ships as a signed, notarized .dmg that passes Gatekeeper, with a first-run onboarding flow | Xcode Archive → Developer ID sign → notarytool → staple → create-dmg pipeline; `OnboardingWindowView` + `WindowCoordinator` + `PreferencesStore.hasSeenOnboarding` flag |
| DIST-04 | App auto-updates via Sparkle (EdDSA-signed updates) | `SPUStandardUpdaterController` SPM wiring, `generate_keys` + `generate_appcast` tools, `SUPublicEDKey`/`SUFeedURL` in Info.plist, v0.0.1→v0.0.2 dry-run procedure |

</phase_requirements>

---

## Summary

Phase 3 completes Flint's v1.0 distribution readiness. No new tools are added; all four deliverables are integration and distribution concerns that build on frozen Phase 1/2 infrastructure. The technical surface is narrower than prior phases but the failure modes are more consequential: a bad EdDSA key setup locks all users out of auto-update permanently, and a `codesign --deep` mistake silently breaks Sparkle's XPC services at distribution time without failing the build.

The four deliverables are architecturally independent and can be built and verified in parallel waves. DIST-04 (Sparkle + distribution pipeline) carries the most external dependencies and should be de-risked first because it requires an Apple Developer ID certificate and keychain-stored credentials. DIST-01 (Services) and DIST-02 (drag-and-drop) are pure Swift code changes with no external accounts needed. DIST-03 (onboarding) is a single SwiftUI view wired to an existing `PreferencesStore` flag.

The activation-policy dance (Pitfall #2 from Phase 1 research, already solved in `WindowCoordinator`) applies directly to the onboarding window and Services-triggered tool opening — the existing `openWorkspace()` pattern is extended, not replaced.

**Primary recommendation:** Add a new `openOnboarding()` method to the existing `WindowCoordinator`, wire Services via `NSApplicationDelegateAdaptor`-based `AppDelegate` registering a `FlintServiceProvider`, implement drag-drop with `.onDrop(of: [.fileURL])` on each tool surface, and add Sparkle as an SPM dependency initialized in `FlintApp.init()`.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Services pasteboard handler | App / Core Services (`FlintServiceProvider`) | `ToolRegistry.detect()` | NSApplication-level service provider; routing delegated to existing registry |
| Services window activation | App (`WindowCoordinator`) | — | Same activation-policy dance as openWorkspace/openPreferences |
| Drag-and-drop file loading | Tool Views (per-view `.onDrop`) | Core Services (routing for launcher drops) | Each tool view owns its own drop target; launcher uses detect() for routing |
| Drag overlay visual feedback | UI Components (`DropOverlayView`) | — | Stateless overlay composed into tool views |
| Binary file processing on drop | Tools (Base64, Hash chunked pipeline) | — | Reuse existing off-main `FileHandle` chunked pipeline |
| Onboarding window | UI (`OnboardingWindowView`) | App (`WindowCoordinator`) | View owns layout; coordinator owns activation-policy dance to surface it |
| First-run flag | Core Services (`PreferencesStore`) | — | UserDefaults-backed, already the store for all persistent prefs |
| Sparkle updater | App (`SparkleUpdaterService`) | `FlintApp.init()` | SPUStandardUpdaterController lifecycle owned at App level alongside other services |
| EdDSA key + appcast | Build/distribution pipeline | `Info.plist` (SUPublicEDKey) | Key generated once; public key embedded at build time |
| DMG creation + notarization | Build pipeline (CI / manual script) | — | External to Swift code; Xcode Archive + notarytool + staple + create-dmg |

---

## Standard Stack

### Core (already in project, zero new dependencies for DIST-01/02/03)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI | macOS 14.0+ | Onboarding window, drag-drop `.onDrop` modifier | Native; no alternative |
| AppKit (`NSApplication`, `NSPasteboard`) | macOS 14.0+ | Services provider registration, pasteboard reading | Required by NSServices API |
| ServiceManagement (`SMAppService`) | macOS 13.0+ | Launch-at-login CTA in onboarding | Already used in PreferencesStore (INFRA-13) |

### New Package (DIST-04 only)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Sparkle | 2.9.3 | Auto-update with EdDSA-signed appcast | Only production-ready non-MAS update framework; CLAUDE.md locked |

[CITED: CLAUDE.md Sparkle 2.9.3 — locked toolchain decision]
[VERIFIED: GitHub API, 2026-06-08 release date confirms 2.9.3 is current]

### Distribution Toolchain (external, not Swift packages)

| Tool | Version | Purpose | Source |
|------|---------|---------|--------|
| `xcrun notarytool` | bundled with Xcode 26.5 (1.1.2 installed) | Notarize app ZIP / DMG | `altool` permanently removed Nov 2023 |
| `xcrun stapler` | bundled with Xcode | Staple notarization ticket | Required for offline Gatekeeper |
| `create-dmg` | 8.1.0 | DMG packaging with background + symlink | CLAUDE.md locked; NOT yet installed on this machine |
| Sparkle `generate_keys` | bundled with Sparkle 2.9.3 | EdDSA keypair generation, saved to Keychain | Official Sparkle distribution |
| Sparkle `generate_appcast` | bundled with Sparkle 2.9.3 | Sign DMG and generate appcast.xml | Official Sparkle distribution |

[CITED: CLAUDE.md tooling decisions]
[VERIFIED: `xcrun notarytool --version` output = 1.1.2 on this machine]

**Installation required before DIST-04:**
```bash
brew install create-dmg  # or npm install -g create-dmg
```

Node.js 22.22.0 is installed (`node --version`), satisfying create-dmg 8.1.0's Node 20+ requirement. [VERIFIED: `node --version` = v22.22.0]

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Sparkle 2.9.3 | Squirrel | Squirrel is Electron-oriented, unmaintained for native macOS — CLAUDE.md explicitly rejects |
| `notarytool` | `altool` | altool removed Nov 2023 — CLAUDE.md explicitly rejects |
| `create-dmg` | `hdiutil` raw | create-dmg adds background, symlink, DS_Store layout automatically; hdiutil is bare |

---

## Package Legitimacy Audit

> Only one new external Swift package in Phase 3: Sparkle. Slopcheck was unavailable at research time.

| Package | Registry | Age | Downloads/Stars | Source Repo | slopcheck | Disposition |
|---------|----------|-----|-----------------|-------------|-----------|-------------|
| Sparkle 2.9.3 | Swift/GitHub | 13+ years (2006 origin, Sparkle 2 since 2021) | ~15k GitHub stars | github.com/sparkle-project/Sparkle | [ASSUMED] — slopcheck unavailable | Approved — well-known framework, only production-ready non-MAS updater, CLAUDE.md locked |

**Packages removed due to slopcheck [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

*slopcheck was unavailable at research time. Sparkle is the only new package; it is a widely-documented, 13-year-old framework with no credible hallucination risk. Its GitHub URL is the known authoritative source.*

---

## Architecture Patterns

### System Architecture Diagram

```
User selects text in any app
        │
        ▼
macOS Services dispatch ──► FlintServiceProvider.openInFlint(_:userData:error:)
        │                         │
        │                    NSPasteboard.string
        │                         │
        │                    ToolRegistry.detect(from:)
        │                         │
        │               ┌─────────┴──────────┐
        │          match found           no match
        │               │                    │
        │         ToolSeed.set()      launch search with
        │         open matched tool   text staged in field
        │               │                    │
        │         WindowCoordinator.openToolViaService()
        │         (.accessory→.regular→activate→restore)
        │
        ▼
User drops file onto tool surface
        │
        ├── open tool surface ──► .onDrop(of:[.fileURL]) ──► load directly into tool
        │
        └── launcher surface ──► .onDrop(of:[.fileURL]) ──► detect() → ToolSeed.set() → open tool
                                      │
                                 text file?   binary file?
                                      │            │
                                 load as      route to Base64/Hash
                                 String       chunked pipeline

User launches for first time
        │
        ▼
FlintApp.init() checks PreferencesStore.hasSeenOnboarding
        │
        └─ false ──► WindowCoordinator.openOnboarding()
                     (.accessory→.regular→activate→show window)
                           │
                     OnboardingWindowView (480×360, not resizable)
                           │
                     "Enable Launch at Login" ──► PreferencesStore.launchAtLogin = true
                     "Get Started" / "Skip"  ──► hasSeenOnboarding = true, close

Sparkle update check (background, auto on launch 2)
        │
        ▼
SPUStandardUpdaterController (owned in FlintApp.init)
        │
        ├── checks SUFeedURL appcast.xml
        └── if update found ──► Sparkle standard UI sheet (Flint owns no custom UI)
```

### Recommended Project Structure (new files only)

```
App/
├── FlintApp.swift             # add Sparkle init + onboarding gate + AppDelegate adaptor
├── AppDelegate.swift          # NEW: NSApplicationDelegateAdaptor target — registers servicesProvider
├── WindowCoordinator.swift    # add openOnboarding(), openToolViaService() methods
Core/
├── Services/
│   ├── FlintServiceProvider.swift   # NEW: NSObject @objc service handler
│   ├── SparkleUpdaterService.swift  # NEW: SPUStandardUpdaterController wrapper
│   └── PreferencesStore.swift       # add hasSeenOnboarding key
UI/
├── OnboardingWindowView.swift       # NEW: first-run welcome window
├── Components/
│   └── DropOverlayView.swift        # NEW: drag-over visual feedback
```

### Pattern 1: NSServices Registration (DIST-01)

**What:** Register a service provider in applicationDidFinishLaunching so macOS routes "Open in Flint" invocations to the app.

**When to use:** Once at app startup, in the AppDelegate.

```swift
// App/AppDelegate.swift
// Source: Apple Dev Docs — SysServices/Articles/providing.html [CITED]

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register the service provider (only one per app).
        // FlintServiceProvider handles the pasteboard text and routes via ToolRegistry.
        NSApp.servicesProvider = FlintServiceProvider.shared
    }
}

// Add to FlintApp.swift:
// @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
```

**Info.plist NSServices entry** — because GENERATE_INFOPLIST_FILE is enabled (confirmed in pbxproj), NSServices must be added via a supplementary plist file or by switching to a manual Info.plist. Recommended: create `Info.plist` at the project root and set INFOPLIST_FILE in build settings (turn off GENERATE_INFOPLIST_FILE), or use the Xcode target's Info tab to add the NSServices array as a custom entry.

```xml
<!-- Info.plist NSServices section [CITED: Apple Dev Docs — SysServices/Articles/properties.html] -->
<key>NSServices</key>
<array>
  <dict>
    <key>NSMenuItem</key>
    <dict>
      <key>default</key>
      <string>Open in Flint</string>
    </dict>
    <key>NSMessage</key>
    <string>openInFlint</string>
    <key>NSPortName</key>
    <string>Flint</string>
    <key>NSSendTypes</key>
    <array>
      <string>public.plain-text</string>
    </array>
    <!-- NSReturnTypes omitted: service only reads text, does not replace it -->
  </dict>
</array>
```

Key notes:
- `NSMessage` maps to the selector name. The `@objc` method is `openInFlint(_:userData:error:)`. [CITED: nilcoalescing.com/blog/macOSSystemWideServices]
- `NSPortName` must match `CFBundleName` (or a shortened name). For Flint: `"Flint"`.
- `NSSendTypes`: `"public.plain-text"` is the modern UTI equivalent of `NSStringPboardType`. [ASSUMED — should be verified; `NSStringPboardType` also works and is more widely documented in examples]
- `NSReturnTypes` can be omitted when the service only reads the selection and doesn't replace it. [ASSUMED — the Apple archive docs show examples without return types for read-only services]
- Services from apps outside `~/Library/Services/` require logout/login to appear — OR call `NSUpdateDynamicServices()` immediately after setting `servicesProvider`. During development, call this manually to avoid log-out/log-in cycles. [CITED: developer.apple.com/library/archive SysServices]

```swift
// Core/Services/FlintServiceProvider.swift
// [CITED: nilcoalescing.com/blog/macOSSystemWideServices]

import AppKit

final class FlintServiceProvider: NSObject, @unchecked Sendable {
    static let shared = FlintServiceProvider()
    private override init() {}

    // The selector name must match NSMessage in Info.plist: "openInFlint"
    @objc func openInFlint(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString>?
    ) {
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return }
        // Route on main actor — service handler is called on an arbitrary thread.
        Task { @MainActor in
            let registry = ToolRegistry.shared  // or inject; see integration note below
            let seed = ToolSeed.shared
            if let result = registry.detect(from: text) {
                seed.set(toolId: result.toolId, value: text)
                WindowCoordinator.shared.openToolViaService(toolId: result.toolId)
            } else {
                // No match — open launcher with text staged
                WindowCoordinator.shared.openLauncherWithStagedText(text)
            }
        }
    }
}
```

**Integration note:** `ToolRegistry` and `ToolSeed` are `@State` in `FlintApp` (the lifecycle-safe pattern from Phase 1). `FlintServiceProvider` needs access to them. Options:
- Add `ToolRegistry.shared` and `ToolSeed.shared` static singletons (Phase 1 avoided this by using `@State`-based injection into views, but service providers are not views).
- Post a `Notification` from `FlintServiceProvider` and have `FlintApp` observe it on `@MainActor`. This is the cleanest pattern that preserves the existing `@State` ownership.

**Recommended:** Post a notification with the text payload from `FlintServiceProvider`; `FlintApp` observes it and performs the seed + open dance. This avoids adding global singletons to previously-clean service objects.

### Pattern 2: Drag-and-Drop File Loading (DIST-02)

**What:** Each tool view and the launcher surface use `.onDrop(of: [.fileURL])` to accept dropped files.

**When to use:** On every tool's root view and on `MenuBarPopoverView`'s root content area.

```swift
// Source: eclecticlight.co/2024/05/21/swiftui-on-macos-drag-and-drop-and-more [MEDIUM confidence]
// and Apple SwiftUI documentation for onDrop [CITED]

import SwiftUI
import UniformTypeIdentifiers

// 1. Text-only tool view — load as String, reject binary
.onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
    guard let provider = providers.first else { return false }
    _ = provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier,
                          options: nil) { item, error in
        guard let data = item as? Data,
              let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
        Task {
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                await MainActor.run { viewModel.loadInput(text) }
            } catch {
                // Binary or non-UTF8: show WarningBannerView
                await MainActor.run {
                    viewModel.showDropError("File contains non-text data. Try Base64 or Hash.")
                }
            }
        }
    }
    return true
}
```

**File type detection (text vs binary):** The safest approach for non-sandboxed apps is to attempt `String(contentsOf: url, encoding: .utf8)` and catch the error — a binary file will throw, triggering the rejection path. Do not rely on UTI alone because `.txt` files contain text but Finder labels any file with `.fileURL`. [ASSUMED — this is a common pattern but not verified against official docs]

**File reference URL canonicalization:** macOS sometimes delivers `file:///.file/id=...` alias URLs rather than regular paths. These resolve automatically when passed to `String(contentsOf:)` or `FileHandle(forReadingFrom:)` on non-sandboxed apps. No special handling needed for v1. [MEDIUM confidence — community-verified behavior on non-sandboxed apps]

**NSItemProvider threading:** The completion block for `loadItem(forTypeIdentifier:options:completionHandler:)` is called on an internal queue, NOT main. Always dispatch UI updates via `Task { @MainActor in ... }` or `DispatchQueue.main.async`. [CITED: Apple NSItemProvider documentation]

**Binary tools (Base64/Hash):** The existing `FileHandle`-based chunked pipeline in `Base64ViewModel` and `HashViewModel` already handles `URL` inputs off-main. The `.onDrop` handler only needs to resolve the URL and pass it to the existing `loadFile(url:)` entry point on those ViewModels.

### Pattern 3: Sparkle Integration (DIST-04)

**What:** Wrap `SPUStandardUpdaterController` in a service, initialize it in `FlintApp.init()`, wire `SUPublicEDKey`/`SUFeedURL` into Info.plist.

**When to use:** Add to `FlintApp` alongside other service initialization.

```swift
// Core/Services/SparkleUpdaterService.swift
// Source: sparkle-project.org/documentation/programmatic-setup [CITED]

import Sparkle

@Observable
@MainActor
final class SparkleUpdaterService {
    let updaterController: SPUStandardUpdaterController

    // Expose canCheckForUpdates for optional "Check for Updates" menu item
    var canCheckForUpdates: Bool = false

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        updaterController.updater.checkForUpdates()
    }
}

// In FlintApp.init() or as @State:
// @State private var sparkle = SparkleUpdaterService()
// No .environment() injection needed — updater is self-contained.
```

**Info.plist keys required for Sparkle** [CITED: sparkle-project.org/documentation]:
```xml
<key>SUPublicEDKey</key>
<string><!-- base64 public key from generate_keys output --></string>
<key>SUFeedURL</key>
<string>https://YOUR_HOST/appcast.xml</string>
```

These must be added to the actual Info.plist. Since Flint currently uses GENERATE_INFOPLIST_FILE=YES (confirmed in pbxproj), these keys must either:
- Be added via Xcode's target Info tab → Custom iOS Target Properties (they appear in the generated plist), OR
- Switch to a manual Info.plist and set `INFOPLIST_FILE` in build settings.

The GENERATE_INFOPLIST_FILE path is preferable to avoid maintaining a full Info.plist. [ASSUMED — Xcode 16 supports custom keys in generated plist via build settings / target Info tab, but the exact UI path should be verified]

### Pattern 4: EdDSA Key Generation and Appcast (DIST-04)

**The one-time setup sequence** [CITED: sparkle-project.org/documentation]:

```bash
# Step 1 — Run ONCE. Private key saved to login Keychain. Public key printed to stdout.
# Run from the Sparkle distribution root (or the .build/checkouts path after SPM resolves).
./bin/generate_keys
# Output: "Public key (SUPublicEDKey value): <base64-string>"
# Embed this in Info.plist SUPublicEDKey immediately. NEVER lose the private key.
```

**Appcast XML format** [CITED: sparkle-project.org/documentation/publishing]:
```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Flint Updates</title>
    <link>https://YOUR_HOST/appcast.xml</link>
    <item>
      <title>Version 0.0.2</title>
      <sparkle:version>2</sparkle:version>
      <sparkle:shortVersionString>0.0.2</sparkle:shortVersionString>
      <sparkle:releaseNotesLink>https://YOUR_HOST/release-notes/0.0.2.html</sparkle:releaseNotesLink>
      <pubDate>Thu, 26 Jun 2026 00:00:00 +0000</pubDate>
      <enclosure url="https://YOUR_HOST/Flint-0.0.2.dmg"
                 sparkle:edSignature="[generated by generate_appcast]"
                 length="[bytes]"
                 type="application/octet-stream"/>
    </item>
  </channel>
</rss>
```

**generate_appcast usage** [CITED: sparkle-project.org/documentation/publishing]:
```bash
# Place Flint-0.0.2.dmg (notarized, stapled) in a folder.
# Run generate_appcast from Sparkle's bin/ directory.
./bin/generate_appcast /path/to/updates_folder/
# Produces: appcast.xml with sparkle:edSignature populated (reads private key from Keychain)
# Produces: delta .delta files for incremental updates
# Grant Keychain access when prompted.
```

### Pattern 5: Notarization Pipeline (DIST-03/04)

**Full sequence for a release build** [CITED: Apple Developer Documentation; CITED: steipete.me/posts/2025/code-signing-and-notarization-sparkle-and-tears]:

```bash
# 1. Archive in Xcode: Product → Archive → Distribute App → Developer ID
#    Xcode automatically re-signs Sparkle XPC services and strips get-task-allow.
#    STRONGLY PREFERRED over manual codesign sequence for first-time setup.

# 2. Export the .app from the archive organizer.

# 3. Store notarization credentials ONCE (one-time setup):
xcrun notarytool store-credentials "NOTARYTOOL_PROFILE" \
  --apple-id "you@example.com" \
  --team-id "XXXXXXXXXX" \
  --password "app-specific-password"

# 4. ZIP the app for notarization submission:
ditto -c -k --keepParent Flint.app Flint.zip

# 5. Submit and wait:
xcrun notarytool submit Flint.zip \
  --keychain-profile "NOTARYTOOL_PROFILE" \
  --wait

# 6. Staple the notarization ticket to the app:
xcrun stapler staple Flint.app

# 7. Verify:
spctl -a -t exec -vvv Flint.app

# 8. Create the DMG (create-dmg handles notarization-ready layout):
create-dmg Flint.app ./dist/
# Produces: Flint X.Y.Z.dmg (drag-to-Applications layout)

# 9. Notarize the DMG as well (optional but recommended):
xcrun notarytool submit "Flint X.Y.Z.dmg" \
  --keychain-profile "NOTARYTOOL_PROFILE" \
  --wait
xcrun stapler staple "Flint X.Y.Z.dmg"
```

**Sparkle XPC re-signing warning** [CITED: steipete.me/posts/2025/code-signing-and-notarization-sparkle-and-tears]:
- Xcode Archive → Export → Developer ID path re-signs XPC services automatically in the correct order. Use this path.
- If doing manual `codesign`, NEVER use `codesign --deep`. Sign XPC services individually first (Installer.xpc, Downloader.xpc, Autoupdate binary, Sparkle.framework), then sign the app bundle last.
- Non-sandboxed apps: the XPC services (Installer, Downloader) are bundled with Sparkle but not strictly required for functionality. They can be removed via a post-install script. However, leaving them in and letting Xcode Archive handle signing is simpler and safer. [CITED: sparkle-project.org/documentation/sandboxing — "non-sandboxed apps may optionally remove XPC services"]
- No extra entitlements needed for non-sandboxed app. The `-spks`/`-spki` mach-lookup entitlements are only for sandboxed apps.

### Pattern 6: Onboarding Window (DIST-03)

**What:** Show a 480×360 non-resizable window once on first launch, above the frontmost app.

**First-run detection:**
```swift
// Core/Services/PreferencesStore.swift — add this property:
var hasSeenOnboarding: Bool {
    get { defaults.bool(forKey: "lathe.hasSeenOnboarding") }
    set { defaults.set(newValue, forKey: "lathe.hasSeenOnboarding") }
}
```

**Trigger in FlintApp:**
```swift
// In FlintApp — scene modifier on MenuBarExtra or an .onAppear on the popover:
.onAppear {
    if !prefs.hasSeenOnboarding {
        WindowCoordinator.shared.openOnboarding()
    }
}
```

**WindowCoordinator extension:**
```swift
// App/WindowCoordinator.swift — add:
func openOnboarding() {
    windowCount += 1
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        NotificationCenter.default.post(name: .openOnboarding, object: nil)
    }
}
```

Add a new `WindowGroup(id: "onboarding")` in `FlintApp.body` for `OnboardingWindowView`. Use `@Environment(\.openWindow) private var openWindow` to open it, or use the `NotificationCenter` pattern already established for `.openWorkspace`.

**Window sizing:** `.defaultSize(width: 480, height: 360)` + `.resizability(.contentSize)` (lock aspect, no free resize) or `.fixedSize()` on the content view. The onboarding window should not be resizable (D-07 spec: 480×360).

**Dismiss and flag:**
```swift
// OnboardingWindowView dismissal:
prefs.hasSeenOnboarding = true
// Then close window:
NSApp.windows.first { $0.identifier?.rawValue == "onboarding" }?.close()
// OR use @Environment(\.dismiss) — works for WindowGroup-based windows (not MenuBarExtra)
```

### Anti-Patterns to Avoid

- **`codesign --deep` on Sparkle bundles:** Corrupts XPC service signatures. Sign each component individually, or use Xcode Archive export. [CITED: steipete.me 2025]
- **`altool` for notarization:** Permanently removed November 2023. Will fail silently with auth errors. [CITED: CLAUDE.md]
- **`NSUpdateDynamicServices()` not called during dev:** Services registered in `/Applications` require logout/login without it. Call it immediately after `servicesProvider =` in development. [CITED: Apple SysServices archive docs]
- **Firing Sparkle on first launch:** Sparkle's default is to not check on the very first launch (only on second+ launch). This is intentional and correct per Sparkle docs. Do not override it for v1.
- **Not incrementing `CFBundleVersion`:** Sparkle uses the integer `CFBundleVersion` (not `CFBundleShortVersionString`) to determine if an update is available. `CFBundleVersion` for v0.0.1 must be `1`, v0.0.2 must be `2`, etc. The appcast `sparkle:version` must match this. [CITED: sparkle-project.org/documentation/publishing]
- **Losing the EdDSA private key:** The private key is saved in the login Keychain by `generate_keys`. If lost, all existing users cannot receive future updates (Sparkle will refuse appcast items that don't match the embedded public key). Store the private key in a secure off-machine location (CI secrets, 1Password). [CITED: SUMMARY.md Pitfall #10]

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Auto-update mechanism | Custom update checker + installer | Sparkle 2.9.3 | Delta updates, EdDSA verification, XPC sandbox installer, standard macOS UI sheet — 13+ years of edge cases |
| EdDSA signing for appcast | Custom signing script | `generate_appcast` (Sparkle bin) | Handles key retrieval from Keychain, delta file generation, XML format, and signature verification |
| DMG creation with symlink | `hdiutil` raw commands | `create-dmg 8.1.0` | Background image, Applications symlink, DS_Store layout, notarization-compatible output in one command |
| File type detection on drop | `libmagic` or manual byte sniffing | `String(contentsOf:encoding:.utf8)` throw | Sufficient for the text/binary distinction needed; existing chunked pipeline handles binary |
| Services activation dance | Custom `NSWorkspace` activation | `WindowCoordinator.shared.openToolViaService()` | Already solved and tested for workspace/preferences; extend, don't rewrite |

**Key insight:** The distribution pipeline toolchain (Sparkle, notarytool, create-dmg) is well-maintained software that encapsulates 10+ years of macOS distribution edge cases. Any custom reimplementation will miss delta updates, Gatekeeper-specific DMG layout requirements, or EdDSA signature format details.

---

## Runtime State Inventory

> Not applicable. Phase 3 adds new capabilities (Services, drag-drop, Sparkle, onboarding). No renaming, refactoring, or migration of existing stored state. Existing `PreferencesStore` keys are extended (new `hasSeenOnboarding` key added); no migration needed because a missing UserDefaults key returns `false` (Bool default), which correctly triggers onboarding on the first run after the update.

---

## Common Pitfalls

### Pitfall 1: GENERATE_INFOPLIST_FILE conflicts with NSServices and Sparkle keys

**What goes wrong:** The project uses `GENERATE_INFOPLIST_FILE = YES` (confirmed in pbxproj). `NSServices` is a complex array-of-dictionaries key that cannot be expressed as a single `INFOPLIST_KEY_*` build setting. Similarly, `SUPublicEDKey` is a string that cannot be set via build settings in Xcode's generated plist UI.

**Why it happens:** Xcode's auto-generated plist supports simple scalar keys via `INFOPLIST_KEY_*` build settings, but not arbitrary nested structures like `NSServices`.

**How to avoid:** Create a manual `Info.plist` file at the project root. In Xcode build settings: set `GENERATE_INFOPLIST_FILE = NO`, set `INFOPLIST_FILE = Info.plist`. Migrate all existing `INFOPLIST_KEY_*` build settings into the manual file (there are ~5: `CFBundleDisplayName`, `LSApplicationCategoryType`, `LSBackgroundOnly`, `LSUIElement`, `NSHumanReadableCopyright`, `NSPrincipalClass`).

**Warning signs:** `codesign -d --entitlements - Flint.app` shows no `NSServices` key at runtime; Services entry never appears in the menu.

### Pitfall 2: Services entry not appearing in Services menu

**What goes wrong:** After Info.plist is configured and the app is running, "Open in Flint" does not appear in other apps' Services menus.

**Why it happens:** macOS caches the services database. Apps in `/Applications` update the cache on login. During development, the app is launched from Xcode or a build folder.

**How to avoid:** Call `NSUpdateDynamicServices()` immediately after setting `NSApp.servicesProvider` in `applicationDidFinishLaunching`. In production, install the app to `/Applications/` and the cache updates normally at login. [CITED: Apple SysServices archive docs]

**Warning signs:** Services menu appears but "Open in Flint" is missing even after app restart.

### Pitfall 3: Activation policy race condition when Services opens a window

**What goes wrong:** The tool or launcher opens behind the frontmost app, invisible to the user.

**Why it happens:** Flint runs as `.accessory` policy (no Dock icon). macOS requires `.regular` policy for windows to appear in front reliably. The `openWorkspace()` pattern already addresses this, but service invocations arrive on an AppKit queue, not the main SwiftUI queue.

**How to avoid:** All window-opening logic must be on `@MainActor`. The `FlintServiceProvider` handler posts a `Notification` (not a direct call) which `FlintApp` receives on the main actor. The `WindowCoordinator.openToolViaService()` method follows the identical `.accessory → .regular → activate → 100ms delay → show → restore .accessory` dance from the existing `openWorkspace()`. [CITED: SUMMARY.md Pitfall #2, WindowCoordinator.swift]

**Warning signs:** Window appears in Exposé but is behind other apps; requires clicking Flint's Dock icon (which shouldn't exist) to focus.

### Pitfall 4: NSItemProvider file URL delivered as file reference (alias) URL

**What goes wrong:** `url.path` returns `/private/var/folders/.../...` or `file:///.file/id=...` instead of the user-visible path.

**Why it happens:** Finder can deliver file-reference URLs for alias-style drags, especially from the Desktop or external volumes.

**How to avoid:** Pass the URL directly to `String(contentsOf:)` or `FileHandle(forReadingFrom:)`. Swift's Foundation resolves file-reference URLs automatically on non-sandboxed apps. Do NOT use `url.path` for display — use `url.lastPathComponent` instead. [MEDIUM confidence — community-verified behavior; no official Apple doc found]

### Pitfall 5: Sparkle EdDSA public key embedded AFTER first v1.0 release

**What goes wrong:** If Flint ships v1.0 without `SUPublicEDKey` in Info.plist, then adds it in v1.1, Sparkle will see a new key in the new bundle but no key in the old bundle. The update will be rejected as a security downgrade.

**Why it happens:** Sparkle checks that the key hasn't *disappeared* (which would allow stripping signatures). Adding a new key to a previously unsigned app is treated as suspicious.

**How to avoid:** Run `generate_keys`, embed the public key in Info.plist, and ship v0.0.1 (or v1.0) with the key already present — even before the first appcast update exists. The key must be in the FIRST distributed build. [CITED: SUMMARY.md Pitfall #10; Sparkle discussion #2597]

### Pitfall 6: Cold-start regression from Sparkle initialization

**What goes wrong:** `SPUStandardUpdaterController(startingUpdater: true, ...)` called in `FlintApp.init()` adds synchronous initialization cost, pushing cold start above 500ms budget.

**Why it happens:** Sparkle starts its updater logic immediately when `startingUpdater: true` is passed. Even if it defers the actual network check, the initialization path touches disk for preferences.

**How to avoid:** Initialize `SparkleUpdaterService` lazily — create it in `FlintApp.init()` but with `startingUpdater: false`, then call `startUpdater()` in an async task from `.onAppear` on the popover content. This shifts the Sparkle startup off the critical path. Measure with Instruments "App Launch" before and after to verify cold-start stays under 500ms. [ASSUMED — this lazy init approach is documented in Sparkle's programmatic setup guide but the exact cold-start impact is unconfirmed]

### Pitfall 7: OnboardingWindowView shown before app is fully initialized

**What goes wrong:** Onboarding window opens before `ToolRegistry`, `HistoryStore`, or other services finish async init (GRDB opening off-main), causing crashes or empty state in early frames.

**Why it happens:** `PreferencesStore.hasSeenOnboarding` is checked at app launch; if the flag triggers `openOnboarding()` synchronously before the async database open completes, race conditions occur.

**How to avoid:** Gate the onboarding check inside `.onAppear` on `MenuBarPopoverView` (the popover is shown only after the MenuBarExtra scene is ready and all services are injected). The services are `@State` in `FlintApp`, which means they're initialized before `body` is computed. GRDB's async open is a background task already; `PreferencesStore` reads only `UserDefaults` which is synchronous. This is safe. [MEDIUM confidence]

### Pitfall 8: `create-dmg` not installed at distribution time

**What goes wrong:** The distribution pipeline script calls `create-dmg` and fails because it's not on the build machine's `PATH`.

**Why it happens:** `create-dmg` is not bundled with Xcode; it must be installed via Homebrew or npm.

**How to avoid:** Add `brew install create-dmg` (or `npm install -g create-dmg`) to the project README's "Distribution" section. On this machine, Node.js 22.22.0 is installed, so `npm install -g create-dmg` works. Homebrew is the recommended approach for CI. Document this dependency explicitly in the release checklist. [VERIFIED: node --version = v22.22.0 on this machine; create-dmg not yet installed]

---

## Code Examples

### Services handler — full wiring via Notification

```swift
// App/AppDelegate.swift [CITED: nilcoalescing.com/blog/macOSSystemWideServices]
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = FlintServiceProvider.shared
        // Force cache update during development — harmless in production
        NSUpdateDynamicServices()
    }
}
```

```swift
// Core/Services/FlintServiceProvider.swift
import AppKit

final class FlintServiceProvider: NSObject, @unchecked Sendable {
    static let shared = FlintServiceProvider()

    @objc func openInFlint(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString>?
    ) {
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return }
        NotificationCenter.default.post(
            name: .serviceDidReceiveText,
            object: nil,
            userInfo: ["text": text]
        )
    }
}

extension Notification.Name {
    static let serviceDidReceiveText = Notification.Name("lathe.serviceDidReceiveText")
    static let openOnboarding = Notification.Name("lathe.openOnboarding")
}
```

```swift
// FlintApp.swift — receive service notification on MainActor
.onReceive(NotificationCenter.default.publisher(for: .serviceDidReceiveText)) { notification in
    guard let text = notification.userInfo?["text"] as? String else { return }
    if let result = toolRegistry.detect(from: text) {
        toolSeed.set(toolId: result.toolId, value: text)
        WindowCoordinator.shared.openToolViaService(toolId: result.toolId)
    } else {
        WindowCoordinator.shared.openLauncherWithStagedText(text)
    }
}
```

### Drag-and-drop with overlay — text tool

```swift
// Generic drop handler for text-only tools [MEDIUM confidence: pattern from community sources]
import SwiftUI
import UniformTypeIdentifiers

extension View {
    func textFileDrop(onLoad: @escaping (String) -> Void,
                      onError: @escaping (String) -> Void) -> some View {
        self.onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task {
                    do {
                        let text = try String(contentsOf: url, encoding: .utf8)
                        await MainActor.run { onLoad(text) }
                    } catch {
                        await MainActor.run {
                            onError("File contains non-text data. Try Base64 or Hash.")
                        }
                    }
                }
            }
            return true
        }
    }
}
```

### Sparkle init (lazy, off critical path)

```swift
// Core/Services/SparkleUpdaterService.swift [CITED: sparkle-project.org/documentation/programmatic-setup]
import Sparkle

@Observable @MainActor
final class SparkleUpdaterService {
    private(set) var controller: SPUStandardUpdaterController?

    func start() {
        // Called from popover .onAppear — off cold-start critical path
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
}
```

### Local v0.0.1 → v0.0.2 dry-run procedure

```bash
# [CITED: sparkle-project.org/documentation — Testing Updates section]

# 1. Build and archive v0.0.1 with CFBundleVersion=1, SUPublicEDKey embedded.
# 2. Notarize v0.0.1.dmg, staple it.
# 3. Run generate_appcast on a folder containing only Flint-0.0.1.dmg.
#    Host appcast.xml locally or on a staging server.
# 4. Install v0.0.1 to /Applications/Flint.app.

# 5. Build v0.0.2 with CFBundleVersion=2, same SUPublicEDKey, same SUFeedURL.
# 6. Notarize v0.0.2.dmg, staple it.
# 7. Run generate_appcast on a folder containing BOTH v0.0.1.dmg and v0.0.2.dmg.
#    This generates delta updates from v0.0.1→v0.0.2.
# 8. Host (or replace) appcast.xml with the new one pointing to v0.0.2.

# 9. Force an immediate update check (skips the "second launch" requirement):
defaults delete com.flint.app SULastCheckTime

# 10. Launch Flint. Sparkle should detect the update and show the update sheet.
# Verify: update sheet appears, installs, app restarts at v0.0.2.
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `altool` for notarization | `xcrun notarytool` | Nov 2023 (Apple removed altool) | altool now returns auth error; notarytool is the only path |
| DSA/RSA signatures in Sparkle 1.x | EdDSA (Ed25519) in Sparkle 2.x | Sparkle 2.0 (2021) | Simpler key management; `generate_keys` + Keychain storage |
| Sparkle via CocoaPods/Carthage | Sparkle 2.x via SPM | Sparkle 2.0+ | Native SPM package, no separate Carthage build step |
| `NSStringPboardType` pasteboard type | `public.plain-text` UTI | macOS 10.15+ (UTType framework) | Both work; UTI is the modern approach |

**Deprecated/outdated:**
- `altool`: removed. Use `notarytool`. [CITED: CLAUDE.md]
- Sparkle 1.x DSA signatures: superseded by EdDSA in all Sparkle 2.x versions. Do not use `SUPublicDSAKeyFile`. [ASSUMED — based on Sparkle 2.x changelog; verified Sparkle 2.9.3 is current]
- Highlightr: deprecated by maintainer — already addressed in Phase 1/2. Not relevant to Phase 3.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `NSSendTypes: ["public.plain-text"]` is the correct modern UTI for NSServices text input (vs `NSStringPboardType`) | Pattern 1 | Services entry may not fire for plain text in some apps; use `NSStringPboardType` as fallback or test both |
| A2 | `NSReturnTypes` can be omitted when the service only reads text and does not replace the selection | Pattern 1 | If required, macOS might not show the Services entry or might expect a replaced selection; test by invoking service and checking if original text is replaced |
| A3 | String(contentsOf:encoding:.utf8) throwing is a reliable text-vs-binary detector for the drop handler | Pattern 2 | Files with valid UTF-8 that are semantically binary (e.g., Base64-encoded zip in a .txt) would be accepted; acceptable risk for v1 |
| A4 | File reference URLs (file:///.file/id=...) resolve automatically via Foundation on non-sandboxed macOS 14 | Pattern 2 | Drop handler silently fails to read file; add URL.resolvingSymlinksInPath() or URL(resolvingBookmarkData:) as fallback |
| A5 | SPUStandardUpdaterController with startingUpdater:false + lazy .start() call from onAppear keeps cold-start under 500ms | Pitfall 6 | If Sparkle's init is still synchronous even with startingUpdater:false, the cold-start budget may be exceeded; measure with Instruments before shipping |
| A6 | Custom NSServices Info.plist keys can be added via Xcode 16's target Info tab when GENERATE_INFOPLIST_FILE=YES, without switching to a manual Info.plist | Pitfall 1 | If Xcode doesn't support nested array-of-dict keys in the Info tab for generated plist, a manual Info.plist is required |
| A7 | The 100ms DispatchQueue.main.asyncAfter delay in WindowCoordinator is sufficient for service-triggered window activation | Pattern 1 | Window may still appear behind other apps on slower machines; may need to increase to 150ms or use a different activation strategy |

**If this table is empty:** All claims in this research were verified or cited — no user confirmation needed. (Table is not empty — A1-A7 flag areas to test during implementation.)

---

## Open Questions

1. **NSServices Info.plist with GENERATE_INFOPLIST_FILE=YES in Xcode 16**
   - What we know: The project uses generated Info.plist; NSServices is a complex nested structure.
   - What's unclear: Whether Xcode 16's target Info tab supports array-of-dict entries like NSServices natively, or if a manual Info.plist is required.
   - Recommendation: Test in Wave 0 (DIST-01 setup). If Xcode Info tab supports it, use it. Otherwise, create `Info.plist` manually and set `INFOPLIST_FILE` build setting.

2. **ToolRegistry / ToolSeed access from FlintServiceProvider**
   - What we know: Both are `@State` objects owned by `FlintApp`; `FlintServiceProvider` is an NSObject created before the SwiftUI environment is ready.
   - What's unclear: Whether the Notification-based bridge pattern introduces any ordering issues (FlintApp must subscribe before any service invocation arrives).
   - Recommendation: Subscribe to `.serviceDidReceiveText` in `FlintApp.body` using `.onReceive` inside the `MenuBarExtra` content. The MenuBarExtra is created at app launch, so this subscription is in place before any user action can trigger a service invocation.

3. **Appcast hosting URL for v0.0.1→v0.0.2 dry-run**
   - What we know: `SUFeedURL` must be a resolvable URL; Sparkle will not check a local file URL in production mode.
   - What's unclear: Whether a localhost HTTP server (via `python3 -m http.server`) is sufficient for the local dry-run, or if Sparkle requires HTTPS.
   - Recommendation: Test with localhost HTTP first. If Sparkle requires HTTPS, use a staging server or a tunneling service (ngrok) for the dry-run. Update `SUFeedURL` to the production URL before the real v1.0 release.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode | All build/sign/notarize | ✓ | Xcode 26.5 (17F42) | — |
| `xcrun notarytool` | DIST-03/04 notarization | ✓ | 1.1.2 | — |
| `xcrun stapler` | DIST-03/04 stapling | ✓ | bundled with Xcode | — |
| `create-dmg` | DIST-03 DMG creation | ✗ | — | `npm install -g create-dmg` (Node 22 available) |
| Node.js (≥20) | create-dmg dependency | ✓ | v22.22.0 | — |
| Apple Developer ID certificate | DIST-03/04 signing | Unknown | — | Cannot ship without it; requires Apple Developer Program |
| `SPUStandardUpdaterController` (Sparkle) | DIST-04 | ✗ (SPM not yet resolved) | 2.9.3 target | Add via Xcode: File → Add Package Dependencies |

**Missing dependencies with no fallback:**
- Apple Developer ID certificate — required for notarization; cannot be generated automatically. Developer must be enrolled in Apple Developer Program.

**Missing dependencies with fallback:**
- `create-dmg` — install with `npm install -g create-dmg` (Node.js present). Add to release checklist.
- Sparkle SPM package — add via Xcode's Add Package Dependencies UI (github.com/sparkle-project/Sparkle, version 2.9.3). No code runs until added.

---

## Security Domain

> `security_enforcement` not explicitly set in config.json; treating as enabled.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | — (no auth in Flint) |
| V3 Session Management | no | — |
| V4 Access Control | no | — |
| V5 Input Validation | yes — drag-drop file content | Attempt UTF-8 decode; reject binary with `WarningBannerView`; no shell injection risk (content is read, not executed) |
| V6 Cryptography | yes — Sparkle EdDSA signature | `generate_keys` (Ed25519); `SUPublicEDKey` embedded in bundle; private key in Keychain only — never in repo |

### Known Threat Patterns for This Stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Malicious file dropped into text tool (binary with valid UTF-8 header) | Tampering | WarningBannerView on oversized or suspicious content; no file is executed |
| Services invocation with oversized text (1MB+ clipboard) | Denial of Service | Apply the same oversized-input guard used in clipboard detection; cap Services text at e.g. 1MB, show error if exceeded |
| EdDSA private key exposure | Information Disclosure | `generate_keys` writes to login Keychain only; never write to repo, dotfiles, or env vars |
| Sparkle feeding a malicious appcast URL | Tampering | `SUFeedURL` hardcoded in Info.plist at build time; not user-configurable in v1; EdDSA signature required on every update |
| Notarization with `get-task-allow` in release entitlements | Privilege Escalation | `Flint-release.entitlements` confirmed to have no `get-task-allow` (verified in code); dual entitlements files already established |

---

## Sources

### Primary (HIGH confidence)
- CLAUDE.md (repo root) — locked toolchain decisions: Sparkle 2.9.3, notarytool, create-dmg 8.1.0, SMAppService — authoritative project instructions
- `.planning/research/SUMMARY.md` — layered architecture, ToolRegistry/ToolSeed pattern, WindowCoordinator activation-policy dance (Pitfall #2), cold-start budget (Pitfall #6), EdDSA key pitfall (Pitfall #10)
- `.planning/phases/03-polish-distribution/03-CONTEXT.md` — all implementation decisions (D-01..D-09, CF-01..CF-03)
- `App/WindowCoordinator.swift` (codebase) — existing activation-policy dance implementation; confirmed `openWorkspace()` / `openPreferences()` patterns
- `Core/Services/ToolRegistry.swift` (codebase) — confirmed `detect(from:)` and `ToolSeed` are frozen and available
- `Core/Services/PreferencesStore.swift` (codebase) — confirmed `launchAtLogin` (SMAppService) and UserDefaults pattern for new `hasSeenOnboarding` key
- Sparkle official documentation — sparkle-project.org/documentation/ — SPUStandardUpdaterController setup, generate_keys, generate_appcast, appcast XML format, SUPublicEDKey
- Sparkle programmatic setup — sparkle-project.org/documentation/programmatic-setup/ — SwiftUI init pattern
- Sparkle sandboxing docs — sparkle-project.org/documentation/sandboxing/ — confirmed non-sandboxed apps don't need XPC entitlements
- Apple SysServices archive docs — developer.apple.com/library/archive/documentation/Cocoa/Conceptual/SysServices/Articles/providing.html — NSServices Info.plist keys, NSUpdateDynamicServices
- GitHub API (Sparkle) — confirmed 2.9.3 released 2026-06-08
- GitHub API (create-dmg) — confirmed 8.1.0 released 2026-03-21

### Secondary (MEDIUM confidence)
- Peter Steinberger (steipete.me/posts/2025/code-signing-and-notarization-sparkle-and-tears) — Sparkle XPC signing order, `codesign --deep` pitfall, DMG notarization sequence — 2025 post, verified against Sparkle discussion #2597
- nilcoalescing.com/blog/macOSSystemWideServices — NSServices Swift implementation, `@objc` handler signature, servicesProvider registration
- Apple Developer Forums / notarytool — `store-credentials` + `--wait` + `stapler` workflow
- eclecticlight.co/2024/05/21/swiftui-on-macos-drag-and-drop-and-more — onDrop NSItemProvider pattern (2024 article)

### Tertiary (LOW confidence)
- File reference URL resolution behavior on non-sandboxed macOS (community-documented, no official Apple source found)
- UTF-8 decode as text/binary discriminator (common pattern, not in official Apple docs)

---

## Metadata

**Confidence breakdown:**
- DIST-01 (Services): HIGH — Apple's NSServices API is stable and well-documented; the SwiftUI/NSApplicationDelegateAdaptor wiring is a known pattern. The only uncertainty is the GENERATE_INFOPLIST_FILE interaction (A6).
- DIST-02 (Drag-drop): MEDIUM-HIGH — `.onDrop` is well-documented; file URL resolution edge cases have some community-only evidence. The chunked pipeline reuse is verified from existing code.
- DIST-03 (DMG + onboarding): HIGH — notarytool, stapler, create-dmg workflows are well-documented. The onboarding window pattern reuses verified WindowCoordinator code.
- DIST-04 (Sparkle): HIGH — Sparkle documentation is comprehensive and current. The XPC signing order is verified by a 2025 post-mortem. EdDSA key embedding requirement is well-documented.

**Research date:** 2026-06-26
**Valid until:** 2026-09-26 (90 days — Sparkle and notarytool are stable; check for Sparkle version update before implementation)
