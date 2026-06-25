// Tools/Hash/HashDefinition.swift
// STUB — Wave-2 plan 01-04 overwrites this file with the real Hash tool.
// DO NOT add implementation here. This stub allows ToolRegistry to compile.

import SwiftUI

enum HashDefinition {
    static func make() -> ToolDefinition {
        ToolDefinition(
            id: "hash-generator",
            name: "Hash Generator",
            category: .analysis,
            keywords: ["hash", "md5", "sha", "sha256", "sha512", "crc32", "hmac", "checksum"],
            sfSymbol: "number.square",
            detectionPredicate: nil,  // Hash has no clipboard detection predicate
            makeView: {
                AnyView(Text("Hash Generator — Coming Soon")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity))
            }
        )
    }
}
