// Core/Services/SearchResultsMerger.swift
// Pure, UI-free merge and rank function for global fuzzy search (INFRA-10).
// Tools-only merge — history support removed (Phase 06: remove-the-history-feature).
// Zero SwiftUI imports — fully testable without UI infrastructure.
// Source: 01-06-PLAN.md Task 2 (acceptance: grep "import SwiftUI" == 0)

import Foundation

/// A single ranked search result — a tool.
enum SearchResult: Sendable {
    case tool(ToolDefinition)
}

/// Merged, ranked result set from a global fuzzy search query (INFRA-10).
struct MergedSearchResults: Sendable {
    let toolResults: [ToolDefinition]

    var isEmpty: Bool { toolResults.isEmpty }
}

/// Pure merge/rank function — no UI, no async, fully testable.
/// Accepts pre-fetched tool results and produces a ranked merged set.
/// Call from SearchView with results from ToolRegistry.search().
enum SearchResultsMerger {
    /// Merge tool results into a ranked MergedSearchResults.
    /// Tools are ranked first (name-exact > keyword-exact > contains).
    ///
    /// - Parameters:
    ///   - tools: Tool matches from ToolRegistry.search(query)
    ///   - query: The user's search string (used for rank scoring)
    /// - Returns: MergedSearchResults with ranked tools
    static func merge(
        tools: [ToolDefinition],
        query: String
    ) -> MergedSearchResults {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)

        // Rank tools: name exact match > name starts with > contains > keyword match
        let rankedTools = tools.sorted { a, b in
            let aNameLower = a.name.lowercased()
            let bNameLower = b.name.lowercased()
            let aExact = aNameLower == q
            let bExact = bNameLower == q
            if aExact != bExact { return aExact }
            let aStarts = aNameLower.hasPrefix(q)
            let bStarts = bNameLower.hasPrefix(q)
            if aStarts != bStarts { return aStarts }
            return aNameLower < bNameLower
        }

        return MergedSearchResults(toolResults: rankedTools)
    }

    /// Empty-query default state: all tools.
    static func defaultState(allTools: [ToolDefinition]) -> MergedSearchResults {
        MergedSearchResults(toolResults: allTools)
    }
}
