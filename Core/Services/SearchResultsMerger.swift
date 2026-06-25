// Core/Services/SearchResultsMerger.swift
// Pure, UI-free merge and rank function for global fuzzy search (INFRA-10).
// Combines ToolRegistry tool matches with HistoryStore history matches.
// Zero SwiftUI imports — fully testable without UI infrastructure.
// Source: 01-06-PLAN.md Task 2 (acceptance: grep "import SwiftUI" == 0)

import Foundation

/// A single ranked search result — either a tool or a history entry.
enum SearchResult: Sendable {
    case tool(ToolDefinition)
    case historyEntry(HistoryEntry)
}

/// Merged, ranked result set from a global fuzzy search query (INFRA-10).
struct MergedSearchResults: Sendable {
    let toolResults: [ToolDefinition]
    let historyResults: [HistoryEntry]

    var isEmpty: Bool { toolResults.isEmpty && historyResults.isEmpty }
}

/// Pure merge/rank function — no UI, no async, fully testable.
/// Accepts pre-fetched tool and history results and produces a ranked merged set.
/// Call from SearchView with results from ToolRegistry.search() + HistoryStore.search().
enum SearchResultsMerger {
    /// Merge tool results and history results into a ranked MergedSearchResults.
    /// Tools are ranked first (name-exact > keyword-exact > contains).
    /// History entries are ranked by timestamp (most recent first, pinned on top).
    ///
    /// - Parameters:
    ///   - tools: Tool matches from ToolRegistry.search(query)
    ///   - history: History matches from HistoryStore.search(query)
    ///   - query: The user's search string (used for rank scoring)
    /// - Returns: MergedSearchResults with ranked tools and history
    static func merge(
        tools: [ToolDefinition],
        history: [HistoryEntry],
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

        // Rank history: pinned on top, then most recent first
        let rankedHistory = history.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            return a.timestamp > b.timestamp
        }

        return MergedSearchResults(
            toolResults: rankedTools,
            historyResults: Array(rankedHistory.prefix(10))
        )
    }

    /// Check if a query should trigger the history panel (D-07: search "history").
    static func isHistoryQuery(_ query: String) -> Bool {
        query.trimmingCharacters(in: .whitespaces).lowercased() == "history"
    }

    /// Empty-query default state: all tools + recent history (last 5).
    static func defaultState(allTools: [ToolDefinition], recentHistory: [HistoryEntry]) -> MergedSearchResults {
        MergedSearchResults(toolResults: allTools, historyResults: Array(recentHistory.prefix(5)))
    }
}
