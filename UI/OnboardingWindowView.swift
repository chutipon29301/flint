// UI/OnboardingWindowView.swift
// First-run welcome window (DIST-03, D-07). Shown ONCE on first launch via the
// WindowCoordinator activation-policy dance (appears above the frontmost app).
//
// Its real job is the "where did it go?" problem of a no-Dock-icon menubar app:
//  1. points at the menubar wrench icon,
//  2. teaches the ⌘⇧Space global hotkey,
//  3. offers one CTA to enable Launch at Login — reusing the existing
//     PreferencesStore.launchAtLogin SMAppService path (INFRA-13, no new launch code).
//
// Single non-carousel layout (D-07). Every dismiss path sets hasSeenOnboarding=true so
// the window never reappears. Restores the .accessory activation policy on close via
// WindowCoordinator.windowWillClose() (analog: UI/PreferencesView.swift).
//
// Accessibility (INFRA-15): every Text/Button carries a VoiceOver-readable label; decorative
// SF Symbols are .accessibilityHidden(true). Logical reading order: headline → step bodies →
// CTA → Skip. Background/text stay system semantic (windowBackground, primary, secondary —
// this window is intentionally light/dark adaptive, unlike the graphite popover). The one
// primary CTA uses DesignSystem's PrimaryButtonStyle (spark fill) per the redesign brief's
// "scalpel" rule; step icons stay `.secondary` so spark isn't diluted across 4 bullets
// (260704-mgn task 5 — accent-inheriting controls fix).
//
// Source: UI-SPEC.md § "Copywriting → Onboarding Window" (exact copy), § "Typography",
// § "Spacing"; 03-PATTERNS.md "OnboardingWindowView.swift".

import SwiftUI

struct OnboardingWindowView: View {
    @Environment(PreferencesStore.self) private var prefs
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var prefs = prefs

        VStack(alignment: .leading, spacing: 16) {
            // Headline (Display 20pt semibold)
            Text("Welcome to Flint")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.primary)
                .accessibilityAddTraits(.isHeader)

            // Step 1: menubar callout
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 22))
                    .foregroundColor(.secondary)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Flint lives in your menubar")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("Look for the wrench icon in the menu bar at the top of your screen. Click it to open Flint anytime.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Step 2: global hotkey teach
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "command")
                    .font(.system(size: 22))
                    .foregroundColor(.secondary)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Open Flint from anywhere")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("Press ⌘⇧Space in any app to instantly open Flint — no switching needed.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Step 3: Services menu (D-06)
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "text.cursor")
                    .font(.system(size: 22))
                    .foregroundColor(.secondary)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Route text from any app")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("Select text anywhere, right-click, and choose Services > Open in Flint to process it instantly.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Step 4: Drag-and-drop (D-06)
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 22))
                    .foregroundColor(.secondary)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Drag files directly")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("Drop a text or binary file onto any tool — Base64 and Hash accept any file type.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)

            // Actions
            VStack(spacing: 8) {
                if prefs.launchAtLogin {
                    // Already enabled (e.g. re-triggered) — primary becomes the sole "Get Started".
                    Button("Get Started") {
                        finish()
                    }
                    .buttonStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Get started using Flint")
                } else {
                    // Primary CTA: enable Launch at Login via the existing SMAppService path.
                    Button("Enable Launch at Login") {
                        prefs.launchAtLogin = true   // existing PreferencesStore SMAppService path (INFRA-13)
                        finish()
                    }
                    .buttonStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Enable Flint to launch automatically at login")

                    // Secondary: dismiss without enabling launch-at-login.
                    Button("Get Started") {
                        finish()
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Get started using Flint")
                }

                Button("Skip") {
                    finish()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .accessibilityLabel("Skip onboarding")
            }
        }
        .padding(24)
        .frame(width: 480, height: 480)
        .background(Color(NSColor.windowBackgroundColor))
        // Task 5 (260704-mgn follow-up): tint ONCE at the onboarding scene root (no Toggle/Picker
        // present today, but this keeps any future inherited-accent control ember by default).
        .tint(Color.spark)
        .onDisappear {
            // Restore .accessory activation policy when the window closes (mirrors PreferencesView).
            WindowCoordinator.shared.windowWillClose()
        }
    }

    /// Every dismiss path: mark onboarding seen so it never reappears, then close the window.
    private func finish() {
        prefs.hasSeenOnboarding = true
        dismiss()
    }
}

#Preview {
    OnboardingWindowView()
        .environment(PreferencesStore())
}
