// Core/Services/FileDropHandler.swift
// Shared `.onDrop` helper for TEXT tools and the launcher (DIST-02, D-06).
//
// Resolves a dropped file URL off-main, reads it as UTF-8 (binary → rejection), and dispatches
// the result back on @MainActor via onText / onError. Binary tools (Base64, Hash) do NOT use this
// helper — they accept ANY file directly via their own permissive `.onDrop` calling the existing
// off-main chunked pipeline (no UTF-8 gate, no size cap — D-06).
//
// D-06 rejection model: the drag-over overlay is the single valid-state affordance; binary vs text
// and oversized are determined POST-DROP (UTF-8 decode + fileSizeKey), so rejection surfaces after
// the drop via WarningBannerView — never during the drag.
//
// Pitfall #4 (RESEARCH.md): use `url.lastPathComponent` for any display, never `url.path`.
// Source: RESEARCH.md Pattern 2 (onDrop/NSItemProvider), UI-SPEC.md § "Error States" (rejection copy).

import SwiftUI
import UniformTypeIdentifiers

extension View {
    /// Applies a text-oriented file drop: decodes the dropped file as UTF-8 off-main and routes the
    /// text to `onText`, or routes a binary / oversized / unreadable file to `onError` POST-DROP with
    /// the canonical UI-SPEC rejection copy (the caller surfaces it via WarningBannerView).
    ///
    /// - Parameters:
    ///   - isTargeted: drag-over binding driving the parent's DropOverlayView.
    ///   - onText: called on @MainActor with the decoded UTF-8 file contents.
    ///   - onError: called on @MainActor with a user-facing rejection message.
    func fileDrop(
        isTargeted: Binding<Bool>,
        onText: @escaping @MainActor @Sendable (String) -> Void,
        onError: @escaping @MainActor @Sendable (String) -> Void
    ) -> some View {
        self.onDrop(of: [.fileURL], isTargeted: isTargeted) { providers in
            guard let provider = providers.first else { return false }

            _ = provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                // loadItem completion runs off-main on an arbitrary queue.
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    Task { @MainActor in
                        onError("File contains non-text data and can't be loaded here. Try Base64 or Hash.")
                    }
                    return
                }

                // Size guard (D-06): 5MB text threshold — text tools only, NOT a universal cap.
                // Binary tools (Base64/Hash) bypass this helper entirely and stay uncapped.
                let textSizeThreshold = 5 * 1_024 * 1_024
                if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                   size > textSizeThreshold {
                    Task { @MainActor in
                        onError("File is too large to load as text. Try dropping into Hash for checksums.")
                    }
                    return
                }

                // UTF-8 decode off-main; binary content throws → post-drop rejection.
                Task {
                    do {
                        let text = try String(contentsOf: url, encoding: .utf8)
                        await MainActor.run { onText(text) }
                    } catch {
                        await MainActor.run {
                            onError("File contains non-text data and can't be loaded here. Try Base64 or Hash.")
                        }
                    }
                }
            }

            return true
        }
    }
}
