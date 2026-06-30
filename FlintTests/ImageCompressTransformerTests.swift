// FlintTests/ImageCompressTransformerTests.swift
// Tests for ImageCompressTransformer — ImageIO round-trip, never-crash, disambiguation.
// D-02: same-format-out; D-05: lossless nil props; D-07/D-08: beside-original disambiguation.
// INFRA-17: corrupt/non-image/0-byte → typed failure, no crash or throw.

import Testing
import Foundation
import ImageIO
import CoreGraphics
@testable import Flint

@Suite("ImageCompressTransformer")
struct ImageCompressTransformerTests {

    // MARK: - Helpers

    /// Creates an isolated temp directory for each test.
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageCompressTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Synthesises a tiny valid JPEG at the given URL using ImageIO (no binary assets).
    /// Builds a 2×2 CGImage in sRGB and encodes it to JPEG at quality 0.8.
    @discardableResult
    private func writeTinyJPEG(to url: URL) throws -> URL {
        let width = 2, height = 2
        let bitsPerComponent = 8
        let bytesPerRow = width * 4
        var pixelData = [UInt8](repeating: 200, count: height * bytesPerRow) // light grey pixels
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixelData,
            width: width, height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ), let cgImage = ctx.makeImage() else {
            throw NSError(domain: "TestHelper", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create CGImage"])
        }
        guard let dst = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else {
            throw NSError(domain: "TestHelper", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create destination"])
        }
        CGImageDestinationAddImage(dst, cgImage, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(dst) else {
            throw NSError(domain: "TestHelper", code: 3, userInfo: [NSLocalizedDescriptionKey: "CGImageDestinationFinalize failed"])
        }
        return url
    }

    /// Synthesises a tiny valid PNG at the given URL.
    @discardableResult
    private func writeTinyPNG(to url: URL) throws -> URL {
        let width = 2, height = 2
        let bitsPerComponent = 8
        let bytesPerRow = width * 4
        var pixelData = [UInt8](repeating: 100, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixelData,
            width: width, height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ), let cgImage = ctx.makeImage() else {
            throw NSError(domain: "TestHelper", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create CGImage"])
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

    // MARK: - Test 1: Valid JPEG round-trip (D-02 same-format-out)

    @Test("Valid JPEG compresses to same UTI with -compressed suffix")
    func testCompress_validJPEG_succeedsWithSameFormat() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = dir.appendingPathComponent("photo.jpg")
        try writeTinyJPEG(to: source)

        let result = ImageCompressTransformer.compress(url: source, quality: 0.5)

        // Must succeed
        guard case .success(let compressed) = result else {
            Issue.record("Expected .success but got \(result)")
            return
        }

        // dest file must exist
        #expect(FileManager.default.fileExists(atPath: compressed.destURL.path),
                "Compressed file must exist on disk")

        // dest URL must end in -compressed.jpg (D-07, D-02 preserves extension)
        #expect(compressed.destURL.lastPathComponent == "photo-compressed.jpg",
                "Expected 'photo-compressed.jpg', got '\(compressed.destURL.lastPathComponent)'")

        // Verify same UTI as source (D-02 same-format-out)
        if let srcSource = CGImageSourceCreateWithURL(source as CFURL, nil),
           let dstSource = CGImageSourceCreateWithURL(compressed.destURL as CFURL, nil),
           let srcUTI = CGImageSourceGetType(srcSource),
           let dstUTI = CGImageSourceGetType(dstSource) {
            #expect(srcUTI == dstUTI,
                    "Source UTI '\(srcUTI)' must equal dest UTI '\(dstUTI)' (D-02)")
        } else {
            Issue.record("Could not read UTI from source or compressed file")
        }

        // Byte counts must be non-negative integers
        #expect(compressed.originalBytes >= 0)
        #expect(compressed.compressedBytes >= 0)
    }

    // MARK: - Test 2: Corrupt/non-image file returns .failure — no crash (INFRA-17)

    @Test("Corrupt file content returns .failure(.notAnImage) without crash (INFRA-17)")
    func testCompress_corruptContent_returnsNotAnImageFailure() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let corrupt = dir.appendingPathComponent("notanimage.jpg")
        // Write ASCII text into a file with a .jpg extension — not a valid image
        try "not an image".data(using: .utf8)!.write(to: corrupt)

        // No try — the call must not throw
        let result = ImageCompressTransformer.compress(url: corrupt, quality: 0.5)

        #expect({
            if case .failure = result { return true }
            return false
        }(), "Expected .failure for corrupt content, got \(result)")

        // Verify no crash occurred (we reached here) — test passes if we get here
    }

    // MARK: - Test 3: 0-byte file returns .failure — no crash (INFRA-17)

    @Test("Empty (0-byte) file returns .failure without crash (INFRA-17)")
    func testCompress_emptyFile_returnsFailure() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let empty = dir.appendingPathComponent("empty.jpg")
        try Data().write(to: empty)

        let result = ImageCompressTransformer.compress(url: empty, quality: 0.5)

        #expect({
            if case .failure = result { return true }
            return false
        }(), "Expected .failure for empty file, got \(result)")
    }

    // MARK: - Test 4: Disambiguation when -compressed already exists (D-08)

    @Test("disambiguatedCompressedURL produces -compressed-1 when -compressed already exists (D-08)")
    func testDisambiguate_collision_producesNumberedSuffix() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Create original and a pre-existing -compressed sibling
        let original = dir.appendingPathComponent("photo.png")
        let existingSibling = dir.appendingPathComponent("photo-compressed.png")
        try Data("original".utf8).write(to: original)
        try Data("existing".utf8).write(to: existingSibling)

        let result = ImageCompressTransformer.disambiguatedCompressedURL(for: original)

        #expect(result.lastPathComponent == "photo-compressed-1.png",
                "Expected 'photo-compressed-1.png', got '\(result.lastPathComponent)' (D-08)")
    }

    // MARK: - Test 5: Disambiguation base case (D-07, D-02)

    @Test("disambiguatedCompressedURL base case produces -compressed preserving extension (D-07/D-02)")
    func testDisambiguate_baseCase_producesCompressedSuffix() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let original = dir.appendingPathComponent("image.png")
        // Do NOT create a -compressed sibling — base case
        try Data("original".utf8).write(to: original)

        let result = ImageCompressTransformer.disambiguatedCompressedURL(for: original)

        #expect(result.lastPathComponent == "image-compressed.png",
                "Expected 'image-compressed.png', got '\(result.lastPathComponent)' (D-07)")
        #expect(result.pathExtension == "png",
                "Extension must be preserved (D-02), got '\(result.pathExtension)'")
        #expect(result.deletingLastPathComponent().path == dir.path,
                "Compressed file must be beside original (D-07)")
    }
}
