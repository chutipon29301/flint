// UI/ToolHeaderView.swift
// Back-to-picker header (D-02) — sits at the top of every tool view, wrapping tool.makeView().
// Stateless: caller (MenuBarPopoverView) owns onBack callback which sets navigationState = .root.
//
// Layout: HStack (back button | centered tool name | invisible spacer) + Divider()
// Back button: chevron.left + "All Tools" in .spark at 13pt regular
// Tool name: detailHeading (16pt semibold) .chalk, .accessibilityAddTraits(.isHeader) for VoiceOver orientation
// Minimum height: 44pt (standard hit-target rule)
//
// Design: 04-UI-SPEC.md § "Back-to-Picker Affordance — D-02"
// Pattern: UI/Components/DetectionBannerView.swift (stateless HStack + 12pt/8pt padding)
// Colors: Core/DesignSystem.swift tokens (spark back link, chalk title, graphite800 divider)

import SwiftUI

struct ToolHeaderView: View {
    let toolName: String
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Leading: back button — chevron.left + "All Tools" in accent color
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13))
                        Text("All Tools")
                            .font(.system(size: 13))
                    }
                    .foregroundColor(.spark)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to tool picker")

                // Center: tool name (heading landmark for VoiceOver)
                Text(toolName)
                    .font(.detailHeading)
                    .foregroundColor(.chalk)
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.isHeader)

                // Trailing: invisible spacer mirroring the back-button width to balance the title
                // Uses a hidden clone of the back button content to match width automatically.
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13))
                    Text("All Tools")
                        .font(.system(size: 13))
                }
                .hidden()
                .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 12)

            Divider()
                .overlay(Color.graphite800)
        }
    }
}
