// Tools/Base64/Base64Transformer.swift
// Pure Base64 encode/decode transformer — zero UI imports.
// Source: Foundation Data.base64EncodedString / Data(base64Encoded:) [VERIFIED]
// Covers: B64-01 (standard), B64-02 (URL-safe), B64-03 (auto-detect), B64-05 (byte/char counts)
// Security: T-02-SP — isLikelyBase64 requires ≥12 chars + full alphabet guard

import Foundation

enum Base64Transformer {

    // MARK: - Errors

    enum TransformError: LocalizedError {
        case invalidBase64
        case decodedDataNotUTF8

        var errorDescription: String? {
            switch self {
            case .invalidBase64:
                return "Not valid Base64"
            case .decodedDataNotUTF8:
                return "Not valid Base64"
            }
        }
    }

    // MARK: - Encode (B64-01, B64-02)

    /// Encode a UTF-8 string to Base64.
    /// - Parameters:
    ///   - text: The string to encode.
    ///   - urlSafe: If true, uses URL-safe (RFC 4648 §5) variant: replaces +→- and /→_ and strips padding.
    /// - Returns: Base64-encoded string (standard) or URL-safe Base64 string.
    static func encode(_ text: String, urlSafe: Bool) -> String {
        guard !text.isEmpty else { return "" }
        let data = Data(text.utf8)
        var encoded = data.base64EncodedString()
        if urlSafe {
            encoded = encoded
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")   // RFC 4648 §5: URL-safe omits padding
        }
        return encoded
    }

    // MARK: - Decode (B64-01, B64-02)

    /// Decode a Base64 (standard or URL-safe) string to text.
    /// Normalizes URL-safe chars (-/_) to standard (+//) and re-pads before decoding.
    /// - Parameter base64: The Base64 or Base64url string to decode.
    /// - Returns: Success with decoded UTF-8 text, or failure with a user-facing error.
    static func decode(_ base64: String) -> Result<String, Error> {
        guard !base64.isEmpty else { return .success("") }

        // B64-02: normalize URL-safe chars to standard base64
        let normalized = base64
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Re-pad to multiple of 4 (URL-safe omits padding; standard may also be unpadded)
        let remainder = normalized.count % 4
        let padded = remainder == 0
            ? normalized
            : normalized + String(repeating: "=", count: 4 - remainder)

        // .ignoreUnknownCharacters: tolerates whitespace/newlines in the input
        guard let data = Data(base64Encoded: padded, options: .ignoreUnknownCharacters) else {
            return .failure(TransformError.invalidBase64)
        }

        guard let text = String(data: data, encoding: .utf8) else {
            return .failure(TransformError.decodedDataNotUTF8)
        }

        return .success(text)
    }

    // MARK: - Auto-detect (B64-03, T-02-SP)

    /// Heuristic to determine if a string is likely Base64-encoded content.
    ///
    /// Security guard T-02-SP: requires ≥12 chars to avoid false-positives on short words
    /// (e.g. "hello", "world" look like base64 but aren't meaningful encoded content).
    /// The 12-char threshold prevents accidental detection of natural-language words.
    ///
    /// - Parameter input: The string to test.
    /// - Returns: True if the input meets the base64 heuristic.
    static func isLikelyBase64(_ input: String) -> Bool {
        guard input.count >= 12 else { return false }   // T-02-SP: short string guard

        // Allow all base64 chars: standard alphabet + URL-safe variants + padding
        let base64Chars = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=-_"
        )
        return input.unicodeScalars.allSatisfy { base64Chars.contains($0) }
    }

    // MARK: - Byte + Char counts (B64-05)

    /// Returns the byte count of decoded data.
    static func byteCount(for data: Data) -> Int {
        return data.count
    }

    /// Returns the Unicode character count of a decoded string.
    static func charCount(for text: String) -> Int {
        return text.count
    }

    // MARK: - Encode Data (B64-04 — used by file encode)

    /// Encode raw Data to Base64 string (for file encode use case).
    /// - Parameters:
    ///   - data: The data to encode.
    ///   - urlSafe: If true, uses URL-safe variant.
    /// - Returns: Base64-encoded string.
    static func encodeData(_ data: Data, urlSafe: Bool) -> String {
        var encoded = data.base64EncodedString()
        if urlSafe {
            encoded = encoded
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return encoded
    }

    /// Decode a Base64 string to raw Data (for file decode use case).
    /// - Parameter base64: The Base64 or Base64url string to decode.
    /// - Returns: Success with decoded Data, or failure.
    static func decodeToData(_ base64: String) -> Result<Data, Error> {
        let normalized = base64
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = normalized.count % 4
        let padded = remainder == 0
            ? normalized
            : normalized + String(repeating: "=", count: 4 - remainder)

        guard let data = Data(base64Encoded: padded, options: .ignoreUnknownCharacters) else {
            return .failure(TransformError.invalidBase64)
        }
        return .success(data)
    }
}
