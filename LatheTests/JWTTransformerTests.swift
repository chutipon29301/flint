// LatheTests/JWTTransformerTests.swift
// Unit tests for JWTTransformer — covers JWT-01..06 + INFRA-17 no-crash guarantee.
// TDD: Tests written against the behavior spec before implementation.
// Regression tests for pitfall #4 (base64url -/_ decode) and pitfall #11 (timezone).

import XCTest
import CryptoKit
@testable import Lathe

final class JWTTransformerTests: XCTestCase {

    // MARK: - JWT-01: Data.fromBase64URL extension (Pitfall #4 regression)

    /// Pitfall #4 regression: segment containing "-" and "_" must decode to non-nil Data.
    func testFromBase64URL_withDashAndUnderscore_returnsNonNil() {
        // "dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U" contains "_"
        let urlSafeSegment = "dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U"
        let result = Data.fromBase64URL(urlSafeSegment)
        XCTAssertNotNil(result, "fromBase64URL must handle '_' without returning nil (pitfall #4)")
    }

    func testFromBase64URL_standardSegment_decodesCorrectly() {
        // "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9" = {"alg":"HS256","typ":"JWT"}
        let header = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
        let data = Data.fromBase64URL(header)
        XCTAssertNotNil(data, "Standard base64url header segment should decode")
        if let data {
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            XCTAssertEqual(json?["alg"] as? String, "HS256")
            XCTAssertEqual(json?["typ"] as? String, "JWT")
        }
    }

    func testFromBase64URL_emptyString_returnsEmptyOrNilData() {
        // Empty base64url decodes to empty data (not nil) — acceptable either way
        let result = Data.fromBase64URL("")
        // Either nil or empty Data is fine for empty input
        if let data = result {
            XCTAssertEqual(data.count, 0, "Empty base64url should decode to empty Data")
        }
    }

    // MARK: - JWT-01: Full decode — header, payload, signature (Pitfall #4 vector)

    /// Pitfall #4 regression: full decode of real JWT with "_" in signature must succeed.
    func testDecode_realJWTWithUrlSafeChars_returnsHeaderAndPayload() {
        // Token from pitfall #4: signature segment contains "_"
        let token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U"
        let result = JWTTransformer.decode(token)
        guard case .success(let jwt) = result else {
            XCTFail("Expected success, got \(result) — pitfall #4 regression: '_' in JWT signature")
            return
        }
        XCTAssertEqual(jwt.header["alg"] as? String, "HS256", "alg must be HS256")
        XCTAssertEqual(jwt.header["typ"] as? String, "JWT", "typ must be JWT")
        XCTAssertEqual(jwt.payload["sub"] as? String, "1234567890", "sub must be 1234567890")
    }

    func testDecode_validJWT_returnsHeaderPayloadAndSignature() {
        // JWT.io default HS256 token with name and iat
        let token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        let result = JWTTransformer.decode(token)
        guard case .success(let jwt) = result else {
            XCTFail("Expected success decoding valid JWT, got \(result)")
            return
        }
        XCTAssertEqual(jwt.header["alg"] as? String, "HS256")
        XCTAssertEqual(jwt.header["typ"] as? String, "JWT")
        XCTAssertEqual(jwt.payload["sub"] as? String, "1234567890")
        XCTAssertEqual(jwt.payload["name"] as? String, "John Doe")
        XCTAssertFalse(jwt.signature.isEmpty, "Signature segment must be captured")
    }

    // MARK: - JWT-01: Malformed token — no crash (INFRA-17)

    func testDecode_onlyTwoSegments_returnsFailure() {
        let malformed = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjMifQ"
        let result = JWTTransformer.decode(malformed)
        guard case .failure = result else {
            XCTFail("Expected failure for 2-segment token, got \(result)")
            return
        }
    }

    func testDecode_emptyString_returnsFailureNoCrash() {
        let result = JWTTransformer.decode("")
        guard case .failure = result else {
            XCTFail("Expected failure for empty token, got \(result)")
            return
        }
    }

    func testDecode_tooManySegments_returnsFailureNoCrash() {
        let result = JWTTransformer.decode("a.b.c.d.e.f")
        // Must not crash; failure is expected for 6-segment input
        guard case .failure = result else {
            XCTFail("Expected failure for 6-segment string, got \(result)")
            return
        }
    }

    // MARK: - JWT-03: Expiry status — timezone-correct (Pitfall #11)

    /// Pitfall #11 regression: exp = now+3600 must return .valid with ~3600s remaining.
    /// Uses Date(timeIntervalSince1970:), not timeIntervalSinceReferenceDate.
    func testExpiryStatus_futureExp_returnsValid() {
        let futureExp = Date().timeIntervalSince1970 + 3600.0  // 1 hour from now
        let payload: [String: Any] = ["exp": futureExp]
        let status = JWTTransformer.expiryStatus(payload: payload)
        guard case .valid(let remaining) = status else {
            XCTFail("Expected .valid for future exp, got \(status) — check timeIntervalSince1970 vs timeIntervalSinceReferenceDate (pitfall #11)")
            return
        }
        // Should be approximately 3600s remaining (allow ±10s for test execution time)
        XCTAssertGreaterThan(remaining, 3590.0, "Remaining time must be ~3600s not ~31 years (pitfall #11)")
        XCTAssertLessThan(remaining, 3601.0, "Remaining time must be ~3600s")
    }

    /// Pitfall #11 regression: if timeIntervalSinceReferenceDate was used, exp would show
    /// "31 years" instead of "~1h". This test catches that implementation error.
    func testExpiryStatus_futureExp_isNotThirtyOneYears() {
        let futureExp = Date().timeIntervalSince1970 + 3600.0
        let payload: [String: Any] = ["exp": futureExp]
        let status = JWTTransformer.expiryStatus(payload: payload)
        guard case .valid(let remaining) = status else {
            XCTFail("Expected .valid, got \(status)")
            return
        }
        // 31 years ≈ 978,307,200s — using timeIntervalSinceReferenceDate gives ~this result for a "now+1h" exp
        let thirtyOneYearsApprox = 978_000_000.0
        XCTAssertLessThan(remaining, thirtyOneYearsApprox * 0.001,
                          "Remaining time must not be ~31 years — ensure Date(timeIntervalSince1970:) is used (pitfall #11)")
    }

    func testExpiryStatus_pastExp_returnsExpired() {
        let pastExp = Date().timeIntervalSince1970 - 3600.0  // 1 hour ago
        let payload: [String: Any] = ["exp": pastExp]
        let status = JWTTransformer.expiryStatus(payload: payload)
        guard case .expired(let ago) = status else {
            XCTFail("Expected .expired for past exp, got \(status)")
            return
        }
        XCTAssertGreaterThan(ago, 3590.0, "Expired-ago should be ~3600s")
    }

    func testExpiryStatus_noExpClaim_returnsNoExpiry() {
        let payload: [String: Any] = ["sub": "123", "name": "Test"]
        let status = JWTTransformer.expiryStatus(payload: payload)
        guard case .noExpiry = status else {
            XCTFail("Expected .noExpiry for payload without exp, got \(status)")
            return
        }
    }

    // MARK: - JWT-04: HMAC signature verification

    func testVerifyHMAC_HS256_correctSecret_returnsTrue() {
        // Standard HS256 test vector from JWT.io
        // Secret: "your-256-bit-secret"
        let token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        let result = JWTTransformer.verifyHMAC(token: token, secret: "your-256-bit-secret", algorithm: "HS256")
        XCTAssertTrue(result, "verifyHMAC must return true for correct HS256 secret")
    }

    func testVerifyHMAC_HS256_wrongSecret_returnsFalse() {
        let token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        let result = JWTTransformer.verifyHMAC(token: token, secret: "wrong-secret", algorithm: "HS256")
        XCTAssertFalse(result, "verifyHMAC must return false for wrong secret")
    }

    func testVerifyHMAC_HS256_tamperedPayload_returnsFalse() {
        // Change payload segment to tamper the token
        let tampered = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI5OTk5OTk5OTk5In0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        let result = JWTTransformer.verifyHMAC(token: tampered, secret: "your-256-bit-secret", algorithm: "HS256")
        XCTAssertFalse(result, "verifyHMAC must return false for tampered payload")
    }

    func testVerifyHMAC_HS384_correctSecret_returnsTrue() {
        // Build a self-consistent HS384 token inline to avoid external dependency
        let headerB64 = "eyJhbGciOiJIUzM4NCIsInR5cCI6IkpXVCJ9"   // {"alg":"HS384","typ":"JWT"}
        let payloadB64 = "eyJzdWIiOiIxMjMifQ"                       // {"sub":"123"}
        let message = "\(headerB64).\(payloadB64)"
        let secret = "test-secret-384"
        let key = SymmetricKey(data: Data(secret.utf8))
        let mac = HMAC<SHA384>.authenticationCode(for: Data(message.utf8), using: key)
        let sigB64 = Data(mac).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let token = "\(message).\(sigB64)"
        XCTAssertTrue(JWTTransformer.verifyHMAC(token: token, secret: secret, algorithm: "HS384"),
                      "verifyHMAC must return true for correct HS384 token/secret pair")
    }

    func testVerifyHMAC_HS512_correctSecret_returnsTrue() {
        // Build a self-consistent HS512 token inline
        let headerB64 = "eyJhbGciOiJIUzUxMiIsInR5cCI6IkpXVCJ9"   // {"alg":"HS512","typ":"JWT"}
        let payloadB64 = "eyJzdWIiOiI0NTYifQ"                       // {"sub":"456"}
        let message = "\(headerB64).\(payloadB64)"
        let secret = "test-secret-512"
        let key = SymmetricKey(data: Data(secret.utf8))
        let mac = HMAC<SHA512>.authenticationCode(for: Data(message.utf8), using: key)
        let sigB64 = Data(mac).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let token = "\(message).\(sigB64)"
        XCTAssertTrue(JWTTransformer.verifyHMAC(token: token, secret: secret, algorithm: "HS512"),
                      "verifyHMAC must return true for correct HS512 token/secret pair")
    }

    func testVerifyHMAC_unknownAlgorithm_returnsFalse() {
        let token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U"
        let result = JWTTransformer.verifyHMAC(token: token, secret: "secret", algorithm: "RS256")
        XCTAssertFalse(result, "Unknown algorithm must return false, not crash")
    }

    // MARK: - JWT-05: Claim partition

    func testClaimsPartition_standardClaims_separatedCorrectly() {
        let now = Date().timeIntervalSince1970
        let payload: [String: Any] = [
            "iss": "https://example.com",
            "sub": "1234567890",
            "aud": "api.example.com",
            "exp": now + 3600,
            "iat": now,
            "nbf": now,
            "custom_claim": "custom_value",
            "role": "admin"
        ]
        let header: [String: Any] = ["alg": "HS256", "typ": "JWT"]
        let partition = JWTTransformer.partitionClaims(payload: payload, header: header)

        XCTAssertNotNil(partition.standard["iss"], "iss is a standard claim")
        XCTAssertNotNil(partition.standard["sub"], "sub is a standard claim")
        XCTAssertNotNil(partition.standard["aud"], "aud is a standard claim")
        XCTAssertNotNil(partition.standard["exp"], "exp is a standard claim")
        XCTAssertNotNil(partition.standard["iat"], "iat is a standard claim")
        XCTAssertNotNil(partition.standard["nbf"], "nbf is a standard claim")

        XCTAssertNotNil(partition.custom["custom_claim"], "custom_claim should be in custom")
        XCTAssertNotNil(partition.custom["role"], "role should be in custom")

        XCTAssertEqual(partition.algorithm, "HS256", "Algorithm must be read from header alg field")
    }

    func testClaimsPartition_emptyPayload_returnsEmptyPartitions() {
        let payload: [String: Any] = [:]
        let header: [String: Any] = ["alg": "HS256"]
        let partition = JWTTransformer.partitionClaims(payload: payload, header: header)
        XCTAssertTrue(partition.standard.isEmpty, "Standard claims should be empty")
        XCTAssertTrue(partition.custom.isEmpty, "Custom claims should be empty")
    }

    // MARK: - JWT-06: Warning flags

    func testWarnings_expiredToken_flagsExpired() {
        let pastExp = Date().timeIntervalSince1970 - 100
        let payload: [String: Any] = ["exp": pastExp, "sub": "123"]
        let header: [String: Any] = ["alg": "HS256"]
        let warnings = JWTTransformer.warnings(payload: payload, header: header)
        XCTAssertTrue(warnings.isExpired, "Expired token must set isExpired = true")
    }

    func testWarnings_validToken_doesNotFlagExpired() {
        let futureExp = Date().timeIntervalSince1970 + 3600
        let payload: [String: Any] = ["exp": futureExp, "sub": "123"]
        let header: [String: Any] = ["alg": "HS256"]
        let warnings = JWTTransformer.warnings(payload: payload, header: header)
        XCTAssertFalse(warnings.isExpired, "Valid (non-expired) token must not flag isExpired")
    }

    func testWarnings_algNone_flagsAlgNone() {
        let payload: [String: Any] = ["sub": "123"]
        let header: [String: Any] = ["alg": "none"]
        let warnings = JWTTransformer.warnings(payload: payload, header: header)
        XCTAssertTrue(warnings.isAlgNone, "alg:none must trigger the algNone warning (JWT-06)")
    }

    func testWarnings_algHS256_doesNotFlagAlgNone() {
        let payload: [String: Any] = ["sub": "123"]
        let header: [String: Any] = ["alg": "HS256"]
        let warnings = JWTTransformer.warnings(payload: payload, header: header)
        XCTAssertFalse(warnings.isAlgNone, "alg:HS256 must not trigger the algNone warning")
    }

    func testWarnings_missingStandardClaims_listsThemAll() {
        let payload: [String: Any] = ["custom": "value"]
        let header: [String: Any] = ["alg": "HS256"]
        let warnings = JWTTransformer.warnings(payload: payload, header: header)
        XCTAssertTrue(warnings.missingStandardClaims.contains("iss"), "iss should be listed as missing")
        XCTAssertTrue(warnings.missingStandardClaims.contains("sub"), "sub should be listed as missing")
        XCTAssertTrue(warnings.missingStandardClaims.contains("exp"), "exp should be listed as missing")
    }

    func testWarnings_allStandardClaimsPresent_missingIsEmpty() {
        let now = Date().timeIntervalSince1970
        let payload: [String: Any] = [
            "iss": "https://example.com",
            "sub": "123",
            "aud": "client",
            "exp": now + 3600,
            "iat": now,
            "nbf": now
        ]
        let header: [String: Any] = ["alg": "HS256"]
        let warnings = JWTTransformer.warnings(payload: payload, header: header)
        XCTAssertTrue(warnings.missingStandardClaims.isEmpty,
                      "All standard claims present — missing list must be empty")
    }

    // MARK: - JWT-02: Pretty-print reuse

    func testPrettyPrintPayload_validDict_returnsFormattedJSON() {
        let payload: [String: Any] = ["sub": "123", "name": "Alice"]
        let result = JWTTransformer.prettyPrintPayload(payload)
        XCTAssertNotNil(result, "prettyPrintPayload must produce non-nil output for valid dict")
        if let json = result {
            XCTAssertTrue(json.contains("sub") || json.contains("name"), "Output should contain original keys")
            // Verify it's valid JSON
            let reparsed = try? JSONSerialization.jsonObject(with: Data(json.utf8))
            XCTAssertNotNil(reparsed, "prettyPrintPayload output must be valid JSON")
        }
    }

    // MARK: - INFRA-17: No crash on garbage input

    func testDecode_randomGarbage_doesNotCrash() {
        let garbage = "garbage.garbage.garbage"
        let result = JWTTransformer.decode(garbage)
        _ = result  // Must not crash
    }

    func testDecode_veryLongToken_doesNotCrash() {
        let longPart = String(repeating: "a", count: 10_000)
        let result = JWTTransformer.decode("\(longPart).\(longPart).\(longPart)")
        _ = result  // Must not crash or hang
    }
}
