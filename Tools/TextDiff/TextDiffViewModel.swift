// Tools/TextDiff/TextDiffViewModel.swift
// @Observable ViewModel for the Text Diff tool.
// Owns debounced diff scheduling, jump navigation state, and history write.
// SECURITY (INFRA-09): Never imports GRDB. History write via injected onSaveHistory closure.

import Foundation
import Observation

// MARK: - View Mode

enum DiffViewMode: String, CaseIterable {
    case unified = "Unified"
    case sideBySide = "Side by Side"
}

// MARK: - Text Diff ViewModel

@Observable
@MainActor
final class TextDiffViewModel: ToolShortcutActions {

    // MARK: - Observable State (inputs)

    var original: String = "" {
        didSet { scheduleDiff() }
    }
    var changed: String = "" {
        didSet { scheduleDiff() }
    }
    var ignoreWhitespace: Bool = false {
        didSet { scheduleDiff() }
    }
    var ignoreCase: Bool = false {
        didSet { scheduleDiff() }
    }
    var viewMode: DiffViewMode = .unified

    // MARK: - Observable State (output)

    /// The latest diff result (nil until first diff computed).
    var result: DiffResult? = nil
    /// Current diff-hunk navigation index (0-based).
    var currentDiffIndex: Int = 0

    /// Human-readable status: nil = no result yet, "No differences found" if identical, else nil (results shown).
    var statusMessage: String? = nil

    // MARK: - Private

    private let onSaveHistory: (HistoryEntry) -> Void
    private let debounce = Debounce()

    // MARK: - Computed

    /// Number of diff hunks in the current result.
    var diffCount: Int {
        result?.diffHunkCount ?? 0
    }

    /// Clamped current diff index (1-based label = currentDiffIndex + 1).
    var currentDiffLabel: String {
        guard diffCount > 0 else { return "" }
        return "Diff \(min(currentDiffIndex + 1, diffCount)) of \(diffCount)"
    }

    // MARK: - Init

    init(onSaveHistory: @escaping (HistoryEntry) -> Void) {
        self.onSaveHistory = onSaveHistory
    }

    // MARK: - Scheduling

    private func scheduleDiff() {
        // Both fields empty → clear state
        guard !original.isEmpty || !changed.isEmpty else {
            result = nil
            currentDiffIndex = 0
            statusMessage = nil
            return
        }
        // Either field empty → show placeholder message
        guard !original.isEmpty && !changed.isEmpty else {
            result = nil
            currentDiffIndex = 0
            statusMessage = nil
            return
        }
        Task {
            await debounce.schedule(delay: .milliseconds(200)) { [weak self] in
                await self?.runDiff()
            }
        }
    }

    private func runDiff() {
        let diffResult = TextDiffTransformer.diff(
            original: original, changed: changed,
            ignoreWhitespace: ignoreWhitespace, ignoreCase: ignoreCase
        )
        result = diffResult
        currentDiffIndex = 0
        if diffResult.hasDiffs {
            statusMessage = nil
            // Save history on diff with changes
            onSaveHistory(HistoryEntry(
                tool: "text-diff",
                input: original + "\n---\n" + changed,
                output: diffResult.unifiedPatch,
                timestamp: Date(),
                pinned: false
            ))
        } else {
            statusMessage = "No differences found"
        }
    }

    // MARK: - Navigation (DIFF-03)

    /// Jump to the next diff hunk (wraps around).
    func nextDiff() {
        guard diffCount > 0 else { return }
        currentDiffIndex = (currentDiffIndex + 1) % diffCount
    }

    /// Jump to the previous diff hunk (wraps around).
    func prevDiff() {
        guard diffCount > 0 else { return }
        currentDiffIndex = (currentDiffIndex - 1 + diffCount) % diffCount
    }

    // MARK: - ToolShortcutActions (INFRA-16)

    /// ⌘⇧C copies the unified patch (empty patch when no changes).
    func primaryOutput() -> String? {
        guard let r = result, r.hasDiffs else { return nil }
        return r.unifiedPatch
    }

    /// ⌘⌫ clears both editors.
    func clearInput() {
        original = ""
        changed = ""
    }
}
