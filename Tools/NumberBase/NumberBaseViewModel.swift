// Tools/NumberBase/NumberBaseViewModel.swift
// STUB — will be fully implemented in Task 2.
import Foundation
import Observation

@Observable
@MainActor
final class NumberBaseViewModel: ToolShortcutActions {
    var pattern: UInt64 = 0
    var width: BitWidth = .w8
    var signed: Bool = false
    var overflowWarning: Bool = false
    var errorMessage: String? = nil
    var outputDimmed: Bool = false

    private let onSaveHistory: (HistoryEntry) -> Void

    init(onSaveHistory: @escaping (HistoryEntry) -> Void) {
        self.onSaveHistory = onSaveHistory
    }

    func primaryOutput() -> String? { nil }
    func clearInput() { pattern = 0 }
}
