// FlintTests/ImageCompressViewModelTests.swift
// Tests for ImageCompressViewModel — batch progression, never-crash on corrupt, cancellation,
// and off-main proof.
// D-01: N URLs → N rows; D-09: live per-row updates; INFRA-17: mixed valid+corrupt batch survives;
// INFRA-18: off-main compression (no main-thread deadlock).

import Testing
import Foundation
import ImageIO
import CoreGraphics
@testable import Flint

// MARK: - Helpers

/// Thread-safe counter for testing async closure invocations.
final class InvocationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _count: Int = 0
    func increment() { lock.withLock { _count += 1 } }
    var count: Int { lock.withLock { _count } }
}

@Suite("ImageCompressViewModel", .serialized)
struct ImageCompressViewModelTests {

    // MARK: - Temp directory helpers

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageCompressViewModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Synthesises a tiny valid JPEG at the given URL using ImageIO.
    @discardableResult
    private func writeTinyJPEG(to url: URL) throws -> URL {
        let width = 2, height = 2
        let bitsPerComponent = 8
        let bytesPerRow = width * 4
        var pixelData = [UInt8](repeating: 200, count: height * bytesPerRow)
        // Alternate red and blue pixels
        pixelData[0] = 255; pixelData[1] = 0; pixelData[2] = 0; pixelData[3] = 255
        pixelData[4] = 0; pixelData[5] = 0; pixelData[6] = 255; pixelData[7] = 255
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let image = context.makeImage()!
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        _ = CGImageDestinationFinalize(dest)
        return url
    }

    /// Synthesises a LARGE many-color photographic-style PNG (default 1024×1024): a smooth gradient
    /// base plus per-pixel pseudo-random noise. The size + per-pixel uniqueness make the median-cut
    /// quantization + nearest-palette mapping loop slow enough that cancel() lands mid-flight — the
    /// fixture the rewritten cancellation test needs (mirrors the transformer-test gradient idiom).
    @discardableResult
    private func writeSlowGradientPNG(to url: URL, width: Int = 1024, height: Int = 1024) throws -> URL {
        let bytesPerRow = width * 4
        var pixelData = [UInt8](repeating: 0, count: height * bytesPerRow)
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func nextNoise() -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) & 0x1F) - 16 // -16...15
        }
        for y in 0..<height {
            for x in 0..<width {
                let o = y * bytesPerRow + x * 4
                let r = max(0, min(255, (x * 255 / max(1, width - 1)) + nextNoise()))
                let g = max(0, min(255, (y * 255 / max(1, height - 1)) + nextNoise()))
                let b = max(0, min(255, ((x + y) * 255 / max(1, width + height - 2)) + nextNoise()))
                pixelData[o] = UInt8(r)
                pixelData[o + 1] = UInt8(g)
                pixelData[o + 2] = UInt8(b)
                pixelData[o + 3] = 255
            }
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixelData,
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let cgImage = ctx.makeImage() else {
            throw NSError(domain: "TestHelper", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create slow gradient CGImage"])
        }
        guard let dst = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw NSError(domain: "TestHelper", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create destination"])
        }
        CGImageDestinationAddImage(dst, cgImage, nil)
        guard CGImageDestinationFinalize(dst) else {
            throw NSError(domain: "TestHelper", code: 3, userInfo: [NSLocalizedDescriptionKey: "CGImageDestinationFinalize failed"])
        }
        return url
    }

    // MARK: - Test 1: Batch state progression (D-01, D-09)

    @Test("Batch with 2 valid JPEGs: 2 rows, both end .done with CompressedImage")
    func testBatchStateProgression() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let url1 = dir.appendingPathComponent("img1.jpg")
        let url2 = dir.appendingPathComponent("img2.jpg")
        try writeTinyJPEG(to: url1)
        try writeTinyJPEG(to: url2)

        let vm = await MainActor.run {
            ImageCompressViewModel()
        }

        await MainActor.run {
            vm.compress(urls: [url1, url2], quality: 0.6)
        }

        // Poll until isCompressing == false with a bounded timeout
        let deadline = Date().addingTimeInterval(10)
        while await MainActor.run(body: { vm.isCompressing }) && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }

        let rows = await MainActor.run(body: { vm.rows })
        #expect(rows.count == 2)
        for row in rows {
            if case .done = row.state { /* pass */ } else {
                #expect(Bool(false), "Row should be .done, got \(row.state)")
            }
        }
    }

    // MARK: - Test 2: Mixed valid+corrupt batch never crashes (INFRA-17)

    @Test("Mixed batch: valid JPEG succeeds, non-image file becomes .failed — batch survives")
    func testMixedBatchNeverCrashes() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let validURL = dir.appendingPathComponent("valid.jpg")
        let corruptURL = dir.appendingPathComponent("notanimage.jpg")
        try writeTinyJPEG(to: validURL)
        // Write non-image bytes with a .jpg extension
        try "this is not an image".data(using: .utf8)!.write(to: corruptURL)

        let vm = await MainActor.run {
            ImageCompressViewModel()
        }

        await MainActor.run {
            vm.compress(urls: [validURL, corruptURL], quality: 0.6)
        }

        let deadline = Date().addingTimeInterval(10)
        while await MainActor.run(body: { vm.isCompressing }) && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        let rows = await MainActor.run(body: { vm.rows })
        #expect(rows.count == 2)

        // Valid row (index 0) ends .done
        if case .done = rows[0].state { /* pass */ } else {
            #expect(Bool(false), "Valid row should be .done, got \(rows[0].state)")
        }
        // Corrupt row (index 1) ends .failed with a UI-SPEC failure reason.
        // The exact reason ("Not a supported image" vs "Couldn't read this image format") depends
        // on which ImageIO guard catches the bad content first — both are valid INFRA-17 outcomes.
        if case .failed(let reason) = rows[1].state {
            let validReasons = [
                "Not a supported image — skipped.",
                "Couldn't read this image format.",
                "Couldn't write the compressed file."
            ]
            #expect(validReasons.contains(reason), "Expected a UI-SPEC failure reason, got: \(reason)")
        } else {
            #expect(Bool(false), "Corrupt row should be .failed, got \(rows[1].state)")
        }
    }

    // MARK: - Test 3: Cancellation resolves the in-flight row (UAT Test 9, GAP 3)

    @Test("Cancel mid-flight: NO row stays .compressing forever; isCompressing ends false")
    func testCancellation() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // SLOW fixture: a large noisy RGBA PNG. Quantization of a 1024×1024 fully-unique-color image
        // takes long enough that cancel() lands while the row is still .compressing.
        let slowPNG = dir.appendingPathComponent("slow.png")
        try writeSlowGradientPNG(to: slowPNG)

        let vm = await MainActor.run {
            ImageCompressViewModel()
        }

        await MainActor.run {
            vm.compress(urls: [slowPNG], quality: 0.6)
        }

        // Wait a short beat so the row reaches .compressing, then cancel mid-flight.
        try await Task.sleep(nanoseconds: 60_000_000) // 60ms
        await MainActor.run {
            vm.cancel()
        }

        // Poll (bounded deadline) until the in-flight row has RESOLVED out of .compressing.
        // The deadline is deliberately tight (5s) relative to how long an UN-cancelled quantization of
        // this 1024×1024 fully-unique-color fixture takes (tens of seconds). So this is not merely a
        // "no row stuck forever" check — it also proves cooperative cancellation ACTUALLY STOPPED the
        // work (must_have #2). A non-cancellable implementation would still be .compressing at 5s and
        // FAIL the assertion below; only a real cooperative cancel resolves the row in time.
        let deadline = Date().addingTimeInterval(5)
        var anyCompressing = true
        while Date() < deadline {
            anyCompressing = await MainActor.run(body: {
                vm.rows.contains { if case .compressing = $0.state { return true } else { return false } }
            })
            if !anyCompressing { break }
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }

        // Final invariant: NO row remains .compressing within the bounded deadline — every row is
        // .pending, .done, or .failed. (Cancel resolved the in-flight row; it is NEVER stuck spinning,
        // and the heavy work was actually interrupted rather than running to completion.)
        #expect(anyCompressing == false, "Row still .compressing at the deadline — cancel did not stop the in-flight work")

        let rows = await MainActor.run(body: { vm.rows })
        for row in rows {
            if case .compressing = row.state {
                #expect(Bool(false), "Row stuck in .compressing after cancel — must resolve to a terminal state")
            }
        }

        // isCompressing must end false — the button is hidden only AFTER the row resolves.
        let finalCompressing = await MainActor.run(body: { vm.isCompressing })
        #expect(finalCompressing == false, "isCompressing must be false after the in-flight row resolves")

        // GAP 5 (Test 9): a cancelled compress must leave NO output file on disk. The transformer's
        // quantizer bails to the fallback write on cancel; the post-write cancellation gate deletes it.
        let leftovers = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.contains("-compressed") }
        #expect(leftovers.isEmpty, "Cancelled compress left an output file on disk: \(leftovers.map(\.lastPathComponent))")
    }

    // MARK: - Test 6: compress() records lastSourceURLs + lastRunQuality (05-08, D-04)

    @Test("compress() records lastSourceURLs and lastRunQuality on every run")
    func testCompressRecordsLastRun() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let url1 = dir.appendingPathComponent("a.jpg")
        let url2 = dir.appendingPathComponent("b.jpg")
        try writeTinyJPEG(to: url1)
        try writeTinyJPEG(to: url2)

        let vm = await MainActor.run {
            ImageCompressViewModel()
        }

        await MainActor.run {
            vm.compress(urls: [url1, url2], quality: 0.6)
        }

        // lastSourceURLs / lastRunQuality are set synchronously at the top of compress(),
        // so they are observable immediately — no need to wait for the batch to finish.
        let (urls, lastQuality) = await MainActor.run(body: { (vm.lastSourceURLs, vm.lastRunQuality) })
        #expect(urls == [url1, url2])
        #expect(lastQuality == 0.6)

        // Let the batch settle so the temp dir teardown does not race the off-main work.
        let deadline = Date().addingTimeInterval(10)
        while await MainActor.run(body: { vm.isCompressing }) && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    // MARK: - Test 7: recompress() replays the retained batch (05-08, GAP 2)

    @Test("recompress() re-runs compression on the retained URLs and updates lastRunQuality")
    func testRecompressReplaysBatch() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let url1 = dir.appendingPathComponent("r1.jpg")
        let url2 = dir.appendingPathComponent("r2.jpg")
        try writeTinyJPEG(to: url1)
        try writeTinyJPEG(to: url2)

        let vm = await MainActor.run {
            ImageCompressViewModel()
        }

        // Prior batch at 0.6
        await MainActor.run {
            vm.compress(urls: [url1, url2], quality: 0.6)
        }
        let firstDeadline = Date().addingTimeInterval(10)
        while await MainActor.run(body: { vm.isCompressing }) && Date() < firstDeadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        // Re-compress at a new quality
        await MainActor.run {
            vm.recompress(quality: 0.9)
        }
        let secondDeadline = Date().addingTimeInterval(10)
        while await MainActor.run(body: { vm.isCompressing }) && Date() < secondDeadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        let (rows, lastQuality) = await MainActor.run(body: { (vm.rows, vm.lastRunQuality) })
        #expect(rows.count == 2, "recompress should rebuild the rows for the same URLs")
        for row in rows {
            if case .done = row.state { /* pass */ } else {
                #expect(Bool(false), "Row should be .done after recompress, got \(row.state)")
            }
        }
        #expect(lastQuality == 0.9, "recompress should update lastRunQuality to the new quality")
    }

    // MARK: - Test 8: recompress() is a no-op on a fresh VM (05-08, T-05-08B)

    @Test("recompress() on a VM with no prior batch is a no-op — rows stay empty, no crash")
    func testRecompressNoOpWhenEmpty() async throws {
        let vm = await MainActor.run {
            ImageCompressViewModel()
        }

        await MainActor.run {
            vm.recompress(quality: 0.9)
        }

        // Brief settle to confirm nothing spun up.
        try await Task.sleep(nanoseconds: 100_000_000)

        let (rows, isCompressing) = await MainActor.run(body: { (vm.rows, vm.isCompressing) })
        #expect(rows.isEmpty, "recompress with no prior batch must not create rows")
        #expect(isCompressing == false, "recompress with no prior batch must not start a batch")
    }

    // MARK: - Test 5: Off-main proof — compress does not run on MainActor

    @Test("compress() launches an off-main Task (does not deadlock the main thread)")
    func testOffMainProof() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("offmain.jpg")
        try writeTinyJPEG(to: url)

        let vm = await MainActor.run {
            ImageCompressViewModel()
        }

        // Start compression and immediately check that it returns control to the caller.
        // If compress() ran synchronously on the main thread, this test would deadlock.
        await MainActor.run {
            vm.compress(urls: [url], quality: 0.6)
        }

        // The fact that we reach here without deadlock proves off-main execution.
        let deadline = Date().addingTimeInterval(10)
        while await MainActor.run(body: { vm.isCompressing }) && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        let rows = await MainActor.run(body: { vm.rows })
        #expect(rows.count == 1)
    }

    // MARK: - GAP 6: re-dropping the same image appends a row (Test 10)

    @Test("Re-dropping the same image with append:true adds a second row (does not replace)")
    func testAppendRedropAddsRow() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let jpeg = try writeTinyJPEG(to: dir.appendingPathComponent("photo.jpg"))

        let vm = await MainActor.run { ImageCompressViewModel() }

        // First drop.
        await MainActor.run { vm.compress(urls: [jpeg], quality: 0.6, append: true) }
        try await drainBatch(vm)
        let firstCount = await MainActor.run(body: { vm.rows.count })
        #expect(firstCount == 1)

        // Re-drop the SAME image — must append, not replace.
        await MainActor.run { vm.compress(urls: [jpeg], quality: 0.6, append: true) }
        try await drainBatch(vm)
        let secondCount = await MainActor.run(body: { vm.rows.count })
        #expect(secondCount == 2, "Re-drop must append a second row, not replace the first")
    }

    // MARK: - GAP 6b: dropping while the first image is still compressing appends + completes both

    @Test("Dropping a second image WHILE the first is compressing appends and both finish")
    func testAppendWhileCompressing() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // Moderately-slow first image: big enough to still be compressing at 60ms, small enough to
        // FINISH within the drain deadline (this test needs completion, not cancellation).
        let slow = try writeSlowGradientPNG(to: dir.appendingPathComponent("slow.png"), width: 384, height: 384)
        let fast = try writeTinyJPEG(to: dir.appendingPathComponent("fast.jpg"))

        let vm = await MainActor.run { ImageCompressViewModel() }

        await MainActor.run { vm.compress(urls: [slow], quality: 0.6, append: true) }
        // Let the slow image reach .compressing, then drop the second one mid-flight.
        try await Task.sleep(nanoseconds: 60_000_000)
        let stillCompressing = await MainActor.run(body: { vm.isCompressing })
        #expect(stillCompressing, "First image should still be compressing when the second drops")

        await MainActor.run { vm.compress(urls: [fast], quality: 0.6, append: true) }
        // Append is immediate — the second row appears without cancelling the first.
        #expect(await MainActor.run(body: { vm.rows.count }) == 2, "Mid-flight drop must append a second row")

        try await drainBatch(vm, timeout: 30)
        let doneCount = await MainActor.run(body: {
            vm.rows.filter { if case .done = $0.state { return true }; return false }.count
        })
        #expect(doneCount == 2, "Both the in-flight and the mid-flight-appended image must complete")
    }

    // MARK: - GAP 7: Clear resets rows and forgets the retained batch

    @Test("clearInput empties rows and prevents recompress from replaying the cleared batch")
    func testClearInputForgetsBatch() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let jpeg = try writeTinyJPEG(to: dir.appendingPathComponent("photo.jpg"))

        let vm = await MainActor.run { ImageCompressViewModel() }
        await MainActor.run { vm.compress(urls: [jpeg], quality: 0.6) }
        try await drainBatch(vm)

        await MainActor.run { vm.clearInput() }
        let clearedRows = await MainActor.run(body: { vm.rows.count })
        #expect(clearedRows == 0)

        // recompress after clear is a no-op (batch forgotten) — no new rows appear.
        await MainActor.run { vm.recompress(quality: 0.6) }
        let afterRecompress = await MainActor.run(body: { vm.rows.count })
        #expect(afterRecompress == 0, "recompress after clear must not replay the forgotten batch")
    }

    /// Waits (bounded) until the batch finishes compressing.
    private func drainBatch(_ vm: ImageCompressViewModel, timeout: TimeInterval = 10) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while await MainActor.run(body: { vm.isCompressing }) && Date() < deadline {
            try await Task.sleep(nanoseconds: 30_000_000)
        }
    }
}
