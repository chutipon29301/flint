// Tools/Hash/HashView.swift
// Hash Generator UI — HASH-01..04, INFRA-09.
// SECURITY: HMAC key is a View-local @State — NEVER passed to ViewModel onSaveHistory.

import SwiftUI
import AppKit

struct HashView: View {
    @State private var viewModel: HashViewModel

    // SECURITY (INFRA-09, pitfall #3): HMAC key lives here as View-local state.
    // It is NEVER passed to viewModel.onSaveHistory or any history-writing path.
    @State private var hmacKey: String = ""

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
                .background(.blue.opacity(0.05))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Text Hash Output (6 rows with copy buttons)

    @ViewBuilder
    private var textHashOutputSection: some View {
        if let result = viewModel.textHashResult {
            VStack(alignment: .leading, spacing: 6) {
                Text("Text Hashes")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ProgressHashView(
                    result: result,
                    progress: 1.0,
                    isHashing: false,
                    uppercase: viewModel.uppercase
                )
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
