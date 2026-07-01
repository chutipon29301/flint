// Tools/ImageCompress/ImageCompressViewModel.swift
// @Observable @MainActor batch orchestrator for the Image Compressor tool.
// D-01: N dropped URLs → N CompressRow entries, each progressing .pending → .done/.failed.
// D-05: ImageFormatTag.isLossless gates the slider; per-row format tag set BEFORE compression.
// D-09: Live per-row updates via await MainActor.run { rows[i].apply(result) }.
// INFRA-17: Failed images become .failed rows; the batch never crashes on bad input.
// INFRA-18: Each image is compressed inside autoreleasepool in an off-main Task, bounding peak memory.
// T-05-06: History capture removed — history subsystem deleted in Phase 06.

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

    /// Pending work items the drain loop hasn't started yet. Each item carries the row's STABLE id
    /// (not a positional index) so appending more drops mid-flight never shifts an in-flight item's
    /// target (GAP 6b). A drop enqueues here and (re)starts the drain loop; recompress()/cancel() clear
    /// this so superseded/cancelled work never runs.
    private var pendingQueue: [(rowID: UUID, url: URL, quality: Double)] = []

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

    init() {}

    // MARK: - Compress

    /// Starts a batch compression of the provided URLs at the given quality (0.0–1.0).
    ///
    /// - Parameters:
    ///   - urls: Source image URLs to compress. One `CompressRow` is created per URL.
    ///   - quality: Lossy compression quality (0.0 = minimum, 1.0 = maximum).
    ///             Only applied to JPEG/HEIC; PNG/TIFF receive nil props (D-05).
    ///             The View maps its 0–100 slider to 0.0–1.0 before calling this.
    ///   - append: GAP 6 — when true (a fresh drop), the new rows are ADDED beside the existing ones
    ///             and ENQUEUED onto the shared work queue, so drops accumulate whether the previous
    ///             batch is finished OR still compressing (drop-while-loading). When false (recompress),
    ///             the in-flight work is superseded and rows are replaced.
    func compress(urls: [URL], quality: Double, append: Bool = false) {
        // Retain the source URLs + quality of this run so recompress() can replay the batch at a new
        // quality, and so the View can detect "quality changed since last run" (05-08, GAP 2).
        lastSourceURLs = urls
        lastRunQuality = quality

        if append {
            // GAP 6b: accumulate — never cancel the in-flight item; just add rows + queue them and
            // ensure the drain loop is running. Works whether idle or mid-compression.
            let newRows = urls.map { CompressRow(sourceURL: $0, format: ImageFormatTag.from(url: $0), state: .pending) }
            rows.append(contentsOf: newRows)
            pendingQueue.append(contentsOf: zip(newRows, urls).map { ($0.id, $1, quality) })
        } else {
            // Supersede (recompress / replace): cancel the current item, drop any queued work, replace
            // the row list. batchGeneration bump lets a superseded drain loop bow out cleanly (CR-02).
            currentWorkTask?.cancel()
            task?.cancel()
            pendingQueue.removeAll()
            let newRows = urls.map { CompressRow(sourceURL: $0, format: ImageFormatTag.from(url: $0), state: .pending) }
            rows = newRows
            pendingQueue = zip(newRows, urls).map { ($0.id, $1, quality) }
        }

        startDrainIfNeeded()
    }

    /// Starts the single serial drain loop if it isn't already running. The loop pulls one queued item
    /// at a time, compresses it off-main, and self-terminates when the queue empties. A single loop (not
    /// one Task per drop) keeps compression serial + memory bounded (INFRA-18) and lets drops appended
    /// mid-flight be picked up without spawning competing loops.
    private func startDrainIfNeeded() {
        guard task == nil else { return }  // a loop is already draining the queue

        isCompressing = true
        batchGeneration += 1
        let myGeneration = batchGeneration

        // OUTER loop = MainActor-bound `Task { }` (NOT Task.detached) so state is never accessed
        // off the MainActor.
        task = Task { [weak self] in
            while true {
                // Pull the next item on the MainActor. Cancellation (supersede) breaks out.
                let item: (rowID: UUID, url: URL, quality: Double)? = await MainActor.run { [weak self] in
                    guard let self, !Task.isCancelled, !self.pendingQueue.isEmpty else { return nil }
                    return self.pendingQueue.removeFirst()
                }
                guard let item else { break }

                // Locate this item's row BY ID (robust to appends shifting positions) and mark it
                // .compressing (D-09).
                await MainActor.run { [weak self] in
                    guard let self, let idx = self.rows.firstIndex(where: { $0.id == item.rowID }) else { return }
                    self.rows[idx].state = .compressing
                }

                // INNER per-image work = Task.detached running the nonisolated compressOffMain OFF the
                // MainActor (a plain Task here would run the synchronous work on the main thread, freezing
                // the UI — INFRA-18/testOffMainProof). Stored in currentWorkTask so cancel() flips
                // Task.isCancelled inside the quantizer checkpoint and stops the heavy work (T-05-07A).
                let url = item.url, quality = item.quality
                let workTask = Task.detached(priority: .userInitiated) {
                    ImageCompressTransformer.compressOffMain(url: url, quality: quality)
                }
                await MainActor.run { [weak self] in self?.currentWorkTask = workTask }
                let result = await workTask.value
                await MainActor.run { [weak self] in
                    if self?.currentWorkTask == workTask { self?.currentWorkTask = nil }
                }

                // GAP 3: on cancel, resolve THIS row out of .compressing (never stranded/spinning) and
                // stop the loop. Only the current item is cancelled — already-done rows keep their result.
                if Task.isCancelled || workTask.isCancelled {
                    await MainActor.run { [weak self] in
                        guard let self, let idx = self.rows.firstIndex(where: { $0.id == item.rowID }) else { return }
                        if case .compressing = self.rows[idx].state { self.rows[idx].state = .pending }
                    }
                    break
                }

                // Live per-row update (D-09) — failure = row state, not a crash (INFRA-17).
                await MainActor.run { [weak self] in
                    guard let self, let idx = self.rows.firstIndex(where: { $0.id == item.rowID }) else { return }
                    self.rows[idx].apply(result)
                }
            }

            // Loop ended. Clear our task handle so a later drop can start a fresh loop, and settle
            // isCompressing — but only if we're still the current generation (a supersede owns it now).
            await MainActor.run { [weak self] in
                guard let self else { return }
                // A supersede bumped the generation and owns task/isCompressing now — don't touch them.
                guard self.batchGeneration == myGeneration else { return }
                self.task = nil
                self.isCompressing = false
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
    ///
    /// Also drops any queued-but-not-started items so a Cancel during a multi-drop batch stops the whole
    /// queue, not just the current image. Queued rows stay .pending (render "—").
    func cancel() {
        pendingQueue.removeAll()
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
        pendingQueue.removeAll()
        currentWorkTask?.cancel()
        currentWorkTask = nil
        task?.cancel()
        task = nil
        // Bump generation so a still-resolving stale loop bows out (its completion guard fails) and
        // can't clobber task/isCompressing after this hard reset.
        batchGeneration += 1
        rows = []
        isCompressing = false
        // GAP 7: forget the retained batch too, so a cleared state can't be replayed by recompress().
        lastSourceURLs = []
        lastRunQuality = 0
    }
}
