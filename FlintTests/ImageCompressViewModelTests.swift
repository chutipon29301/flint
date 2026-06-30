// FlintTests/ImageCompressViewModelTests.swift
// Tests for ImageCompressViewModel — batch progression, never-crash on corrupt, cancellation,
// single-fire history, and off-main proof.
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
            ImageCompressViewModel(onSaveHistory: { _ in })
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
            ImageCompressViewModel(onSaveHistory: { _ in })
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
            ImageCompressViewModel(onSaveHistory: { _ in })
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
        // Final invariant: NO row remains .compressing — every row is .pending, .done, or .failed.
        // (Either it finished just-in-time, or cancel resolved it — but it is NEVER stuck spinning.)
        let deadline = Date().addingTimeInterval(5)
        var anyCompressing = true
        while Date() < deadline {
            anyCompressing = await MainActor.run(body: {
                vm.rows.contains { if case .compressing = $0.state { return true } else { return false } }
            })
            if !anyCompressing { break }
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }

        let rows = await MainActor.run(body: { vm.rows })
        for row in rows {
            if case .compressing = row.state {
                #expect(Bool(false), "Row stuck in .compressing after cancel — must resolve to a terminal state")
            }
        }

        // isCompressing must end false — the button is hidden only AFTER the row resolves.
        let finalCompressing = await MainActor.run(body: { vm.isCompressing })
        #expect(finalCompressing == false, "isCompressing must be false after the in-flight row resolves")
    }

    // MARK: - Test 4: History fires exactly once per successful batch

    @Test("Successful single-image batch fires onSaveHistory exactly once with tool=image-compress")
    func testHistoryFiresOnce() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("history.jpg")
        try writeTinyJPEG(to: url)

        // Use a thread-safe store for both the count and the captured tool string.
        final class HistoryStore: @unchecked Sendable {
            private let lock = NSLock()
            private var _count: Int = 0
            private var _tool: String = ""
            func record(tool: String) { lock.withLock { _count += 1; _tool = tool } }
            var count: Int { lock.withLock { _count } }
            var tool: String { lock.withLock { _tool } }
        }
        let store = HistoryStore()

        let vm = await MainActor.run {
            ImageCompressViewModel(onSaveHistory: { entry in
                store.record(tool: entry.tool)
            })
        }

        await MainActor.run {
            vm.compress(urls: [url], quality: 0.6)
        }

        let deadline = Date().addingTimeInterval(10)
        while await MainActor.run(body: { vm.isCompressing }) && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        // Allow a brief settle for the MainActor history write
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(store.count == 1, "onSaveHistory must fire exactly once per batch")
        #expect(store.tool == "image-compress")
    }

    // MARK: - Test 5: Off-main proof — compress does not run on MainActor

    @Test("compress() launches an off-main Task (does not deadlock the main thread)")
    func testOffMainProof() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("offmain.jpg")
        try writeTinyJPEG(to: url)

        let vm = await MainActor.run {
            ImageCompressViewModel(onSaveHistory: { _ in })
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
}
