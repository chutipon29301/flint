// Tools/Regex/RegexViewModel.swift
// Stub — will be implemented in Task 2.
import Foundation
import Observation

@Observable
@MainActor
final class RegexViewModel: ToolShortcutActions {
    var pattern: String = ""
    var testString: String = ""
    var flags: Set<RegexFlag> = []
    var template: String = ""
    var replaceMode: Bool = false
    var matches: [RegexMatch] = []
    var matchCountText: String = ""
    var substitutionPreview: String = ""
    var outputDimmed: Bool = false
    var errorMessage: String? = nil
    var timedOut: Bool = false

    private let onSaveHistory: (HistoryEntry) -> Void

    init(onSaveHistory: @escaping (HistoryEntry) -> Void) {
        self.onSaveHistory = onSaveHistory
    }

    func primaryOutput() -> String? { nil }
    func clearInput() {
        pattern = ""
        testString = ""
    }
}
