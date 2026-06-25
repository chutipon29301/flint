// Tools/Timestamp/TimestampTransformer.swift
// Pure timestamp conversion logic — NO SwiftUI/AppKit imports.
// Covers TS-01..05, INFRA-17, pitfall #8 (11/12-digit ambiguity).

import Foundation

enum TimestampTransformer {

    // MARK: - Types

    enum TimestampUnit: Equatable {
        case seconds
        case milliseconds
        case ambiguous  // 11 or 12 digits — never auto-convert without showing selector (pitfall #8)
    }

    // MARK: - TS-01: Auto-detect unit

    /// Detects whether an integer value represents seconds, milliseconds, or is ambiguous.
    /// - 10 digits → seconds (e.g. 1700000000 → 2023)
    /// - 13 digits → milliseconds (e.g. 1700000000000)
    /// - 11 or 12 digits → .ambiguous: show unit selector to user (pitfall #8)
    /// - Other digit counts → .ambiguous (treat gracefully — INFRA-17)
    static func detectUnit(_ value: Int64) -> TimestampUnit {
        let digitCount = String(abs(value)).count
        switch digitCount {
        case 10: return .seconds
        case 13: return .milliseconds
        default: return .ambiguous  // 11, 12, or any other digit count
        }
    }

    // MARK: - TS-02: Convert to Date

    /// Converts a Unix timestamp integer to a Date given its unit.
    /// For `.ambiguous`, defaults to seconds interpretation — caller must show selector.
    static func toDate(_ value: Int64, unit: TimestampUnit) -> Date {
        switch unit {
        case .seconds:
            return Date(timeIntervalSince1970: Double(value))
        case .milliseconds:
            return Date(timeIntervalSince1970: Double(value) / 1000.0)
        case .ambiguous:
            // Default to seconds for display; caller must show toggle (pitfall #8)
            return Date(timeIntervalSince1970: Double(value))
        }
    }

    // MARK: - TS-03: Reverse-convert Date → timestamp

    /// Converts a Date back to a Unix timestamp integer in the specified unit.
    static func toUnixTimestamp(_ date: Date, unit: TimestampUnit) -> Int64 {
        let seconds = date.timeIntervalSince1970
        switch unit {
        case .seconds, .ambiguous:
            return Int64(seconds)
        case .milliseconds:
            return Int64(seconds * 1000)
        }
    }

    // MARK: - TS-02: Format in multiple timezones

    /// Formats a Date in multiple timezones, returning (TimeZone, formattedString) tuples.
    static func formatInTimezones(_ date: Date, zones: [TimeZone]) -> [(TimeZone, String)] {
        zones.map { tz in
            let fmt = DateFormatter()
            fmt.timeZone = tz
            fmt.dateStyle = .full
            fmt.timeStyle = .long
            return (tz, fmt.string(from: date))
        }
    }

    // MARK: - TS-05: ISO 8601

    /// Formats a Date as an ISO 8601 string.
    static func toISO8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    // MARK: - TS-04: Relative time

    /// Returns a human-readable relative time string (e.g. "2 hours ago", "in 3 days").
    static func relativeTime(from date: Date) -> String {
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .full
        return fmt.localizedString(for: date, relativeTo: Date())
    }
}
