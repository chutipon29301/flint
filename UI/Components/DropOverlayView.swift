// UI/Components/DropOverlayView.swift
// Stateless full-surface drag-over overlay (DIST-02, D-05). Shown via the parent's
// `.onDrop(of: [.fileURL], isTargeted:)` binding while a file is dragged over the surface.
//
// DESIGN (checker WARNING 5): this overlay has a SINGLE valid drag-over state — there is no
// rejected-style visual. `.onDrop(of: [.fileURL])` accepts all file URLs during a drag; whether
// a file is text vs binary is only known AFTER the drop completes (post UTF-8 decode). Drag-time
// rejection styling would therefore be dead code with no wiring. Rejection feedback is surfaced
// POST-DROP via WarningBannerView (D-06), never via this overlay.
//
// Source: UI-SPEC.md § "Color" (Phase 3 new semantic — accentColor.opacity(0.08) fill, 2pt accent
// border, cornerRadius 8), § "Copywriting → Drag-and-Drop", § "Interaction → Drag-and-Drop".
// Analog: UI/Components/WarningBannerView.swift (stateless struct + semantic color + a11y shape).

import SwiftUI

struct DropOverlayView: View {
    /// Contextual label ("Drop to load file" for binary tools, "Drop to open in best tool" for the launcher).
    let label: String

    var body: some View {
        ZStack {
            Color.accentColor.opacity(0.08)

            VStack(spacing: 8) {
                Image(systemName: "doc.fill.badge.plus")
                    .font(.system(size: 32))
                    .foregroundColor(.accentColor)
                    .accessibilityHidden(true)

                Text(label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor, lineWidth: 2)
        )
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }
}

#Preview {
    VStack {
        Text("Surface behind the overlay")
    }
    .frame(width: 480, height: 300)
    .overlay {
        DropOverlayView(label: "Drop to open in best tool")
    }
}
