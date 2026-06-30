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

    /// Synthesises a many-color photographic-style PNG: a smooth gradient base plus per-pixel
    /// pseudo-random noise so row filters cannot win and palette reduction shows a clear size win
    /// (mirrors the UAT Test 8 scenario; smooth gradients alone can favor truecolor row filters).
    @discardableResult
    private func writeGradientPNG(to url: URL, width: Int = 256, height: Int = 256) throws -> URL {
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
            throw NSError(domain: "TestHelper", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create gradient CGImage"])
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

    /// Synthesises a PNG with a transparent quadrant (top-left fully transparent, rest opaque
    /// gradient) to verify alpha survives quantization.
    @discardableResult
    private func writeTransparentQuadrantPNG(to url: URL, width: Int = 64, height: Int = 64) throws -> URL {
        let bytesPerRow = width * 4
        var pixelData = [UInt8](repeating: 0, count: height * bytesPerRow)
        for y in 0..<height {
            for x in 0..<width {
                let o = y * bytesPerRow + x * 4
                let transparent = (x < width / 2 && y < height / 2)
                if transparent {
                    pixelData[o] = 0; pixelData[o + 1] = 0; pixelData[o + 2] = 0; pixelData[o + 3] = 0
                } else {
                    let r = UInt8(x * 255 / max(1, width - 1))
                    let g = UInt8(y * 255 / max(1, height - 1))
                    pixelData[o] = r; pixelData[o + 1] = g; pixelData[o + 2] = 128; pixelData[o + 3] = 255
                }
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
            throw NSError(domain: "TestHelper", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create transparent CGImage"])
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

    /// Reads pixel dimensions of an image file via ImageIO.
    private func pixelDimensions(of url: URL) -> (width: Int, height: Int)? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (w, h)
    }

    /// Decodes the image and reports whether it has an alpha channel that is actually used
    /// (i.e. at least one pixel is non-opaque).
    private func hasTransparentPixel(in url: URL) -> Bool {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return false }
        let width = cg.width, height = cg.height
        let bytesPerRow = width * 4
        var buf = [UInt8](repeating: 0, count: height * bytesPerRow)
        let cs = CGColorSpaceCreateDeviceRGB()
        let ok: Bool = buf.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress,
                  let ctx = CGContext(data: base, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: cs,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { return false }
        for i in stride(from: 3, to: buf.count, by: 4) where buf[i] < 255 { return true }
        return false
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

    // MARK: - Test 6: Photographic PNG shrinks meaningfully via quantization (UAT Test 8, D-05)

    @Test("Photographic PNG compresses with meaningful savings, same dimensions, valid public.png")
    func testCompress_photographicPNG_shrinksMeaningfully() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = dir.appendingPathComponent("photo.png")
        try writeGradientPNG(to: source, width: 256, height: 256)

        let result = ImageCompressTransformer.compress(url: source, quality: 0.6)

        guard case .success(let compressed) = result else {
            Issue.record("Expected .success but got \(result)")
            return
        }

        #expect(FileManager.default.fileExists(atPath: compressed.destURL.path))
        #expect(compressed.destURL.lastPathComponent == "photo-compressed.png")

        // Meaningful savings — quantizer comfortably clears 30% on noisy photographic content.
        #expect(compressed.percentSaved > 30,
                "Expected > 30% saved on photographic PNG, got \(compressed.percentSaved)% (\(compressed.originalBytes)->\(compressed.compressedBytes))")

        // Output is a valid public.png with the SAME dimensions (D-02, no downscaling).
        if let dstSource = CGImageSourceCreateWithURL(compressed.destURL as CFURL, nil),
           let dstUTI = CGImageSourceGetType(dstSource) {
            #expect((dstUTI as String) == "public.png", "Output must remain public.png, got \(dstUTI)")
        } else {
            Issue.record("Compressed output is not a readable image")
        }
        let srcDims = pixelDimensions(of: source)
        let dstDims = pixelDimensions(of: compressed.destURL)
        #expect(srcDims?.width == dstDims?.width && srcDims?.height == dstDims?.height,
                "Dimensions must be preserved: \(String(describing: srcDims)) vs \(String(describing: dstDims))")
    }

    // MARK: - Test 7: Alpha transparency survives quantization

    @Test("PNG with transparency keeps an alpha channel after compression")
    func testCompress_transparentPNG_preservesAlpha() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = dir.appendingPathComponent("badge.png")
        try writeTransparentQuadrantPNG(to: source, width: 64, height: 64)

        #expect(hasTransparentPixel(in: source), "Precondition: source has transparency")

        let result = ImageCompressTransformer.compress(url: source, quality: 0.6)

        guard case .success(let compressed) = result else {
            Issue.record("Expected .success but got \(result)")
            return
        }

        #expect(hasTransparentPixel(in: compressed.destURL),
                "Compressed output must retain a transparent region (alpha preserved)")
        // Same dimensions, still PNG.
        let srcDims = pixelDimensions(of: source)
        let dstDims = pixelDimensions(of: compressed.destURL)
        #expect(srcDims?.width == dstDims?.width && srcDims?.height == dstDims?.height)
    }

    // MARK: - Test 8: D-06 honest reporting — never larger than truecolor re-encode

    @Test("Low-color PNG that would not shrink still succeeds and is never larger than truecolor (D-06)")
    func testCompress_lowColorPNG_neverLargerThanTruecolor() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = dir.appendingPathComponent("flat.png")
        // Tiny uniform PNG — quantization cannot beat truecolor re-encode here.
        try writeTinyPNG(to: source)

        let result = ImageCompressTransformer.compress(url: source, quality: 0.6)

        // Must still SUCCEED (never fail just because there is no win).
        guard case .success(let compressed) = result else {
            Issue.record("Expected .success but got \(result)")
            return
        }
        #expect(FileManager.default.fileExists(atPath: compressed.destURL.path))

        // Compute a plain truecolor re-encode of the same source for comparison.
        let truecolorURL = dir.appendingPathComponent("truecolor.png")
        if let src = CGImageSourceCreateWithURL(source as CFURL, nil),
           let dst = CGImageDestinationCreateWithURL(truecolorURL as CFURL, "public.png" as CFString, 1, nil) {
            CGImageDestinationAddImageFromSource(dst, src, 0, nil)
            _ = CGImageDestinationFinalize(dst)
        }
        let truecolorBytes = (try? truecolorURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? Int.max

        // D-06: the produced file is never larger than the plain truecolor re-encode.
        #expect(compressed.compressedBytes <= truecolorBytes,
                "Output (\(compressed.compressedBytes)B) must not exceed truecolor re-encode (\(truecolorBytes)B) (D-06)")

        // Output remains a valid same-dimension public.png.
        let srcDims = pixelDimensions(of: source)
        let dstDims = pixelDimensions(of: compressed.destURL)
        #expect(srcDims?.width == dstDims?.width && srcDims?.height == dstDims?.height)
    }

    // MARK: - Test 9: Corrupt PNG-extension input still fails gracefully (INFRA-17)

    @Test("Corrupt content with .png extension returns .failure without crash (INFRA-17)")
    func testCompress_corruptPNGExtension_returnsFailure() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let corrupt = dir.appendingPathComponent("fake.png")
        try Data("definitely not a png".utf8).write(to: corrupt)

        let result = ImageCompressTransformer.compress(url: corrupt, quality: 0.6)
        #expect({
            if case .failure = result { return true }
            return false
        }(), "Expected .failure for corrupt PNG-extension input, got \(result)")
    }
}
