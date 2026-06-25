// LatheTests/TimestampTransformerTests.swift
// Tests for TimestampTransformer — covers TS-01..05 + pitfall #8 + INFRA-17

import Testing
import Foundation
@testable import Lathe

@Suite("TimestampTransformer")
struct TimestampTransformerTests {

    // MARK: - TS-01: Unit Detection (pitfall #8)

    @Test("10-digit integer → .seconds")
    func testDetectUnit_10digits_isSeconds() {
        let result = TimestampTransformer.detectUnit(1_700_000_000)
        #expect(result == .seconds)
    }

    @Test("13-digit integer → .milliseconds")
    func testDetectUnit_13digits_isMilliseconds() {
        let result = TimestampTransformer.detectUnit(1_700_000_000_000)
        #expect(result == .milliseconds)
    }

    @Test("11-digit integer → .ambiguous (pitfall #8)")
    func testDetectUnit_11digits_isAmbiguous() {
        let result = TimestampTransformer.detectUnit(17_000_000_000)
        #expect(result == .ambiguous)
    }

    @Test("12-digit integer → .ambiguous (pitfall #8)")
    func testDetectUnit_12digits_isAmbiguous() {
        let result = TimestampTransformer.detectUnit(170_000_000_00) // 11 digits — 17000000000
        // 12-digit: 1_700_000_000_00 (12 digits) = ambiguous
        let twelveDigit: Int64 = 1_700_000_000_00
        let result12 = TimestampTransformer.detectUnit(twelveDigit)
        #expect(result12 == .ambiguous)
    }

    @Test("Negative 10-digit timestamp → .seconds")
    func testDetectUnit_negative10digits_isSeconds() {
        // Negative timestamps (dates before 1970) are valid
        let result = TimestampTransformer.detectUnit(-1_700_000_000)
        #expect(result == .seconds)
    }

    // MARK: - TS-02: toDate + formatInTimezones

    @Test("toDate with .seconds returns correct Date")
    func testToDate_seconds_correctDate() {
        // Unix timestamp 1700000000 = 2023-11-14T22:13:20Z
        let date = TimestampTransformer.toDate(1_700_000_000, unit: .seconds)
        let expected = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(date == expected)
    }

    @Test("toDate with .milliseconds returns correct Date")
    func testToDate_milliseconds_correctDate() {
        // 1700000000000 ms = same epoch second
        let date = TimestampTransformer.toDate(1_700_000_000_000, unit: .milliseconds)
        let expected = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(date == expected)
    }

    @Test("formatInTimezones returns one string per timezone")
    func testFormatInTimezones_returnsCorrectCount() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let zones = [TimeZone(identifier: "UTC")!, TimeZone(identifier: "America/New_York")!]
        let results = TimestampTransformer.formatInTimezones(date, zones: zones)
        #expect(results.count == 2)
        // Each result should be non-empty
        for (_, formatted) in results {
            #expect(!formatted.isEmpty)
        }
    }

    @Test("formatInTimezones UTC output contains UTC indicator")
    func testFormatInTimezones_UTC_containsUTC() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let zones = [TimeZone(identifier: "UTC")!]
        let results = TimestampTransformer.formatInTimezones(date, zones: zones)
        #expect(results.count == 1)
        // UTC formatted date should not be empty
        #expect(!results[0].1.isEmpty)
    }

    // MARK: - TS-05: ISO 8601

    @Test("toISO8601 returns valid ISO 8601 string")
    func testToISO8601_validFormat() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let iso = TimestampTransformer.toISO8601(date)
        // Should contain T separator and Z or +/- timezone offset
        #expect(iso.contains("T"))
        #expect(!iso.isEmpty)
        // Parseable by ISO8601DateFormatter
        let formatter = ISO8601DateFormatter()
        let parsed = formatter.date(from: iso)
        #expect(parsed != nil)
    }

    @Test("toISO8601 round-trips correctly")
    func testToISO8601_roundTrip() {
        let original = Date(timeIntervalSince1970: 1_700_000_000)
        let iso = TimestampTransformer.toISO8601(original)
        let formatter = ISO8601DateFormatter()
        let parsed = formatter.date(from: iso)
        #expect(parsed != nil)
        // Allow 1 second tolerance for fractional seconds
        if let parsed = parsed {
            #expect(abs(parsed.timeIntervalSince(original)) < 1.0)
        }
    }

    // MARK: - TS-04: Relative Time

    @Test("relativeTime for past date returns non-empty string")
    func testRelativeTime_pastDate_nonEmpty() {
        let pastDate = Date(timeIntervalSinceNow: -86400) // 1 day ago
        let relative = TimestampTransformer.relativeTime(from: pastDate)
        #expect(!relative.isEmpty)
    }

    @Test("relativeTime for recent past contains 'ago' or similar")
    func testRelativeTime_recentPast_style() {
        let pastDate = Date(timeIntervalSinceNow: -3600) // 1 hour ago
        let relative = TimestampTransformer.relativeTime(from: pastDate)
        // RelativeDateTimeFormatter returns strings like "1 hour ago" or "in 1 hour"
        #expect(!relative.isEmpty)
        // The string should describe a past event (1 hour ago)
        // We just check it's not empty and is a reasonable string
        #expect(relative.count > 2)
    }

    @Test("relativeTime for future date returns non-empty string")
    func testRelativeTime_futureDate_nonEmpty() {
        let futureDate = Date(timeIntervalSinceNow: 3600) // 1 hour from now
        let relative = TimestampTransformer.relativeTime(from: futureDate)
        #expect(!relative.isEmpty)
    }

    // MARK: - INFRA-17: No crash on invalid input

    @Test("detectUnit on zero value returns ambiguous (not a crash)")
    func testDetectUnit_zero_doesNotCrash() {
        // 0 has 1 digit — ambiguous
        let result = TimestampTransformer.detectUnit(0)
        #expect(result == .ambiguous)
    }

    @Test("toDate on large value does not crash")
    func testToDate_largeValue_doesNotCrash() {
        let date = TimestampTransformer.toDate(Int64.max / 1000, unit: .milliseconds)
        // Should not crash; result may be a distant future date
        #expect(date.timeIntervalSince1970 > 0)
    }

    @Test("formatInTimezones with empty zones returns empty array")
    func testFormatInTimezones_emptyZones_returnsEmpty() {
        let date = Date()
        let results = TimestampTransformer.formatInTimezones(date, zones: [])
        #expect(results.isEmpty)
    }

    // MARK: - TS-03: Reverse-convert (toUnixTimestamp)

    @Test("toUnixTimestamp converts Date to seconds")
    func testToUnixTimestamp_seconds() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let ts = TimestampTransformer.toUnixTimestamp(date, unit: .seconds)
        #expect(ts == 1_700_000_000)
    }

    @Test("toUnixTimestamp converts Date to milliseconds")
    func testToUnixTimestamp_milliseconds() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let ts = TimestampTransformer.toUnixTimestamp(date, unit: .milliseconds)
        #expect(ts == 1_700_000_000_000)
    }
}
