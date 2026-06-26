// Tools/TextDiff/TextDiffViewModel.swift
// STUB — placeholder for TDD RED phase
import SwiftUI
import Observation

@Observable
@MainActor
final class TextDiffViewModel: ToolShortcutActions {
    var original: String = ""
    var changed: String = ""
    func primaryOutput() -> String? { nil }
    func clearInput() { original = ""; changed = "" }
}
