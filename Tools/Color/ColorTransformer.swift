// Tools/Color/ColorTransformer.swift
// Pure color math transformer — NO SwiftUI imports (testable without UI).
// OKLCH forward via ChromaKit; OKLCH reverse hand-computed via CSS Color Level 4 math.
// INFRA-17: All parse paths return Result/total fn; never force-unwrap; never crash on bad input.
// T-02-CLR-IV: every parse path guards garbage input.
// T-02-CLR-GAMUT: out-of-gamut OKLCH sets isOutOfGamut via own range check (not ChromaKit clamp).

import Foundation
import AppKit      // NSColor + NSColor.usingColorSpace(.sRGB) — no SwiftUI needed here
import ChromaKit

// MARK: - Canonical sRGB RGBA

/// Canonical internal representation: sRGB RGBA all in 0.0...1.0.
struct RGBA: Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    static let black = RGBA(red: 0, green: 0, blue: 0, alpha: 1)
    static let white = RGBA(red: 1, green: 1, blue: 1, alpha: 1)
}

// MARK: - HSL

struct HSLA: Equatable {
    var hue: Double        // 0...360
    var saturation: Double // 0...1
    var lightness: Double  // 0...1
    var alpha: Double      // 0...1
}

// MARK: - HSV

struct HSVA: Equatable {
    var hue: Double        // 0...360
    var saturation: Double // 0...1
    var value: Double      // 0...1
    var alpha: Double      // 0...1
}

// MARK: - OKLCH

struct OKLCHA: Equatable {
    var l: Double    // 0...1
    var c: Double    // 0...0.5 (typical)
    var h: Double    // 0...360
    var alpha: Double // 0...1
}

// MARK: - Gamut Result

/// Result of OKLCH→sRGB conversion, carrying the clamped RGBA and a gamut flag.
struct GamutResult: Equatable {
    let rgba: RGBA
    /// True if any raw (unclamped) sRGB channel was outside [0, 1].
    let isOutOfGamut: Bool
}

// MARK: - WCAG Results

struct WCAGResults: Equatable {
    let contrastRatio: Double
    let aaNormal: Bool   // ratio >= 4.5
    let aaLarge: Bool    // ratio >= 3.0
    let aaaNormal: Bool  // ratio >= 7.0
    let aaaLarge: Bool   // ratio >= 4.5
}

// MARK: - ColorTransformer

enum ColorTransformer {

    // MARK: - HEX Parse/Emit

    /// Parse a HEX string (#RGB, #RRGGBB, #RRGGBBAA) into sRGB RGBA.
    /// Returns nil on failure — never crashes on bad input (INFRA-17).
    static func parseHex(_ input: String) -> RGBA? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Strip leading #
        let hex = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        let len = hex.count
        guard len == 3 || len == 6 || len == 8 else { return nil }
        // Validate hex digits
        guard hex.allSatisfy({ $0.isHexDigit }) else { return nil }

        let expanded: String
        if len == 3 {
            // #RGB → #RRGGBB
            expanded = hex.map { "\($0)\($0)" }.joined()
        } else {
            expanded = hex
        }

        guard expanded.count == 6 || expanded.count == 8 else { return nil }

        // Parse each 2-char hex chunk using Array indexing to avoid String subscript ambiguity
        let chars = Array(expanded)
        func byteAt(_ i: Int) -> Double {
            let s = String(chars[i..<i+2])
            return Double(UInt8(s, radix: 16) ?? 0) / 255.0
        }
        let r = byteAt(0)
        let g = byteAt(2)
        let b = byteAt(4)
        let a: Double = expanded.count == 8 ? byteAt(6) : 1.0
        return RGBA(red: r, green: g, blue: b, alpha: a)
    }

    /// Emit a HEX string from sRGB RGBA.
    /// If alpha < 1.0, emits 8-digit form (#RRGGBBAA); otherwise 6-digit form (#RRGGBB).
    static func emitHex(_ rgba: RGBA, includeAlpha: Bool = false) -> String {
        let r = clampByte(rgba.red)
        let g = clampByte(rgba.green)
        let b = clampByte(rgba.blue)
        let a = clampByte(rgba.alpha)
        if includeAlpha || rgba.alpha < 1.0 - 1e-9 {
            return String(format: "#%02X%02X%02X%02X", r, g, b, a)
        }
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    private static func clampByte(_ v: Double) -> UInt8 {
        UInt8(max(0, min(255, (v * 255).rounded())))
    }

    // MARK: - RGB ↔ HSL

    /// Convert sRGB RGBA to HSLA.
    static func rgbToHSL(_ rgba: RGBA) -> HSLA {
        let r = rgba.red, g = rgba.green, b = rgba.blue
        let cMax = max(r, g, b)
        let cMin = min(r, g, b)
        let delta = cMax - cMin
        let l = (cMax + cMin) / 2.0

        let s: Double
        if delta < 1e-10 {
            // Achromatic — guard divide-by-zero (S=0)
            s = 0.0
        } else {
            s = delta / (1.0 - abs(2 * l - 1))
        }

        let h: Double
        if delta < 1e-10 {
            h = 0.0 // Achromatic
        } else if cMax == r {
            h = 60.0 * (((g - b) / delta).truncatingRemainder(dividingBy: 6.0))
        } else if cMax == g {
            h = 60.0 * (((b - r) / delta) + 2.0)
        } else {
            h = 60.0 * (((r - g) / delta) + 4.0)
        }

        let hNorm = h < 0 ? h + 360.0 : h
        return HSLA(hue: hNorm, saturation: s, lightness: l, alpha: rgba.alpha)
    }

    /// Wrap a hue angle into [0, 360). Handles 360, negatives, and >360 inputs.
    private static func normalizedHue(_ hue: Double) -> Double {
        let h = hue.truncatingRemainder(dividingBy: 360.0)
        return h < 0 ? h + 360.0 : h
    }

    /// Convert HSLA to sRGB RGBA.
    static func hslToRGB(_ hsla: HSLA) -> RGBA {
        // Normalize hue into [0,360) so 360 (== 0, red) doesn't fall through to black (#CR-03).
        let h = normalizedHue(hsla.hue), s = hsla.saturation, l = hsla.lightness
        let c = (1.0 - abs(2 * l - 1)) * s
        let x = c * (1.0 - abs((h / 60.0).truncatingRemainder(dividingBy: 2.0) - 1.0))
        let m = l - c / 2.0

        let (r1, g1, b1): (Double, Double, Double)
        switch h {
        case 0..<60:   (r1, g1, b1) = (c, x, 0)
        case 60..<120: (r1, g1, b1) = (x, c, 0)
        case 120..<180:(r1, g1, b1) = (0, c, x)
        case 180..<240:(r1, g1, b1) = (0, x, c)
        case 240..<300:(r1, g1, b1) = (x, 0, c)
        case 300..<360:(r1, g1, b1) = (c, 0, x)
        default:        (r1, g1, b1) = (0, 0, 0)
        }
        return RGBA(red: r1 + m, green: g1 + m, blue: b1 + m, alpha: hsla.alpha)
    }

    // MARK: - RGB ↔ HSV

    /// Convert sRGB RGBA to HSVA.
    static func rgbToHSV(_ rgba: RGBA) -> HSVA {
        let r = rgba.red, g = rgba.green, b = rgba.blue
        let cMax = max(r, g, b)
        let cMin = min(r, g, b)
        let delta = cMax - cMin

        let v = cMax

        let s: Double
        if cMax < 1e-10 {
            // Guard achromatic: V=0 → avoid divide-by-zero
            s = 0.0
        } else {
            s = delta / cMax
        }

        let h: Double
        if delta < 1e-10 {
            h = 0.0 // Achromatic
        } else if cMax == r {
            h = 60.0 * (((g - b) / delta).truncatingRemainder(dividingBy: 6.0))
        } else if cMax == g {
            h = 60.0 * (((b - r) / delta) + 2.0)
        } else {
            h = 60.0 * (((r - g) / delta) + 4.0)
        }

        let hNorm = h < 0 ? h + 360.0 : h
        return HSVA(hue: hNorm, saturation: s, value: v, alpha: rgba.alpha)
    }

    /// Convert HSVA to sRGB RGBA.
    static func hsvToRGB(_ hsva: HSVA) -> RGBA {
        // Normalize hue into [0,360) so 360 (== 0, red) doesn't fall through to black (#CR-03).
        let h = normalizedHue(hsva.hue), s = hsva.saturation, v = hsva.value
        if s < 1e-10 {
            // Achromatic — guard divide-by-zero for S=0
            return RGBA(red: v, green: v, blue: v, alpha: hsva.alpha)
        }
        let c = v * s
        let x = c * (1.0 - abs((h / 60.0).truncatingRemainder(dividingBy: 2.0) - 1.0))
        let m = v - c

        let (r1, g1, b1): (Double, Double, Double)
        switch h {
        case 0..<60:   (r1, g1, b1) = (c, x, 0)
        case 60..<120: (r1, g1, b1) = (x, c, 0)
        case 120..<180:(r1, g1, b1) = (0, c, x)
        case 180..<240:(r1, g1, b1) = (0, x, c)
        case 240..<300:(r1, g1, b1) = (x, 0, c)
        case 300..<360:(r1, g1, b1) = (c, 0, x)
        default:        (r1, g1, b1) = (0, 0, 0)
        }
        return RGBA(red: r1 + m, green: g1 + m, blue: b1 + m, alpha: hsva.alpha)
    }

    // MARK: - OKLCH (Forward: OKLCH → sRGB via ChromaKit)

    /// Convert OKLCH → sRGB RGBA using ChromaKit for the forward transformation.
    /// Returns a GamutResult with the clamped RGBA and an explicit isOutOfGamut flag.
    /// ChromaKit silently clamps; we detect out-of-gamut via our own unclamped range check.
    static func oklchToRGB(_ oklcha: OKLCHA) -> GamutResult {
        // ChromaKit: NSColor.oklch returns NSColor(displayP3Red:…) in Display P3 space.
        let nsColor = NSColor.oklch(oklcha.l, oklcha.c, oklcha.h, oklcha.alpha)
        // Always convert to sRGB before reading components (RESEARCH §4 "NSColor read safety").
        guard let srgb = nsColor.usingColorSpace(.sRGB) else {
            // Nil can happen if colorspace conversion fails — return black, mark out-of-gamut.
            return GamutResult(rgba: RGBA(red: 0, green: 0, blue: 0, alpha: oklcha.alpha), isOutOfGamut: true)
        }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        srgb.getRed(&r, green: &g, blue: &b, alpha: &a)

        // Own gamut check: if ChromaKit clamped, the raw components may differ.
        // We reconstruct the unclamped linear prediction to detect gamut.
        // Since NSColor.usingColorSpace(.sRGB) already clamps, we detect it by checking
        // if the P3→sRGB conversion produced channels outside [0,1] before NSColor clamped.
        // Approach: compare what NSColor reports vs what we'd expect from a purely unclamped path.
        // We do the unclamped sRGB math ourselves using the same OKLCH→Oklab→XYZ→sRGB chain.
        let (unclampedR, unclampedG, unclampedB) = oklchToLinearSRGB_unclamped(oklcha)
        let isOutOfGamut = unclampedR < -1e-6 || unclampedR > 1.0 + 1e-6 ||
                           unclampedG < -1e-6 || unclampedG > 1.0 + 1e-6 ||
                           unclampedB < -1e-6 || unclampedB > 1.0 + 1e-6

        return GamutResult(
            rgba: RGBA(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a)),
            isOutOfGamut: isOutOfGamut
        )
    }

    /// Returns unclamped sRGB channels from OKLCH via CSS Color Level 4 math.
    /// Used for gamut detection only — do NOT use for display (use oklchToRGB instead).
    /// Chain: OKLCH → Oklab → XYZ D65 → linear sRGB → gamma-corrected sRGB
    private static func oklchToLinearSRGB_unclamped(_ oklcha: OKLCHA) -> (Double, Double, Double) {
        let hRad = oklcha.h * .pi / 180.0
        // OKLCH → Oklab
        let labA = cos(hRad) * oklcha.c
        let labB = sin(hRad) * oklcha.c
        let labL = oklcha.l

        // Oklab → XYZ D65 (via LMS cube-root space)
        // Matrix: Oklab → LMS (linear)
        let lms = (
            labL + 0.39633779217376786 * labA + 0.21580375806075880 * labB,
            labL - 0.10556134232365635 * labA - 0.06385417477170590 * labB,
            labL - 0.08948418209496576 * labA - 1.29148553786409170 * labB
        )
        // Cube the LMS values back
        let lms3 = (lms.0 * lms.0 * lms.0, lms.1 * lms.1 * lms.1, lms.2 * lms.2 * lms.2)
        // LMS³ → XYZ D65
        let x = 1.22687987337415570 * lms3.0 - 0.55781499655548140 * lms3.1 + 0.28139105017721580 * lms3.2
        let y = -0.04057576262431372 * lms3.0 + 1.11228682939705940 * lms3.1 - 0.07171106666151700 * lms3.2
        let z = -0.07637294974672142 * lms3.0 - 0.42149332396279140 * lms3.1 + 1.58692402442724180 * lms3.2

        // XYZ D65 → linear sRGB (IEC 61966-2-1, standard matrix)
        let linR =  3.2404542 * x - 1.5371385 * y - 0.4985314 * z
        let linG = -0.9692660 * x + 1.8760108 * y + 0.0415560 * z
        let linB =  0.0556434 * x - 0.2040259 * y + 1.0572252 * z

        // Linear sRGB → gamma-corrected sRGB (IEC 61966-2-1 transfer function)
        func gammaCorrected(_ c: Double) -> Double {
            if abs(c) <= 0.0031308 { return 12.92 * c }
            let sign = c < 0 ? -1.0 : 1.0
            return sign * (1.055 * pow(abs(c), 1.0 / 2.4) - 0.055)
        }
        return (gammaCorrected(linR), gammaCorrected(linG), gammaCorrected(linB))
    }

    // MARK: - OKLCH (Reverse: sRGB → OKLCH, hand-computed)

    /// Convert sRGB RGBA to OKLCH using the CSS Color Level 4 inverse matrix chain.
    /// sRGB → linear sRGB → XYZ D65 → Oklab → OKLCH
    static func rgbToOKLCH(_ rgba: RGBA) -> OKLCHA {
        let r = rgba.red, g = rgba.green, b = rgba.blue

        // sRGB → linear sRGB (inverse gamma: IEC 61966-2-1)
        func linearize(_ c: Double) -> Double {
            if c <= 0.04045 { return c / 12.92 }
            return pow((c + 0.055) / 1.055, 2.4)
        }
        let linR = linearize(r), linG = linearize(g), linB = linearize(b)

        // Linear sRGB → XYZ D65 (inverse of the matrix above, CSS Color 4 values)
        let x = 0.4124564 * linR + 0.3575761 * linG + 0.1804375 * linB
        let y = 0.2126729 * linR + 0.7151522 * linG + 0.0721750 * linB
        let z = 0.0193339 * linR + 0.1191920 * linG + 0.9503041 * linB

        // XYZ D65 → LMS (Oklab's cube-root LMS space)
        // Matrix from CSS Color 4 spec (Björn Ottosson's Oklab)
        let lms0 = 0.8189330101 * x + 0.3618667424 * y - 0.1288597137 * z
        let lms1 = 0.0329845436 * x + 0.9293118715 * y + 0.0361456387 * z
        let lms2 = 0.0482003018 * x + 0.2643662691 * y + 0.6338517070 * z

        // Cube root
        func cbrt(_ v: Double) -> Double {
            if v < 0 { return -pow(-v, 1.0/3.0) }
            return pow(v, 1.0/3.0)
        }
        let l_ = cbrt(lms0), m_ = cbrt(lms1), s_ = cbrt(lms2)

        // LMS³⁻¹/³ → Oklab
        let labL = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_
        let labA = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_
        let labB = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_

        // Oklab → OKLCH
        let c = sqrt(labA * labA + labB * labB)
        var h = atan2(labB, labA) * 180.0 / .pi
        if h < 0 { h += 360.0 }

        return OKLCHA(l: labL, c: c, h: h, alpha: rgba.alpha)
    }

    // MARK: - WCAG Contrast Ratio

    /// Compute the WCAG 2.1 relative luminance of an sRGB RGBA value.
    /// Formula (W3C): linearize each channel, then L = 0.2126R + 0.7152G + 0.0722B.
    static func relativeLuminance(_ rgba: RGBA) -> Double {
        func linearize(_ c: Double) -> Double {
            // W3C WCAG uses 0.03928 threshold (some docs use 0.04045; 0.03928 is the WCAG spec value)
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let r = linearize(rgba.red)
        let g = linearize(rgba.green)
        let b = linearize(rgba.blue)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// Compute WCAG 2.1 contrast ratio between two sRGB RGBA colors.
    /// ratio = (Llighter + 0.05) / (Ldarker + 0.05). Range: 1:1 to 21:1.
    static func wcagContrastRatio(_ a: RGBA, _ b: RGBA) -> Double {
        let la = relativeLuminance(a)
        let lb = relativeLuminance(b)
        let light = max(la, lb)
        let dark = min(la, lb)
        return (light + 0.05) / (dark + 0.05)
    }

    /// Classify a WCAG contrast ratio against AA/AAA normal/large thresholds.
    /// AA normal ≥ 4.5, AA large ≥ 3.0, AAA normal ≥ 7.0, AAA large ≥ 4.5.
    static func wcagResults(ratio: Double) -> WCAGResults {
        WCAGResults(
            contrastRatio: ratio,
            aaNormal: ratio >= 4.5,
            aaLarge: ratio >= 3.0,
            aaaNormal: ratio >= 7.0,
            aaaLarge: ratio >= 4.5
        )
    }
}

