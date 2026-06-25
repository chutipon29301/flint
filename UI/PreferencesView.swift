// UI/PreferencesView.swift
// Preferences window — General / Appearance / History / Per-Tool tabs.
// Opens via WindowCoordinator activation dance (INFRA-12).
// pitfall #2: openSettings() is broken on macOS 14 with .accessory — handled in MenuBarPopoverView.
// Source: RESEARCH.md Pattern 7, § "SMAppService — Launch at Login", REQUIREMENTS.md INFRA-12/13.

import SwiftUI
import KeyboardShortcuts

struct PreferencesView: View {
    @Environment(PreferencesStore.self) private var prefs
    @Environment(HotkeyManager.self) private var hotkeyManager
    @Environment(HistoryStore.self) private var historyStore

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

            HistoryPreferencesTab()
                .tabItem {
                    Label("History", systemImage: "clock")
                }

            PerToolPreferencesTab()
                .tabItem {
                    Label("Tools", systemImage: "wrench.and.screwdriver")
                }
        }
        .environment(prefs)
        .environment(hotkeyManager)
        .environment(historyStore)  // CR-01: propagate to HistoryPreferencesTab
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

    var body: some View {
        @Bindable var prefs = prefs

        Form {
            // MARK: Startup
            Section("Startup") {
                // INFRA-13: Launch at login via SMAppService.mainApp.register()/unregister()
                Toggle("Launch at login", isOn: $prefs.launchAtLogin)
                    .accessibilityLabel("Launch Lathe at login")
                    .help("Automatically start Lathe when you log in to your Mac.")

                Toggle("Show in Dock", isOn: $prefs.showInDock)
                    .accessibilityLabel("Show Lathe in the Dock")
                    .help("Keep the Lathe icon in the Dock at all times (not just when windows are open).")
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
                    .help("Lathe will check the clipboard when the popover opens and suggest the right tool for the content.")
            }

            // MARK: Global Hotkey (INFRA-04, INFRA-13)
            Section("Global Hotkey") {
                HStack {
                    Text("Open / focus Lathe")
                        .accessibilityLabel("Hotkey to open or focus Lathe")
                    Spacer()
                    KeyboardShortcuts.Recorder("", name: .openLathe)
                        .accessibilityLabel("Record new hotkey for opening Lathe")
                        .help("Click to record a new global hotkey. Default: ⌘⇧Space.")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 420)
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
                .help("Override the system appearance for Lathe's windows.")
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

// MARK: - History Tab (INFRA-13)

private struct HistoryPreferencesTab: View {
    @Environment(PreferencesStore.self) private var prefs
    @Environment(HistoryStore.self) private var historyStore
    @State private var showClearConfirmation = false

    var body: some View {
        @Bindable var prefs = prefs

        Form {
            Section("History Limit") {
                HStack {
                    Text("Keep last")
                    Spacer()
                    HStack(spacing: 6) {
                        Button {
                            if prefs.historyLimit > 10 { prefs.historyLimit -= 10 }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Decrease history limit by 10")
                        .disabled(prefs.historyLimit <= 10)

                        Text("\(prefs.historyLimit) items")
                            .font(.system(size: 13))
                            .frame(width: 70, alignment: .center)
                            .accessibilityLabel("History limit: \(prefs.historyLimit) items")

                        Button {
                            if prefs.historyLimit < 100 { prefs.historyLimit += 10 }
                        } label: {
                            Image(systemName: "plus.circle")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Increase history limit by 10")
                        .disabled(prefs.historyLimit >= 100)
                    }
                }

                Text("Pinned items are always kept, regardless of the limit.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .accessibilityLabel("Note: Pinned history items are exempt from the limit")
            }

            Section {
                Button(role: .destructive) {
                    showClearConfirmation = true
                } label: {
                    Label("Clear All History", systemImage: "trash")
                        .foregroundColor(.red)
                }
                .accessibilityLabel("Clear all unpinned history items")
                .help("Remove all unpinned history entries. Pinned items will be kept.")
                .confirmationDialog(
                    "Clear History?",
                    isPresented: $showClearConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Clear History", role: .destructive) {
                        // CR-01: call directly — no notification needed; avoids dangling observer risk
                        historyStore.clearUnpinned()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("All unpinned history entries will be removed. Pinned items will be kept.")
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
