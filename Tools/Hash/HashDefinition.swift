// Tools/Hash/HashDefinition.swift
// Real Hash Generator definition — overwrites stub from 01-01.
// Hash has NO detection predicate — search-only tool, unpinned by default (D-13).
// ToolRegistry.swift is FROZEN — not edited here.

import SwiftUI

enum HashDefinition {
    static func make() -> ToolDefinition {
        ToolDefinition(
            id: "hash-generator",
            name: "Hash Generator",
            category: .analysis,
            keywords: ["hash", "md5", "sha", "sha1", "sha256", "sha512", "crc32", "hmac", "checksum", "digest"],
            sfSymbol: "number.square",
            detectionPredicate: nil,  // Hash is search-only per D-13 — no clipboard detection
            makeView: { @MainActor in
                AnyView(HashView())
            }
        )
    }
}
