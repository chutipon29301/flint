// Tools/Timestamp/TimestampView.swift
// Timestamp Converter UI — TS-01..05, D-12 per-field copy buttons, pitfall #8 ambiguous toggle.

import SwiftUI

struct TimestampView: View {
    @State private var viewModel: TimestampViewModel
    @State private var isDragTargeted = false
    @Environment(ToolSeed.self) private var toolSeed

    init(onSaveHistory: @escaping (HistoryEntry) -> Void) {
        _viewModel = State(initialValue: TimestampViewModel(onSaveHistory: onSaveHistory))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                inputSection
                ambiguousUnitSection
                outputSection
                reverseConvertSection
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .toolShortcuts(viewModel)
        .onAppear {
            // DIST-02: launcher detect()-routing pre-fill. consume() is one-shot.
            if let seed = toolSeed.consume(for: "timestamp") {
                viewModel.input = seed
            }
        }
        .fileDrop(
            isTargeted: $isDragTargeted,
            onText: { viewModel.input = $0 },
            onError: { viewModel.errorMessage = $0 }
        )
        .overlay {
            if isDragTargeted {
                DropOverlayView(label: "Drop to load")
                    .transition(.opacity.animation(.easeOut(duration: 0.15)))
            }
        }
    }

    // MARK: - Input Section

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Unix Timestamp")
                .font(.headline)

            HStack {
                TextField("Enter timestamp (seconds or milliseconds)", text: $viewModel.input)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .accessibilityLabel("Unix timestamp input")

                Button("Now") {
                    viewModel.insertNow()
                }
                .accessibilityLabel("Insert current timestamp")
            }

            if let error = viewModel.errorMessage {
                InlineErrorView(message: error)
            }
        }
    }

    // MARK: - Ambiguous Unit Toggle (pitfall #8)

    @ViewBuilder
    private var ambiguousUnitSection: some View {
        if viewModel.detectedUnit == .ambiguous && !viewModel.input.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Ambiguous timestamp length — select unit:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Unit", selection: $viewModel.selectedUnit) {
                    Text("Seconds").tag(TimestampTransformer.TimestampUnit.seconds)
                    Text("Milliseconds").tag(TimestampTransformer.TimestampUnit.milliseconds)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Timestamp unit selector")
            }
            .padding(10)
            .background(.yellow.opacity(0.1))
            .cornerRadius(8)
        }
    }

    // MARK: - Output Section

    @ViewBuilder
    private var outputSection: some View {
        if viewModel.convertedDate != nil || viewModel.outputDimmed {
            VStack(alignment: .leading, spacing: 12) {
                Text("Converted Date")
                    .font(.headline)

                // Timezone rows (TS-02, D-12)
                if !viewModel.timezoneRows.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(Array(viewModel.timezoneRows.enumerated()), id: \.offset) { _, row in
                            timezoneRow(label: row.label, value: row.formatted)
                        }
                    }
                    .opacity(viewModel.outputDimmed ? 0.4 : 1.0)
                }

                // Relative time (TS-04)
                if !viewModel.relativeTimeString.isEmpty {
                    HStack {
                        Label(viewModel.relativeTimeString, systemImage: "clock.arrow.circlepath")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .opacity(viewModel.outputDimmed ? 0.4 : 1.0)
                        Spacer()
                    }
                }

                // ISO 8601 (TS-05)
                if !viewModel.iso8601.isEmpty {
                    outputRow(label: "ISO 8601", value: viewModel.iso8601)
                        .opacity(viewModel.outputDimmed ? 0.4 : 1.0)
                }
            }
        }
    }

    private func timezoneRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
            Spacer()
            CopyButtonView(text: value)
                .accessibilityLabel("Copy \(label) value")
        }
        .padding(10)
        .background(.quaternary.opacity(0.5))
        .cornerRadius(8)
    }

    private func outputRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
            Spacer()
            CopyButtonView(text: value)
                .accessibilityLabel("Copy \(label) value")
        }
        .padding(10)
        .background(.quaternary.opacity(0.5))
        .cornerRadius(8)
    }

    // MARK: - Reverse Convert (TS-03)

    private var reverseConvertSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Date to Timestamp")
                .font(.headline)

            DatePicker(
                "Pick a date",
                selection: $viewModel.pickedDate,
                displayedComponents: [.date, .hourAndMinute]
            )
            .accessibilityLabel("Date picker for reverse conversion")

            HStack(spacing: 8) {
                reverseOutputRow(label: "Seconds", value: viewModel.reverseTimestampSeconds)
                reverseOutputRow(label: "Milliseconds", value: viewModel.reverseTimestampMilliseconds)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.3))
        .cornerRadius(8)
    }

    private func reverseOutputRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text(value)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
                CopyButtonView(text: value)
                    .accessibilityLabel("Copy \(label) timestamp")
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.5))
        .cornerRadius(6)
    }
}
