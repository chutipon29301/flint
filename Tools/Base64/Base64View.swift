// Tools/Base64/Base64View.swift
// Base64 Encoder/Decoder UI — input/output, URL-safe toggle, byte/char counts, file I/O.
// Source: UI-SPEC.md § "Per-Field Copy Buttons", § "Live Transform + Debounce", § "Error State"
// Covers: B64-01..05, D-10, D-11, D-12

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct Base64View: View {
    @Environment(HistoryStore.self) private var historyStore
    @Environment(ToolSeed.self) private var toolSeed
    @State private var viewModel: Base64ViewModel?

    var body: some View {
        Group {
            if let vm = viewModel {
                Base64ContentView(viewModel: vm)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = Base64ViewModel(
                    onSaveHistory: { [historyStore] entry in
                        historyStore.save(entry)
                    }
                )
            }
            // DIST-02: launcher detect()-routing pre-fill. consume() is one-shot.
            if let seed = toolSeed.consume(for: "base64") {
                viewModel?.input = seed
            }
        }
    }
}

private struct Base64ContentView: View {
    @Bindable var viewModel: Base64ViewModel

    // DIST-02: binary tool drop — accepts ANY file via the existing off-main chunked pipeline.
    @State private var isDragTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            // Controls bar
            HStack(spacing: 12) {
                // B64-02: URL-safe toggle
                Toggle("URL-safe (RFC 4648 §5)", isOn: $viewModel.urlSafe)
                    .toggleStyle(.checkbox)
                    .accessibilityLabel("URL-safe Base64 variant (RFC 4648 §5)")

                Spacer()

                // File operations (B64-04, D-10: button-triggered)
                if viewModel.isProcessingFile {
                    ProgressView()
                        .scaleEffect(0.7)
                        .accessibilityLabel("Processing file")
                }

                Button(action: { viewModel.encodeFile() }) {
                    Label("Encode File", systemImage: "doc.badge.arrow.up")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Encode file to Base64")

                Button(action: { viewModel.decodeToFile() }) {
                    Label("Decode to File", systemImage: "doc.badge.arrow.down")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Decode Base64 to file")

                // Primary copy button (D-12)
                if !viewModel.output.isEmpty {
                    CopyButtonView(getText: { viewModel.output })
                    Text("Copy Output")
                        .font(.system(size: 13))
                        .foregroundColor(.accentColor)
                        .onTapGesture {
                            let pb = NSPasteboard.general
                            pb.clearContents()
                            pb.setString(viewModel.output, forType: .string)
                        }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            // File operation error banner
            if let fileError = viewModel.fileErrorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(fileError)
                        .font(.caption)
                        .foregroundColor(.orange)
                    Spacer()
                    Button("Dismiss") {
                        viewModel.fileErrorMessage = nil
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))

                Divider()
            }

            Divider()

            HSplitView {
                // Input panel
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Input")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)

                        // Mode indicator (B64-03: auto-detect)
                        if !viewModel.input.isEmpty {
                            Text(viewModel.isDecodeMode ? "Decoding" : "Encoding")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(4)
                        }

                        Spacer()

                        // Manual override buttons
                        if !viewModel.input.isEmpty {
                            Button("Encode") {
                                viewModel.forceEncode()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .accessibilityLabel("Force encode mode")

                            Button("Decode") {
                                viewModel.forceDecode()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .accessibilityLabel("Force decode mode")
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 8)

                    SyntaxEditorView(text: $viewModel.input, accessibilityLabel: "Base64 input")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Inline error (D-11, INFRA-17)
                    InlineErrorView(message: viewModel.errorMessage)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                }
                .frame(minWidth: 200)

                // Output panel
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Output")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)

                        Spacer()

                        // B64-05: byte/char counts when decoding
                        if let bytes = viewModel.decodedByteCount,
                           let chars = viewModel.decodedCharCount {
                            Text("\(bytes) bytes · \(chars) chars")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .accessibilityLabel("\(bytes) bytes, \(chars) characters")
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 8)

                    // D-11: dims to 40% opacity when output is stale (last-good-output-dimmed)
                    CodeDisplayView(code: viewModel.output, language: "text")
                        .opacity(viewModel.outputDimmed ? 0.4 : 1.0)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .font(.system(size: 13, design: .monospaced))
                }
                .frame(minWidth: 200)
            }
        }
        .navigationTitle("Base64 Encoder/Decoder")
        .toolShortcuts(viewModel)
        // DIST-02 (D-06): binary tool accepts ANY dropped file — route directly to the
        // existing off-main chunked pipeline (loadFile). No UTF-8 gate, no size cap.
        .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { @MainActor in
                    viewModel.loadFile(url: url)
                }
            }
            return true
        }
        .overlay {
            if isDragTargeted {
                DropOverlayView(label: "Drop to load file")
                    .transition(.opacity.animation(.easeOut(duration: 0.15)))
            }
        }
    }
}

#Preview {
    Base64View()
        .environment(HistoryStore())
        .frame(width: 700, height: 500)
}
