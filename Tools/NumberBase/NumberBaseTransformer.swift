// Tools/NumberBase/NumberBaseTransformer.swift
// Pure number-base transformer — NO SwiftUI/AppKit imports (testable without UI).
// Canonical representation: UInt64 bit pattern + BitWidth + signed flag.
// INFRA-17: All parse paths return Result; overflow → mask+flag; never force-unwrap; never crash.
// NUM-01..03: four-base conversion, two's-complement, bit-toggle, overflow handling.
// T-02-NUM-IV, T-02-NUM-OF: threat mitigations implemented here.

import Foundation

// MARK: - NumberBase enum

/// The four bases supported by the Number Base Converter.
enum NumberBase: CaseIterable {
    case bin  // base 2
    case oct  // base 8
    case dec  // base 10
    case hex  // base 16

    var radix: Int {
        switch self {
        case .bin: return 2
        case .oct: return 8
        case .dec: return 10
        case .hex: return 16
        }
    }
}

// MARK: - BitWidth enum

/// Supported bit widths for the canonical UInt64 pattern.
enum BitWidth: Int, CaseIterable {
    case w8  = 8
    case w16 = 16
    case w32 = 32
    case w64 = 64

    /// Mask for this width. Special-cases w64 to avoid 1<<64 undefined behavior.
    var mask: UInt64 {
        switch self {
        case .w8:  return 0x0000_0000_0000_00FF
        case .w16: return 0x0000_0000_0000_FFFF
        case .w32: return 0x0000_0000_FFFF_FFFF
        case .w64: return UInt64.max  // no shift needed — avoids 1<<64 UB
        }
    }
}

// MARK: - ParseResult

/// Returned by `parse(_:base:width:)` on success.
struct NumberBaseParseResult {
    /// Canonical bit pattern, already masked to the active width.
    let pattern: UInt64
    /// True when the parsed magnitude exceeded the active width and was truncated.
    let overflow: Bool
}

// MARK: - TransformError

enum NumberBaseTransformError: Error, Equatable {
    case emptyInput
    case invalidDigit(String)
}

// MARK: - NumberBaseTransformer

/// Pure number-base conversion engine.
/// Canonical representation: a `UInt64` bit pattern masked to the active `BitWidth`.
/// All math is integer; no floating-point. No imports beyond Foundation.
enum NumberBaseTransformer {

    // MARK: - Parse

    /// Parse a text string in `base`, mask result to `width`.
    /// Returns success with overflow=true when magnitude exceeds width.
    /// INFRA-17: Returns Result — never throws, never force-unwraps, never crashes.
    static func parse(
        _ text: String,
        base: NumberBase,
        width: BitWidth
    ) -> Result<NumberBaseParseResult, NumberBaseTransformError> {
        // Strip leading/trailing whitespace
        let trimmed = text.trimmingCharacters(in: .whitespaces)

        guard !trimmed.isEmpty else {
            return .failure(.emptyInput)
        }

        // For decimal base, support negative values (two's-complement wrap)
        if base == .dec {
            return parseDecimal(trimmed, width: width)
        }

        // Strip allowed prefixes for binary (0b/0B) and hex (0x/0X)
        let stripped: String
        switch base {
        case .bin:
            if trimmed.hasPrefix("0b") || trimmed.hasPrefix("0B") {
                stripped = String(trimmed.dropFirst(2))
            } else {
                stripped = trimmed
            }
        case .hex:
            if trimmed.hasPrefix("0x") || trimmed.hasPrefix("0X") {
                stripped = String(trimmed.dropFirst(2))
            } else {
                stripped = trimmed
            }
        default:
            stripped = trimmed
        }

        guard !stripped.isEmpty else {
            return .failure(.emptyInput)
        }

        // Validate: all chars must be valid for the radix
        let validChars = validCharacterSet(for: base)
        let upperStripped = stripped.uppercased()
        for ch in upperStripped {
            guard validChars.contains(ch) else {
                return .failure(.invalidDigit(String(ch)))
            }
        }

        // Parse via UInt64 (handles up to 64-bit unsigned cleanly)
        // For very long strings, UInt64 init returns nil — treat as overflow
        guard let raw = UInt64(upperStripped, radix: base.radix) else {
            // Value too large even for UInt64 — mask to width's max (all 1s)
            return .success(NumberBaseParseResult(pattern: width.mask, overflow: true))
        }

        let masked = raw & width.mask
        let overflow = raw != masked
        return .success(NumberBaseParseResult(pattern: masked, overflow: overflow))
    }

    // MARK: - Emit

    /// Emit the binary string for `pattern`, zero-padded to `width` bits.
    /// High bits above `width` are masked out.
    static func binary(pattern: UInt64, width: BitWidth) -> String {
        let masked = pattern & width.mask
        let s = String(masked, radix: 2)
        // Zero-pad to exactly `width` bits
        return String(repeating: "0", count: max(0, width.rawValue - s.count)) + s
    }

    /// Emit the octal string for `pattern` (no padding).
    static func octal(pattern: UInt64, width: BitWidth) -> String {
        let masked = pattern & width.mask
        return String(masked, radix: 8).uppercased()
    }

    /// Emit the decimal string for `pattern`.
    /// For signed mode, interprets the top bit of `width` as the sign bit (two's-complement).
    static func decimal(pattern: UInt64, width: BitWidth, signed: Bool) -> String {
        let masked = pattern & width.mask
        if signed {
            return signedDecimal(pattern: masked, width: width)
        }
        return String(masked)
    }

    /// Emit the hex string for `pattern`, uppercase, zero-padded to width/4 hex digits.
    static func hex(pattern: UInt64, width: BitWidth) -> String {
        let masked = pattern & width.mask
        let s = String(masked, radix: 16, uppercase: true)
        let digits = width.rawValue / 4
        return String(repeating: "0", count: max(0, digits - s.count)) + s
    }

    // MARK: - Bit Toggle

    /// XOR bit at `index` (0 = LSB) and return the new pattern.
    /// Works on the full 64-bit pattern — caller is responsible for masking to width if needed.
    static func toggleBit(pattern: UInt64, index: Int) -> UInt64 {
        guard index >= 0, index < 64 else { return pattern }
        return pattern ^ (1 << index)
    }

    // MARK: - Private Helpers

    private static func parseDecimal(
        _ text: String,
        width: BitWidth
    ) -> Result<NumberBaseParseResult, NumberBaseTransformError> {
        // Determine sign
        let isNegative = text.hasPrefix("-")
        let magnitude: String
        if isNegative {
            magnitude = String(text.dropFirst())
        } else if text.hasPrefix("+") {
            magnitude = String(text.dropFirst())
        } else {
            magnitude = text
        }

        guard !magnitude.isEmpty else {
            return .failure(.emptyInput)
        }

        // Validate digits
        for ch in magnitude {
            guard ch.isNumber else {
                return .failure(.invalidDigit(String(ch)))
            }
        }

        if isNegative {
            // Negative decimal — need to two's-complement encode
            // Parse magnitude as UInt64, then two's-complement negate within width
            if let mag = UInt64(magnitude) {
                // In two's complement: -mag mod 2^width = (2^width - mag) mod 2^width
                // Special case width 64: UInt64 wraps automatically
                let pattern: UInt64
                let overflow: Bool
                if width == .w64 {
                    // For 64-bit: -mag as two's complement
                    // Valid range: -1...-9223372036854775808 (Int64.min)
                    // Int64.min magnitude = 9223372036854775808 = UInt64(Int64.max) + 1 = 0x8000000000000000
                    // Values magnitude > 9223372036854775808 would overflow 64-bit signed
                    if mag > 0x8000_0000_0000_0000 {
                        // Overflow: mask to width
                        let p = (0 &- mag) & width.mask
                        return .success(NumberBaseParseResult(pattern: p, overflow: true))
                    }
                    // 0 &- mag does the two's complement correctly at UInt64 level
                    pattern = (0 &- mag) & width.mask
                    overflow = false
                } else {
                    let widthValue = UInt64(width.rawValue)
                    let maxMag: UInt64 = (1 << (widthValue - 1))  // 2^(w-1)
                    if mag > maxMag {
                        // Magnitude exceeds what fits in two's complement for this width
                        let p = (0 &- mag) & width.mask
                        return .success(NumberBaseParseResult(pattern: p, overflow: true))
                    }
                    pattern = (0 &- mag) & width.mask
                    overflow = false
                }
                return .success(NumberBaseParseResult(pattern: pattern, overflow: overflow))
            } else {
                // Magnitude too large even for UInt64 — overflow
                return .success(NumberBaseParseResult(pattern: width.mask, overflow: true))
            }
        } else {
            // Non-negative decimal
            if let raw = UInt64(magnitude) {
                let masked = raw & width.mask
                let overflow = raw != masked
                return .success(NumberBaseParseResult(pattern: masked, overflow: overflow))
            } else {
                // Value too large for UInt64 — overflow
                return .success(NumberBaseParseResult(pattern: width.mask, overflow: true))
            }
        }
    }

    /// Two's-complement signed decimal rendering for the given width.
    private static func signedDecimal(pattern: UInt64, width: BitWidth) -> String {
        // Top-bit of active width is the sign bit
        let signBit: UInt64 = {
            switch width {
            case .w8:  return 0x80
            case .w16: return 0x8000
            case .w32: return 0x8000_0000
            case .w64: return 0x8000_0000_0000_0000
            }
        }()

        guard pattern & signBit != 0 else {
            // Positive: render as unsigned
            return String(pattern)
        }

        // Negative: compute magnitude as 2^width - pattern
        switch width {
        case .w8:
            let value = Int8(bitPattern: UInt8(pattern & 0xFF))
            return String(value)
        case .w16:
            let value = Int16(bitPattern: UInt16(pattern & 0xFFFF))
            return String(value)
        case .w32:
            let value = Int32(bitPattern: UInt32(pattern & 0xFFFF_FFFF))
            return String(value)
        case .w64:
            let value = Int64(bitPattern: pattern)
            return String(value)
        }
    }

    private static func validCharacterSet(for base: NumberBase) -> Set<Character> {
        switch base {
        case .bin: return Set("01")
        case .oct: return Set("01234567")
        case .dec: return Set("0123456789")
        case .hex: return Set("0123456789ABCDEF")
        }
    }
}
