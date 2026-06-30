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

    /// The source URLs of the most recent compress() call, retained so recompress() can replay the
    /// batch at a new quality without re-dropping (05-08, GAP 2). MainActor-confined @Observable
    /// state — never captured off-main, so no Sendable concern (D-04).
    private(set) var lastSourceURLs: [URL] = []

    /// The quality (0.0–1.0) of the most recent compress() call. The View compares the live slider
    /// value against this to decide whether to surface the "Re-compress at {n}%" button (05-08).
    private(set) var lastRunQuality: Double = 0

    // MARK: - Private

    private var task: Task<Void, Never>?
    private let onSaveHistory: (HistoryEntry) -> Void

    /// The in-flight per-image work Task (the off-main `Task.detached` quantization for the CURRENT
    /// image). Stored so cancel() can cancel it DIRECTLY. A detached Task opts out of INHERITED
    /// cancellation, so cancelling the enclosing batch Task alone would never flip Task.isCancelled
    /// inside the transformer's quantize checkpoint — but an explicit .cancel() on THIS stored handle
    /// does, which is what makes the cooperative checkpoint fire and stops the heavy work mid-flight
    /// (T-05-07A). Task.detached is also what keeps the synchronous nonisolated compressOffMain OFF the
    /// MainActor (a plain Task in this @MainActor context would run it on the main thread — INFRA-18).
    private var currentWorkTask: Task<Result<ImageCompressTransformer.CompressedImage, ImageCompressTransformer.CompressError>, Never>?

    /// Monotonic batch generation. compress() bumps this and the batch Task captures its value so the
    /// completion path can tell a user-cancel of THIS batch (still current → resolve UI + flip
    /// isCompressing) apart from a supersede by a newer compress() (newer batch owns isCompressing →
    /// leave it alone, CR-02).
    private var batchGeneration: Int = 0

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
        // Cancel any in-flight batch before starting a new one (both the batch loop and the
        // currently-running per-image work Task, so a superseded image stops quantizing too).
        task?.cancel()
        currentWorkTask?.cancel()

        // Retain the source URLs + quality of this run so recompress() can replay the batch at a
        // new quality without re-dropping, and so the View can detect "quality changed since last
        // run" to surface the explicit Re-compress affordance (05-08, GAP 2).
        lastSourceURLs = urls
        lastRunQuality = quality

        // Build the row list with format tags BEFORE compression starts (D-05 gate)
        rows = urls.map { CompressRow(sourceURL: $0, format: ImageFormatTag.from(url: $0), state: .pending) }
        isCompressing = true

        // Bump the batch generation so the completion path can detect supersede (CR-02).
        batchGeneration += 1
        let myGeneration = batchGeneration

        // Capture the closure BEFORE the off-main Task (mirrors HashViewModel line 113).
        // The closure is called on the MainActor so no cross-actor send occurs.
        let capturedOnSave = onSaveHistory
        let sourceURLs = urls

        // OUTER batch loop = MainActor-bound `Task { }` (NOT Task.detached) so the non-Sendable
        // capturedOnSave/onSaveHistory closure is never sent across an actor boundary (05-02 auto-fix #1).
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

                // INNER per-image work = a Task.detached running the `nonisolated` helper compressOffMain.
                //
                // Task.detached is REQUIRED for off-main: a PLAIN `Task { }` created inside this
                // @MainActor batch Task inherits MainActor isolation, and calling a SYNCHRONOUS
                // nonisolated function (compressOffMain) from it does NOT cause an actor hop — so the
                // 58s quantization would run ON the MainActor, both breaking INFRA-18 and freezing the UI
                // (the user's Cancel tap could not even be processed until the work finished). Task.detached
                // runs the synchronous work on a background executor (INFRA-18, testOffMainProof).
                //
                // Cancellation still works because we store the detached Task in currentWorkTask and
                // cancel() calls .cancel() on it DIRECTLY. Detached only opts out of INHERITED cancellation;
                // an explicit .cancel() on the stored handle flips Task.isCancelled true inside
                // compressOffMain, so the cooperative checkpoint in PNGColorQuantizer.quantize fires and the
                // heavy work stops mid-flight (T-05-07A). autoreleasepool lives inside compressOffMain,
                // bounding peak CGImage memory (INFRA-18, Pitfall 4).
                let workTask = Task.detached(priority: .userInitiated) {
                    ImageCompressTransformer.compressOffMain(url: url, quality: quality)
                }
                await MainActor.run { [weak self] in self?.currentWorkTask = workTask }
                let result = await workTask.value
                await MainActor.run { [weak self] in
                    if self?.currentWorkTask == workTask { self?.currentWorkTask = nil }
                }

                // GAP 3 fix: resolve the in-flight row instead of stranding it. The row was set
                // .compressing above; on cancellation it MUST leave that state or the View spins forever.
                // Reset it to .pending (renders "—"; no View change needed). A freshly-cancelled batch
                // must NOT apply its stale result onto a newer batch's rows either (WR-01).
                if Task.isCancelled || workTask.isCancelled {
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        if i < self.rows.count, case .compressing = self.rows[i].state {
                            self.rows[i].state = .pending
                        }
                    }
                    break
                }

                // Live per-row update on MainActor (D-09) — failure = row state, not a crash (INFRA-17)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if i < self.rows.count {
                        self.rows[i].apply(result)
                    }
                }
            }

            // CR-02 + GAP 3 completion. Two cancellation shapes must be distinguished:
            //   (a) USER cancel of THIS batch — this task is still the current generation, so it owns
            //       isCompressing and MUST flip it false now that the in-flight row resolved above (the
            //       Cancel button stays visible until exactly this point — non-eager). NO history.
            //   (b) SUPERSEDE by a newer compress() — a newer batch already set isCompressing = true and
            //       owns it; touching it here would clobber the new batch's state, and firing history would
            //       save the new batch's rows under this stale task. Leave everything alone.
            if Task.isCancelled {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if self.batchGeneration == myGeneration {
                        self.isCompressing = false
                    }
                }
                return
            }

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

    // MARK: - Re-compress

    /// Re-runs the most recent batch at a new quality (05-08, GAP 2). Compress-on-drop is immediate,
    /// so the quality slider can never affect images already dropped; this gives the user an explicit
    /// affordance to re-apply a changed quality to the existing batch.
    ///
    /// No-op when there is no retained batch (lastSourceURLs empty) — never crashes, never compresses
    /// an empty set (T-05-08B). Re-compression fires ONLY from this explicit call (the View's button
    /// press) — there is deliberately no .onChange(of: quality) auto-trigger, which would spew a new
    /// -compressed-N file on every slider tick (T-05-08A, locked decision).
    ///
    /// - Parameter quality: New lossy quality (0.0–1.0), already mapped from the 0–100 slider.
    func recompress(quality: Double) {
        guard !lastSourceURLs.isEmpty else { return }
        compress(urls: lastSourceURLs, quality: quality)
    }

    // MARK: - Cancellation

    /// Requests cancellation of the in-flight batch.
    ///
    /// GAP 3: this is NON-EAGER. It cancels BOTH the batch loop Task and the currently-running per-image
    /// work Task (the latter is what flips Task.isCancelled inside the transformer's quantize checkpoint,
    /// actually stopping the heavy work — T-05-07A). It does NOT flip isCompressing false or drop the
    /// task reference here: the batch Task observes cancellation, resolves the in-flight .compressing row
    /// out of its spinning state, and only THEN flips isCompressing = false on the MainActor (see the
    /// completion path in compress()). So the Cancel button stays visible until the row resolves.
    func cancel() {
        currentWorkTask?.cancel()
        task?.cancel()
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

    /// Clears all rows and cancels any in-flight batch. This is a HARD reset (unlike cancel()): the user
    /// has cleared the input entirely, so there is no row to keep spinning — drop everything immediately.
    func clearInput() {
        currentWorkTask?.cancel()
        currentWorkTask = nil
        task?.cancel()
        task = nil
        rows = []
        isCompressing = false
    }
}
