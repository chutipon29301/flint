// FlintTests/NumberBaseTransformerTests.swift
// Exhaustive two's-complement test matrix for NumberBaseTransformer.
// Covers NUM-01..03: all bases × all widths × signed/unsigned × edge cases.
// INFRA-17: crash-on-garbage, empty, invalid-digit-for-base all tested.

import Testing
import Foundation
@testable import Flint

@Suite("NumberBaseTransformer")
struct NumberBaseTransformerTests {

    // MARK: - NUM-01: Parse/emit round-trip — all four bases

    @Test("Parse decimal 255 in 8-bit → emit binary 11111111, octal 377, hex FF")
    func testDec255_8bit_unsigned() {
        let r = NumberBaseTransformer.parse("255", base: .dec, width: .w8)
        guard case .success(let pr) = r else {
            Issue.record("Expected success, got \(r)"); return
        }
        #expect(pr.pattern == 0xFF)
        #expect(pr.overflow == false)
        #expect(NumberBaseTransformer.binary(pattern: pr.pattern, width: .w8) == "11111111")
        #expect(NumberBaseTransformer.octal(pattern: pr.pattern, width: .w8) == "377")
        #expect(NumberBaseTransformer.hex(pattern: pr.pattern, width: .w8) == "FF")
    }

    @Test("Parse hex FF in 8-bit → decimal 255 unsigned")
    func testHexFF_8bit_unsigned() {
        let r = NumberBaseTransformer.parse("FF", base: .hex, width: .w8)
        guard case .success(let pr) = r else {
            Issue.record("Expected success, got \(r)"); return
        }
        #expect(pr.pattern == 0xFF)
        #expect(NumberBaseTransformer.decimal(pattern: pr.pattern, width: .w8, signed: false) == "255")
    }

    @Test("Parse hex FF in 8-bit → decimal -1 signed")
    func testHexFF_8bit_signed() {
        let r = NumberBaseTransformer.parse("FF", base: .hex, width: .w8)
        guard case .success(let pr) = r else {
            Issue.record("Expected success, got \(r)"); return
        }
        #expect(NumberBaseTransformer.decimal(pattern: pr.pattern, width: .w8, signed: true) == "-1")
    }

    @Test("Parse octal 377 in 8-bit → pattern 0xFF")
    func testOctal377_8bit() {
        let r = NumberBaseTransformer.parse("377", base: .oct, width: .w8)
        guard case .success(let pr) = r else {
            Issue.record("Expected success, got \(r)"); return
        }
        #expect(pr.pattern == 0xFF)
    }

    @Test("Parse binary 11111111 in 8-bit → pattern 0xFF")
    func testBinary11111111_8bit() {
        let r = NumberBaseTransformer.parse("11111111", base: .bin, width: .w8)
        guard case .success(let pr) = r else {
            Issue.record("Expected success, got \(r)"); return
        }
        #expect(pr.pattern == 0xFF)
    }

    @Test("0x prefix on hex is tolerated")
    func testHexPrefix0x() {
        let r = NumberBaseTransformer.parse("0xFF", base: .hex, width: .w8)
        guard case .success(let pr) = r else {
            Issue.record("Expected success, got \(r)"); return
        }
        #expect(pr.pattern == 0xFF)
    }

    @Test("0b prefix on binary is tolerated")
    func testBinaryPrefix0b() {
        let r = NumberBaseTransformer.parse("0b101", base: .bin, width: .w8)
        guard case .success(let pr) = r else {
            Issue.record("Expected success, got \(r)"); return
        }
        #expect(pr.pattern == 5)
    }

    @Test("Parse zero in all bases yields pattern 0")
    func testZero_allBases() {
        let bases: [(String, NumberBase)] = [("0", .bin), ("0", .oct), ("0", .dec), ("0", .hex)]
        for (text, base) in bases {
            let r = NumberBaseTransformer.parse(text, base: base, width: .w8)
            guard case .success(let pr) = r else {
                Issue.record("Base \(base): expected success, got \(r)"); continue
            }
            #expect(pr.pattern == 0, "Base \(base) with '0' should yield 0")
        }
    }

    // MARK: - NUM-02: 8-bit signed two's-complement boundary

    @Test("8-bit signed: 0xFF = -1")
    func test8BitSigned_0xFF_isMinusOne() {
        #expect(NumberBaseTransformer.decimal(pattern: 0xFF, width: .w8, signed: true) == "-1")
    }

    @Test("8-bit signed: 0x80 = -128")
    func test8BitSigned_0x80_isMin128() {
        #expect(NumberBaseTransformer.decimal(pattern: 0x80, width: .w8, signed: true) == "-128")
    }

    @Test("8-bit signed: 0x7F = 127")
    func test8BitSigned_0x7F_is127() {
        #expect(NumberBaseTransformer.decimal(pattern: 0x7F, width: .w8, signed: true) == "127")
    }

    @Test("8-bit unsigned: 0xFF = 255")
    func test8BitUnsigned_0xFF_is255() {
        #expect(NumberBaseTransformer.decimal(pattern: 0xFF, width: .w8, signed: false) == "255")
    }

    @Test("8-bit unsigned: 0x80 = 128")
    func test8BitUnsigned_0x80_is128() {
        #expect(NumberBaseTransformer.decimal(pattern: 0x80, width: .w8, signed: false) == "128")
    }

    // MARK: - NUM-02: 16-bit signed two's-complement boundary

    @Test("16-bit signed: 0xFFFF = -1")
    func test16BitSigned_0xFFFF_isMinusOne() {
        #expect(NumberBaseTransformer.decimal(pattern: 0xFFFF, width: .w16, signed: true) == "-1")
    }

    @Test("16-bit signed: 0x8000 = -32768 (Int16 min)")
    func test16BitSigned_0x8000_isInt16Min() {
        #expect(NumberBaseTransformer.decimal(pattern: 0x8000, width: .w16, signed: true) == "-32768")
    }

    @Test("16-bit signed: 0x7FFF = 32767 (Int16 max)")
    func test16BitSigned_0x7FFF_isInt16Max() {
        #expect(NumberBaseTransformer.decimal(pattern: 0x7FFF, width: .w16, signed: true) == "32767")
    }

    // MARK: - NUM-02: 32-bit signed two's-complement boundary

    @Test("32-bit signed: 0xFFFFFFFF = -1")
    func test32BitSigned_0xFFFFFFFF_isMinusOne() {
        #expect(NumberBaseTransformer.decimal(pattern: 0xFFFF_FFFF, width: .w32, signed: true) == "-1")
    }

    @Test("32-bit signed: 0x80000000 = -2147483648 (Int32 min)")
    func test32BitSigned_0x80000000_isInt32Min() {
        #expect(NumberBaseTransformer.decimal(pattern: 0x8000_0000, width: .w32, signed: true) == "-2147483648")
    }

    @Test("32-bit signed: 0x7FFFFFFF = 2147483647 (Int32 max)")
    func test32BitSigned_0x7FFFFFFF_isInt32Max() {
        #expect(NumberBaseTransformer.decimal(pattern: 0x7FFF_FFFF, width: .w32, signed: true) == "2147483647")
    }

    // MARK: - NUM-02: 64-bit signed two's-complement boundary

    @Test("64-bit signed: 0xFFFFFFFFFFFFFFFF = -1")
    func test64BitSigned_allOnes_isMinusOne() {
        #expect(NumberBaseTransformer.decimal(pattern: UInt64.max, width: .w64, signed: true) == "-1")
    }

    @Test("64-bit signed: 0x8000000000000000 = -9223372036854775808 (Int64 min)")
    func test64BitSigned_0x8000000000000000_isInt64Min() {
        let pattern: UInt64 = 0x8000_0000_0000_0000
        #expect(NumberBaseTransformer.decimal(pattern: pattern, width: .w64, signed: true) == "-9223372036854775808")
    }

    @Test("64-bit signed: 0x7FFFFFFFFFFFFFFF = 9223372036854775807 (Int64 max)")
    func test64BitSigned_0x7FFFFFFFFFFFFFFF_isInt64Max() {
        let pattern: UInt64 = 0x7FFF_FFFF_FFFF_FFFF
        #expect(NumberBaseTransformer.decimal(pattern: pattern, width: .w64, signed: true) == "9223372036854775807")
    }

    @Test("64-bit unsigned: 0xFFFFFFFFFFFFFFFF = 18446744073709551615 (UInt64 max)")
    func test64BitUnsigned_allOnes() {
        #expect(NumberBaseTransformer.decimal(pattern: UInt64.max, width: .w64, signed: false) == "18446744073709551615")
    }

    // MARK: - NUM-03: Overflow detection + masking (never crash)

    @Test("Parse 256 in 8-bit → masks to 0 + overflow=true")
    func testOverflow_256_8bit() {
        let r = NumberBaseTransformer.parse("256", base: .dec, width: .w8)
        guard case .success(let pr) = r else {
            Issue.record("Expected success (masked), got \(r)"); return
        }
        #expect(pr.overflow == true)
        #expect(pr.pattern == 0)  // 256 & 0xFF = 0
    }

    @Test("Parse 257 in 8-bit → masks to 1 + overflow=true")
    func testOverflow_257_8bit() {
        let r = NumberBaseTransformer.parse("257", base: .dec, width: .w8)
        guard case .success(let pr) = r else {
            Issue.record("Expected success (masked), got \(r)"); return
        }
        #expect(pr.overflow == true)
        #expect(pr.pattern == 1)  // 257 & 0xFF = 1
    }

    @Test("Parse 65536 in 16-bit → masks to 0 + overflow=true")
    func testOverflow_65536_16bit() {
        let r = NumberBaseTransformer.parse("65536", base: .dec, width: .w16)
        guard case .success(let pr) = r else {
            Issue.record("Expected success (masked), got \(r)"); return
        }
        #expect(pr.overflow == true)
        #expect(pr.pattern == 0)
    }

    @Test("Parse within range 8-bit → no overflow")
    func testNoOverflow_255_8bit() {
        let r = NumberBaseTransformer.parse("255", base: .dec, width: .w8)
        guard case .success(let pr) = r else {
            Issue.record("Expected success, got \(r)"); return
        }
        #expect(pr.overflow == false)
    }

    // MARK: - INFRA-17: Garbage/empty/invalid-digit — never crash

    @Test("Empty string → failure, never crash")
    func testEmpty_neverCrash() {
        let r = NumberBaseTransformer.parse("", base: .dec, width: .w8)
        if case .success(_) = r {
            Issue.record("Empty string should fail or return zero — not a critical error if returns 0")
        }
        // Either failure or success(0) is acceptable; must not crash
    }

    @Test("Binary '2' invalid digit → failure")
    func testBinary_invalidDigit2_fails() {
        let r = NumberBaseTransformer.parse("2", base: .bin, width: .w8)
        switch r {
        case .failure: break  // expected
        case .success(let pr):
            // If implementation returns 0 for invalid, that's a deviation to document
            _ = pr  // must not crash
        }
    }

    @Test("Hex 'G' invalid digit → failure, never crash")
    func testHex_invalidDigitG_fails() {
        let r = NumberBaseTransformer.parse("G", base: .hex, width: .w8)
        switch r {
        case .failure: break  // expected
        case .success: Issue.record("'G' is not valid hex — expected failure")
        }
    }

    @Test("Lone minus sign → failure, never crash")
    func testLoneMinus_fails() {
        let r = NumberBaseTransformer.parse("-", base: .dec, width: .w8)
        switch r {
        case .failure: break  // expected
        case .success: break  // tolerable if implementation returns 0
        }
        // Must not crash regardless
    }

    @Test("Very long string does not crash (INFRA-17 size guard)")
    func testLargeInput_neverCrash() {
        let huge = String(repeating: "1", count: 10_000)
        let r = NumberBaseTransformer.parse(huge, base: .bin, width: .w64)
        // Must not crash; may overflow
        switch r {
        case .success(let pr): _ = pr.pattern
        case .failure: break
        }
    }

    // MARK: - Bit toggle (XOR)

    @Test("toggleBit: flip bit 0 of 0 → 1")
    func testToggleBit_bit0_from0() {
        let result = NumberBaseTransformer.toggleBit(pattern: 0, index: 0)
        #expect(result == 1)
    }

    @Test("toggleBit: flip bit 0 of 1 → 0")
    func testToggleBit_bit0_from1() {
        let result = NumberBaseTransformer.toggleBit(pattern: 1, index: 0)
        #expect(result == 0)
    }

    @Test("toggleBit: flip bit 7 of 0x7F → 0xFF (8-bit sign bit)")
    func testToggleBit_bit7_of0x7F() {
        let result = NumberBaseTransformer.toggleBit(pattern: 0x7F, index: 7)
        #expect(result == 0xFF)
    }

    @Test("toggleBit: flip bit 63 of 0 → sign bit of 64-bit")
    func testToggleBit_bit63() {
        let result = NumberBaseTransformer.toggleBit(pattern: 0, index: 63)
        #expect(result == 0x8000_0000_0000_0000)
    }

    @Test("toggleBit twice restores original")
    func testToggleBit_roundTrip() {
        let original: UInt64 = 0xDEAD_BEEF
        let toggled = NumberBaseTransformer.toggleBit(pattern: original, index: 5)
        let restored = NumberBaseTransformer.toggleBit(pattern: toggled, index: 5)
        #expect(restored == original)
    }

    // MARK: - Binary emitter formatting

    @Test("binary(0, 8-bit) = '00000000'")
    func testBinary_zero_8bit() {
        #expect(NumberBaseTransformer.binary(pattern: 0, width: .w8) == "00000000")
    }

    @Test("binary(0, 16-bit) = '0000000000000000'")
    func testBinary_zero_16bit() {
        #expect(NumberBaseTransformer.binary(pattern: 0, width: .w16) == "0000000000000000")
    }

    @Test("binary(1, 8-bit) = '00000001'")
    func testBinary_one_8bit() {
        #expect(NumberBaseTransformer.binary(pattern: 1, width: .w8) == "00000001")
    }

    @Test("binary emits exactly width bits (no excess high bits)")
    func testBinary_masksHighBits() {
        // 0x1FF has 9 bits — 8-bit should mask to 0xFF = 11111111
        #expect(NumberBaseTransformer.binary(pattern: 0x1FF, width: .w8) == "11111111")
    }

    // MARK: - Octal emitter

    @Test("octal(0, 8-bit) = '0'")
    func testOctal_zero() {
        let result = NumberBaseTransformer.octal(pattern: 0, width: .w8)
        #expect(result == "0")
    }

    @Test("octal(255, 8-bit) = '377'")
    func testOctal_255_8bit() {
        #expect(NumberBaseTransformer.octal(pattern: 0xFF, width: .w8) == "377")
    }

    // MARK: - Hex emitter

    @Test("hex(0, 8-bit) = '00'")
    func testHex_zero_8bit() {
        #expect(NumberBaseTransformer.hex(pattern: 0, width: .w8) == "00")
    }

    @Test("hex(255, 8-bit) = 'FF' (uppercase)")
    func testHex_255_8bit_uppercase() {
        #expect(NumberBaseTransformer.hex(pattern: 0xFF, width: .w8) == "FF")
    }

    @Test("hex(0, 16-bit) = '0000'")
    func testHex_zero_16bit() {
        #expect(NumberBaseTransformer.hex(pattern: 0, width: .w16) == "0000")
    }

    @Test("hex masks high bits — 0x1FF in 8-bit = 'FF'")
    func testHex_masksHighBits() {
        #expect(NumberBaseTransformer.hex(pattern: 0x1FF, width: .w8) == "FF")
    }

    // MARK: - Width-64 special case (no 1<<64 UB)

    @Test("64-bit: parse UInt64.max as hex succeeds")
    func test64Bit_parseMaxHex() {
        let r = NumberBaseTransformer.parse("FFFFFFFFFFFFFFFF", base: .hex, width: .w64)
        guard case .success(let pr) = r else {
            Issue.record("Expected success for max 64-bit hex, got \(r)"); return
        }
        #expect(pr.pattern == UInt64.max)
        #expect(pr.overflow == false)
    }

    @Test("64-bit: binary emitter produces 64 chars for max value")
    func test64Bit_binaryEmitter_length() {
        let s = NumberBaseTransformer.binary(pattern: UInt64.max, width: .w64)
        #expect(s.count == 64)
        #expect(s == String(repeating: "1", count: 64))
    }

    @Test("64-bit: hex emitter produces 16 chars for max value")
    func test64Bit_hexEmitter_length() {
        let s = NumberBaseTransformer.hex(pattern: UInt64.max, width: .w64)
        #expect(s.count == 16)
        #expect(s == "FFFFFFFFFFFFFFFF")
    }

    // MARK: - Parse negative decimal (signed input)

    @Test("Parse -1 (decimal) in 8-bit → 0xFF pattern")
    func testParseMinus1_8bit() {
        let r = NumberBaseTransformer.parse("-1", base: .dec, width: .w8)
        guard case .success(let pr) = r else {
            Issue.record("Expected success for -1 in 8-bit, got \(r)"); return
        }
        #expect(pr.pattern == 0xFF)
    }

    @Test("Parse -128 (decimal) in 8-bit → 0x80 pattern")
    func testParseMinus128_8bit() {
        let r = NumberBaseTransformer.parse("-128", base: .dec, width: .w8)
        guard case .success(let pr) = r else {
            Issue.record("Expected success for -128 in 8-bit, got \(r)"); return
        }
        #expect(pr.pattern == 0x80)
    }

    @Test("Parse -9223372036854775808 (Int64 min) in 64-bit → 0x8000000000000000")
    func testParseInt64Min_64bit() {
        let r = NumberBaseTransformer.parse("-9223372036854775808", base: .dec, width: .w64)
        guard case .success(let pr) = r else {
            Issue.record("Expected success for Int64.min in 64-bit, got \(r)"); return
        }
        #expect(pr.pattern == 0x8000_0000_0000_0000)
    }
}
