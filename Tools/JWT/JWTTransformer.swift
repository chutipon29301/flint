// Tools/JWT/JWTTransformer.swift
// Pure JWT transformer — NO SwiftUI/AppKit imports (testable without UI).
// Covers: JWT-01 (decode + base64url), JWT-02 (pretty-print), JWT-03 (expiry timezone-correct),
//         JWT-04 (HMAC verify), JWT-05 (claims partition), JWT-06 (warnings).
// INFRA-17: Returns Result, never force-unwraps, never crashes on bad input.
// PITFALL #4: Uses Data.fromBase64URL for "-"/"_" safe decode (Core/Extensions/Data+Base64URL.swift).
// PITFALL #11: Uses Date(timeIntervalSince1970:) NOT timeIntervalSinceReferenceDate.

import Foundation
import CryptoKit

// MARK: - Error

enum JWTError: Error, LocalizedError {
    case invalidFormat
    case invalidBase64URL
    case invalidJSON(segment: String)

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Invalid JWT format: expected 3 segments separated by '.'"
        case .invalidBase64URL:
            return "Invalid Base64URL encoding in JWT segment"
        case .invalidJSON(let segment):
            return "Invalid JSON in JWT \(segment)"
        }
    }
}

// MARK: - Expiry Status

enum JWTExpiryStatus: Equatable {
    /// Token has no "exp" claim.
    case noExpiry
    /// Token is still valid; remaining seconds until expiry.
    case valid(remaining: TimeInterval)
    /// Token is expired; seconds since expiry.
    case expired(since: TimeInterval)
}

// MARK: - Claims Partition

struct JWTClaimsPartition {
    /// Standard RFC 7519 registered claims.
    let standard: [String: Any]
    /// All other claims.
    let custom: [String: Any]
    /// Algorithm from the header's "alg" field.
    let algorithm: String
}

// MARK: - Warnings

struct JWTWarnings {
    /// True if the token has an "exp" claim in the past.
    let isExpired: Bool
    /// True if the header's "alg" field is "none".
    let isAlgNone: Bool
    /// Standard claims that are absent from the payload.
    let missingStandardClaims: [String]
}

// MARK: - Decoded JWT

struct DecodedJWT {
    let header: [String: Any]
    let payload: [String: Any]
    /// Raw signature segment (Base64URL, not decoded to bytes) for display/copy.
    let signature: String
    /// Verification result; nil means not yet verified.
    let signatureValid: Bool?
}

// MARK: - JWTTransformer

enum JWTTransformer {

    // MARK: - JWT-01: Decode

    /// Decodes a JWT token string into header, payload, and signature.
    /// Returns .failure for any malformed input — never crashes (INFRA-17).
    /// PITFALL #4: Uses Data.fromBase64URL to handle "-" and "_" correctly.
    static func decode(_ token: String) -> Result<DecodedJWT, Error> {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else {
            return .failure(JWTError.invalidFormat)
        }

        let headerSegment = String(parts[0])
        let payloadSegment = String(parts[1])
        let signatureSegment = String(parts[2])

        guard let headerData = Data.fromBase64URL(headerSegment) else {
            return .failure(JWTError.invalidBase64URL)
        }
        guard let payloadData = Data.fromBase64URL(payloadSegment) else {
            return .failure(JWTError.invalidBase64URL)
        }

        guard let header = (try? JSONSerialization.jsonObject(with: headerData, options: [])) as? [String: Any] else {
            return .failure(JWTError.invalidJSON(segment: "header"))
        }
        guard let payload = (try? JSONSerialization.jsonObject(with: payloadData, options: [])) as? [String: Any] else {
            return .failure(JWTError.invalidJSON(segment: "payload"))
        }

        let decoded = DecodedJWT(
            header: header,
            payload: payload,
            signature: signatureSegment,
            signatureValid: nil
        )
        return .success(decoded)
    }

    // MARK: - JWT-02: Pretty-print

    /// Pretty-prints a JSON dictionary as a formatted string.
    /// Reuses the same 2-space indent as JSONTransformer.
    /// Returns nil on serialization failure (INFRA-17).
    static func prettyPrintPayload(_ dict: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(dict) else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: dict,
                                                      options: [.prettyPrinted, .sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - JWT-03: Expiry Status

    /// Returns the expiry status for a JWT payload.
    /// PITFALL #11: MUST use Date(timeIntervalSince1970:) — NOT timeIntervalSinceReferenceDate.
    /// Using timeIntervalSinceReferenceDate would give ~31 years of remaining time for a
    /// "now + 1 hour" exp claim because timeIntervalSinceReferenceDate epoch is Jan 1, 2001,
    /// while JWT exp is always Unix epoch (Jan 1, 1970).
    static func expiryStatus(payload: [String: Any]) -> JWTExpiryStatus {
        // exp claim may be Int, Double, or other numeric type
        let expInterval: TimeInterval?
        if let exp = payload["exp"] as? TimeInterval {
            expInterval = exp
        } else if let exp = payload["exp"] as? Int {
            expInterval = TimeInterval(exp)
        } else if let exp = payload["exp"] as? Int64 {
            expInterval = TimeInterval(exp)
        } else {
            expInterval = nil
        }

        guard let exp = expInterval else {
            return .noExpiry
        }

        // PITFALL #11: Must use timeIntervalSince1970, not timeIntervalSinceReferenceDate
        let expiryDate = Date(timeIntervalSince1970: exp)
        let now = Date()

        if expiryDate <= now {
            return .expired(since: now.timeIntervalSince(expiryDate))
        }
        return .valid(remaining: expiryDate.timeIntervalSince(now))
    }

    // MARK: - JWT-04: HMAC Verify

    /// Verifies the HMAC signature of a JWT token with the given secret and algorithm.
    /// Supports HS256, HS384, HS512 via CryptoKit with constant-time comparison.
    /// Returns false for any invalid input, wrong secret, or unsupported algorithm — never crashes.
    /// SECURITY: The secret parameter is only used here in-memory and is NEVER persisted.
    static func verifyHMAC(token: String, secret: String, algorithm: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return false }

        let message = "\(parts[0]).\(parts[1])"
        guard let messageData = message.data(using: .utf8),
              let keyData = secret.data(using: .utf8),
              let sigData = Data.fromBase64URL(String(parts[2])) else { return false }

        // sigData must be non-empty to prevent trivially passing empty-sig tokens
        guard !sigData.isEmpty else { return false }

        let key = SymmetricKey(data: keyData)

        // WR-01: Use CryptoKit's built-in constant-time isValidAuthenticationCode(_:authenticating:using:)
        // instead of Data(mac) == sigData. Swift's Data.== performs an early-return byte comparison
        // and is NOT constant-time. The CryptoKit API is timing-safe by design (JWT-04, T-03-T).
        switch algorithm {
        case "HS256":
            return HMAC<SHA256>.isValidAuthenticationCode(sigData, authenticating: messageData, using: key)
        case "HS384":
            return HMAC<SHA384>.isValidAuthenticationCode(sigData, authenticating: messageData, using: key)
        case "HS512":
            return HMAC<SHA512>.isValidAuthenticationCode(sigData, authenticating: messageData, using: key)
        default:
            return false
        }
    }

    // MARK: - JWT-05: Claims Partition

    /// Partitions JWT payload into standard (RFC 7519) and custom claims.
    /// Reads algorithm from the header "alg" field.
    static func partitionClaims(payload: [String: Any], header: [String: Any]) -> JWTClaimsPartition {
        // RFC 7519 Section 4.1 registered claim names
        let standardClaimNames: Set<String> = ["iss", "sub", "aud", "exp", "nbf", "iat", "jti"]

        var standardClaims: [String: Any] = [:]
        var customClaims: [String: Any] = [:]

        for (key, value) in payload {
            if standardClaimNames.contains(key) {
                standardClaims[key] = value
            } else {
                customClaims[key] = value
            }
        }

        let algorithm = header["alg"] as? String ?? "unknown"

        return JWTClaimsPartition(
            standard: standardClaims,
            custom: customClaims,
            algorithm: algorithm
        )
    }

    // MARK: - JWT-06: Warnings

    /// Computes warning flags for a JWT.
    /// - isExpired: exp claim is in the past.
    /// - isAlgNone: header alg is "none" (insecure — T-03-SP).
    /// - missingStandardClaims: standard claim names absent from payload.
    static func warnings(payload: [String: Any], header: [String: Any]) -> JWTWarnings {
        // Check expiry
        let expiryStatus = self.expiryStatus(payload: payload)
        let isExpired: Bool
        if case .expired = expiryStatus {
            isExpired = true
        } else {
            isExpired = false
        }

        // Check alg:none (T-03-SP: never treat as valid)
        let alg = header["alg"] as? String ?? ""
        let isAlgNone = alg.lowercased() == "none"

        // Missing standard claims
        let standardClaimNames = ["iss", "sub", "aud", "exp", "iat", "nbf"]
        let missingStandardClaims = standardClaimNames.filter { payload[$0] == nil }

        return JWTWarnings(
            isExpired: isExpired,
            isAlgNone: isAlgNone,
            missingStandardClaims: missingStandardClaims
        )
    }

    // MARK: - Human-readable expiry description

    /// Returns a human-readable description of the expiry status.
    /// e.g. "Expires in ~1h 2m" or "Expired 3h 15m ago"
    static func expiryDescription(_ status: JWTExpiryStatus) -> String {
        switch status {
        case .noExpiry:
            return "No expiry claim"
        case .valid(let remaining):
            return "Expires in \(formatDuration(remaining))"
        case .expired(let since):
            return "Expired \(formatDuration(since)) ago"
        }
    }

    // MARK: - Private helpers

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute, .second]
        formatter.maximumUnitCount = 2
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds) ?? "\(Int(seconds))s"
    }
}
