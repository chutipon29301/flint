// LatheTests/UUIDTransformerTests.swift
// Tests for UUIDTransformer covering UUID-01..04 and INFRA-17.

import XCTest
@testable import Lathe

final class UUIDTransformerTests: XCTestCase {

    // MARK: - UUID-01: v4 generation

    func testGenerateV4Single() {
        let uuids = UUIDTransformer.generateV4(count: 1)
        XCTAssertEqual(uuids.count, 1)
        let info = UUIDTransformer.inspect(uuids[0])
        XCTAssertEqual(info.version, 4, "generateV4 must produce version 4 UUIDs")
    }

    func testGenerateV4Bulk() {
        let uuids = UUIDTransformer.generateV4(count: 100)
        XCTAssertEqual(uuids.count, 100)
        // All distinct
        let set = Set(uuids.map { $0.uuidString })
        XCTAssertEqual(set.count, 100, "bulk v4 UUIDs must all be distinct")
        // All version 4
        for uuid in uuids {
            let info = UUIDTransformer.inspect(uuid)
            XCTAssertEqual(info.version, 4)
        }
    }

    func testGenerateV4BulkMax() {
        let uuids = UUIDTransformer.generateV4(count: 1000)
        XCTAssertEqual(uuids.count, 1000, "bulk generation must produce exactly 1000 UUIDs")
    }

    // MARK: - UUID-01: v1 generation (hand-rolled)

    func testGenerateV1Single() {
        let uuids = UUIDTransformer.generateV1(count: 1)
        XCTAssertEqual(uuids.count, 1)
        let info = UUIDTransformer.inspect(uuids[0])
        XCTAssertEqual(info.version, 1, "generateV1 must produce version 1 UUIDs")
    }

    func testGenerateV1VersionAndVariant() {
        let uuids = UUIDTransformer.generateV1(count: 5)
        for uuid in uuids {
            let info = UUIDTransformer.inspect(uuid)
            XCTAssertEqual(info.version, 1, "v1 UUID must have version 1")
            XCTAssertEqual(info.variant, 2, "v1 UUID must have RFC 4122 variant (2)")
        }
    }

    func testGenerateV1HasTimestamp() {
        let before = Date()
        let uuids = UUIDTransformer.generateV1(count: 1)
        let after = Date()
        let info = UUIDTransformer.inspect(uuids[0])
        XCTAssertNotNil(info.timestamp, "v1 UUID must have a non-nil embedded timestamp")
        if let ts = info.timestamp {
            // Allow ±5 seconds for clock precision differences
            XCTAssertTrue(ts >= before.addingTimeInterval(-5) && ts <= after.addingTimeInterval(5),
                         "v1 embedded timestamp must be approximately now (got \(ts))")
        }
    }

    func testGenerateV1Bulk() {
        let uuids = UUIDTransformer.generateV1(count: 10)
        XCTAssertEqual(uuids.count, 10)
        for uuid in uuids {
            let info = UUIDTransformer.inspect(uuid)
            XCTAssertEqual(info.version, 1)
        }
    }

    // MARK: - UUID-01: v5 generation (hand-rolled, CryptoKit SHA1)

    func testGenerateV5Deterministic() {
        // v5 must be deterministic: same namespace + name → same UUID (RFC 4122 §4.3)
        let namespace = UUIDTransformer.namespaceDNS
        let name = "www.example.com"
        let a = UUIDTransformer.generateV5(namespace: namespace, name: name)
        let b = UUIDTransformer.generateV5(namespace: namespace, name: name)
        XCTAssertEqual(a, b, "v5 UUIDs with same namespace+name must be identical")
    }

    func testGenerateV5KnownVector() {
        // v5 for DNS namespace + "www.widgets.com":
        // SHA1 hash verified against Python's uuid.uuid5(uuid.NAMESPACE_DNS, "www.widgets.com")
        // = 21f7f8de-8051-5b89-8680-0195ef798b6a
        // Note: RFC 4122 Appendix B test vector 886313e1-... is for v3 (MD5), not v5.
        let expected = UUID(uuidString: "21f7f8de-8051-5b89-8680-0195ef798b6a")!
        let result = UUIDTransformer.generateV5(namespace: UUIDTransformer.namespaceDNS, name: "www.widgets.com")
        XCTAssertEqual(result, expected, "v5 for DNS+www.widgets.com must match Python uuid.uuid5 output")
    }

    func testGenerateV5VersionAndVariant() {
        let uuid = UUIDTransformer.generateV5(namespace: UUIDTransformer.namespaceDNS, name: "test")
        let info = UUIDTransformer.inspect(uuid)
        XCTAssertEqual(info.version, 5, "v5 UUID must have version 5")
        XCTAssertEqual(info.variant, 2, "v5 UUID must have RFC 4122 variant")
    }

    func testGenerateV5DifferentNamesAreDifferent() {
        let a = UUIDTransformer.generateV5(namespace: UUIDTransformer.namespaceDNS, name: "foo")
        let b = UUIDTransformer.generateV5(namespace: UUIDTransformer.namespaceDNS, name: "bar")
        XCTAssertNotEqual(a, b, "v5 UUIDs with different names must differ")
    }

    func testGenerateV5DifferentNamespacesAreDifferent() {
        let name = "test"
        let a = UUIDTransformer.generateV5(namespace: UUIDTransformer.namespaceDNS, name: name)
        let b = UUIDTransformer.generateV5(namespace: UUIDTransformer.namespaceURL, name: name)
        XCTAssertNotEqual(a, b, "v5 UUIDs with different namespaces must differ")
    }

    // MARK: - UUID-02: v7 generation (leodabus/UUIDv7 package)

    func testGenerateV7Single() {
        let uuids = UUIDTransformer.generateV7(count: 1)
        XCTAssertEqual(uuids.count, 1)
        let info = UUIDTransformer.inspect(uuids[0])
        XCTAssertEqual(info.version, 7, "generateV7 must produce version 7 UUIDs")
    }

    func testGenerateV7HasTimestamp() {
        let before = Date()
        let uuids = UUIDTransformer.generateV7(count: 1)
        let after = Date()
        let info = UUIDTransformer.inspect(uuids[0])
        XCTAssertNotNil(info.timestamp, "v7 UUID must have a non-nil embedded timestamp")
        if let ts = info.timestamp {
            XCTAssertTrue(ts >= before.addingTimeInterval(-1) && ts <= after.addingTimeInterval(1),
                         "v7 embedded timestamp must be approximately now")
        }
    }

    func testGenerateV7VersionAndVariant() {
        let uuid = UUIDTransformer.generateV7(count: 1)[0]
        let info = UUIDTransformer.inspect(uuid)
        XCTAssertEqual(info.version, 7, "v7 UUID must have version 7")
        XCTAssertEqual(info.variant, 2, "v7 UUID must have RFC 4122 variant")
    }

    func testGenerateV7Bulk() {
        let uuids = UUIDTransformer.generateV7(count: 10)
        XCTAssertEqual(uuids.count, 10)
        for uuid in uuids {
            let info = UUIDTransformer.inspect(uuid)
            XCTAssertEqual(info.version, 7)
        }
    }

    // MARK: - UUID-03: inspect — known UUID vectors

    func testInspectKnownV4() {
        let uuidStr = "550e8400-e29b-41d4-a716-446655440000"
        guard let info = UUIDTransformer.inspect(uuidStr) else {
            XCTFail("inspect of valid UUID must not return nil")
            return
        }
        XCTAssertEqual(info.version, 4)
        XCTAssertNil(info.timestamp, "v4 UUIDs have no embedded timestamp")
    }

    func testInspectKnownV1() {
        // A known v1 UUID: version nibble = 1, variant = RFC4122
        // time: corresponds roughly to a past date
        let uuidStr = "c232ab00-9414-11ec-b3c8-9e6bdeced846"
        guard let info = UUIDTransformer.inspect(uuidStr) else {
            XCTFail("inspect of valid v1 UUID must not return nil")
            return
        }
        XCTAssertEqual(info.version, 1, "must detect version 1")
        XCTAssertEqual(info.variant, 2, "must detect RFC 4122 variant")
        XCTAssertNotNil(info.timestamp, "v1 inspect must extract embedded timestamp")
        // The timestamp should be somewhere in the past
        if let ts = info.timestamp {
            XCTAssertTrue(ts < Date(), "v1 embedded timestamp must be in the past")
        }
    }

    func testInspectKnownV7() {
        // Construct a known v7 UUID: timestamp = 0x18C3A5C37C0 ms = 1700000000000 ms
        // = Unix 1700000000.000s ≈ 2023-11-14 (UTC)
        // Byte layout: [0-5] = 0x018C3A5C37C0 (big-endian) ... but let's use a literal
        // ms = 0x0189_4EDA_A800 = 1691100826624 ms (a recent past date)
        // Let's use the leodabus package to generate one and test inspection:
        let uuid = UUIDTransformer.generateV7(count: 1)[0]
        guard let info = UUIDTransformer.inspect(uuid.uuidString) else {
            XCTFail("inspect of a just-generated v7 UUID must not return nil")
            return
        }
        XCTAssertEqual(info.version, 7, "generated v7 UUID must inspect as version 7")
        XCTAssertNotNil(info.embeddedMs, "v7 inspect must extract embeddedMs")
        XCTAssertNotNil(info.timestamp, "v7 inspect must have a non-nil timestamp")

        // Also test with a hardcoded v7 vector for the bit-mask (pitfall #17)
        // Bytes [0-5] = 0x01_8C_3A_5C_37_C0 → ms = 0x018C3A5C37C0 = 1701786171328
        // = Unix epoch 1701786171.328s ≈ 2023-12-05 (UTC)
        let v7vector = UUID(uuid: (
            0x01, 0x8C, 0x3A, 0x5C, 0x37, 0xC0,  // 48-bit ms timestamp (1701786171328 ms)
            0x7A, 0xBC,                             // version 7 (0x7_ upper nibble), rand_a
            0xBD, 0xEF,                             // variant 0x80 mask, rand_b
            0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC     // rand_b cont.
        ))
        guard let v7info = UUIDTransformer.inspect(v7vector.uuidString) else {
            XCTFail("v7 known vector inspect must not return nil")
            return
        }
        XCTAssertEqual(v7info.version, 7, "known v7 vector must inspect as version 7")
        // 0x018C3A5C37C0 = 1701786171328 ms
        XCTAssertEqual(v7info.embeddedMs, 1_701_786_171_328, "v7 embedded ms must match timestamp bytes exactly")
        let expectedDate = Date(timeIntervalSince1970: 1_701_786_171.328)
        if let ts = v7info.timestamp {
            XCTAssertEqual(ts.timeIntervalSince1970, expectedDate.timeIntervalSince1970,
                           accuracy: 0.001, "v7 timestamp must match embedded ms divided by 1000")
        } else {
            XCTFail("v7 known vector must have a non-nil timestamp")
        }
    }

    func testInspectNilUUID() {
        // The nil UUID (all zeros) should not crash and report version 0
        let nilStr = "00000000-0000-0000-0000-000000000000"
        let info = UUIDTransformer.inspect(nilStr)
        XCTAssertNotNil(info, "inspect of nil UUID must not return nil (no crash)")
        XCTAssertEqual(info?.version, 0, "nil UUID has version 0")
    }

    func testInspectMalformedStringDoesNotCrash() {
        // INFRA-17: malformed input must return nil, not crash
        let malformed = ["", "not-a-uuid", "12345", "ZZZZZZZZ-ZZZZ-ZZZZ-ZZZZ-ZZZZZZZZZZZZ",
                         "550e8400-e29b-41d4-a716", "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"]
        for bad in malformed {
            let result = UUIDTransformer.inspect(bad)
            XCTAssertNil(result, "inspect('\(bad)') must return nil for malformed input")
        }
    }

    func testInspectTrimsWhitespace() {
        let uuidStr = "  550e8400-e29b-41d4-a716-446655440000  \n"
        let info = UUIDTransformer.inspect(uuidStr)
        XCTAssertNotNil(info, "inspect must trim whitespace before parsing")
    }

    // MARK: - UUID-04: export

    func testExportNewline() {
        let uuids = UUIDTransformer.generateV4(count: 3)
        let result = UUIDTransformer.export(uuids, format: .newline, uppercase: false)
        let lines = result.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 3, "newline export of 3 UUIDs must have 3 lines")
        for line in lines {
            XCTAssertNotNil(UUID(uuidString: line), "each newline-separated item must be a valid UUID")
        }
    }

    func testExportCSV() {
        let uuids = UUIDTransformer.generateV4(count: 3)
        let result = UUIDTransformer.export(uuids, format: .csv, uppercase: false)
        let items = result.components(separatedBy: ",")
        XCTAssertEqual(items.count, 3, "CSV export of 3 UUIDs must have 3 comma-separated items")
    }

    func testExportJSON() {
        let uuids = UUIDTransformer.generateV4(count: 3)
        let result = UUIDTransformer.export(uuids, format: .json, uppercase: false)
        XCTAssertTrue(result.hasPrefix("["), "JSON export must start with [")
        XCTAssertTrue(result.hasSuffix("]"), "JSON export must end with ]")
        // Validate it's parseable JSON
        if let data = result.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String] {
            XCTAssertEqual(parsed.count, 3)
        } else {
            XCTFail("JSON export must produce valid JSON array")
        }
    }

    func testExportUppercase() {
        let uuids = UUIDTransformer.generateV4(count: 1)
        let upper = UUIDTransformer.export(uuids, format: .newline, uppercase: true)
        XCTAssertEqual(upper, upper.uppercased(), "uppercase export must be all uppercase")
    }

    func testExportLowercase() {
        let uuids = UUIDTransformer.generateV4(count: 1)
        let lower = UUIDTransformer.export(uuids, format: .newline, uppercase: false)
        XCTAssertEqual(lower, lower.lowercased(), "lowercase export must be all lowercase")
    }

    func testExportNilUUID() {
        // Nil UUID should render without crashing
        let nilUUID = UUIDTransformer.nilUUID
        let result = UUIDTransformer.export([nilUUID], format: .newline, uppercase: false)
        XCTAssertEqual(result.lowercased(), "00000000-0000-0000-0000-000000000000",
                       "nil UUID export must render as all-zeros string")
    }

    func testExportBulk1000() {
        // UUID-01: bulk export must handle 1000 UUIDs
        let uuids = UUIDTransformer.generateV4(count: 1000)
        let result = UUIDTransformer.export(uuids, format: .newline, uppercase: false)
        let lines = result.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 1000, "bulk export of 1000 must produce 1000 lines")
    }

    // MARK: - Source assertion (no UI imports)
    // Verified at build time: UUIDTransformer.swift has 0 SwiftUI/AppKit imports.
    // See acceptance criteria grep check in plan 01-05, Task 2.
}
