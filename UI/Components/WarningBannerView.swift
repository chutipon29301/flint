// UI/Components/WarningBannerView.swift
// JWT/general warning banner row. Severity-tinted, palette-harmonized (rose-red = error,
// muted gold = warning — deliberately duller than the `spark` accent so it stays special).
// Source: UI-SPEC.md § "Component Inventory" (WarningBannerView), § "Color" (JWT warnings)
// Covers: JWT-06 (expired/alg:none/missing-claims banners)

import SwiftUI

enum BannerSeverity {
    case warning   // Muted gold — JWT alg:none, missing claims (JWT-06)
    case error     // Rose-red — JWT expired (JWT-06)
}

struct WarningBannerView: View {
    let message: String
    let severity: BannerSeverity

    private var iconName: String {
        switch severity {
        case .warning: return "exclamationmark.triangle.fill"
        case .error:   return "xmark.octagon.fill"
        }
    }

    private var tintColor: Color {
        switch severity {
        case .warning: return .warningText
        case .error:   return .errorText
        }
    }

    private var fillColor: Color {
        switch severity {
        case .warning: return .warningFill
        case .error:   return .errorFill
        }
    }

    private var borderColor: Color {
        switch severity {
        case .warning: return .warningBorder
        case .error:   return .errorBorder
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .foregroundColor(tintColor)
                .font(.system(size: 13))
                .accessibilityHidden(true)

            Text(message)
                .font(.system(size: 12))
                .foregroundColor(.chalk)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Radius.control)
                .fill(fillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.control)
                        .strokeBorder(borderColor, lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}

#Preview {
    VStack(spacing: 8) {
        WarningBannerView(message: "Token expired 3h 15m ago", severity: .error)
        WarningBannerView(message: "Warning: algorithm is 'none' — signature not verified", severity: .warning)
        WarningBannerView(message: "Missing standard claims: iss, sub, aud", severity: .warning)
    }
    .padding()
}
