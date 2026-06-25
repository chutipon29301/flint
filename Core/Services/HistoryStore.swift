// Core/Services/HistoryStore.swift
// GRDB-backed SQLite history store for the last 100 transformations.
// Opened off the main thread to protect the <500ms cold-start budget (Pitfall #6).
// Source: RESEARCH.md Pattern 4 [VERIFIED]

import GRDB
import Foundation
import Observation

@Observable
@MainActor
final class HistoryStore {
    private(set) var dbQueue: DatabaseQueue?
    private(set) var entries: [HistoryEntry] = []
    private var observation: AnyDatabaseCancellable?

    init() {
        // Kick off async database initialization — does NOT block main thread (Pitfall #6)
        Task { @MainActor in
            await self.initializeDatabase()
        }
    }

    private func initializeDatabase() async {
        do {
            // openDatabase() is nonisolated — Task.detached runs it off the main thread
            let queue = try await Task.detached(priority: .utility) {
                try HistoryStore.openDatabase()
            }.value
            dbQueue = queue
            startObservation(queue: queue)
        } catch {
            print("[HistoryStore] Failed to open database: \(error)")
        }
    }

    /// Opens the GRDB DatabaseQueue and runs migrations. Nonisolated for Task.detached.
    private nonisolated static func openDatabase() throws -> DatabaseQueue {
        let appSupport = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask,
                 appropriateFor: nil, create: true)
        let latheDir = appSupport.appendingPathComponent("Lathe", isDirectory: true)
        try FileManager.default.createDirectory(at: latheDir,
                                                withIntermediateDirectories: true)
        let dbURL = latheDir.appendingPathComponent("history.db")
        let queue = try DatabaseQueue(path: dbURL.path)

        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "historyEntry", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("tool", .text).notNull()
                t.column("input", .text).notNull()
                t.column("output", .text).notNull()
                t.column("timestamp", .datetime).notNull()
                t.column("pinned", .boolean).notNull().defaults(to: false)
            }
            try db.create(index: "historyEntry_on_timestamp",
                          on: "historyEntry",
                          columns: ["timestamp"],
                          ifNotExists: true)
        }
        try migrator.migrate(queue)
        return queue
    }

    private func startObservation(queue: DatabaseQueue) {
        // ValueObservation is @MainActor-friendly in GRDB 7
        // D-09: pinned items exempt from 100-item eviction cap
        observation = ValueObservation
            .tracking { db in
                try HistoryEntry
                    .order(Column("pinned").desc, Column("timestamp").desc)
                    .limit(200)   // fetch slightly over 100 for eviction pass
                    .fetchAll(db)
            }
            .start(in: queue,
                   scheduling: .async(onQueue: .main)) { error in
                print("[HistoryStore] Observation error: \(error)")
            } onChange: { [weak self] allEntries in
                // D-09: pinned items exempt from 100-item cap
                let pinned = allEntries.filter { $0.pinned }
                let unpinned = Array(allEntries.filter { !$0.pinned }.prefix(100))
                let sorted = (pinned + unpinned).sorted {
                    if $0.pinned != $1.pinned { return $0.pinned }
                    return $0.timestamp > $1.timestamp
                }
                Task { @MainActor [weak self] in
                    self?.entries = sorted
                }
            }
    }

    /// Save a history entry. Write is off-main, in GRDB's background queue.
    func save(_ entry: HistoryEntry) {
        guard let queue = dbQueue else { return }
        Task.detached(priority: .utility) {
            do {
                try await queue.write { db in
                    try entry.insert(db)
                }
            } catch {
                print("[HistoryStore] Save failed: \(error)")
            }
        }
    }

    /// Remove all unpinned items. Pinned items survive (D-09).
    func clearUnpinned() {
        guard let queue = dbQueue else { return }
        Task.detached(priority: .utility) {
            do {
                _ = try await queue.write { db in
                    try HistoryEntry.filter(Column("pinned") == false).deleteAll(db)
                }
            } catch {
                print("[HistoryStore] clearUnpinned failed: \(error)")
            }
        }
    }

    /// Pin or unpin an entry.
    func togglePin(entry: HistoryEntry) {
        guard let queue = dbQueue, let entryId = entry.id else { return }
        let newPinned = !entry.pinned
        Task.detached(priority: .utility) {
            do {
                _ = try await queue.write { db in
                    try db.execute(sql: "UPDATE historyEntry SET pinned = ? WHERE id = ?",
                                   arguments: [newPinned, entryId])
                }
            } catch {
                print("[HistoryStore] togglePin failed: \(error)")
            }
        }
    }

    /// Delete a single entry.
    func delete(entry: HistoryEntry) {
        guard let queue = dbQueue, let entryId = entry.id else { return }
        Task.detached(priority: .utility) {
            do {
                _ = try await queue.write { db in
                    try db.execute(sql: "DELETE FROM historyEntry WHERE id = ?",
                                   arguments: [entryId])
                }
            } catch {
                print("[HistoryStore] delete failed: \(error)")
            }
        }
    }
}
