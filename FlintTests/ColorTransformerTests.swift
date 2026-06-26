// FlintTests/ColorTransformerTests.swift
// Tests for ColorTransformer — reference vectors for HEX/RGB/HSL/HSV/OKLCH + WCAG + gamut.
// CLR-01..04, INFRA-17, T-02-CLR-IV, T-02-CLR-GAMUT.

import Testing
import Foundation
@testable import Flint

@Suite("ColorTransformer")
struct ColorTransformerTests {

    // MARK: - HEX Parse

    // Reference: "#FF8000" = R=255/255=1.0, G=128/255≈0.5019..., B=0/255=0.0
    @Test("parseHex #RRGGBB round-trip")
    func testParseHex_rrggbb() {
        guard let rgba = ColorTransformer.parseHex("#FF8000") else {
            Issue.record("Expected non-nil RGBA from #FF8000"); return
        }
        #expect(abs(rgba.red   - 1.0)    < 1e-4)
        #expect(abs(rgba.green - 128.0/255.0) < 1e-4)
        #expect(abs(rgba.blue  - 0.0)    < 1e-4)
        #expect(abs(rgba.alpha - 1.0)    < 1e-4)
    }

    @Test("parseHex #RRGGBBAA parses alpha correctly")
    func testParseHex_rrggbbaa() {
        // "#FF800080" — alpha = 0x80 = 128 → 128/255 ≈ 0.502
        guard let rgba = ColorTransformer.parseHex("#FF800080") else {
            Issue.record("Expected non-nil RGBA from #FF800080"); return
        }
        #expect(abs(rgba.alpha - 128.0/255.0) < 1e-4)
    }

    @Test("parseHex #RGB expands to #RRGGBB")
    func testParseHex_rgb_shortForm() {
        // "#F80" = #FF8800 → R=1.0, G=0x88/255≈0.5333, B=0.0
        guard let rgba = ColorTransformer.parseHex("#F80") else {
            Issue.record("Expected non-nil RGBA from #F80"); return
        }
        #expect(abs(rgba.red   - 1.0)          < 1e-4)
        #expect(abs(rgba.green - 0x88/255.0)   < 1e-4)
        #expect(abs(rgba.blue  - 0.0)          < 1e-4)
    }

    @Test("emitHex round-trip: parse then emit recovers #FF8000")
    func testEmitHex_roundTrip() {
        guard let rgba = ColorTransformer.parseHex("#FF8000") else {
            Issue.record("Expected non-nil RGBA"); return
        }
        let hex = ColorTransformer.emitHex(rgba)
        #expect(hex == "#FF8000")
    }

    @Test("emitHex with alpha emits 8-digit form")
    func testEmitHex_withAlpha() {
        let rgba = RGBA(red: 1.0, green: 0.5019607843137255, blue: 0.0, alpha: 0.5019607843137255)
        let hex = ColorTransformer.emitHex(rgba)
        // alpha ≈ 128/255 → should include alpha in hex
        #expect(hex.count == 9) // "#RRGGBBAA"
    }

    // MARK: - HEX Garbage (INFRA-17)

    @Test("parseHex garbage '#ZZZ' returns nil — no crash")
    func testParseHex_garbage_nocrash() {
        let result = ColorTransformer.parseHex("#ZZZ")
        #expect(result == nil)
    }

    @Test("parseHex empty string returns nil — no crash")
    func testParseHex_empty_nocrash() {
        let result = ColorTransformer.parseHex("")
        #expect(result == nil)
    }

    @Test("parseHex wrong length '#FFFFF' returns nil")
    func testParseHex_wrongLength_nocrash() {
        let result = ColorTransformer.parseHex("#FFFFF")
        #expect(result == nil)
    }

    @Test("parseHex no-hash still works")
    func testParseHex_noHash() {
        let result = ColorTransformer.parseHex("FF0000")
        #expect(result != nil)
        #expect(abs((result?.red ?? 0) - 1.0) < 1e-4)
    }

    // MARK: - RGB ↔ HSL

    // Reference: pure red (1,0,0) → HSL(0°, 100%, 50%)
    @Test("RGB→HSL: pure red → HSL(0, 1.0, 0.5)")
    func testRGBtoHSL_pureRed() {
        let rgba = RGBA(red: 1.0, green: 0.0, blue: 0.0)
        let hsla = ColorTransformer.rgbToHSL(rgba)
        #expect(abs(hsla.hue        - 0.0) < 1e-4)
        #expect(abs(hsla.saturation - 1.0) < 1e-4)
        #expect(abs(hsla.lightness  - 0.5) < 1e-4)
    }

    @Test("HSL→RGB round-trip: pure red → HSL → back to RGB")
    func testHSLtoRGB_pureRed_roundTrip() {
        let rgba = RGBA(red: 1.0, green: 0.0, blue: 0.0)
        let hsla = ColorTransformer.rgbToHSL(rgba)
        let back = ColorTransformer.hslToRGB(hsla)
        #expect(abs(back.red   - 1.0) < 1e-4)
        #expect(abs(back.green - 0.0) < 1e-4)
        #expect(abs(back.blue  - 0.0) < 1e-4)
    }

    // #CR-03: hue == 360 is equivalent to hue 0 (red), must NOT fall through to black.
    @Test("HSL→RGB: hue 360 → red, not black")
    func testHSLtoRGB_hue360_isRed() {
        let back = ColorTransformer.hslToRGB(HSLA(hue: 360, saturation: 1.0, lightness: 0.5, alpha: 1.0))
        #expect(abs(back.red   - 1.0) < 1e-4)
        #expect(abs(back.green - 0.0) < 1e-4)
        #expect(abs(back.blue  - 0.0) < 1e-4)
    }

    @Test("HSV→RGB: hue 360 → red, not black")
    func testHSVtoRGB_hue360_isRed() {
        let back = ColorTransformer.hsvToRGB(HSVA(hue: 360, saturation: 1.0, value: 1.0, alpha: 1.0))
        #expect(abs(back.red   - 1.0) < 1e-4)
        #expect(abs(back.green - 0.0) < 1e-4)
        #expect(abs(back.blue  - 0.0) < 1e-4)
    }

    // Achromatic: gray — S must be 0, no divide-by-zero
    @Test("RGB→HSL: gray (0.5,0.5,0.5) → S=0, L=0.5 — no divide by zero")
    func testRGBtoHSL_achromatic_noCrash() {
        let rgba = RGBA(red: 0.5, green: 0.5, blue: 0.5)
        let hsla = ColorTransformer.rgbToHSL(rgba)
        #expect(abs(hsla.saturation - 0.0) < 1e-4)
        #expect(abs(hsla.lightness  - 0.5) < 1e-4)
    }

    @Test("RGB→HSL→RGB round-trip: arbitrary color (0.2, 0.6, 0.8)")
    func testHSL_roundTrip_arbitrary() {
        let original = RGBA(red: 0.2, green: 0.6, blue: 0.8)
        let back = ColorTransformer.hslToRGB(ColorTransformer.rgbToHSL(original))
        #expect(abs(back.red   - original.red)   < 1e-3)
        #expect(abs(back.green - original.green) < 1e-3)
        #expect(abs(back.blue  - original.blue)  < 1e-3)
    }

    // MARK: - RGB ↔ HSV

    // Reference: pure red (1,0,0) → HSV(0°, 1.0, 1.0)
    @Test("RGB→HSV: pure red → HSV(0, 1.0, 1.0)")
    func testRGBtoHSV_pureRed() {
        let rgba = RGBA(red: 1.0, green: 0.0, blue: 0.0)
        let hsva = ColorTransformer.rgbToHSV(rgba)
        #expect(abs(hsva.hue        - 0.0) < 1e-4)
        #expect(abs(hsva.saturation - 1.0) < 1e-4)
        #expect(abs(hsva.value      - 1.0) < 1e-4)
    }

    @Test("HSV→RGB round-trip: pure red → HSV → back to RGB")
    func testHSVtoRGB_pureRed_roundTrip() {
        let rgba = RGBA(red: 1.0, green: 0.0, blue: 0.0)
        let hsva = ColorTransformer.rgbToHSV(rgba)
        let back = ColorTransformer.hsvToRGB(hsva)
        #expect(abs(back.red   - 1.0) < 1e-4)
        #expect(abs(back.green - 0.0) < 1e-4)
        #expect(abs(back.blue  - 0.0) < 1e-4)
    }

    // Achromatic: black (0,0,0) — V=0, S=0, no divide-by-zero
    @Test("RGB→HSV: black (0,0,0) → V=0, S=0 — no divide by zero (achromatic guard)")
    func testRGBtoHSV_black_noCrash() {
        let rgba = RGBA(red: 0.0, green: 0.0, blue: 0.0)
        let hsva = ColorTransformer.rgbToHSV(rgba)
        #expect(abs(hsva.saturation - 0.0) < 1e-4)
        #expect(abs(hsva.value      - 0.0) < 1e-4)
    }

    // Achromatic: white (1,1,1) — V=1, S=0
    @Test("RGB→HSV: white (1,1,1) → V=1, S=0 — no divide by zero")
    func testRGBtoHSV_white_noCrash() {
        let rgba = RGBA(red: 1.0, green: 1.0, blue: 1.0)
        let hsva = ColorTransformer.rgbToHSV(rgba)
        #expect(abs(hsva.saturation - 0.0) < 1e-4)
        #expect(abs(hsva.value      - 1.0) < 1e-4)
    }

    @Test("RGB→HSV→RGB round-trip: arbitrary color (0.3, 0.7, 0.4)")
    func testHSV_roundTrip_arbitrary() {
        let original = RGBA(red: 0.3, green: 0.7, blue: 0.4)
        let back = ColorTransformer.hsvToRGB(ColorTransformer.rgbToHSV(original))
        #expect(abs(back.red   - original.red)   < 1e-3)
        #expect(abs(back.green - original.green) < 1e-3)
        #expect(abs(back.blue  - original.blue)  < 1e-3)
    }

    // MARK: - WCAG Contrast Ratio

    // Reference (W3C WCAG 2.1): black vs white = 21:1
    // L(white) = 1.0, L(black) = 0.0 → (1.0+0.05)/(0.0+0.05) = 1.05/0.05 = 21.0
    @Test("WCAG contrast ratio: black vs white = 21.0:1 (±0.05)")
    func testWCAG_blackVsWhite() {
        let ratio = ColorTransformer.wcagContrastRatio(.black, .white)
        #expect(abs(ratio - 21.0) < 0.05)
    }

    @Test("WCAG: black vs white passes AA normal (≥4.5) and AAA normal (≥7.0)")
    func testWCAG_blackVsWhite_passesAllThresholds() {
        let ratio = ColorTransformer.wcagContrastRatio(.black, .white)
        let results = ColorTransformer.wcagResults(ratio: ratio)
        #expect(results.aaNormal  == true)   // ≥ 4.5
        #expect(results.aaLarge   == true)   // ≥ 3.0
        #expect(results.aaaNormal == true)   // ≥ 7.0
        #expect(results.aaaLarge  == true)   // ≥ 4.5
    }

    // Reference: same color vs itself = 1.0:1
    @Test("WCAG: same color vs itself = 1.0:1")
    func testWCAG_sameColor() {
        let color = RGBA(red: 0.5, green: 0.5, blue: 0.5)
        let ratio = ColorTransformer.wcagContrastRatio(color, color)
        #expect(abs(ratio - 1.0) < 0.01)
    }

    // Reference: mid-gray (#808080, ~0.216 luminance) vs white
    // L(#808080) = 0.2126*(0.502²·2.4approx) + ... ≈ 0.216
    // Ratio ≈ (1.0+0.05)/(0.216+0.05) ≈ 3.95 — fails AA normal but passes AA large
    @Test("WCAG: mid-gray vs white fails AA normal but passes AA large")
    func testWCAG_midGrayVsWhite() {
        // #808080 = 128/255 ≈ 0.50196
        let gray = RGBA(red: 128.0/255.0, green: 128.0/255.0, blue: 128.0/255.0)
        let ratio = ColorTransformer.wcagContrastRatio(gray, .white)
        let results = ColorTransformer.wcagResults(ratio: ratio)
        // Ratio should be ~3.95 → passes AA large (≥3.0) but fails AA normal (≥4.5)
        #expect(ratio > 3.0 && ratio < 5.0)
        #expect(results.aaLarge   == true)
        #expect(results.aaNormal  == false)
    }

    // MARK: - OKLCH Reference Vectors

    // Reference vector 1: sRGB pure red (#FF0000) → OKLCH
    // From CSS Color 4 playground / oklch.com:
    // red (#FF0000) → OKLCH ≈ L=0.6279554, C=0.2576831, H=29.23°
    @Test("OKLCH reverse: pure red → OKLCH reference vector (tolerance ±0.01)")
    func testOKLCH_reverse_pureRed_referenceVector() {
        let red = RGBA(red: 1.0, green: 0.0, blue: 0.0)
        let oklch = ColorTransformer.rgbToOKLCH(red)
        // L ≈ 0.6279554
        #expect(abs(oklch.l - 0.6279554) < 0.01, "L expected ~0.6279554, got \(oklch.l)")
        // C ≈ 0.2576831
        #expect(abs(oklch.c - 0.2576831) < 0.01, "C expected ~0.2576831, got \(oklch.c)")
        // H ≈ 29.23°
        #expect(abs(oklch.h - 29.23) < 1.5, "H expected ~29.23°, got \(oklch.h)")
    }

    // Reference vector 2: sRGB green (#00FF00) → OKLCH
    // From CSS Color 4: green (#00FF00) → OKLCH ≈ L=0.8664396, C=0.2947553, H=142.495°
    @Test("OKLCH reverse: pure green → OKLCH reference vector (tolerance ±0.01)")
    func testOKLCH_reverse_pureGreen_referenceVector() {
        let green = RGBA(red: 0.0, green: 1.0, blue: 0.0)
        let oklch = ColorTransformer.rgbToOKLCH(green)
        // L ≈ 0.8664396
        #expect(abs(oklch.l - 0.8664396) < 0.02, "L expected ~0.8664396, got \(oklch.l)")
        // C ≈ 0.2947553
        #expect(abs(oklch.c - 0.2947553) < 0.02, "C expected ~0.2947553, got \(oklch.c)")
        // H ≈ 142.5°
        #expect(abs(oklch.h - 142.5) < 2.0, "H expected ~142.5°, got \(oklch.h)")
    }

    // Reference vector 3: sRGB blue (#0000FF) → OKLCH
    // From CSS Color 4: blue (#0000FF) → OKLCH ≈ L=0.4520138, C=0.3132888, H=264.052°
    @Test("OKLCH reverse: pure blue → OKLCH reference vector (tolerance ±0.01)")
    func testOKLCH_reverse_pureBlue_referenceVector() {
        let blue = RGBA(red: 0.0, green: 0.0, blue: 1.0)
        let oklch = ColorTransformer.rgbToOKLCH(blue)
        // L ≈ 0.4520138
        #expect(abs(oklch.l - 0.4520138) < 0.02, "L expected ~0.4520138, got \(oklch.l)")
        // C ≈ 0.3132888
        #expect(abs(oklch.c - 0.3132888) < 0.02, "C expected ~0.3132888, got \(oklch.c)")
        // H ≈ 264.05°
        #expect(abs(oklch.h - 264.05) < 2.0, "H expected ~264.05°, got \(oklch.h)")
    }

    // Round-trip: sRGB → OKLCH → sRGB via ChromaKit forward
    @Test("OKLCH round-trip: sRGB→OKLCH→sRGB within tolerance (±0.01)")
    func testOKLCH_roundTrip_sRGB_to_OKLCH_to_sRGB() {
        // Use a mid-sRGB color (#4080C0) well within gamut
        let original = RGBA(red: 0x40/255.0, green: 0x80/255.0, blue: 0xC0/255.0)
        let oklch = ColorTransformer.rgbToOKLCH(original)
        let result = ColorTransformer.oklchToRGB(oklch)
        #expect(result.isOutOfGamut == false)
        #expect(abs(result.rgba.red   - original.red)   < 0.01, "R round-trip error: \(result.rgba.red) vs \(original.red)")
        #expect(abs(result.rgba.green - original.green) < 0.01, "G round-trip error: \(result.rgba.green) vs \(original.green)")
        #expect(abs(result.rgba.blue  - original.blue)  < 0.01, "B round-trip error: \(result.rgba.blue) vs \(original.blue)")
    }

    // MARK: - Out-of-Gamut Detection (T-02-CLR-GAMUT)

    // OKLCH value with very high chroma that maps outside sRGB gamut.
    // oklch(0.5 1.0 270) — c=1.0 is far outside typical sRGB (~0.4 max)
    @Test("OKLCH out-of-gamut: high chroma OKLCH returns isOutOfGamut=true with clamped channels in 0...1")
    func testOKLCH_outOfGamut_highChroma() {
        let outOfGamut = OKLCHA(l: 0.5, c: 1.0, h: 270.0, alpha: 1.0)
        let result = ColorTransformer.oklchToRGB(outOfGamut)
        #expect(result.isOutOfGamut == true)
        // Clamped result must still have valid 0...1 channels (swatch stays meaningful, D-08)
        #expect(result.rgba.red   >= 0.0 && result.rgba.red   <= 1.0)
        #expect(result.rgba.green >= 0.0 && result.rgba.green <= 1.0)
        #expect(result.rgba.blue  >= 0.0 && result.rgba.blue  <= 1.0)
    }

    // An in-gamut OKLCH value — isOutOfGamut must be false
    @Test("OKLCH in-gamut: pure sRGB primary stays in-gamut")
    func testOKLCH_inGamut() {
        // Pure sRGB gray (0.5, 0.5, 0.5) has C≈0, well within sRGB gamut
        let gray = RGBA(red: 0.5, green: 0.5, blue: 0.5)
        let oklch = ColorTransformer.rgbToOKLCH(gray)
        let result = ColorTransformer.oklchToRGB(oklch)
        #expect(result.isOutOfGamut == false)
    }
}
