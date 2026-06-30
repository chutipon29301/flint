// Tools/ImageCompress/ImageCompressViewModel.swift
// @Observable @MainActor batch orchestrator for the Image Compressor tool.
// D-01: N dropped URLs → N CompressRow entries, each progressing .pending → .done/.failed.
// D-05: ImageFormatTag.isLossless gates the slider; per-row format tag set BEFORE compression.
// D-09: Live per-row updates via await MainActor.run { rows[i].apply(result) }.
// INFRA-17: Failed images become .failed rows; the batch never crashes on bad input.
// INFRA-18: Each image is compressed inside autoreleasepool in an off-main Task, bounding peak memory.
// T-05-06: HistoryEntry stores only filenames + aggregate savings — no secrets.

import Foundation
import SwiftUI

// MARK: - ImageFormatTag

/// Format classification for a dropped image — derived from the file URL extension BEFORE
/// compression begins so the View can gate the slider and render the format badge (D-05).
enum ImageFormatTag {
    case jpeg
    case heic
    case png
    case tiff
    case other

    /// UI-SPEC-exact display tag for the results table badge.
    var displayTag: String {
        switch self {
        case .jpeg:  return "JPEG"
        case .heic:  return "HEIC"
        case .png:   return "PNG · lossless"
        case .tiff:  return "TIFF · lossless"
        case .other: return "Image"
        }
    }

    /// True for lossless formats (PNG, TIFF). The quality slider does not apply (D-05).
    var isLossless: Bool {
        switch self {
        case .png, .tiff: return true
        default:          return false
        }
    }

    /// Derives the format tag from a file URL path extension (case-insensitive) BEFORE
    /// any compression takes place — used to render the format badge and gate the slider.
    static func from(url: URL) -> ImageFormatTag {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": return .jpeg
        case "heic", "heif": return .heic
        case "png":          return .png
        case "tif", "tiff":  return .tiff
        default:             return .other
        }
    }
}

// MARK: - CompressRowState

/// Live per-row state (D-09) — progresses pending → compressing → done/failed.
enum CompressRowState {
    case pending
    case compressing
    case done(ImageCompressTransformer.CompressedImage)
    case failed(reason: String)
}

// MARK: - CompressRow

/// View-data model for one entry in the results table (D-09).
/// Carries format tag so the View can render the lossless badge before compression (D-05).
struct CompressRow: Identifiable {
    let id = UUID()
    let sourceURL: URL
    var format: ImageFormatTag
    var state: CompressRowState

    init(sourceURL: URL, format: ImageFormatTag, state: CompressRowState = .pending) {
        self.sourceURL = sourceURL
        self.format = format
        self.state = state
    }

    /// Maps a compression result to a row state update.
    /// A failure is ALWAYS a `.failed` row — never a crash (INFRA-17).
    /// Uses the exact UI-SPEC copy strings (05-UI-SPEC.md Copywriting Contract).
    mutating func apply(_ result: Result<ImageCompressTransformer.CompressedImage, ImageCompressTransformer.CompressError>) {
        switch result {
        case .success(let img):
            state = .done(img)
        case .failure(let err):
            let reason: String
            switch err {
            case .notAnImage:
                reason = "Not a supported image — skipped."
            case .unsupportedType:
                reason = "Couldn't read this image format."
            case .writeFailed:
                reason = "Couldn't write the compressed file."
            }
            state = .failed(reason: reason)
        }
    }
}

// MARK: - ImageCompressViewModel

/// @Observable @MainActor batch orchestrator for image compression.
/// Mirrors HashViewModel.startFileHash's off-main Task + progress + cancellation shape,
/// adapted to a multi-image batch loop (D-01) with live per-row updates (D-09).
@Observable
@MainActor
final class ImageCompressViewModel: ToolShortcutActions {

    // MARK: - Published state

    /// One row per dropped image; drives the results table (D-09).
    var rows: [CompressRow] = []

    /// True while the batch Task is running. Used to show/hide the Cancel button.
    var isCompressing: Bool = false

    // MARK: - Private

    private var task: Task<Void, Never>?
    private let onSaveHistory: (HistoryEntry) -> Void

    // MARK: - Init

    init(onSaveHistory: @escaping (HistoryEntry) -> Void) {
        self.onSaveHistory = onSaveHistory
    }

    // MARK: - Compress

    /// Starts a batch compression of the provided URLs at the given quality (0.0–1.0).
    ///
    /// - Parameters:
    ///   - urls: Source image URLs to compress. One `CompressRow` is created per URL.
    ///   - quality: Lossy compression quality (0.0 = minimum, 1.0 = maximum).
    ///             Only applied to JPEG/HEIC; PNG/TIFF receive nil props (D-05).
    ///             The View maps its 0–100 slider to 0.0–1.0 before calling this.
    func compress(urls: [URL], quality: Double) {
        // Cancel any in-flight batch before starting a new one
        task?.cancel()

        // Build the row list with format tags BEFORE compression starts (D-05 gate)
        rows = urls.map { CompressRow(sourceURL: $0, format: ImageFormatTag.from(url: $0), state: .pending) }
        isCompressing = true

        // Capture the closure BEFORE the off-main Task (mirrors HashViewModel line 113).
        // The closure is called on the MainActor so no cross-actor send occurs.
        let capturedOnSave = onSaveHistory
        let sourceURLs = urls

        // Use Task (not Task.detached) so the closure call inside MainActor.run is safe.
        // The actual ImageIO work is dispatched further off via Task.detached inside the loop.
        task = Task { [weak self] in
            for (i, url) in sourceURLs.enumerated() {
                // Cancellation check per iteration — stops the loop before the next image
                guard !Task.isCancelled else { break }

                // Mark row .compressing so the View shows a spinner (D-09)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if i < self.rows.count {
                        self.rows[i].state = .compressing
                    }
                }

                guard !Task.isCancelled else { break }

                // Run the actual ImageIO work off the MainActor in a child Task.
                // autoreleasepool per image bounds peak CGImage memory (INFRA-18, Pitfall 4).
                let result: Result<ImageCompressTransformer.CompressedImage, ImageCompressTransformer.CompressError> = await Task.detached(priority: .userInitiated) {
                    autoreleasepool {
                        ImageCompressTransformer.compress(url: url, quality: quality)
                    }
                }.value

                // WR-01: re-check cancellation after the await — a cancelled batch must not
                // apply its stale ImageIO result onto the NEXT batch's rows (same index reuse).
                guard !Task.isCancelled else { break }

                // Live per-row update on MainActor (D-09) — failure = row state, not a crash (INFRA-17)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if i < self.rows.count {
                        self.rows[i].apply(result)
                    }
                }
            }

            // CR-02: if this batch was cancelled (superseded by a newer compress() call), do NOT
            // touch shared state — isCompressing belongs to the new batch, and firing history here
            // would save the new batch's rows under this stale task.
            guard !Task.isCancelled else { return }

            // Batch complete — update isCompressing and fire history (MainActor, so capturedOnSave is safe)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isCompressing = false

                // Count successful rows
                let successCount = self.rows.filter {
                    if case .done = $0.state { return true }
                    return false
                }.count

                guard successCount > 0 else { return }

                // Build aggregate savings summary — no secrets, no new HistoryEntry column (T-05-06)
                let filenames = self.rows.map { $0.sourceURL.lastPathComponent }.joined(separator: ", ")
                let totalSaved = self.rows.compactMap { row -> Double? in
                    if case .done(let img) = row.state { return img.percentSaved }
                    return nil
                }.reduce(0, +)
                let avgSaved = totalSaved / Double(max(successCount, 1))
                let outputSummary = "\(successCount) image\(successCount == 1 ? "" : "s") compressed, avg \(String(format: "%.0f", avgSaved))% saved"

                // ONE entry per batch (05-PATTERNS.md line 150)
                capturedOnSave(HistoryEntry(
                    tool: "image-compress",
                    input: filenames,
                    output: outputSummary,
                    timestamp: Date(),
                    pinned: false
                ))
            }
        }
    }

    // MARK: - Cancellation

    /// Cancels the in-flight batch Task.
    /// Already-finished rows retain their state; pending rows stop progressing.
    func cancel() {
        task?.cancel()
        task = nil
        isCompressing = false
    }

    // MARK: - ToolShortcutActions (INFRA-16)

    /// Returns a brief savings summary string when any rows are done, or nil (harmless no-op).
    func primaryOutput() -> String? {
        let done = rows.compactMap { row -> String? in
            if case .done(let img) = row.state {
                let pct = String(format: "%.0f", img.percentSaved)
                return "\(row.sourceURL.lastPathComponent): \(pct)% saved"
            }
            return nil
        }
        guard !done.isEmpty else { return nil }
        return done.joined(separator: "\n")
    }

    /// Clears all rows and cancels any in-flight batch.
    func clearInput() {
        task?.cancel()
        task = nil
        rows = []
        isCompressing = false
    }
}
