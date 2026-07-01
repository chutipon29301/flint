// Tools/NumberBase/NumberBaseViewModel.swift
// Single canonical UInt64 pattern source-of-truth ViewModel for the Number Base Converter.
// Conforms to ToolShortcutActions — ⌘⇧C copies DEC, ⌘⌫ resets to 0.
// Synchronous pure transforms — no debounce needed (CF-01: cheap integer operations).
// Source: PATTERNS.md "Color/NumberBase note" + PATTERNS.md ViewModel analog

import Foundation
import Observation

@Observable
@MainActor
final class NumberBaseViewModel: ToolShortcutActions {

    // MARK: - Canonical Source-of-Truth

    /// The ONE canonical bit pattern for the current value.
    /// All four base fields and the bit-field grid derive from this — never N drifting strings.
    var pattern: UInt64 = 0 {
        didSet { deriveAllFields() }
    }

    // MARK: - Width and Signed Mode

    var width: BitWidth = .w8 {
        didSet { deriveAllFields() }
    }

    var signed: Bool = false {
        didSet { deriveAllFields() }
    }

    // MARK: - Derived Display Strings (computed from canonical pattern)

    private(set) var binText: String = "00000000"
    private(set) var octText: String = "0"
    private(set) var decText: String = "0"
    private(set) var hexText: String = "00"

    // MARK: - Error and Warning State

    /// True when the last parsed input exceeded the active width (NUM-03, T-02-NUM-OF).
    var overflowWarning: Bool = false

    /// Inline error message when input has invalid digits for a base.
    var errorMessage: String? = nil

    /// True while input is invalid — dims the field (CF-02).
    var outputDimmed: Bool = false

    // MARK: - Init

    init() {
        deriveAllFields()
    }

    // MARK: - ToolShortcutActions (INFRA-16)

    /// ⌘⇧C copies the DEC value (primary output for a number tool).
    func primaryOutput() -> String? {
        decText.isEmpty ? nil : decText
    }

    /// ⌘⌫ resets to 0.
    func clearInput() {
        overflowWarning = false
        errorMessage = nil
        outputDimmed = false
        pattern = 0
    }

    // MARK: - D-08 Row Copy (⌘1–⌘9)

    /// Returns the copyable string for the given row index.
    /// Row map (UI-SPEC D-08): 1=BIN, 2=OCT, 3=DEC, 4=HEX (with "0x" prefix).
    /// Returns nil for out-of-range index — silent no-op (CF-01, T-04-06).
    func outputForRow(_ index: Int) -> String? {
        switch index {
        case 1: return binText.isEmpty ? nil : binText
        case 2: return octText.isEmpty ? nil : octText
        case 3: return decText.isEmpty ? nil : decText
        case 4: return hexText.isEmpty ? nil : "0x" + hexText
        default: return nil // out-of-range: silent no-op (CF-01, T-04-06)
        }
    }

    // MARK: - Update from base field edit

    /// Called when the user edits any of the four text fields.
    /// Synchronously re-parses and updates the canonical pattern (CF-01 — cheap, no debounce).
    func update(from base: NumberBase, text: String) {
        lastEditedBase = base
        lastEditedText = text

        guard !text.isEmpty else {
            // Empty field: silently reset without error (allow clearing)
            overflowWarning = false
            errorMessage = nil
            outputDimmed = false
            pattern = 0
            return
        }

        switch NumberBaseTransformer.parse(text, base: base, width: width) {
        case .success(let pr):
            overflowWarning = pr.overflow
            errorMessage = nil
            outputDimmed = false
            pattern = pr.pattern

        case .failure(let error):
            // CF-02: keep last good values visible but dimmed; show inline error
            outputDimmed = true
            switch error {
            case .emptyInput:
                errorMessage = "Empty input"
            case .invalidDigit(let ch):
                let baseName: String
                switch base {
                case .bin: baseName = "binary"
                case .oct: baseName = "octal"
                case .dec: baseName = "decimal"
                case .hex: baseName = "hexadecimal"
                }
                errorMessage = "Invalid digit '\(ch)' for \(baseName)"
            }
        }
    }

    // MARK: - Toggle a bit

    /// XOR bit at `index` in the canonical pattern, then re-derive all fields.
    func toggleBit(_ index: Int) {
        pattern = NumberBaseTransformer.toggleBit(pattern: pattern, index: index)
        // Overflow cannot arise from bit toggle — reset warning if no active error
        if !outputDimmed {
            overflowWarning = false
        }
    }

    // MARK: - Width change re-derive

    /// When width changes, mask the current pattern to the new width and re-derive.
    func applyWidthChange(_ newWidth: BitWidth) {
        width = newWidth
        // Masking: if current pattern fits within new width, no overflow
        let masked = pattern & newWidth.mask
        let hadOverflow = masked != pattern
        if hadOverflow {
            overflowWarning = true
        }
        pattern = masked
    }

    // MARK: - Private: derive all four fields from canonical pattern

    private func deriveAllFields() {
        binText = NumberBaseTransformer.binary(pattern: pattern, width: width)
        octText = NumberBaseTransformer.octal(pattern: pattern, width: width)
        decText = NumberBaseTransformer.decimal(pattern: pattern, width: width, signed: signed)
        hexText = NumberBaseTransformer.hex(pattern: pattern, width: width)
    }
}
