// UI/Components/ToolShortcutActions.swift
// Shared protocol + view modifier for INFRA-16 keyboard shortcuts.
//
// INFRA-16 gap-closure: the producer side (MenuBarPopoverView) posts .copyOutput and .clearInput
// correctly, but no tool view had observers. This file wires the observer side in one place so
// all 7 tool content views can subscribe consistently via a single call:
//   .toolShortcuts(viewModel)
//
// Threat mitigations honoured here:
//   T-09-02 (DoS — empty output): primaryOutput() returns nil/empty → harmless no-op, never crash.
//   T-09-03 (broadcast to non-visible tool): only the mounted active tool view has a live
//            .onReceive subscription; backgrounded views are not in the view hierarchy.
//
// Notification names are declared in UI/MenuBarPopoverView.swift — NOT redeclared here.

import SwiftUI
import AppKit

// MARK: - Protocol

/// A tool ViewModel must conform to this protocol to participate in INFRA-16 keyboard shortcuts.
/// Both requirements are called on the MainActor (all tool ViewModels are @MainActor already).
@MainActor
protocol ToolShortcutActions: AnyObject {
    /// Returns the tool's primary copyable output, or nil/empty when there is nothing to copy.
    /// A nil or empty return is a harmless no-op — the shortcut never crashes (T-09-02).
    func primaryOutput() -> String?

    /// Clears the tool's primary input field(s).
    func clearInput()
}

// MARK: - View Modifier

/// Attaches INFRA-16 shortcut observers to a tool content view.
/// - Cmd+Shift+C: copies primaryOutput() to NSPasteboard.general (no-op if nil/empty).
/// - Cmd+Delete:  calls clearInput().
/// - Cmd+1:       copies primaryOutput() — row 1 = primary output for all single-output tools (D-08).
/// - Cmd+2…9:     silent no-op at this shared layer (multi-output tools wire their own observer).
@MainActor
private struct ToolShortcutsModifier<Actions: ToolShortcutActions>: ViewModifier {
    let actions: Actions

    func body(content: Content) -> some View {
        content
            // Cmd+Shift+C — copy active tool's primary output (INFRA-16)
            .onReceive(NotificationCenter.default.publisher(for: .copyOutput)) { _ in
                guard let text = actions.primaryOutput(), !text.isEmpty else {
                    // T-09-02: empty or nil — harmless no-op; never crash
                    return
                }
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(text, forType: .string)
            }
            // Cmd+Delete — clear active tool's input (INFRA-16)
            .onReceive(NotificationCenter.default.publisher(for: .clearInput)) { _ in
                actions.clearInput()
            }
            // Cmd+1–9 row copy (D-08): row 1 = primaryOutput() for all 12 tools via this shared
            // layer. Multi-output tools (Color/Hash/NumberBase) add their OWN .selectOutputRow
            // observer on their content view body, which handles indices 1–N for their specific
            // rows. For those three tools, both observers fire on ⌘1 — both produce the same
            // primary output, so the copy is idempotent (no corruption). Indices 2–9 at this
            // shared layer are silent no-ops (multi-output tool observer handles them).
            // Out-of-range or nil: harmless no-op — CF-01, T-04-06.
            .onReceive(NotificationCenter.default.publisher(for: .selectOutputRow)) { note in
                guard let index = note.userInfo?["index"] as? Int else { return }
                guard index == 1 else { return } // only row 1 handled at shared layer
                guard let text = actions.primaryOutput(), !text.isEmpty else { return }
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(text, forType: .string)
            }
    }
}

// MARK: - View Extension

extension View {
    /// Attaches INFRA-16 shortcut observers (Cmd+Shift+C / Cmd+Delete) to a tool content view.
    /// Call this on the root container of a tool's body, passing the tool's @Bindable viewModel.
    ///
    ///     .toolShortcuts(viewModel)
    ///
    /// The viewModel must conform to `ToolShortcutActions`. Since @Observable classes are reference
    /// types, the modifier captures it directly — no Equatable conformance required.
    @MainActor
    func toolShortcuts<A: ToolShortcutActions>(_ actions: A) -> some View {
        modifier(ToolShortcutsModifier(actions: actions))
    }
}
