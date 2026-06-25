// Core/Extensions/Array+HexString.swift
// Hex-string helper used by HashTransformer for all six digest algorithms.
// HASH-01, HASH-04: produces lowercase hex; caller uppercases via String.uppercased() for toggle.

import Foundation
import CryptoKit

extension Array where Element == UInt8 {
    /// Returns the byte array as a lowercase hex string (e.g. "deadbeef").
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - CryptoKit Digest → hex

extension Digest {
    /// Convenience: lowercase hex string from any CryptoKit Digest.
    var hexString: String {
        Array(self).hexString
    }
}
