// Core/Extensions/View+CopyButton.swift
// SwiftUI modifier that adds a copy button overlay to any view.
// Source: UI-SPEC.md § "Per-Field Copy Buttons" (D-12)

import SwiftUI
import AppKit

extension View {
    /// Adds a trailing copy button that copies `text` to the clipboard.
    /// Button shows checkmark for 1.5s (D-12).
    func copyButton(text: @escaping () -> String) -> some View {
        overlay(alignment: .trailing) {
            CopyButtonView(getText: text)
        }
    }
}
