// UI/Components/CopyButtonView.swift
// Per-field copy button. doc.on.doc → checkmark for 1.5s (D-12).
// Source: UI-SPEC.md § "Per-Field Copy Buttons"

import SwiftUI
import AppKit

struct CopyButtonView: View {
    let getText: () -> String
    @State private var copied = false
    @State private var isHovered = false

    init(text: String) {
        self.getText = { text }
    }

    init(getText: @escaping () -> String) {
        self.getText = getText
    }

    var body: some View {
        Button(action: performCopy) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .foregroundColor(copied ? .success : (isHovered ? .spark : .ash))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(copied ? "Copied" : "Copy")
        .onHover { hovered in
            isHovered = hovered
        }
    }

    private func performCopy() {
        let text = getText()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copied = false
        }
    }
}

#Preview {
    CopyButtonView(text: "Hello, World!")
        .padding()
}
