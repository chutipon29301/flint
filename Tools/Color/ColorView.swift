// Tools/Color/ColorView.swift
// Color Converter UI — swatch + eyedropper/picker + editable format rows + sliders + collapsible WCAG.
// Convention A: lazy @State viewModel built on .onAppear (matches JSONFormatterView pattern).
// NSColorSampler eyedropper — zero permissions (CLR-02, RESEARCH §4).
// INFRA-15: Every interactive element has .accessibilityLabel.
// Source: UI-SPEC.md "Tool 2: Color Converter" + PATTERNS.md "Color-specific (D-06)"

import SwiftUI
import AppKit

// MARK: - ColorView (Convention A wrapper)

struct ColorView: View {
    @Environment(HistoryStore.self) private var historyStore
    @Environment(ToolSeed.self) private var toolSeed
    @State private var viewModel: ColorViewModel?

    var body: some View {
        Group {
            if let vm = viewModel {
                ColorContentView(viewModel: vm)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = ColorViewModel(
                    onSaveHistory: { [historyStore] entry in historyStore.save(entry) }
                )
            }
            // If opened from clipboard detection, pre-fill from the detected value (CLR-02).
            // consume() returns the seed once and clears it, so a later manual open is clean.
            if let seed = toolSeed.consume(for: "color") {
                viewModel?.updateFromHex(seed)
            }
        }
    }
}

// MARK: - Color Content View

private struct ColorContentView: View {
    @Bindable var viewModel: ColorViewModel

    // Local TextFields for editable format rows — track last-committed values to avoid feedback loop
    @State private var hexFieldText: String = ""
    @State private var rgbR: String = "0"
    @State private var rgbG: String = "0"
    @State private var rgbB: String = "0"
    @State private var rgbA: String = "1.00"
    @State private var hslH: String = "0"
    @State private var hslS: String = "0"
    @State private var hslL: String = "0"
    @State private var hslA: String = "1.00"
    @State private var hsvH: String = "0"
    @State private var hsvS: String = "0"
    @State private var hsvV: String = "0"
    @State private var hsvA: String = "1.00"
    @State private var oklchL: String = "0.000"
    @State private var oklchC: String = "0.000"
    @State private var oklchH: String = "0.0"
    @State private var oklchA: String = "1.00"

    @State private var wcagExpanded: Bool = false

    // ColorViewModel has no errorMessage; drop errors surface via this view-local
    // WarningBannerView (the only sanctioned drop-error surface — no new UI introduced).
    @State private var dropError: String?
    @State private var isDragTargeted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Drop-error banner (DIST-02) — post-drop rejection of binary/oversized files.
                if let dropError {
                    WarningBannerView(message: dropError, severity: .warning)
                        .padding(.horizontal, 12)
                }

                // Out-of-gamut warning banner (D-08) — above swatch
                if viewModel.outOfGamutWarning {
                    WarningBannerView(message: "Out of sRGB gamut — clipped", severity: .warning)
                        .padding(.horizontal, 12)
                }

                swatchSection
                Divider()
                formatRowsSection
                Divider()
                slidersSection
                Divider()
                wcagSection
            }
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .toolShortcuts(viewModel)
        .onAppear { syncFieldsFromVM() }
        .onChange(of: viewModel.canonicalRGBA) { _, _ in syncFieldsFromVM() }
        .fileDrop(
            isTargeted: $isDragTargeted,
            onText: { text in
                // Primary input for this tool is a color string (e.g. hex); trim and
                // drive the existing hex-parse transform.
                dropError = nil
                viewModel.updateFromHex(text.trimmingCharacters(in: .whitespacesAndNewlines))
            },
            onError: { dropError = $0 }
        )
        .overlay {
            if isDragTargeted {
                DropOverlayView(label: "Drop to load")
                    .transition(.opacity.animation(.easeOut(duration: 0.15)))
            }
        }
    }

    // MARK: - Swatch + Eyedropper + ColorPicker

    private var swatchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Color swatch
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(
                    red: viewModel.canonicalRGBA.red,
                    green: viewModel.canonicalRGBA.green,
                    blue: viewModel.canonicalRGBA.blue,
                    opacity: viewModel.canonicalRGBA.alpha
                ))
                .frame(height: 72)
                .padding(.horizontal, 12)
                .accessibilityLabel("Current color preview")

            HStack(spacing: 12) {
                // Eyedropper — NSColorSampler, zero permissions (D-06, CLR-02)
                Button {
                    NSColorSampler().show { nsColor in
                        guard let nsColor else { return }
                        viewModel.updateFromNSColor(nsColor)
                    }
                } label: {
                    Label("Pick color from screen", systemImage: "eyedropper")
                        .labelStyle(.iconOnly)
                        .frame(width: 28, height: 28)
                }
                .help("Pick color from screen")
                .accessibilityLabel("Pick color from screen")

                // System color picker (wraps NSColorPanel)
                ColorPicker("", selection: $viewModel.swiftUIColor)
                    .labelsHidden()
                    .help("Open system color picker")
                    .accessibilityLabel("Open system color picker")

                Spacer()
            }
            .padding(.horizontal, 12)
        }
    }

    // MARK: - Editable Format Rows (D-05)

    private var formatRowsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            // HEX row (D-08 badge index 1)
            formatRow(label: "HEX", rowIndex: 1, copyTooltip: "Copy HEX", copyText: { viewModel.hexString }) {
                TextField("#RRGGBB", text: $hexFieldText)
                    .font(.system(size: 13, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 120)
                    .accessibilityLabel("HEX color value")
                    .onSubmit { viewModel.updateFromHex(hexFieldText) }
                    .onChange(of: hexFieldText) { _, _ in }
            }

            // RGB row (D-08 badge index 2)
            formatRow(label: "RGB", rowIndex: 2, copyTooltip: "Copy RGB", copyText: { "\(viewModel.rgbString)" }) {
                HStack(spacing: 4) {
                    componentField("R:", $rgbR, label: "Red channel") { commitRGB() }
                    componentField("G:", $rgbG, label: "Green channel") { commitRGB() }
                    componentField("B:", $rgbB, label: "Blue channel") { commitRGB() }
                    componentField("A:", $rgbA, label: "Alpha channel") { commitRGB() }
                }
            }

            // HSL row (D-08 badge index 3)
            formatRow(label: "HSL", rowIndex: 3, copyTooltip: "Copy HSL", copyText: { "hsl(\(viewModel.hslString) / \(String(format: "%.2f", viewModel.canonicalRGBA.alpha)))" }) {
                HStack(spacing: 4) {
                    componentField("H:", $hslH, label: "Hue degrees") { commitHSL() }
                    componentField("S:", $hslS, label: "Saturation percent") { commitHSL() }
                    componentField("L:", $hslL, label: "Lightness percent") { commitHSL() }
                    componentField("A:", $hslA, label: "Alpha channel") { commitHSL() }
                }
            }

            // HSV row (D-08 badge index 4)
            formatRow(label: "HSV", rowIndex: 4, copyTooltip: "Copy HSV", copyText: { "hsv(\(viewModel.hsvString) / \(String(format: "%.2f", viewModel.canonicalRGBA.alpha)))" }) {
                HStack(spacing: 4) {
                    componentField("H:", $hsvH, label: "Hue degrees") { commitHSV() }
                    componentField("S:", $hsvS, label: "HSV saturation percent") { commitHSV() }
                    componentField("V:", $hsvV, label: "Value percent") { commitHSV() }
                    componentField("A:", $hsvA, label: "Alpha channel") { commitHSV() }
                }
            }

            // OKLCH row (D-08 badge index 5)
            formatRow(label: "OKLCH", rowIndex: 5, copyTooltip: "Copy OKLCH", copyText: { "oklch(\(viewModel.oklchString) / \(String(format: "%.2f", viewModel.canonicalRGBA.alpha)))" }) {
                HStack(spacing: 4) {
                    componentField("L:", $oklchL, label: "OKLCH lightness") { commitOKLCH() }
                    componentField("C:", $oklchC, label: "OKLCH chroma") { commitOKLCH() }
                    componentField("H:", $oklchH, label: "OKLCH hue degrees") { commitOKLCH() }
                    componentField("A:", $oklchA, label: "Alpha channel") { commitOKLCH() }
                }
            }
        }
        .padding(.horizontal, 12)
        // D-08 per-tool .selectOutputRow observer — handles ⌘1–⌘5 for Color rows.
        // Index 1 also resolves via the shared ToolShortcutsModifier (idempotent: same HEX value).
        // Out-of-range (⌘6–⌘9): outputForRow returns nil → harmless no-op (CF-01, T-04-06).
        .onReceive(NotificationCenter.default.publisher(for: .selectOutputRow)) { note in
            guard let index = note.userInfo?["index"] as? Int else { return }
            guard let text = viewModel.outputForRow(index), !text.isEmpty else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    // Generic labeled format row: badge + label + fields + copy button (D-08)
    @ViewBuilder
    private func formatRow<Content: View>(
        label: String,
        rowIndex: Int,
        copyTooltip: String,
        copyText: @escaping () -> String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            OutputRowBadge(index: rowIndex) // D-08 — leading numbered badge for ⌘N copy
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 42, alignment: .leading)
            content()
            Spacer()
            CopyButtonView(getText: copyText)
                .help(copyTooltip)
                .accessibilityLabel(copyTooltip)
        }
        .padding(.vertical, 2)
    }

    // Small labeled component TextField (e.g. "R: 255")
    @ViewBuilder
    private func componentField(
        _ prefix: String,
        _ binding: Binding<String>,
        label: String,
        onCommit: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 2) {
            Text(prefix)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("0", text: binding)
                .font(.system(size: 13, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .frame(width: 52)
                .accessibilityLabel(label)
                .onSubmit(onCommit)
        }
    }

    // MARK: - Sliders (D-06, CLR-03)

    private var slidersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sliderRow(label: "R", value: $viewModel.red, range: 0...1, accessibilityLabel: "Red slider")
            sliderRow(label: "G", value: $viewModel.green, range: 0...1, accessibilityLabel: "Green slider")
            sliderRow(label: "B", value: $viewModel.blue, range: 0...1, accessibilityLabel: "Blue slider")
            Divider().padding(.vertical, 2)
            sliderRow(label: "H", value: $viewModel.hue, range: 0...360, accessibilityLabel: "Hue slider")
            sliderRow(label: "S", value: $viewModel.saturation, range: 0...1, accessibilityLabel: "Saturation slider")
            sliderRow(label: "L", value: $viewModel.lightness, range: 0...1, accessibilityLabel: "Lightness slider")
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private func sliderRow(label: String, value: Binding<Double>, range: ClosedRange<Double>, accessibilityLabel: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 16, alignment: .leading)
            Slider(value: value, in: range)
                .accessibilityLabel(accessibilityLabel)
        }
    }

    // MARK: - WCAG Section (D-07, CLR-04)

    private var wcagSection: some View {
        DisclosureGroup(isExpanded: $wcagExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                // Color A (current) vs Color B (compare picker)
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(
                            red: viewModel.canonicalRGBA.red,
                            green: viewModel.canonicalRGBA.green,
                            blue: viewModel.canonicalRGBA.blue,
                            opacity: viewModel.canonicalRGBA.alpha
                        ))
                        .frame(width: 40, height: 32)
                        .accessibilityLabel("Color A (current color)")

                    Text("vs")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)

                    ColorPicker("Compare color", selection: $viewModel.compareSwiftUIColor)
                        .labelsHidden()
                        .accessibilityLabel("Compare color picker")

                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(
                            red: viewModel.compareColor.red,
                            green: viewModel.compareColor.green,
                            blue: viewModel.compareColor.blue,
                            opacity: viewModel.compareColor.alpha
                        ))
                        .frame(width: 40, height: 32)
                        .accessibilityLabel("Color B (compare color)")
                }

                // Contrast ratio
                let ratio = viewModel.wcagResults.contrastRatio
                Text(String(format: "Contrast ratio: %.2f:1", ratio))
                    .font(.system(size: 13))
                    .accessibilityLabel(String(format: "WCAG contrast ratio %.2f:1", ratio))

                // AA/AAA badges
                let results = viewModel.wcagResults
                VStack(alignment: .leading, spacing: 4) {
                    wcagRow("AA Normal (≥ 4.5:1)", pass: results.aaNormal)
                    wcagRow("AA Large (≥ 3.0:1)",  pass: results.aaLarge)
                    wcagRow("AAA Normal (≥ 7.0:1)", pass: results.aaaNormal)
                    wcagRow("AAA Large (≥ 4.5:1)",  pass: results.aaaLarge)
                }
            }
            .padding(.top, 8)
        } label: {
            Text("WCAG Contrast")
                .font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private func wcagRow(_ label: String, pass: Bool) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 13))
                .frame(minWidth: 140, alignment: .leading)
            Text(pass ? "PASS" : "FAIL")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(pass ? Color.green : Color.red)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(pass ? "PASS" : "FAIL")")
    }

    // MARK: - Field Sync

    /// Sync all text field strings from the canonical ViewModel state.
    /// Called on .onAppear and whenever canonicalRGBA changes.
    private func syncFieldsFromVM() {
        hexFieldText = viewModel.hexString

        let rgba = viewModel.canonicalRGBA
        rgbR = String(Int((rgba.red   * 255).rounded()))
        rgbG = String(Int((rgba.green * 255).rounded()))
        rgbB = String(Int((rgba.blue  * 255).rounded()))
        rgbA = String(format: "%.2f", rgba.alpha)

        let hsl = ColorTransformer.rgbToHSL(rgba)
        hslH = String(Int(hsl.hue.rounded()))
        hslS = String(Int((hsl.saturation * 100).rounded()))
        hslL = String(Int((hsl.lightness  * 100).rounded()))
        hslA = String(format: "%.2f", rgba.alpha)

        let hsv = ColorTransformer.rgbToHSV(rgba)
        hsvH = String(Int(hsv.hue.rounded()))
        hsvS = String(Int((hsv.saturation * 100).rounded()))
        hsvV = String(Int((hsv.value      * 100).rounded()))
        hsvA = String(format: "%.2f", rgba.alpha)

        let oklch = ColorTransformer.rgbToOKLCH(rgba)
        oklchL = String(format: "%.3f", oklch.l)
        oklchC = String(format: "%.3f", oklch.c)
        oklchH = String(format: "%.1f", oklch.h)
        oklchA = String(format: "%.2f", rgba.alpha)
    }

    // MARK: - Commit helpers

    private func commitRGB() {
        let r = Double(rgbR) ?? 0
        let g = Double(rgbG) ?? 0
        let b = Double(rgbB) ?? 0
        let a = Double(rgbA) ?? 1
        viewModel.updateFromRGB(r: r, g: g, b: b, a: a)
    }

    private func commitHSL() {
        let h = Double(hslH) ?? 0
        let s = Double(hslS) ?? 0
        let l = Double(hslL) ?? 0
        let a = Double(hslA) ?? 1
        viewModel.updateFromHSL(h: h, s: s, l: l, a: a)
    }

    private func commitHSV() {
        let h = Double(hsvH) ?? 0
        let s = Double(hsvS) ?? 0
        let v = Double(hsvV) ?? 0
        let a = Double(hsvA) ?? 1
        viewModel.updateFromHSV(h: h, s: s, v: v, a: a)
    }

    private func commitOKLCH() {
        let l = Double(oklchL) ?? 0
        let c = Double(oklchC) ?? 0
        let h = Double(oklchH) ?? 0
        let a = Double(oklchA) ?? 1
        viewModel.updateFromOKLCH(l: l, c: c, h: h, a: a)
    }
}
