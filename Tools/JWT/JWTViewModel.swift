// Tools/JWT/JWTViewModel.swift
// MVVM ViewModel for the JWT Decoder — owns debounce, decode state, HMAC verify trigger.
// SECURITY (INFRA-09, T-03-ID, pitfall #3):
//   The HMAC secret is NEVER a property of this ViewModel.
//   The secret is View-local @State in JWTView.
// Source: RESEARCH.md § "Native API Recipes" → "JWT Tool", Pattern 5

import Foundation
import Observation

@Observable
@MainActor
final class JWTViewModel: ToolShortcutActions {

    // MARK: - Observable State

    /// Raw JWT token input (live, 150ms debounce — D-10).
    var token: String = "" {
        didSet { scheduleTransform() }
    }

    /// Decoded header as pretty-printed JSON string (JWT-02).
    var headerJSON: String = ""

    /// Decoded payload as pretty-printed JSON string (JWT-02).
    var payloadJSON: String = ""

    /// Raw signature segment for display/copy (JWT-01).
    var signature: String = ""

    /// Expiry status (JWT-03, pitfall #11: timeIntervalSince1970).
    var expiryStatus: JWTExpiryStatus = .noExpiry

    /// Human-readable expiry description.
    var expiryDescription: String = ""

    /// Claims partition: standard vs custom + algorithm (JWT-05).
    var claimsPartition: JWTClaimsPartition? = nil

    /// Warning flags (JWT-06): expired, alg:none, missing standard claims.
    var warnings: JWTWarnings? = nil

    /// HMAC verification result — nil means not yet verified (JWT-04).
    var hmacVerified: Bool? = nil

    /// True while token input is invalid — dims output (D-11).
    var outputDimmed: Bool = false

    /// Inline error message (INFRA-17, D-11).
    var errorMessage: String? = nil

    // MARK: - Private

    private let debounce = Debounce()

    /// Stored decoded header/payload dictionaries for HMAC verify.
    private var decodedHeader: [String: Any] = [:]
    private var decodedPayload: [String: Any] = [:]

    // MARK: - Init

    init() {}

    // MARK: - Transform (D-10: 150ms debounce)

    private func scheduleTransform() {
        guard !token.isEmpty else {
            clearOutput()
            return
        }
        Task {
            await debounce.schedule(delay: .milliseconds(150)) { [weak self] in
                await self?.runTransform()
            }
        }
    }

    private func clearOutput() {
        headerJSON = ""
        payloadJSON = ""
        signature = ""
        expiryStatus = .noExpiry
        expiryDescription = ""
        claimsPartition = nil
        warnings = nil
        hmacVerified = nil
        outputDimmed = false
        errorMessage = nil
        decodedHeader = [:]
        decodedPayload = [:]
    }

    private func runTransform() {
        switch JWTTransformer.decode(token) {
        case .failure(let error):
            // D-11: keep last valid output visible but dimmed — do NOT clear output
            outputDimmed = true
            errorMessage = (error as? JWTError)?.errorDescription
                ?? "Not a valid JWT — expected 3 dot-separated segments"

        case .success(let jwt):
            // Store for later HMAC verify
            decodedHeader = jwt.header
            decodedPayload = jwt.payload

            // JWT-02: pretty-printed JSON for header and payload
            headerJSON = JWTTransformer.prettyPrintPayload(jwt.header) ?? "{}"
            payloadJSON = JWTTransformer.prettyPrintPayload(jwt.payload) ?? "{}"
            signature = jwt.signature

            // JWT-03: expiry status (pitfall #11: timeIntervalSince1970)
            expiryStatus = JWTTransformer.expiryStatus(payload: jwt.payload)
            expiryDescription = JWTTransformer.expiryDescription(expiryStatus)

            // JWT-05: claims partition
            claimsPartition = JWTTransformer.partitionClaims(payload: jwt.payload, header: jwt.header)

            // JWT-06: warnings
            warnings = JWTTransformer.warnings(payload: jwt.payload, header: jwt.header)

            // Reset HMAC state when token changes
            hmacVerified = nil

            outputDimmed = false
            errorMessage = nil
        }
    }

    // MARK: - ToolShortcutActions (INFRA-16)

    /// Returns the composite header+payload output, or nil when nothing is decoded.
    /// SECURITY (T-09-01, INFRA-09): sources ONLY decoded header/payload — never touches the
    /// HMAC secret (which is View-local @State and never enters this ViewModel).
    func primaryOutput() -> String? {
        guard !headerJSON.isEmpty || !payloadJSON.isEmpty, errorMessage == nil else { return nil }
        let composite = headerJSON + "\n---\n" + payloadJSON
        return composite.isEmpty ? nil : composite
    }

    /// Clears the token input field (triggers scheduleTransform via didSet).
    /// SECURITY: the HMAC secret is NOT cleared here — it is View-local @State, never stored here.
    func clearInput() {
        token = ""
    }

    // MARK: - HMAC Verify (JWT-04)

    /// Verifies the JWT signature with the given HMAC secret.
    /// SECURITY: The secret parameter is consumed here in-memory only.
    /// It is never stored as a property, never persisted.
    func verifyHMAC(secret: String) {
        guard !token.isEmpty, !secret.isEmpty else {
            hmacVerified = nil
            return
        }
        let algorithm = decodedHeader["alg"] as? String ?? "HS256"
        hmacVerified = JWTTransformer.verifyHMAC(token: token, secret: secret, algorithm: algorithm)
    }
}
