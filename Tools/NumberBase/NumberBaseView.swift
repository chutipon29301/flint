// Tools/NumberBase/NumberBaseView.swift
// Number Base Converter UI — NUM-01..03.
// Width selector + signed toggle + 4 editable base fields + BitFieldView + overflow banner.
// Source: UI-SPEC.md "Tool 4: Number Base Converter" + PATTERNS.md "Multi-row output" analog

import SwiftUI

// MARK: - Entry wrapper (Convention B — HashView pattern)

struct NumberBaseView: View {
    @State private var viewModel: NumberBaseViewModel

    init(onSaveHistory: @escaping (HistoryEntry) -> Void) {
        _viewModel = State(initialValue: NumberBaseViewModel(onSaveHistory: onSaveHistory))
    }

    var body: some View {
        NumberBaseContentView(viewModel: viewModel)
    }
}

// MARK: - Content view

private struct NumberBaseContentView: View {
    @Bindable var viewModel: NumberBaseViewModel

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
            baseRow(
                label: "BIN",
                placeholder: "0",
                field: $binField,
                base: .bin,
                accessibilityLabel: "Binary value"
            )
            baseRow(
                label: "OCT",
                placeholder: "0",
                field: $octField,
                base: .oct,
                accessibilityLabel: "Octal value"
            )
            baseRow(
                label: "DEC",
                placeholder: "0",
                field: $decField,
                base: .dec,
                accessibilityLabel: "Decimal value"
            )
            baseRow(
                label: "HEX",
                placeholder: "0x0",
                field: $hexField,
                base: .hex,
                accessibilityLabel: "Hexadecimal value"
            )
        }
    }

    @ViewBuilder
    private func baseRow(
        label: String,
        placeholder: String,
        field: Binding<String>,
        base: NumberBase,
        accessibilityLabel: String
    ) -> some View {
        HStack(spacing: 8) {
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
    NumberBaseView(onSaveHistory: { _ in })
        .frame(width: 480, height: 600)
}
