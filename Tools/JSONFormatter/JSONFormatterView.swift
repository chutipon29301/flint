// Tools/JSONFormatter/JSONFormatterView.swift
// JSON Formatter UI — input editor + output display + controls.
// Source: UI-SPEC.md § "Live Transform + Debounce", § "Error State — Inline, Never Blank"

import SwiftUI
import AppKit

struct JSONFormatterView: View {
    @Environment(ToolSeed.self) private var toolSeed
    @State private var viewModel: JSONFormatterViewModel?

    var body: some View {
        Group {
            if let vm = viewModel {
                JSONFormatterContentView(viewModel: vm)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = JSONFormatterViewModel()
            }
            // DIST-02: launcher detect()-routing pre-fill. consume() is one-shot.
            if let seed = toolSeed.consume(for: "json-formatter") {
                viewModel?.input = seed
            }
        }
    }
}

private struct JSONFormatterContentView: View {
    @Bindable var viewModel: JSONFormatterViewModel
    @State private var isDragTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            // Controls bar
            HStack(spacing: 12) {
                // Indent picker
                Picker("Indent", selection: $viewModel.indentSize) {
                    Text("2 spaces").tag(2)
                    Text("4 spaces").tag(4)
                    Text("Tab").tag(0)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 100)
                .accessibilityLabel("Indent style")

                Toggle("Sort Keys", isOn: $viewModel.sortKeys)
                    .toggleStyle(.checkbox)
                    .accessibilityLabel("Sort keys alphabetically")

                Toggle("Minify", isOn: $viewModel.minifyOutput)
                    .toggleStyle(.checkbox)
                    .accessibilityLabel("Minify output")

                Spacer()

                // JSON-06: Primary copy button
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

            Divider()

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

                    SyntaxEditorView(text: $viewModel.input, accessibilityLabel: "JSON input")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // JSON-03: Inline error (D-11)
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

                    // D-11: opacity dims to 0.4 when output is from last-good (no animation per UI-SPEC)
                    if viewModel.input.isEmpty {
                        Text("Paste or type content above")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    } else {
                        CodeDisplayView(code: viewModel.output, language: "json")
                            .opacity(viewModel.outputDimmed ? 0.4 : 1.0)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 200)
            }
        }
        .navigationTitle("JSON Formatter")
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

#Preview {
    JSONFormatterView()
        .frame(width: 700, height: 500)
}
