// UI/PreferencesView.swift
// Preferences window — General / Appearance / Per-Tool tabs.
// Opens via WindowCoordinator activation dance (INFRA-12).
// pitfall #2: openSettings() is broken on macOS 14 with .accessory — handled in MenuBarPopoverView.
// Source: RESEARCH.md Pattern 7, § "SMAppService — Launch at Login", REQUIREMENTS.md INFRA-12/13.

import SwiftUI
import KeyboardShortcuts
import ApplicationServices

struct PreferencesView: View {
    @Environment(PreferencesStore.self) private var prefs
    @Environment(HotkeyManager.self) private var hotkeyManager

    var body: some View {
        TabView {
            GeneralPreferencesTab()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            AppearancePreferencesTab()
                .tabItem {
                    Label("Appearance", systemImage: "paintpalette")
                }

            PerToolPreferencesTab()
                .tabItem {
                    Label("Tools", systemImage: "wrench.and.screwdriver")
                }
        }
        .environment(prefs)
        .environment(hotkeyManager)
        .frame(minWidth: 460, minHeight: 340)
        .navigationTitle("Preferences")
        .onDisappear {
            // WR-02: restore .accessory activation policy when Preferences closes.
            // WindowCoordinator.openPreferences() increments windowCount; without this hook,
            // closing Preferences without ever opening the workspace window leaves windowCount
            // at 1 and the app permanently visible in the Dock.
            WindowCoordinator.shared.windowWillClose()
        }
    }
}

// MARK: - General Tab (INFRA-12, INFRA-13)

private struct GeneralPreferencesTab: View {
    @Environment(PreferencesStore.self) private var prefs

    // D-09: Accessibility permission state, two-phase UI.
    // Re-checked on view appear and on window focus (no polling) — macOS caches the
    // trust verdict per process, so a focus-driven re-read after the user returns
    // from System Settings is the reliable signal, not a timer.
    @State private var hasAccessibility: Bool = AXIsProcessTrusted()

    // pasteBackEnabled via @AppStorage, NOT prefs.pasteBackEnabled. The store's
    // property is a computed UserDefaults wrapper that @Observable doesn't instrument,
    // so binding to it dropped writes (toggle didn't persist). @AppStorage is the
    // UserDefaults-backed value SwiftUI observes correctly. Same key, so the gate
    // logic in ColorView/HashView/NumberBaseView (which read prefs.pasteBackEnabled)
    // stays consistent.
    @AppStorage("lathe.pasteBackEnabled") private var pasteBackEnabled: Bool = false

    var body: some View {
        @Bindable var prefs = prefs

        Form {
            // MARK: Startup
            Section("Startup") {
                // INFRA-13: Launch at login via SMAppService.mainApp.register()/unregister()
                Toggle("Launch at login", isOn: $prefs.launchAtLogin)
                    .accessibilityLabel("Launch Flint at login")
                    .help("Automatically start Flint when you log in to your Mac.")

                Toggle("Show in Dock", isOn: $prefs.showInDock)
                    .accessibilityLabel("Show Flint in the Dock")
                    .help("Keep the Flint icon in the Dock at all times (not just when windows are open).")
            }

            // MARK: Opening Behaviour
            Section("Opening Behaviour") {
                Picker("Default open mode", selection: $prefs.defaultOpenMode) {
                    ForEach(PreferencesStore.OpenMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                .accessibilityLabel("Default mode for opening tools")
                .help("Choose whether tools open in the menubar popover or the detachable workspace window.")
            }

            // MARK: Clipboard
            Section("Clipboard") {
                Toggle("Auto-detect clipboard content", isOn: $prefs.clipboardAutoDetect)
                    .accessibilityLabel("Automatically detect clipboard content and suggest the best tool")
                    .help("Flint will check the clipboard when the popover opens and suggest the right tool for the content.")
            }

            // MARK: Global Hotkey (INFRA-04, INFRA-13)
            Section("Global Hotkey") {
                HStack {
                    Text("Open / focus Flint")
                        .accessibilityLabel("Hotkey to open or focus Flint")
                    Spacer()
                    KeyboardShortcuts.Recorder("", name: .openFlint)
                        .accessibilityLabel("Record new hotkey for opening Flint")
                        .help("Click to record a new global hotkey. Default: ⌘⇧Space.")
                    // ⌘⇧Space (the default) is a macOS-reserved combo the recorder won't accept,
                    // so a Reset button restores it via the supported reset() API instead.
                    Button("Reset") {
                        KeyboardShortcuts.reset(.openFlint)
                    }
                    .accessibilityLabel("Reset hotkey to the default ⌘⇧Space")
                    .help("Restore the default hotkey (⌘⇧Space).")
                }
            }

            // Updates: removed for the unsigned/ad-hoc distribution. Sparkle cannot install
            // updates on a non-notarized build, so a "Check for Updates…" button would only
            // surface a confusing error. SparkleUpdaterService still exists — re-add this
            // section when shipping the signed+notarized (release.sh) build.

            // MARK: Keyboard Flow (D-09) — two-phase: grant first, then toggle.
            Section("Keyboard Flow") {
                if hasAccessibility {
                    // Permission granted → show the enable/disable toggle.
                    Toggle("Auto-paste result after copying", isOn: $pasteBackEnabled)
                        .accessibilityLabel("Enable automatic paste-back after copying a result")
                        .help("When enabled, pressing ⌘1–⌘9 copies the result AND pastes it into the previously-focused app.")
                    if pasteBackEnabled {
                        Text("⌘1–⌘9 will copy a result and paste it into the previously-focused app.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    // Permission not granted → button to grant it (no toggle, no poll).
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Auto-paste result after copying")
                        Text("Paste-back needs Accessibility permission so Flint can paste into the previously-focused app. Grant it, then return to this window.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Grant Accessibility Permission…") {
                            // Trigger the system prompt (T-04-11: only call site, explicit opt-in),
                            // then deep-link to the pane in case the prompt is suppressed.
                            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as NSDictionary)
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .accessibilityLabel("Grant Accessibility permission for paste-back")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 420)
        // Re-check permission when the window appears or regains focus — this is how
        // the UI flips from the grant button to the toggle after the user returns
        // from System Settings (no timer/poll needed).
        .onAppear { hasAccessibility = AXIsProcessTrusted() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasAccessibility = AXIsProcessTrusted()
        }
    }
}

// MARK: - Appearance Tab (INFRA-14)

private struct AppearancePreferencesTab: View {
    @Environment(PreferencesStore.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs

        Form {
            // MARK: Theme
            Section("Theme") {
                Picker("Appearance", selection: $prefs.theme) {
                    ForEach(PreferencesStore.AppTheme.allCases) { theme in
                        Text(theme.label).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Appearance theme — System, Light, or Dark")
                .help("Override the system appearance for Flint's windows.")
            }

            // MARK: Code Font
            Section("Code Font") {
                HStack {
                    Text("Font")
                    Spacer()
                    // Font family selector — system monospaced fonts via NSFontManager
                    MonospacedFontPicker(selectedFont: $prefs.codeFont)
                }

                HStack {
                    Text("Size")
                    Spacer()
                    HStack(spacing: 6) {
                        Button {
                            if prefs.codeFontSize > 10 { prefs.codeFontSize -= 1 }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Decrease code font size")
                        .disabled(prefs.codeFontSize <= 10)

                        Text("\(prefs.codeFontSize)pt")
                            .font(.system(size: 13, design: .monospaced))
                            .frame(width: 40, alignment: .center)
                            .accessibilityLabel("Code font size: \(prefs.codeFontSize) points")

                        Button {
                            if prefs.codeFontSize < 20 { prefs.codeFontSize += 1 }
                        } label: {
                            Image(systemName: "plus.circle")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Increase code font size")
                        .disabled(prefs.codeFontSize >= 20)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 420)
    }
}

// MARK: - Per-Tool Defaults Tab

private struct PerToolPreferencesTab: View {
    @Environment(PreferencesStore.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs

        Form {
            // MARK: JSON Formatter Defaults
            Section("JSON Formatter") {
                Picker("Default indent", selection: $prefs.jsonDefaultIndent) {
                    Text("2 spaces").tag(2)
                    Text("4 spaces").tag(4)
                    Text("Tab").tag(0)
                }
                .pickerStyle(.radioGroup)
                .accessibilityLabel("Default JSON indent style")
                .help("The indent style used when JSON Formatter opens.")
            }

            // MARK: Base64 Defaults
            Section("Base64") {
                Toggle("URL-safe encoding by default", isOn: $prefs.base64UrlSafe)
                    .accessibilityLabel("Use URL-safe Base64 encoding by default")
                    .help("When enabled, Base64 output uses - and _ instead of + and /, and omits padding (=). Suitable for URLs and filenames.")
            }

            // MARK: Hash Generator Defaults
            Section("Hash Generator") {
                Toggle("Uppercase hex output by default", isOn: $prefs.hashUppercase)
                    .accessibilityLabel("Show hash output in uppercase by default")
                    .help("When enabled, hash hex strings are uppercase (e.g. 5D41402A instead of 5d41402a).")
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 420)
    }
}

// MARK: - MonospacedFontPicker

/// Simple picker for monospaced system fonts.
private struct MonospacedFontPicker: View {
    @Binding var selectedFont: String

    // Common monospaced fonts available on macOS
    private let fonts = ["", "Menlo", "Monaco", "Courier New", "SF Mono", "Fira Code", "JetBrains Mono"]

    var body: some View {
        Picker("Font", selection: $selectedFont) {
            Text("System (SF Mono)").tag("")
            Divider()
            ForEach(fonts.dropFirst(), id: \.self) { font in
                Text(font)
                    .font(.custom(font, size: 13))
                    .tag(font)
            }
        }
        .labelsHidden()
        .frame(maxWidth: 200)
        .accessibilityLabel("Code font family")
        .help("The font used in code editor and output areas. System uses SF Mono.")
    }
}

// MARK: - Preview

#Preview {
    PreferencesView()
        .environment(PreferencesStore())
        .environment(HotkeyManager())
}
