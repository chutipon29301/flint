// Tools/Color/ColorViewModel.swift
// Single canonical sRGB RGBA source-of-truth ViewModel for the Color Converter.
// Conforms to ToolShortcutActions — ⌘⇧C copies HEX, ⌘⌫ resets to black.
// Synchronous pure transforms — no debounce needed (CF-01: cheap operations).
// Source: UI-SPEC.md "Tool 2: Color Converter" + PATTERNS.md "Color/NumberBase note"

import Foundation
import Observation
import SwiftUI
import AppKit

@Observable
@MainActor
final class ColorViewModel: ToolShortcutActions {

    // MARK: - Canonical Source-of-Truth

    /// The ONE canonical sRGB RGBA, all channels in 0.0...1.0.
    /// All format rows and sliders derive from this — no independent drifting strings.
    var canonicalRGBA: RGBA = .black {
        didSet { deriveAllRows() }
    }

    // MARK: - Out-of-Gamut Warning (D-08, T-02-CLR-GAMUT)

    /// True when the last OKLCH→sRGB conversion clipped at least one channel.
    var outOfGamutWarning: Bool = false

    // MARK: - Derived Display Strings (computed from canonicalRGBA)

    private(set) var hexString: String = "#000000"
    private(set) var rgbString: String = "0, 0, 0"
    private(set) var hslString: String = "0, 0%, 0%"
    private(set) var hsvString: String = "0, 0%, 0%"
    private(set) var oklchString: String = "0.000, 0.000, 0.000"

    // MARK: - Slider bindings (direct R/G/B/H/S/L)

    var red: Double {
        get { canonicalRGBA.red }
        set { canonicalRGBA.red = max(0, min(1, newValue)) }
    }
    var green: Double {
        get { canonicalRGBA.green }
        set { canonicalRGBA.green = max(0, min(1, newValue)) }
    }
    var blue: Double {
        get { canonicalRGBA.blue }
        set { canonicalRGBA.blue = max(0, min(1, newValue)) }
    }
    var alpha: Double {
        get { canonicalRGBA.alpha }
        set { canonicalRGBA.alpha = max(0, min(1, newValue)) }
    }

    // HSL computed from canonical (two-way via setters)
    var hue: Double {
        get { ColorTransformer.rgbToHSL(canonicalRGBA).hue }
        set {
            var hsl = ColorTransformer.rgbToHSL(canonicalRGBA)
            hsl.hue = max(0, min(360, newValue))
            canonicalRGBA = ColorTransformer.hslToRGB(hsl)
            outOfGamutWarning = false
        }
    }
    var saturation: Double {
        get { ColorTransformer.rgbToHSL(canonicalRGBA).saturation }
        set {
            var hsl = ColorTransformer.rgbToHSL(canonicalRGBA)
            hsl.saturation = max(0, min(1, newValue))
            canonicalRGBA = ColorTransformer.hslToRGB(hsl)
            outOfGamutWarning = false
        }
    }
    var lightness: Double {
        get { ColorTransformer.rgbToHSL(canonicalRGBA).lightness }
        set {
            var hsl = ColorTransformer.rgbToHSL(canonicalRGBA)
            hsl.lightness = max(0, min(1, newValue))
            canonicalRGBA = ColorTransformer.hslToRGB(hsl)
            outOfGamutWarning = false
        }
    }

    // MARK: - SwiftUI Color binding (for system ColorPicker)

    /// SwiftUI Color binding for system ColorPicker panel — two-way via NSColor sRGB conversion.
    var swiftUIColor: SwiftUI.Color {
        get {
            SwiftUI.Color(red: canonicalRGBA.red, green: canonicalRGBA.green, blue: canonicalRGBA.blue, opacity: canonicalRGBA.alpha)
        }
        set {
            // Convert SwiftUI.Color → NSColor → sRGB components
            let nsColor = NSColor(newValue)
            if let srgb = nsColor.usingColorSpace(.sRGB) {
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                srgb.getRed(&r, green: &g, blue: &b, alpha: &a)
                canonicalRGBA = RGBA(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a))
                outOfGamutWarning = false
            }
        }
    }

    // MARK: - WCAG Compare Color

    /// Second color for WCAG contrast comparison (D-07, CLR-04).
    var compareColor: RGBA = .white {
        didSet { deriveWCAG() }
    }

    var compareSwiftUIColor: SwiftUI.Color {
        get {
            SwiftUI.Color(red: compareColor.red, green: compareColor.green, blue: compareColor.blue, opacity: compareColor.alpha)
        }
        set {
            let nsColor = NSColor(newValue)
            if let srgb = nsColor.usingColorSpace(.sRGB) {
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                srgb.getRed(&r, green: &g, blue: &b, alpha: &a)
                compareColor = RGBA(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a))
            }
        }
    }

    private(set) var wcagResults: WCAGResults = WCAGResults(contrastRatio: 21.0, aaNormal: true, aaLarge: true, aaaNormal: true, aaaLarge: true)

    // MARK: - Init

    init() {
        deriveAllRows()
    }

    // MARK: - Update from format rows (called from View TextFields)

    /// Update canonical RGBA from a HEX string edit. Silently no-ops on invalid input (INFRA-17).
    func updateFromHex(_ hexInput: String) {
        guard let rgba = ColorTransformer.parseHex(hexInput) else { return }
        outOfGamutWarning = false
        canonicalRGBA = rgba
    }

    /// Update canonical RGBA from RGB string (format "R, G, B" or individual components 0-255).
    /// Each component is in 0...255.
    func updateFromRGB(r: Double, g: Double, b: Double, a: Double) {
        let newRGBA = RGBA(
            red:   max(0, min(1, r / 255.0)),
            green: max(0, min(1, g / 255.0)),
            blue:  max(0, min(1, b / 255.0)),
            alpha: max(0, min(1, a))
        )
        outOfGamutWarning = false
        canonicalRGBA = newRGBA
    }

    /// Update canonical RGBA from HSL components (H 0-360, S 0-100%, L 0-100%, A 0-1).
    func updateFromHSL(h: Double, s: Double, l: Double, a: Double) {
        let hsla = HSLA(hue: h, saturation: s / 100.0, lightness: l / 100.0, alpha: a)
        outOfGamutWarning = false
        canonicalRGBA = ColorTransformer.hslToRGB(hsla)
    }

    /// Update canonical RGBA from HSV components (H 0-360, S 0-100%, V 0-100%, A 0-1).
    func updateFromHSV(h: Double, s: Double, v: Double, a: Double) {
        let hsva = HSVA(hue: h, saturation: s / 100.0, value: v / 100.0, alpha: a)
        outOfGamutWarning = false
        canonicalRGBA = ColorTransformer.hsvToRGB(hsva)
    }

    /// Update canonical RGBA from OKLCH components (L 0-1, C 0-0.5, H 0-360, A 0-1).
    func updateFromOKLCH(l: Double, c: Double, h: Double, a: Double) {
        let oklcha = OKLCHA(l: l, c: c, h: h, alpha: a)
        let result = ColorTransformer.oklchToRGB(oklcha)
        // D-08: keep clamped color + set warning flag
        outOfGamutWarning = result.isOutOfGamut
        canonicalRGBA = result.rgba
    }

    /// Update canonical RGBA from NSColorSampler or NSColorPanel pick.
    func updateFromNSColor(_ nsColor: NSColor) {
        guard let srgb = nsColor.usingColorSpace(.sRGB) else { return }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        srgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        outOfGamutWarning = false
        canonicalRGBA = RGBA(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a))
    }

    // MARK: - ToolShortcutActions (INFRA-16)

    /// Primary output is the HEX string (⌘⇧C copies this).
    func primaryOutput() -> String? {
        hexString
    }

    /// Clear/reset to black (⌘⌫).
    func clearInput() {
        outOfGamutWarning = false
        canonicalRGBA = .black
    }

    // MARK: - D-08 Row Copy (⌘1–⌘9)

    /// Returns the copyable string for the given row index.
    /// Row map (UI-SPEC D-08): 1=HEX, 2=RGB, 3=HSL, 4=HSV, 5=OKLCH.
    /// Returns nil for out-of-range index — silent no-op (CF-01, T-04-06).
    func outputForRow(_ index: Int) -> String? {
        let rgba = canonicalRGBA
        switch index {
        case 1:
            return hexString.isEmpty ? nil : hexString
        case 2:
            return rgbString.isEmpty ? nil : rgbString
        case 3:
            let alpha = rgba.alpha
            let full = "hsl(\(hslString) / \(String(format: "%.2f", alpha)))"
            return full.isEmpty ? nil : full
        case 4:
            let alpha = rgba.alpha
            let full = "hsv(\(hsvString) / \(String(format: "%.2f", alpha)))"
            return full.isEmpty ? nil : full
        case 5:
            let alpha = rgba.alpha
            let full = "oklch(\(oklchString) / \(String(format: "%.2f", alpha)))"
            return full.isEmpty ? nil : full
        default:
            return nil // out-of-range: silent no-op (CF-01, T-04-06)
        }
    }

    // MARK: - Private Helpers

    private func deriveAllRows() {
        let rgba = canonicalRGBA
        hexString = ColorTransformer.emitHex(rgba)

        // RGB 0-255 display
        let r255 = Int((rgba.red   * 255).rounded())
        let g255 = Int((rgba.green * 255).rounded())
        let b255 = Int((rgba.blue  * 255).rounded())
        rgbString = "\(r255), \(g255), \(b255)"

        // HSL
        let hsl = ColorTransformer.rgbToHSL(rgba)
        hslString = "\(Int(hsl.hue.rounded())), \(Int((hsl.saturation * 100).rounded()))%, \(Int((hsl.lightness * 100).rounded()))%"

        // HSV
        let hsv = ColorTransformer.rgbToHSV(rgba)
        hsvString = "\(Int(hsv.hue.rounded())), \(Int((hsv.saturation * 100).rounded()))%, \(Int((hsv.value * 100).rounded()))%"

        // OKLCH
        let oklch = ColorTransformer.rgbToOKLCH(rgba)
        oklchString = String(format: "%.3f, %.3f, %.1f", oklch.l, oklch.c, oklch.h)

        deriveWCAG()
    }

    private func deriveWCAG() {
        let ratio = ColorTransformer.wcagContrastRatio(canonicalRGBA, compareColor)
        wcagResults = ColorTransformer.wcagResults(ratio: ratio)
    }

}
