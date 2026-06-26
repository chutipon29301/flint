// Tools/URLEncoder/URLView.swift
// URL Encoder/Decoder UI — encode/decode field, parsed-component rows with per-field copy,
// add/delete key-value table for query params with rebuild (URL-03), inline error.
// Source: UI-SPEC.md § "Per-Field Copy Buttons", § "Live Transform + Debounce"
// Covers: URL-01..04, D-10, D-11, D-12

import SwiftUI

struct URLView: View {
    @Environment(HistoryStore.self) private var historyStore
    @State private var viewModel: URLViewModel?

    var body: some View {
        Group {
            if let vm = viewModel {
                URLContentView(viewModel: vm)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = URLViewModel(
                    onSaveHistory: { [historyStore] entry in
                        historyStore.save(entry)
                    }
                )
            }
        }
    }
}

private struct URLContentView: View {
    @Bindable var viewModel: URLViewModel
    @State private var isDragTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            // Mode selector bar
            HStack(spacing: 8) {
                Picker("Mode", selection: $viewModel.mode) {
                    ForEach(URLToolMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
                .accessibilityLabel("URL tool mode")

                Spacer()

                // Primary copy button — output or rebuilt URL (D-12)
                let primaryOutput = viewModel.mode == .parse ? viewModel.rebuiltURL : viewModel.encodedOutput
                if !primaryOutput.isEmpty {
                    CopyButtonView(getText: { primaryOutput })
                    Text("Copy Output")
                        .font(.system(size: 13))
                        .foregroundColor(.accentColor)
                        .onTapGesture {
                            let pb = NSPasteboard.general
                            pb.clearContents()
                            pb.setString(primaryOutput, forType: .string)
                        }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if viewModel.mode == .parse {
                ParseModeView(viewModel: viewModel)
            } else {
                EncodeDecodeModeView(viewModel: viewModel)
            }
        }
        .navigationTitle("URL Encoder/Decoder")
        .toolShortcuts(viewModel)
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
}

// MARK: - Encode/Decode Mode

private struct EncodeDecodeModeView: View {
    @Bindable var viewModel: URLViewModel

    var body: some View {
        HSplitView {
            // Input panel
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Input")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)

                SyntaxEditorView(text: $viewModel.input, accessibilityLabel: "URL input")
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
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)

                // D-11: dims to 40% opacity when output is stale
                CodeDisplayView(code: viewModel.encodedOutput, language: "text")
                    .opacity(viewModel.outputDimmed ? 0.4 : 1.0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: 200)
        }
    }
}

// MARK: - Parse Mode

private struct ParseModeView: View {
    @Bindable var viewModel: URLViewModel

    var body: some View {
        HSplitView {
            // Left: Input
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("URL Input")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)

                SyntaxEditorView(text: $viewModel.input, accessibilityLabel: "URL to parse")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Inline error (D-11, INFRA-17)
                InlineErrorView(message: viewModel.errorMessage)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
            }
            .frame(minWidth: 180)

            // Right: Parsed components + query param editor
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // URL-02: Parsed components rows (each with per-field copy — URL-04, D-12)
                    if let parsed = viewModel.parsedURL {
                        Group {
                            ComponentRowView(label: "Scheme", value: parsed.scheme ?? "")
                            ComponentRowView(label: "Host", value: parsed.host ?? "")
                            if let port = parsed.port {
                                ComponentRowView(label: "Port", value: "\(port)")
                            }
                            ComponentRowView(label: "Path", value: parsed.path ?? "")
                            if let fragment = parsed.fragment {
                                ComponentRowView(label: "Fragment", value: fragment)
                            }
                        }

                        // URL-03: Query params edit table
                        if !viewModel.editableQueryItems.isEmpty || viewModel.parsedURL != nil {
                            Divider()
                            QueryParamTableView(viewModel: viewModel)
                        }

                        // Rebuilt URL
                        if !viewModel.rebuiltURL.isEmpty {
                            Divider()
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Rebuilt URL")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    // Per-field copy for rebuilt URL (D-12)
                                    CopyButtonView(getText: { viewModel.rebuiltURL })
                                }

                                Text(viewModel.rebuiltURL)
                                    .font(.system(size: 12, design: .monospaced))
                                    .textSelection(.enabled)
                                    .accessibilityLabel("Rebuilt URL: \(viewModel.rebuiltURL)")
                            }
                            .padding(.horizontal, 12)
                            .opacity(viewModel.outputDimmed ? 0.4 : 1.0)
                        }
                    } else {
                        // Empty state
                        VStack(spacing: 8) {
                            Image(systemName: "link.badge.magnifyingglass")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("Enter a URL to parse its components")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .padding()
                    }
                }
                .padding(.vertical, 12)
            }
            .frame(minWidth: 240)
        }
    }
}

// MARK: - Component Row (URL-04, D-12: per-field copy)

private struct ComponentRowView: View {
    let label: String
    let value: String

    var body: some View {
        guard !value.isEmpty else { return AnyView(EmptyView()) }
        return AnyView(
            HStack(alignment: .top, spacing: 8) {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 60, alignment: .trailing)

                Text(value)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("\(label): \(value)")

                // Per-field copy button (D-12, URL-04)
                CopyButtonView(getText: { value })
            }
            .padding(.horizontal, 12)
        )
    }
}

// MARK: - Query Param Table (URL-03)

private struct QueryParamTableView: View {
    @Bindable var viewModel: URLViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Query Parameters")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: { viewModel.addQueryItem() }) {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Add query parameter")
            }
            .padding(.horizontal, 12)

            // Column headers
            HStack(spacing: 8) {
                Text("Key")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Value")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // Space for copy + delete buttons
                Spacer().frame(width: 60)
            }
            .padding(.horizontal, 12)

            ForEach(viewModel.editableQueryItems.indices, id: \.self) { index in
                QueryItemRowView(
                    item: Binding(
                        get: { viewModel.editableQueryItems[index] },
                        set: { viewModel.editableQueryItems[index] = $0 }
                    ),
                    onDelete: {
                        viewModel.deleteQueryItems(at: IndexSet(integer: index))
                    },
                    onChange: {
                        viewModel.queryItemDidChange()
                    }
                )
                .padding(.horizontal, 12)
            }
        }
    }
}

// MARK: - Individual Query Item Row

private struct QueryItemRowView: View {
    @Binding var item: URLTransformer.QueryItem
    let onDelete: () -> Void
    let onChange: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField("key", text: Binding(
                get: { item.name },
                set: { item.name = $0; onChange() }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12, design: .monospaced))
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Query parameter key")

            TextField("value", text: Binding(
                get: { item.value ?? "" },
                set: { item.value = $0.isEmpty ? nil : $0; onChange() }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12, design: .monospaced))
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Query parameter value for key \(item.name)")

            // Per-field copy button (D-12, URL-04)
            CopyButtonView(getText: { "\(item.name)=\(item.value ?? "")" })

            // Delete button
            Button(action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete query parameter \(item.name)")
        }
    }
}

#Preview {
    URLView()
        .environment(HistoryStore())
        .frame(width: 800, height: 550)
}
