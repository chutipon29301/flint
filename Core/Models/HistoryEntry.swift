// Core/Models/HistoryEntry.swift
// GRDB record for the persistent history store.
// SECURITY (INFRA-09, T-01-ID): Only id/tool/input/output/timestamp/pinned are stored.
// NO secret column exists by design — JWT HMAC keys and Hash HMAC keys are NEVER persisted.
// Source: RESEARCH.md Pattern 4 [VERIFIED]

import GRDB
import Foundation

struct HistoryEntry: Codable, FetchableRecord, PersistableRecord, Sendable {
    var id: Int64?
    var tool: String
    var input: String       // NEVER includes HMAC/JWT secrets — enforced at ViewModel layer
    var output: String
    var timestamp: Date
    var pinned: Bool

    // GRDB table name
    static let databaseTableName = "historyEntry"

    init(id: Int64? = nil,
         tool: String,
         input: String,
         output: String,
         timestamp: Date = Date(),
         pinned: Bool = false) {
        self.id = id
        self.tool = tool
        self.input = input
        self.output = output
        self.timestamp = timestamp
        self.pinned = pinned
    }
}
