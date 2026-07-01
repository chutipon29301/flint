// Tools/NumberBase/NumberBaseView.swift
// Number Base Converter UI — NUM-01..03.
// Width selector + signed toggle + 4 editable base fields + BitFieldView + overflow banner.
// Source: UI-SPEC.md "Tool 4: Number Base Converter" + PATTERNS.md "Multi-row output" analog

import SwiftUI
import AppKit
import ApplicationServices

// MARK: - Entry wrapper (Convention B — HashView pattern)

struct NumberBaseView: View {
    @State private var viewModel = NumberBaseViewModel()

    var body: some View {
        NumberBaseContentView(viewModel: viewModel)
    }
}

// MARK: - Content view

private struct NumberBaseContentView: View {
    @Bindable var viewModel: NumberBaseViewModel

    // D-09: paste-back environments (CF-02: only used when pasteBackEnabled is true)
    @Environment(PreferencesStore.self) private var prefs
    @Environment(HotkeyManager.self) private var hotkeyManager
    @Environment(PasteBackService.self) private var pasteBackService
    @Environment(ClipboardDetector.self) private var clipboard

    // Editable text-field bindings — transient per-field strings that drive update(from:text:)
    @State private var binField: String = "00000000"
    @State private var octField: String = "0"
    @State private var decField: String = "0"
    @State private var hexField: String = "00"

    // Track which field is being edited to avoid feedback loops
    @State private var editingBase: NumberBase? = nil

    @State private var isDragTargeted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                controlBar
                Divider()
                baseFields
                if viewModel.overflowWarning {
                    overflowBanner
                }
                InlineErrorView(message: viewModel.errorMessage)
                Divider()
                BitFieldView(
                    pattern: Binding(
                        get: { viewModel.pattern },
                        set: { _ in }  // read-only binding; toggle handled by onToggle
                    ),
                    width: viewModel.width,
                    onToggle: { newPattern in
                        viewModel.pattern = newPattern
                        syncFieldsFromViewModel()
                    }
                )
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .toolShortcuts(viewModel)
        .onAppear { syncFieldsFromViewModel() }
        .onChange(of: viewModel.binText) { _, new in if editingBase != .bin { binField = new } }
        .onChange(of: viewModel.octText) { _, new in if editingBase != .oct { octField = new } }
        .onChange(of: viewModel.decText) { _, new in if editingBase != .dec { decField = new } }
        .onChange(of: viewModel.hexText) { _, new in if editingBase != .hex { hexField = new } }
        .fileDrop(
            isTargeted: $isDragTargeted,
            onText: { text in
                // Primary input for this tool is the decimal value; trim the dropped
                // file (commonly trailing newlines) and drive the existing transform.
                editingBase = nil
                viewModel.update(from: .dec, text: text.trimmingCharacters(in: .whitespacesAndNewlines))
                syncFieldsFromViewModel()
            },
            onError: { viewModel.errorMessage = $0 }
        )
        .overlay {
            if isDragTargeted {
                DropOverlayView(label: "Drop to load")
                    .transition(.opacity.animation(.easeOut(duration: 0.15)))
            }
        }
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        HStack(spacing: 12) {
            Text("Bit width")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("", selection: Binding(
                get: { viewModel.width },
                set: { newWidth in
                    viewModel.applyWidthChange(newWidth)
                    syncFieldsFromViewModel()
                }
            )) {
                Text("8").tag(BitWidth.w8)
                Text("16").tag(BitWidth.w16)
                Text("32").tag(BitWidth.w32)
                Text("64").tag(BitWidth.w64)
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
            .accessibilityLabel("Bit width")

            Toggle("Signed", isOn: $viewModel.signed)
                .toggleStyle(.checkbox)
                .accessibilityLabel("Signed integer mode")

            Spacer()
        }
    }

    // MARK: - Base Fields

    private var baseFields: some View {
        VStack(spacing: 8) {
            // D-08 badge indices: 1=BIN, 2=OCT, 3=DEC, 4=HEX (UI-SPEC row map)
            baseRow(label: "BIN", rowIndex: 1, placeholder: "0",   field: $binField, base: .bin, accessibilityLabel: "Binary value")
            baseRow(label: "OCT", rowIndex: 2, placeholder: "0",   field: $octField, base: .oct, accessibilityLabel: "Octal value")
            baseRow(label: "DEC", rowIndex: 3, placeholder: "0",   field: $decField, base: .dec, accessibilityLabel: "Decimal value")
            baseRow(label: "HEX", rowIndex: 4, placeholder: "0x0", field: $hexField, base: .hex, accessibilityLabel: "Hexadecimal value")
        }
        // D-08 per-tool .selectOutputRow observer — handles ⌘1–⌘4 for NumberBase rows.
        // Index 1 also resolves via shared ToolShortcutsModifier (idempotent: same BIN value).
        // Wait — DEC is primaryOutput, BIN is row 1 here. The shared modifier copies primaryOutput()
        // (DEC) for ⌘1. The per-tool observer copies outputForRow(1) = BIN for ⌘1.
        // Per plan: per-tool observer is authoritative for the three multi-output tools; the shared
        // modifier row-1 path produces the same primaryOutput (DEC). Both copy text for ⌘1 —
        // DEC via shared modifier, BIN via per-tool observer. The badge index 1 is BIN per UI-SPEC,
        // so the per-tool observer correctly handles ⌘1 → BIN for this tool.
        // Out-of-range (⌘5–⌘9): outputForRow returns nil → harmless no-op (CF-01, T-04-06).
        // D-09 paste-back: gated on pasteBackEnabled && AXIsProcessTrusted() re-verify (T-04-12).
        // CF-02: when pasteBackEnabled == false, NO synthetic event and NO permission check runs.
        .onReceive(NotificationCenter.default.publisher(for: .selectOutputRow)) { note in
            guard let index = note.userInfo?["index"] as? Int else { return }
            guard let text = viewModel.outputForRow(index), !text.isEmpty else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            if prefs.pasteBackEnabled, AXIsProcessTrusted(),
               let app = hotkeyManager.previousFrontmostApp {
                clipboard.isPopoverPresented = false
                pasteBackService.synthesizePaste(into: app)
            }
        }
    }

    @ViewBuilder
    private func baseRow(
        label: String,
        rowIndex: Int,
        placeholder: String,
        field: Binding<String>,
        base: NumberBase,
        accessibilityLabel: String
    ) -> some View {
        HStack(spacing: 8) {
            OutputRowBadge(index: rowIndex) // D-08 — leading numbered badge for ⌘N copy

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .leading)

            TextField(placeholder, text: field)
                .font(.system(size: 13, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .opacity(viewModel.outputDimmed && editingBase != base ? 0.5 : 1.0)
                .accessibilityLabel(accessibilityLabel)
                .onSubmit {
                    editingBase = nil
                    viewModel.update(from: base, text: field.wrappedValue)
                    syncFieldsFromViewModel()
                }
                .onChange(of: field.wrappedValue) { _, newValue in
                    editingBase = base
                    viewModel.update(from: base, text: newValue)
                    if editingBase == base {
                        // Sync other fields but leave current field alone (allow mid-edit)
                        if base != .bin { binField = viewModel.binText }
                        if base != .oct { octField = viewModel.octText }
                        if base != .dec { decField = viewModel.decText }
                        if base != .hex { hexField = viewModel.hexText }
                    }
                }
                .onExitCommand {
                    editingBase = nil
                    syncFieldsFromViewModel()
                }

            CopyButtonView(getText: {
                switch base {
                case .bin: return viewModel.binText
                case .oct: return viewModel.octText
                case .dec: return viewModel.decText
                case .hex: return "0x" + viewModel.hexText
                }
            })
            .accessibilityLabel("Copy \(label)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(6)
    }

    // MARK: - Overflow Banner

    private var overflowBanner: some View {
        WarningBannerView(
            message: "Value truncated — exceeds \(viewModel.width.rawValue)-bit range",
            severity: .warning
        )
    }

    // MARK: - Sync helper

    private func syncFieldsFromViewModel() {
        binField = viewModel.binText
        octField = viewModel.octText
        decField = viewModel.decText
        hexField = viewModel.hexText
    }
}

#Preview {
    NumberBaseView()
        .frame(width: 480, height: 600)
}
