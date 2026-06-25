// UI/Components/WarningBannerView.swift
// JWT/general warning banner row. Severity-tinted (yellow = warning, red = error).
// Source: UI-SPEC.md § "Component Inventory" (WarningBannerView), § "Color" (JWT warnings)
// Covers: JWT-06 (expired/alg:none/missing-claims banners)

import SwiftUI

enum BannerSeverity {
    case warning   // Yellow background — JWT alg:none, missing claims (JWT-06)
    case error     // Red — JWT expired (JWT-06)
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
        case .warning: return .yellow
        case .error:   return .red
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
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tintColor.opacity(0.15))
        .cornerRadius(6)
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
