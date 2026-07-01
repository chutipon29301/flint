// Tools/JWT/JWTView.swift
// JWT Decoder UI — live decode, expiry countdown, claims table, warnings, HMAC verify.
// SECURITY (INFRA-09, T-03-ID, pitfall #3):
//   The HMAC secret is View-local @State ONLY — it NEVER flows into JWTViewModel.
// Covers: JWT-01..06, D-10, D-11, D-12, INFRA-09

import SwiftUI
import AppKit

struct JWTView: View {
    @Environment(ToolSeed.self) private var toolSeed
    @State private var viewModel: JWTViewModel?

    var body: some View {
        Group {
            if let vm = viewModel {
                JWTContentView(viewModel: vm)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = JWTViewModel()
            }
            // DIST-02: launcher detect()-routing pre-fill. consume() is one-shot.
            if let seed = toolSeed.consume(for: "jwt-decoder") {
                viewModel?.token = seed
            }
        }
    }
}

// MARK: - Main Content

private struct JWTContentView: View {
    @Bindable var viewModel: JWTViewModel

    /// SECURITY (INFRA-09, pitfall #3): secret is View-local @State ONLY.
    /// It is never passed to viewModel and never persisted.
    @State private var hmacSecret: String = ""
    @State private var showVerifySection: Bool = false
    @State private var isDragTargeted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // Input field
                VStack(alignment: .leading, spacing: 4) {
                    Text("JWT Token")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.top, 8)

                    SyntaxEditorView(text: $viewModel.token, accessibilityLabel: "JWT token input")
                        .frame(minHeight: 60, maxHeight: 100)

                    // Inline error (D-11)
                    InlineErrorView(message: viewModel.errorMessage)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                }

                // Warning banners (JWT-06)
                if let w = viewModel.warnings, !viewModel.token.isEmpty, !viewModel.outputDimmed {
                    VStack(spacing: 4) {
                        if w.isExpired {
                            WarningBannerView(
                                message: "Token expired \(viewModel.expiryDescription.replacingOccurrences(of: "Expired ", with: "").replacingOccurrences(of: " ago", with: "") + " ago")",
                                severity: .error
                            )
                        }
                        if w.isAlgNone {
                            WarningBannerView(
                                message: "Warning: algorithm is 'none' — signature not verified",
                                severity: .warning
                            )
                        }
                        if !w.missingStandardClaims.isEmpty {
                            WarningBannerView(
                                message: "Missing standard claims: \(w.missingStandardClaims.joined(separator: ", "))",
                                severity: .warning
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }

                Divider()

                // Empty state — shown when no token has been entered (D-05)
                if viewModel.token.isEmpty {
                    Text("Paste or type content above")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                }

                // Decoded segments — shown when token is valid and decoded
                if !viewModel.headerJSON.isEmpty || !viewModel.payloadJSON.isEmpty {
                    // Header (JWT-02)
                    SegmentSection(
                        label: "Header",
                        content: viewModel.headerJSON,
                        isDimmed: viewModel.outputDimmed,
                        copyAccessibilityLabel: "Copy header JSON"
                    )

                    Divider()

                    // Payload (JWT-02)
                    SegmentSection(
                        label: "Payload",
                        content: viewModel.payloadJSON,
                        isDimmed: viewModel.outputDimmed,
                        copyAccessibilityLabel: "Copy payload JSON"
                    )

                    Divider()

                    // Signature (JWT-01)
                    SegmentSection(
                        label: "Signature",
                        content: viewModel.signature,
                        isDimmed: viewModel.outputDimmed,
                        copyAccessibilityLabel: "Copy signature"
                    )

                    Divider()

                    // Expiry countdown (JWT-03)
                    ExpirySection(
                        status: viewModel.expiryStatus,
                        description: viewModel.expiryDescription
                    )

                    Divider()

                    // Claims table (JWT-05)
                    if let partition = viewModel.claimsPartition {
                        ClaimsSection(partition: partition)
                        Divider()
                    }

                    // HMAC Verify (JWT-04)
                    // SECURITY (INFRA-09, pitfall #3): hmacSecret is @State local to this view.
                    // It never reaches viewModel. Verify is a method call only.
                    HMACVerifySection(
                        secret: $hmacSecret,
                        showSection: $showVerifySection,
                        verificationResult: viewModel.hmacVerified,
                        onVerify: {
                            // SECURITY: secret passed only to verifyHMAC() — transient in-memory call.
                            // Never stored in ViewModel as a property.
                            viewModel.verifyHMAC(secret: hmacSecret)
                        }
                    )
                }
            }
        }
        .navigationTitle("JWT Decoder")
        .toolShortcuts(viewModel)
        .fileDrop(
            isTargeted: $isDragTargeted,
            onText: { viewModel.token = $0 },
            onError: { viewModel.errorMessage = $0 }
        )
        .overlay {
            if isDragTargeted {
                DropOverlayView(label: "Drop to load")
                    .transition(.opacity.animation(.easeOut(duration: 0.15)))
            }
        }
    }
}

// MARK: - Segment Section (Header, Payload, Signature)

private struct SegmentSection: View {
    let label: String
    let content: String
    let isDimmed: Bool
    let copyAccessibilityLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                // Per-field copy (D-12, JWT-01, JWT-02)
                CopyButtonView(text: content)
                    .accessibilityLabel(copyAccessibilityLabel)
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            // D-11: dims to 40% opacity on error
            CodeDisplayView(code: content, language: "json")
                .opacity(isDimmed ? 0.4 : 1.0)
                .frame(minHeight: 60)
                .font(.system(size: 13, design: .monospaced))
                .padding(.horizontal, 4)
                .padding(.bottom, 8)
        }
    }
}

// MARK: - Expiry Section

private struct ExpirySection: View {
    let status: JWTExpiryStatus
    let description: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: expiryIcon)
                .foregroundColor(expiryColor)
                .font(.system(size: 13))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Expiry")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(expiryColor)
                    .accessibilityLabel("Expiry: \(description)")
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    private var expiryIcon: String {
        switch status {
        case .noExpiry:           return "clock"
        case .valid:              return "checkmark.circle"
        case .expired:            return "xmark.circle.fill"
        }
    }

    private var expiryColor: Color {
        switch status {
        case .noExpiry:           return .secondary
        case .valid:              return .green
        case .expired:            return .red
        }
    }
}

// MARK: - Claims Table (JWT-05)

private struct ClaimsSection: View {
    let partition: JWTClaimsPartition

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Claims")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Text("alg: \(partition.algorithm)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(4)
                    .accessibilityLabel("Algorithm: \(partition.algorithm)")
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // Standard claims
            if !partition.standard.isEmpty {
                Text("Standard (RFC 7519)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 2)

                ForEach(partition.standard.keys.sorted(), id: \.self) { key in
                    ClaimRow(key: key, value: claimDisplayValue(partition.standard[key]))
                }
            }

            // Custom claims
            if !partition.custom.isEmpty {
                Text("Custom")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, 6)
                    .padding(.bottom, 2)

                ForEach(partition.custom.keys.sorted(), id: \.self) { key in
                    ClaimRow(key: key, value: claimDisplayValue(partition.custom[key]))
                }
            }
        }
        .padding(.bottom, 8)
    }

    private func claimDisplayValue(_ value: Any?) -> String {
        guard let value else { return "" }
        if let str = value as? String { return str }
        if let num = value as? NSNumber { return num.stringValue }
        if let arr = value as? [Any],
           let data = try? JSONSerialization.data(withJSONObject: arr),
           let str = String(data: data, encoding: .utf8) { return str }
        if let dict = value as? [String: Any],
           let data = try? JSONSerialization.data(withJSONObject: dict),
           let str = String(data: data, encoding: .utf8) { return str }
        return String(describing: value)
    }
}

private struct ClaimRow: View {
    let key: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Text(key)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(minWidth: 60, alignment: .leading)

            Text(value)
                .font(.system(size: 12))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)

            // Per-field copy (D-12)
            CopyButtonView(text: value)
                .accessibilityLabel("Copy \(key)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
    }
}

// MARK: - HMAC Verify Section (JWT-04)
// SECURITY (INFRA-09, T-03-ID, pitfall #3):
//   The secret binding comes from JWTContentView's @State var hmacSecret.
//   The View-local @State never propagates to JWTViewModel as a property.
//   The onVerify closure calls JWTViewModel.verifyHMAC(secret:) — a transient in-memory call.

private struct HMACVerifySection: View {
    @Binding var secret: String
    @Binding var showSection: Bool
    let verificationResult: Bool?
    let onVerify: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { showSection.toggle() }) {
                HStack {
                    Text("Verify Signature")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Image(systemName: showSection ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .accessibilityLabel("Verify signature section")

            if showSection {
                HStack(spacing: 8) {
                    // SECURITY (INFRA-09, pitfall #3):
                    // SecureField prevents shoulder-surfing the secret.
                    // Placeholder text "Secret key (never saved)" per UI-SPEC copywriting contract.
                    // This @Binding wraps JWTContentView's @State — it NEVER enters JWTViewModel.
                    SecureField("Secret key (never saved)", text: $secret)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13))
                        .accessibilityLabel("HMAC secret key — never saved to history")

                    Button("Verify") {
                        onVerify()
                    }
                    .buttonStyle(.bordered)
                    .disabled(secret.isEmpty)
                    .accessibilityLabel("Verify HMAC signature")
                }
                .padding(.horizontal, 8)

                // Verification result display
                if let verified = verificationResult {
                    HStack(spacing: 6) {
                        Image(systemName: verified ? "checkmark.shield.fill" : "xmark.shield.fill")
                            .foregroundColor(verified ? .green : .red)
                            .accessibilityHidden(true)
                        Text(verified ? "Signature valid" : "Signature invalid")
                            .font(.system(size: 12))
                            .foregroundColor(verified ? .green : .red)
                            .accessibilityLabel(verified ? "Signature is valid" : "Signature is invalid")
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }
        }
    }
}

#Preview {
    JWTView()
        .frame(width: 480, height: 600)
}
