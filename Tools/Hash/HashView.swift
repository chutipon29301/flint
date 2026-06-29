// Tools/Hash/HashView.swift
// Hash Generator UI — HASH-01..04, INFRA-09.
// SECURITY: HMAC key is a View-local @State — NEVER passed to ViewModel onSaveHistory.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct HashView: View {
    @State private var viewModel: HashViewModel

    // SECURITY (INFRA-09, pitfall #3): HMAC key lives here as View-local state.
    // It is NEVER passed to viewModel.onSaveHistory or any history-writing path.
    @State private var hmacKey: String = ""

    // DIST-02: binary tool drop — accepts ANY file via the existing off-main startFileHash pipeline.
    @State private var isDragTargeted = false

    init(onSaveHistory: @escaping (HistoryEntry) -> Void) {
        _viewModel = State(initialValue: HashViewModel(onSaveHistory: onSaveHistory))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                inputSection
                controlsSection
                hmacSection
                textHashOutputSection
                fileHashSection
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .toolShortcuts(viewModel)
        // DIST-02 (D-06): binary tool accepts ANY dropped file — route directly to the
        // existing off-main chunked file-hash pipeline (startFileHash). No UTF-8 gate, no size cap.
        .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { @MainActor in
                    viewModel.startFileHash(url: url)
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

    // MARK: - Text Input

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hash Generator")
                .font(.headline)

            SyntaxEditorView(text: $viewModel.textInput)
                .frame(minHeight: 80, maxHeight: 150)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .accessibilityLabel("Text to hash")
        }
    }

    // MARK: - Controls

    private var controlsSection: some View {
        HStack(spacing: 12) {
            Toggle("Uppercase", isOn: $viewModel.uppercase)
                .toggleStyle(.checkbox)
                .accessibilityLabel("Toggle uppercase hash output")

            Spacer()

            if let result = viewModel.textHashResult {
                Button("Copy All Hashes") {
                    let allText = viewModel.allHashesText(from: result)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(allText, forType: .string)
                }
                .accessibilityLabel("Copy all hash values to clipboard")
            }
        }
    }

    // MARK: - HMAC Section (HASH-03)

    private var hmacSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("HMAC Mode", isOn: $viewModel.hmacEnabled)
                .toggleStyle(.checkbox)
                .accessibilityLabel("Enable HMAC keyed hashing")

            if viewModel.hmacEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    // SECURITY: SecureField — key never reaches ViewModel's history call
                    SecureField("Secret key (never saved)", text: $hmacKey)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("HMAC secret key — never written to history")
                        .onChange(of: hmacKey) { _, _ in
                            viewModel.computeHMAC(key: hmacKey)
                        }
                        .onChange(of: viewModel.textInput) { _, _ in
                            if !hmacKey.isEmpty {
                                viewModel.computeHMAC(key: hmacKey)
                            }
                        }

                    Picker("Algorithm", selection: $viewModel.hmacAlgorithm) {
                        Text("HMAC-SHA256").tag(HashTransformer.HMACAlgorithm.sha256)
                        Text("HMAC-SHA384").tag(HashTransformer.HMACAlgorithm.sha384)
                        Text("HMAC-SHA512").tag(HashTransformer.HMACAlgorithm.sha512)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("HMAC algorithm selector")
                    .onChange(of: viewModel.hmacAlgorithm) { _, _ in
                        if !hmacKey.isEmpty {
                            viewModel.computeHMAC(key: hmacKey)
                        }
                    }

                    if !viewModel.hmacResult.isEmpty {
                        let displayHMAC = viewModel.uppercase ? viewModel.hmacResult.uppercased() : viewModel.hmacResult
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("HMAC")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(displayHMAC)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .lineLimit(3)
                            }
                            Spacer()
                            CopyButtonView(text: displayHMAC)
                                .accessibilityLabel("Copy HMAC result")
                        }
                        .padding(8)
                        .background(.quaternary.opacity(0.5))
                        .cornerRadius(6)
                    }
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Text Hash Output (6 rows with copy buttons)

    @ViewBuilder
    private var textHashOutputSection: some View {
        if viewModel.textInput.isEmpty && viewModel.fileURL == nil {
            Text("Paste or type content above")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
        } else if let result = viewModel.textHashResult {
            VStack(alignment: .leading, spacing: 6) {
                Text("Text Hashes")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // D-08: showBadges=true renders OutputRowBadge(1..6) on each hash row.
                // .selectOutputRow observer (below) handles ⌘1–⌘6 copies from viewModel.outputForRow.
                ProgressHashView(
                    result: result,
                    progress: 1.0,
                    isHashing: false,
                    uppercase: viewModel.uppercase,
                    showBadges: true
                )
            }
            // D-08 per-tool .selectOutputRow observer — handles ⌘1–⌘6 for Hash rows.
            // Index 1 also resolves via the shared ToolShortcutsModifier (idempotent: same MD5 value).
            // Out-of-range (⌘7–⌘9): outputForRow returns nil → harmless no-op (CF-01, T-04-06).
            .onReceive(NotificationCenter.default.publisher(for: .selectOutputRow)) { note in
                guard let index = note.userInfo?["index"] as? Int else { return }
                guard let text = viewModel.outputForRow(index), !text.isEmpty else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        }
    }

    // MARK: - File Hashing (HASH-02)

    private var fileHashSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("File Hashing")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button("Hash File…") {
                    selectAndHashFile()
                }
                .accessibilityLabel("Open file picker to hash a file")

                if viewModel.isHashing {
                    Button("Cancel") {
                        viewModel.cancelFileHash()
                    }
                    .foregroundStyle(.red)
                    .accessibilityLabel("Cancel file hashing")
                }

                if let url = viewModel.fileURL {
                    Text(url.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            ProgressHashView(
                result: viewModel.fileHashResult,
                progress: viewModel.fileHashProgress,
                isHashing: viewModel.isHashing,
                uppercase: viewModel.uppercase
            )
        }
        .padding(10)
        .background(.quaternary.opacity(0.3))
        .cornerRadius(8)
    }

    // MARK: - File Picker

    private func selectAndHashFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose a file to hash"
        panel.prompt = "Hash File"

        if panel.runModal() == .OK, let url = panel.url {
            viewModel.startFileHash(url: url)
        }
    }
}
