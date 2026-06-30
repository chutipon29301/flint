// Tools/ImageCompress/ImageCompressDefinition.swift
// Image Compressor tool registration — mirrors HashDefinition.swift shape exactly.
// detectionPredicate: nil MANDATORY — image tool has no text to detect (like Hash, D-13 analog).
// T-05-09: nil predicate keeps this tool out of the clipboard detection chain (INFRA-06 chain integrity).

import SwiftUI

enum ImageCompressDefinition {
    static func make() -> ToolDefinition {
        ToolDefinition(
            id: "image-compress",
            name: "Image Compressor",
            category: .conversion,
            keywords: ["image", "compress", "jpeg", "png", "heic", "tiff", "optimize", "shrink", "photo"],
            sfSymbol: "photo",
            detectionPredicate: nil,  // MANDATORY — image tool, no clipboard detection (T-05-09)
            makeView: { @MainActor in
                AnyView(ImageCompressViewWrapper())
            }
        )
    }
}

// MARK: - Wrapper for environment-injected history store

private struct ImageCompressViewWrapper: View {
    @Environment(HistoryStore.self) private var historyStore

    var body: some View {
        ImageCompressView { entry in
            historyStore.save(entry)
        }
    }
}
