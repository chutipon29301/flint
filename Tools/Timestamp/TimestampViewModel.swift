// Tools/Timestamp/TimestampViewModel.swift
// @Observable ViewModel for the Timestamp Converter tool.
// Follows Pattern 5 (150ms debounce, last-good-output-dimmed error).
// NEVER imports GRDB — history injection via closure.

import SwiftUI
import Foundation

@Observable
@MainActor
final class TimestampViewModel: ToolShortcutActions {

    // MARK: - Input

    /// The raw timestamp string the user has typed.
    var input: String = "" {
        didSet { scheduleTransform() }
    }

    /// Explicit unit override for ambiguous inputs (TS-01, pitfall #8).
    var selectedUnit: TimestampTransformer.TimestampUnit = .seconds {
        didSet { if detectedUnit == .ambiguous { runTransform() } }
    }

    // MARK: - Output

    /// The detected unit — .ambiguous means "show toggle" to user.
    var detectedUnit: TimestampTransformer.TimestampUnit = .seconds

    /// Converted date (nil on parse failure).
    var convertedDate: Date? = nil

    /// Formatted strings per timezone: [(label, formatted)]
    var timezoneRows: [(label: String, formatted: String)] = []

    /// ISO 8601 output (TS-05).
    var iso8601: String = ""

    /// Relative time display (TS-04).
    var relativeTimeString: String = ""

    /// Whether the last transform failed (dims output per D-11).
    var outputDimmed: Bool = false

    /// Inline error message.
    var errorMessage: String? = nil

    // MARK: - Reverse Convert (TS-03)

    /// Date selected by the user for reverse-convert (TS-03).
    var pickedDate: Date = Date()

    var reverseTimestampSeconds: String {
        String(TimestampTransformer.toUnixTimestamp(pickedDate, unit: .seconds))
    }

    var reverseTimestampMilliseconds: String {
        String(TimestampTransformer.toUnixTimestamp(pickedDate, unit: .milliseconds))
    }

    // MARK: - Additional timezones

    /// Timezone identifiers to display (local + UTC + additional).
    var displayTimezones: [TimeZone] = [
        .current,
        TimeZone(identifier: "UTC")!,
        TimeZone(identifier: "America/New_York")!,
    ]

    // MARK: - Private

    private let onSaveHistory: (HistoryEntry) -> Void
    private let debounce = Debounce()

    init(onSaveHistory: @escaping (HistoryEntry) -> Void) {
        self.onSaveHistory = onSaveHistory
    }

    // MARK: - ToolShortcutActions (INFRA-16)

    /// Returns the composite timezone+ISO output, or nil when no conversion is available.
    /// Returns nil when errorMessage is set or convertedDate is nil (nothing to copy).
    func primaryOutput() -> String? {
        guard convertedDate != nil, errorMessage == nil else { return nil }
        let text = buildOutputString()
        return text.isEmpty ? nil : text
    }

    /// Clears the input field (triggers scheduleTransform via didSet).
    func clearInput() {
        input = ""
    }

    // MARK: - Output string builder (shared by primaryOutput + runTransform)

    /// Builds the composite output string: timezone rows + ISO 8601.
    /// This is the same string saved to history — factored out to avoid duplication.
    private func buildOutputString() -> String {
        timezoneRows.map { "\($0.label): \($0.formatted)" }.joined(separator: "\n")
            + (iso8601.isEmpty ? "" : "\nISO 8601: \(iso8601)")
    }

    // MARK: - Now (TS-04)

    func insertNow() {
        let now = Int64(Date().timeIntervalSince1970)
        input = String(now)
    }

    // MARK: - Transform

    private func scheduleTransform() {
        Task {
            await debounce.schedule(delay: .milliseconds(150)) { [weak self] in
                await self?.runTransform()
            }
        }
    }

    func runTransform() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            convertedDate = nil
            timezoneRows = []
            iso8601 = ""
            relativeTimeString = ""
            errorMessage = nil
            outputDimmed = false
            return
        }

        // Validate: must be numeric (allow leading minus for negative timestamps)
        let numericString = trimmed.hasPrefix("-") ? String(trimmed.dropFirst()) : trimmed
        guard !numericString.isEmpty, numericString.allSatisfy(\.isNumber) else {
            errorMessage = "Enter a numeric Unix timestamp"
            outputDimmed = true
            return
        }

        guard let value = Int64(trimmed) else {
            errorMessage = "Timestamp out of range"
            outputDimmed = true
            return
        }

        detectedUnit = TimestampTransformer.detectUnit(value)

        // Choose effective unit
        let effectiveUnit: TimestampTransformer.TimestampUnit
        if detectedUnit == .ambiguous {
            effectiveUnit = selectedUnit
        } else {
            effectiveUnit = detectedUnit
        }

        let date = TimestampTransformer.toDate(value, unit: effectiveUnit)

        // Sanity check: reject wildly out-of-range dates (INFRA-17)
        let minDate = Date(timeIntervalSince1970: -62_135_596_800) // year 0001
        let maxDate = Date(timeIntervalSince1970: 32_503_680_000)  // year 3000
        guard date >= minDate && date <= maxDate else {
            errorMessage = "Timestamp out of representable date range"
            outputDimmed = true
            return
        }

        // Success path
        convertedDate = date
        outputDimmed = false
        errorMessage = nil

        let tzRows = TimestampTransformer.formatInTimezones(date, zones: displayTimezones)
        timezoneRows = tzRows.map { (tz, formatted) in
            let label = tz == .current ? "Local (\(tz.abbreviation() ?? tz.identifier))" : tz.identifier
            return (label: label, formatted: formatted)
        }

        iso8601 = TimestampTransformer.toISO8601(date)
        relativeTimeString = TimestampTransformer.relativeTime(from: date)

        // Write history — input + multi-timezone output (no secrets involved here)
        let outputLines = buildOutputString()
        onSaveHistory(HistoryEntry(
            tool: "timestamp",
            input: input,
            output: outputLines,
            timestamp: Date(),
            pinned: false
        ))
    }
}
