// Tools/UUID/UUIDViewModel.swift
// @Observable ViewModel for the UUID Generator/Inspector tool.
// UUID-01: generate single/bulk v1/v4/v5/v7, button-triggered bulk (D-10)
// UUID-02: v7 via leodabus/UUIDv7 (approved package)
// UUID-03: inspect UUID live-debounced 150ms
// UUID-04: case toggle, export format selection

import SwiftUI
import Foundation

/// Which UUID version to generate.
enum UUIDVersion: String, CaseIterable, Sendable {
    case v1 = "v1 — Time-based"
    case v4 = "v4 — Random"
    case v5 = "v5 — Name-based"
    case v7 = "v7 — Time-ordered"
}

@Observable
@MainActor
final class UUIDViewModel: ToolShortcutActions {

    // MARK: - Generation (UUID-01)

    var selectedVersion: UUIDVersion = .v4
    var generateCount: Int = 1          // 1..1000
    var generatedUUIDs: [UUID] = []

    // v5 fields
    var v5Namespace: UUID = UUIDTransformer.namespaceDNS
    var v5Name: String = ""

    // MARK: - Case + export (UUID-04)

    var uppercase: Bool = false
    var exportFormat: UUIDTransformer.ExportFormat = .newline

    // MARK: - Inspect (UUID-03)

    var inspectInput: String = "" {
        didSet { scheduleInspect() }
    }
    var inspectResult: UUIDTransformer.UUIDInfo? = nil
    var inspectError: String? = nil

    // MARK: - Error

    var errorMessage: String? = nil

    // MARK: - Private

    private let debounce = Debounce()

    init() {}

    // MARK: - ToolShortcutActions (INFRA-16)

    /// Returns exportText() when UUIDs have been generated, otherwise nil.
    /// Honours exportFormat + uppercase (same as the visible Copy buttons).
    func primaryOutput() -> String? {
        generatedUUIDs.isEmpty ? nil : exportText()
    }

    /// Resets generation/inspection inputs.
    /// Leaves selectedVersion and uppercase as user preferences (per plan spec).
    func clearInput() {
        inspectInput = ""
        generatedUUIDs = []
        v5Name = ""
    }

    // MARK: - Generation (button-triggered for bulk per D-10)

    /// Generates UUIDs of the selected version. For bulk counts > 1, this is button-triggered.
    func generate() {
        errorMessage = nil
        let count = max(1, min(generateCount, 1000))
        switch selectedVersion {
        case .v1:
            generatedUUIDs = UUIDTransformer.generateV1(count: count)
        case .v4:
            generatedUUIDs = UUIDTransformer.generateV4(count: count)
        case .v5:
            guard !v5Name.isEmpty else {
                errorMessage = "Name field is required for v5 UUIDs."
                return
            }
            generatedUUIDs = (0..<count).map { _ in
                UUIDTransformer.generateV5(namespace: v5Namespace, name: v5Name)
            }
        case .v7:
            generatedUUIDs = UUIDTransformer.generateV7(count: count)
        }
    }

    // MARK: - Export (UUID-04)

    /// Returns the bulk export string for the current generated set.
    func exportText() -> String {
        UUIDTransformer.export(generatedUUIDs, format: exportFormat, uppercase: uppercase)
    }

    /// Returns a single UUID string with the current case toggle applied.
    func displayString(for uuid: UUID) -> String {
        let s = uuid.uuidString
        return uppercase ? s.uppercased() : s.lowercased()
    }

    // MARK: - Inspect (UUID-03, live-debounced 150ms)

    private func scheduleInspect() {
        inspectResult = nil
        inspectError = nil
        guard !inspectInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task {
            await debounce.schedule(delay: .milliseconds(150)) { [weak self] in
                await self?.runInspect()
            }
        }
    }

    private func runInspect() {
        let input = inspectInput
        if let info = UUIDTransformer.inspect(input) {
            inspectResult = info
            inspectError = nil
        } else {
            inspectResult = nil
            inspectError = "Not a valid UUID string."
        }
    }

    private func inspectSummary(_ info: UUIDTransformer.UUIDInfo) -> String {
        var parts = ["Version: \(info.version)", "Variant: \(info.variantDescription)"]
        if let ts = info.timestamp {
            parts.append("Timestamp: \(ts)")
        }
        return parts.joined(separator: " | ")
    }
}
