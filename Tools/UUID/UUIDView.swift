// Tools/UUID/UUIDView.swift
// UUID Generator + Inspector view.
// UUID-01: single/bulk generation (v1/v4/v5/v7), bulk is button-triggered (D-10)
// UUID-02: v7 generation via leodabus/UUIDv7 package
// UUID-03: inspect panel — version/variant/timestamp/component breakdown
// UUID-04: per-UUID copy (D-12), bulk export (clipboard/CSV/JSON), case toggle, nil UUID
// D-13: UUID is a default pinned tool.

import SwiftUI

struct UUIDView: View {

    @State private var viewModel: UUIDViewModel
    @Environment(ToolSeed.self) private var toolSeed

    init() {
        _viewModel = State(wrappedValue: UUIDViewModel())
    }

    var body: some View {
        VSplitView {
            generatorPanel
                .frame(minHeight: 200)
            inspectPanel
                .frame(minHeight: 150)
        }
        .padding(8)
        .toolShortcuts(viewModel)
        .onAppear {
            // DIST-02: launcher detect()-routing pre-fill. A detected UUID is a value
            // to INSPECT, so it populates the inspect panel. consume() is one-shot.
            if let seed = toolSeed.consume(for: "uuid-generator") {
                viewModel.inspectInput = seed
            }
        }
    }

    // MARK: - Generator panel

    private var generatorPanel: some View {
        VStack(alignment: .leading, spacing: 10) {

            // Version selector + count
            HStack(spacing: 12) {
                Picker("Version", selection: $viewModel.selectedVersion) {
                    ForEach(UUIDVersion.allCases, id: \.self) { v in
                        Text(v.rawValue).tag(v)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 200)
                .accessibilityLabel("UUID version")

                Spacer()

                // Count field (UUID-01, D-10)
                Text("Count (max 1000):")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("1", value: $viewModel.generateCount, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                    .accessibilityLabel("UUID count")
                    .onChange(of: viewModel.generateCount) { _, new in
                        viewModel.generateCount = max(1, min(new, 1000))
                    }
            }

            // v5 namespace + name fields
            if viewModel.selectedVersion == .v5 {
                HStack {
                    Text("Namespace:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $viewModel.v5Namespace) {
                        Text("DNS").tag(UUIDTransformer.namespaceDNS)
                        Text("URL").tag(UUIDTransformer.namespaceURL)
                        Text("OID").tag(UUIDTransformer.namespaceOID)
                        Text("X.500").tag(UUIDTransformer.namespaceX500)
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 100)
                    TextField("Name (e.g. www.example.com)", text: $viewModel.v5Name)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("v5 name")
                }
            }

            // Generate buttons (D-10: bulk is button-triggered)
            HStack(spacing: 8) {
                Button("Generate") {
                    viewModel.generateCount = 1
                    viewModel.generate()
                }
                .buttonStyle(.primary)
                .accessibilityLabel("Generate one UUID")

                Button("Generate 1000") {
                    viewModel.generateCount = 1000
                    viewModel.generate()
                }
                .accessibilityLabel("Generate 1000 UUIDs")

                Spacer()

                // Case toggle (UUID-04)
                Toggle("UPPERCASE", isOn: $viewModel.uppercase)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .accessibilityLabel("Uppercase toggle")

                // Export format picker (UUID-04)
                Picker("", selection: $viewModel.exportFormat) {
                    ForEach(UUIDTransformer.ExportFormat.allCases, id: \.self) { fmt in
                        Text(fmt.rawValue).tag(fmt)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 120)
                .accessibilityLabel("Export format")
            }

            if let err = viewModel.errorMessage {
                InlineErrorView(message: err)
            }

            // UUID list (UUID-04: per-UUID copy via CopyButtonView — D-12)
            if viewModel.generatedUUIDs.isEmpty {
                Text("Paste or type content above")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(viewModel.generatedUUIDs, id: \.self) { uuid in
                            HStack {
                                Text(viewModel.displayString(for: uuid))
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                                Spacer()
                                CopyButtonView(text: viewModel.displayString(for: uuid))
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                }
                .frame(maxHeight: 200)

                // Export buttons (UUID-04)
                HStack(spacing: 8) {
                    Button("Copy All") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(viewModel.exportText(), forType: .string)
                    }
                    .accessibilityLabel("Copy all UUIDs")

                    Button("Copy as \(viewModel.exportFormat.rawValue)") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(viewModel.exportText(), forType: .string)
                    }
                    .accessibilityLabel("Copy UUIDs in selected format")

                    Spacer()

                    Text("\(viewModel.generatedUUIDs.count) UUID(s)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
    }

    // MARK: - Inspect panel (UUID-03)

    private var inspectPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Inspect UUID")
                .font(.headline)

            TextField("Paste any UUID to inspect…", text: $viewModel.inspectInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .accessibilityLabel("UUID inspect input")

            if let err = viewModel.inspectError {
                InlineErrorView(message: err)
            }

            if let info = viewModel.inspectResult {
                inspectResultView(info)
            }
        }
        .padding(8)
    }

    @ViewBuilder
    private func inspectResultView(_ info: UUIDTransformer.UUIDInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 16) {
                labeledValue("Version", value: "v\(info.version)")
                labeledValue("Variant", value: info.variantDescription)
                Spacer()
                CopyButtonView(text: viewModel.inspectInput)
            }

            // Embedded timestamp (v1 and v7)
            if let ts = info.timestamp {
                HStack {
                    labeledValue("Timestamp", value: ts.formatted(.dateTime.year().month().day().hour().minute().second().timeZone()))
                    if let ms = info.embeddedMs {
                        Text("(\(ms) ms)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // v1 component breakdown
            if info.version == 1 {
                HStack(spacing: 12) {
                    if let tl = info.timeLow   { labeledValue("time_low",  value: tl) }
                    if let tm = info.timeMid   { labeledValue("time_mid",  value: tm) }
                    if let th = info.timeHigh  { labeledValue("time_high", value: th) }
                    if let cs = info.clockSeq  { labeledValue("clock_seq", value: cs) }
                    if let nd = info.node      { labeledValue("node", value: nd) }
                }
                .font(.caption.monospaced())
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func labeledValue(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.callout.monospaced())
                .textSelection(.enabled)
        }
    }
}
