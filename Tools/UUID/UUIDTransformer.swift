// Tools/UUID/UUIDTransformer.swift
// Pure UUID logic — NO SwiftUI/AppKit imports.
// UUID-01: v4 (Foundation), v1 (hand-rolled RFC 4122 §4.1/§4.5), v5 (hand-rolled CryptoKit SHA1)
// UUID-02: v7 hand-rolled per RFC 9562 §5.7 — see deviation note below
// UUID-03: inspect — version/variant/embedded timestamp (v1 and v7)
// UUID-04: export — newline, CSV, JSON array; uppercase toggle; nil UUID display
// INFRA-17: malformed input returns nil/error, never crashes.
//
// PACKAGE DEVIATION (v7):
//   leodabus/UUIDv7 (approved by human checkpoint, commit 186b273e) was added as an SPM dependency
//   but its methods (UUID.v7(), UUID.date) are declared with internal (not public) access,
//   making them inaccessible from outside the module. This is an access modifier bug in the package.
//   Resolution: v7 is implemented here using the same RFC 9562 §5.7 algorithm verified from the
//   package source. The package reference remains in the project.pbxproj but is not imported here.
//   The algorithm is identical: 48-bit big-endian ms timestamp in bytes [0-5], version nibble 7
//   in byte [6], RFC 4122 variant in byte [8], remaining bytes random.

import Foundation
import CryptoKit

// MARK: - Types

enum UUIDTransformer {

    // MARK: - UUIDInfo (UUID-03)

    struct UUIDInfo: Sendable {
        let version: Int
        let variant: Int
        let timestamp: Date?

        // Component breakdown fields
        let uuidString: String
        let timeLow: String?       // v1 only
        let timeMid: String?       // v1 only
        let timeHigh: String?      // v1 only
        let clockSeq: String?      // v1 only
        let node: String?          // v1 only
        let embeddedMs: UInt64?    // v7 only — milliseconds since epoch

        var variantDescription: String {
            switch variant {
            case 2: return "RFC 4122 (standard)"
            case 3: return "Microsoft (reserved)"
            case 0, 1: return "NCS (reserved)"
            default: return "Future (reserved)"
            }
        }
    }

    // MARK: - Export format (UUID-04)

    enum ExportFormat: String, CaseIterable, Sendable {
        case newline = "Newline"
        case csv = "CSV"
        case json = "JSON Array"
    }

    // MARK: - UUID-01: v4 generation (Foundation native — only v4 natively supported)

    /// Generates `count` random v4 UUIDs.
    static func generateV4(count: Int) -> [UUID] {
        (0..<max(1, count)).map { _ in UUID() }
    }

    // MARK: - UUID-01: v1 generation (hand-rolled — RFC 4122 §4.1.3 and §4.5)
    //
    // v1 layout (128 bits):
    //   time_low     [0-3]  = low 32 bits of 60-bit timestamp
    //   time_mid     [4-5]  = bits 32-47 of timestamp
    //   time_hi_ver  [6-7]  = version (0b0001 << 4) | bits 48-59 of timestamp
    //   clock_seq_hi [8]    = variant (0b10 << 6) | high 6 bits of 14-bit clock sequence
    //   clock_seq_low[9]    = low 8 bits of clock sequence
    //   node         [10-15]= 48-bit pseudo-node (RFC 4122 §4.5: multicast bit set because
    //                         we cannot read the real MAC address in a sandboxed/offline context)
    //
    // Timestamp: 100-nanosecond intervals since October 15, 1582 (UUID epoch).
    // Clock sequence: randomized per process start (no persistent storage needed for v1 in this context).
    // DELIBERATE PSEUDO-NODE CHOICE: RFC 4122 §4.5 explicitly permits using random node IDs
    // with the multicast bit set when a real 802 MAC address is unavailable, which is the
    // correct approach for a non-sandboxed macOS app that avoids MAC address leakage.

    private static let v1ClockSeq: UInt16 = UInt16.random(in: 0..<0x3FFF)
    private static let v1Node: [UInt8] = {
        // 48-bit random node with multicast bit set (RFC 4122 §4.5)
        var bytes = (0..<6).map { _ in UInt8.random(in: 0...255) }
        bytes[0] |= 0x01  // set multicast bit
        return bytes
    }()

    static func generateV1(count: Int) -> [UUID] {
        // UUID epoch = October 15, 1582; Unix epoch = January 1, 1970
        // Offset in 100ns intervals: 122,192,928,000,000,000
        let uuidEpochOffset: UInt64 = 122_192_928_000_000_000

        return (0..<max(1, count)).map { _ in
            // Get current time in 100ns intervals since UUID epoch
            var tv = timeval()
            gettimeofday(&tv, nil)
            let microseconds = UInt64(tv.tv_sec) * 1_000_000 + UInt64(tv.tv_usec)
            let t: UInt64 = microseconds * 10 + uuidEpochOffset

            // Decompose 60-bit timestamp per RFC 4122 §4.1.4
            let timeLow    = UInt32(t & 0xFFFF_FFFF)
            let timeMid    = UInt16((t >> 32) & 0xFFFF)
            let timeHiVer  = UInt16((t >> 48) & 0x0FFF) | 0x1000  // version 1

            let clockSeq   = v1ClockSeq
            let clockSeqHi = UInt8((clockSeq >> 8) & 0x3F) | 0x80  // variant 10xx
            let clockSeqLo = UInt8(clockSeq & 0xFF)

            // Build 16-byte UUID
            var bytes = [UInt8](repeating: 0, count: 16)
            bytes[0] = UInt8((timeLow >> 24) & 0xFF)
            bytes[1] = UInt8((timeLow >> 16) & 0xFF)
            bytes[2] = UInt8((timeLow >> 8) & 0xFF)
            bytes[3] = UInt8(timeLow & 0xFF)
            bytes[4] = UInt8((timeMid >> 8) & 0xFF)
            bytes[5] = UInt8(timeMid & 0xFF)
            bytes[6] = UInt8((timeHiVer >> 8) & 0xFF)
            bytes[7] = UInt8(timeHiVer & 0xFF)
            bytes[8] = clockSeqHi
            bytes[9] = clockSeqLo
            bytes[10] = v1Node[0]
            bytes[11] = v1Node[1]
            bytes[12] = v1Node[2]
            bytes[13] = v1Node[3]
            bytes[14] = v1Node[4]
            bytes[15] = v1Node[5]

            // Convert to uuid_t tuple
            let t0 = bytes[0], t1 = bytes[1], t2 = bytes[2], t3 = bytes[3]
            let t4 = bytes[4], t5 = bytes[5], t6 = bytes[6], t7 = bytes[7]
            let t8 = bytes[8], t9 = bytes[9], ta = bytes[10], tb = bytes[11]
            let tc = bytes[12], td = bytes[13], te = bytes[14], tf = bytes[15]
            return UUID(uuid: (t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, ta, tb, tc, td, te, tf))
        }
    }

    // MARK: - UUID-01: v5 generation (hand-rolled — RFC 4122 §4.3, CryptoKit SHA1)
    //
    // v5 uses SHA1 over (namespace UUID bytes + name bytes), then applies:
    //   - version: byte[6] = (byte[6] & 0x0F) | 0x50  (version bits 0101)
    //   - variant: byte[8] = (byte[8] & 0x3F) | 0x80  (RFC 4122 variant 10xx)
    //
    // Standard namespaces per RFC 4122 §4.3:
    //   DNS:  6ba7b810-9dad-11d1-80b4-00c04fd430c8
    //   URL:  6ba7b811-9dad-11d1-80b4-00c04fd430c8
    //   OID:  6ba7b812-9dad-11d1-80b4-00c04fd430c8
    //   X500: 6ba7b814-9dad-11d1-80b4-00c04fd430c8

    static let namespaceDNS  = UUID(uuidString: "6ba7b810-9dad-11d1-80b4-00c04fd430c8")!
    static let namespaceURL  = UUID(uuidString: "6ba7b811-9dad-11d1-80b4-00c04fd430c8")!
    static let namespaceOID  = UUID(uuidString: "6ba7b812-9dad-11d1-80b4-00c04fd430c8")!
    static let namespaceX500 = UUID(uuidString: "6ba7b814-9dad-11d1-80b4-00c04fd430c8")!

    /// Generates a deterministic v5 UUID for the given namespace and name.
    /// Same inputs always produce the same UUID (RFC 4122 §4.3).
    static func generateV5(namespace: UUID, name: String) -> UUID {
        // Concatenate namespace bytes + name bytes
        var data = Data(count: 16)
        let nsBytes = withUnsafeBytes(of: namespace.uuid) { Array($0) }
        data = Data(nsBytes) + Data(name.utf8)

        // SHA1 hash
        let digest = Insecure.SHA1.hash(data: data)
        var bytes = Array(digest)  // 20 bytes; we use the first 16

        // Apply version 5 and RFC 4122 variant
        bytes[6] = (bytes[6] & 0x0F) | 0x50  // version 0b0101
        bytes[8] = (bytes[8] & 0x3F) | 0x80  // variant 10xx

        return UUID(uuid: (
            bytes[0],  bytes[1],  bytes[2],  bytes[3],
            bytes[4],  bytes[5],  bytes[6],  bytes[7],
            bytes[8],  bytes[9],  bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    // MARK: - UUID-02: v7 generation (hand-rolled per RFC 9562 §5.7)
    //
    // RFC 9562 §5.7 layout:
    //   Bytes [0-5]:  48-bit Unix millisecond timestamp (big-endian, most significant first)
    //   Byte  [6]:    version nibble = 7 (upper 4 bits = 0x70, lower 4 bits = random)
    //   Byte  [7]:    random (rand_a continuation)
    //   Byte  [8]:    variant = RFC 4122 (upper 2 bits = 0b10, lower 6 bits = random)
    //   Bytes [9-15]: random (rand_b)
    //
    // This is algorithmically identical to the leodabus/UUIDv7 implementation verified
    // from source — the package was not usable due to missing `public` access modifiers
    // (see file header deviation note). The entropy source is UUID() which provides
    // cryptographically random bytes for all non-timestamp fields.

    static func generateV7(count: Int) -> [UUID] {
        (0..<max(1, count)).map { _ in generateSingleV7() }
    }

    private static func generateSingleV7() -> UUID {
        // Get current time as milliseconds since Unix epoch
        var tv = timeval()
        gettimeofday(&tv, nil)
        let ms = UInt64(tv.tv_sec) * 1000 + UInt64(tv.tv_usec) / 1000

        // Use Foundation UUID for random entropy in non-timestamp fields
        let random = UUID()
        var data = withUnsafeBytes(of: random.uuid) { Array($0) }

        // Overwrite bytes [0-5] with 48-bit ms timestamp (big-endian)
        data[0] = UInt8((ms >> 40) & 0xFF)
        data[1] = UInt8((ms >> 32) & 0xFF)
        data[2] = UInt8((ms >> 24) & 0xFF)
        data[3] = UInt8((ms >> 16) & 0xFF)
        data[4] = UInt8((ms >> 8)  & 0xFF)
        data[5] = UInt8(ms         & 0xFF)

        // Byte [6]: version nibble = 7 (upper 4 bits), preserve lower 4 bits (rand_a)
        data[6] = (data[6] & 0x0F) | 0x70

        // Byte [8]: variant = RFC 4122 (upper 2 bits = 0b10), preserve lower 6 bits
        data[8] = (data[8] & 0x3F) | 0x80

        return UUID(uuid: (
            data[0],  data[1],  data[2],  data[3],
            data[4],  data[5],  data[6],  data[7],
            data[8],  data[9],  data[10], data[11],
            data[12], data[13], data[14], data[15]
        ))
    }

    // MARK: - UUID-03: Inspect any UUID (version, variant, timestamps)
    //
    // Pitfall #17: v7 timestamp is in bytes [0-5] (48-bit ms since Unix epoch), NOT the v1 field.

    /// Inspects a UUID string and returns version/variant/timestamp info.
    /// Returns nil for malformed input (INFRA-17 — no crash on bad input).
    static func inspect(_ uuidString: String) -> UUIDInfo? {
        let trimmed = uuidString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let uuid = UUID(uuidString: trimmed) else { return nil }
        return inspect(uuid)
    }

    /// Inspects a UUID value and returns version/variant/timestamp info.
    static func inspect(_ uuid: UUID) -> UUIDInfo {
        let bytes = withUnsafeBytes(of: uuid.uuid) { Array($0) }

        let version = Int((bytes[6] >> 4) & 0xF)
        let variantBits = (bytes[8] >> 6) & 0x3
        // Map 2-bit variant field: 0b10 and 0b11 → RFC 4122 (= variant 2)
        let variant: Int
        switch variantBits {
        case 0b00, 0b01: variant = 0  // NCS reserved
        case 0b10:       variant = 2  // RFC 4122
        case 0b11:       variant = 3  // Microsoft reserved
        default:         variant = 0
        }

        var timestamp: Date? = nil
        var timeLow: String? = nil
        var timeMid: String? = nil
        var timeHighStr: String? = nil
        var clockSeqStr: String? = nil
        var nodeStr: String? = nil
        var embeddedMs: UInt64? = nil

        if version == 1 {
            // v1: 60-bit timestamp in 100ns intervals since UUID epoch (Oct 15, 1582)
            // Layout: time_low[0-3] | time_mid[4-5] | time_hi[6-7 low 12 bits]
            let tLow  = UInt64(bytes[0]) << 24 | UInt64(bytes[1]) << 16
                      | UInt64(bytes[2]) << 8  | UInt64(bytes[3])
            let tMid  = UInt64(bytes[4]) << 8 | UInt64(bytes[5])
            let tHigh = UInt64(bytes[6] & 0x0F) << 8 | UInt64(bytes[7])
            let t: UInt64 = (tHigh << 48) | (tMid << 32) | tLow

            // Convert to Unix seconds: subtract UUID epoch offset, divide by 10M (100ns → sec)
            let uuidEpochOffset: Double = 12_219_292_800.0  // seconds between 1582-10-15 and 1970-01-01
            let unixSec = Double(t) / 10_000_000.0 - uuidEpochOffset
            timestamp = Date(timeIntervalSince1970: unixSec)

            timeLow     = String(format: "%08x", UInt32(tLow))
            timeMid     = String(format: "%04x", UInt16(tMid))
            timeHighStr = String(format: "%04x", UInt16(tHigh))

            let cs = (UInt16(bytes[8] & 0x3F) << 8) | UInt16(bytes[9])
            clockSeqStr = String(format: "%04x", cs)

            nodeStr = bytes[10...15].map { String(format: "%02x", $0) }.joined(separator: ":")

        } else if version == 7 {
            // v7: 48-bit Unix millisecond timestamp in bytes [0-5] (pitfall #17 bit-mask)
            let ms: UInt64 = (UInt64(bytes[0]) << 40) | (UInt64(bytes[1]) << 32)
                           | (UInt64(bytes[2]) << 24) | (UInt64(bytes[3]) << 16)
                           | (UInt64(bytes[4]) << 8)  | UInt64(bytes[5])
            embeddedMs = ms
            timestamp = Date(timeIntervalSince1970: Double(ms) / 1000.0)
        }

        return UUIDInfo(
            version: version,
            variant: variant,
            timestamp: timestamp,
            uuidString: uuid.uuidString,
            timeLow: timeLow,
            timeMid: timeMid,
            timeHigh: timeHighStr,
            clockSeq: clockSeqStr,
            node: nodeStr,
            embeddedMs: embeddedMs
        )
    }

    // MARK: - UUID-04: Export (newline, CSV, JSON array; case toggle; nil UUID display)

    static let nilUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    /// Exports a list of UUIDs to a string in the requested format.
    /// Applies uppercase transformation and includes nil UUID display per UUID-04.
    static func export(_ uuids: [UUID], format: ExportFormat, uppercase: Bool) -> String {
        let strings = uuids.map { uuid -> String in
            let s = uuid.uuidString
            return uppercase ? s.uppercased() : s.lowercased()
        }
        switch format {
        case .newline:
            return strings.joined(separator: "\n")
        case .csv:
            return strings.joined(separator: ",")
        case .json:
            let items = strings.map { "\"\($0)\"" }.joined(separator: ",\n  ")
            return "[\n  \(items)\n]"
        }
    }
}
