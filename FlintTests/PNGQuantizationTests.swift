// FlintTests/PNGQuantizationTests.swift
// Tests for the pure-Swift PNG compression engine: IndexedPNGEncoder (color-type 3 writer)
// and PNGColorQuantizer (median-cut RGBA -> palette + index map).
//
// Mirrors ImageCompressTransformerTests style: import Testing, @testable import Flint,
// temp-dir helper, synthesise all inputs in code (no binary assets), assert via #expect,
// re-open encoder output with CGImageSourceCreateWithURL to prove PNG validity.
// INFRA-17: degenerate input must return nil / empty-safe result, never crash.

import Testing
import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
@testable import Flint

@Suite("PNGQuantization")
struct PNGQuantizationTests {

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PNGQuantizationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Builds a CGImage from a tightly-packed RGBA8 buffer (premultipliedLast).
    private func makeCGImage(width: Int, height: Int, rgba: [UInt8]) -> CGImage? {
        precondition(rgba.count == width * height * 4)
        var data = rgba
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &data,
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        return ctx.makeImage()
    }

    /// Re-encodes a CGImage as a truecolor RGBA PNG via CGImageDestination (the size baseline).
    private func truecolorPNGData(_ cgImage: CGImage) -> Data? {
        let mutable = NSMutableData()
        guard let dst = CGImageDestinationCreateWithData(mutable, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dst, cgImage, nil)
        guard CGImageDestinationFinalize(dst) else { return nil }
        return mutable as Data
    }

    /// Writes data to a temp file and returns the decoded (width, height, isPNG) via ImageIO.
    private func decodeViaImageIO(_ data: Data, in dir: URL) -> (width: Int, height: Int, type: String)? {
        let url = dir.appendingPathComponent("out-\(UUID().uuidString).png")
        do { try data.write(to: url) } catch { return nil }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let type = CGImageSourceGetType(src),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            return nil
        }
        return (img.width, img.height, type as String)
    }

    // MARK: - IndexedPNGEncoder: signature + ImageIO validity (Task 1)

    @Test("encode produces an 8-byte PNG signature")
    func testEncode_hasPNGSignature() {
        // 2x1 image, 2-color palette.
        let data = IndexedPNGEncoder.encode(
            width: 2, height: 1,
            palette: [(255, 0, 0), (0, 255, 0)],
            alpha: nil,
            indices: [0, 1]
        )
        guard let data else {
            Issue.record("encode returned nil for valid input")
            return
        }
        let sig: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        #expect(Array(data.prefix(8)) == sig, "PNG must start with the 8-byte signature")
    }

    @Test("encode output opens via ImageIO as public.png with matching dimensions")
    func testEncode_opensAsValidPNG() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let width = 8, height = 4
        // Checkerboard of two palette entries.
        var indices = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                indices[y * width + x] = UInt8((x + y) % 2)
            }
        }
        let data = IndexedPNGEncoder.encode(
            width: width, height: height,
            palette: [(10, 20, 30), (200, 210, 220)],
            alpha: nil,
            indices: indices
        )
        guard let data else {
            Issue.record("encode returned nil for valid input")
            return
        }
        guard let decoded = decodeViaImageIO(data, in: dir) else {
            Issue.record("ImageIO could not decode the encoder output")
            return
        }
        #expect(decoded.type == UTType.png.identifier, "Decoded type must be public.png, got \(decoded.type)")
        #expect(decoded.width == width, "Decoded width \(decoded.width) must equal \(width)")
        #expect(decoded.height == height, "Decoded height \(decoded.height) must equal \(height)")
    }

    // MARK: - IndexedPNGEncoder: tRNS for transparency (Task 1)

    @Test("encode emits a tRNS chunk when any palette alpha < 255")
    func testEncode_emitsTRNSForTransparency() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let data = IndexedPNGEncoder.encode(
            width: 2, height: 2,
            palette: [(255, 0, 0), (0, 0, 255)],
            alpha: [0, 255],            // entry 0 fully transparent
            indices: [0, 1, 1, 0]
        )
        guard let data else {
            Issue.record("encode returned nil for valid input")
            return
        }
        // ASCII "tRNS" must appear in the byte stream.
        let trns: [UInt8] = Array("tRNS".utf8)
        let bytes = [UInt8](data)
        let containsTRNS = (0...(bytes.count - trns.count)).contains { i in
            Array(bytes[i..<(i + trns.count)]) == trns
        }
        #expect(containsTRNS, "tRNS chunk must be present when alpha < 255")

        // And the decoded image must have an alpha channel.
        let url = dir.appendingPathComponent("trns.png")
        try data.write(to: url)
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            Issue.record("Could not decode tRNS PNG")
            return
        }
        let alphaInfo = img.alphaInfo
        #expect(alphaInfo != .none && alphaInfo != .noneSkipFirst && alphaInfo != .noneSkipLast,
                "Decoded transparent PNG must carry an alpha channel, got \(alphaInfo.rawValue)")
    }

    @Test("encode omits tRNS when all alpha == 255")
    func testEncode_noTRNSWhenFullyOpaque() {
        let data = IndexedPNGEncoder.encode(
            width: 2, height: 1,
            palette: [(1, 2, 3), (4, 5, 6)],
            alpha: [255, 255],
            indices: [0, 1]
        )
        guard let data else {
            Issue.record("encode returned nil for valid input")
            return
        }
        let trns: [UInt8] = Array("tRNS".utf8)
        let bytes = [UInt8](data)
        let containsTRNS = (0...(bytes.count - trns.count)).contains { i in
            Array(bytes[i..<(i + trns.count)]) == trns
        }
        #expect(!containsTRNS, "tRNS must be omitted when fully opaque")
    }

    // MARK: - IndexedPNGEncoder: degenerate input -> nil (INFRA-17, Task 1)

    @Test("encode returns nil on degenerate input (INFRA-17)")
    func testEncode_degenerateInputReturnsNil() {
        // width 0
        #expect(IndexedPNGEncoder.encode(width: 0, height: 1, palette: [(0, 0, 0)], alpha: nil, indices: []) == nil)
        // height 0
        #expect(IndexedPNGEncoder.encode(width: 1, height: 0, palette: [(0, 0, 0)], alpha: nil, indices: []) == nil)
        // empty palette
        #expect(IndexedPNGEncoder.encode(width: 1, height: 1, palette: [], alpha: nil, indices: [0]) == nil)
        // indices length mismatch
        #expect(IndexedPNGEncoder.encode(width: 2, height: 2, palette: [(0, 0, 0)], alpha: nil, indices: [0, 0]) == nil)
        // index out of palette range
        #expect(IndexedPNGEncoder.encode(width: 1, height: 1, palette: [(0, 0, 0)], alpha: nil, indices: [5]) == nil)
        // palette too large (>256)
        let bigPalette = (0..<257).map { _ in (UInt8(0), UInt8(0), UInt8(0)) }
        #expect(IndexedPNGEncoder.encode(width: 1, height: 1, palette: bigPalette, alpha: nil, indices: [0]) == nil)
    }

    // MARK: - IndexedPNGEncoder: size win vs truecolor (Task 1)

    @Test("indexed PNG is smaller than truecolor RGBA re-encode of the same 64x64 image")
    func testEncode_smallerThanTruecolor() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let width = 64, height = 64
        // Build a quantizable image: a smooth horizontal gradient over a small palette.
        // Use 16 distinct grey levels -> heavily compressible as indexed.
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        var palette: [(UInt8, UInt8, UInt8)] = []
        for i in 0..<16 { palette.append((UInt8(i * 16), UInt8(i * 16), UInt8(i * 16))) }
        var indices = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let level = (x * 16) / width
                let p = palette[level]
                let off = (y * width + x) * 4
                rgba[off] = p.0; rgba[off + 1] = p.1; rgba[off + 2] = p.2; rgba[off + 3] = 255
                indices[y * width + x] = UInt8(level)
            }
        }

        guard let indexedData = IndexedPNGEncoder.encode(
            width: width, height: height,
            palette: palette, alpha: nil, indices: indices
        ) else {
            Issue.record("encode returned nil for valid gradient")
            return
        }

        guard let cgImage = makeCGImage(width: width, height: height, rgba: rgba),
              let truecolorData = truecolorPNGData(cgImage) else {
            Issue.record("Could not build truecolor baseline")
            return
        }

        #expect(indexedData.count < truecolorData.count,
                "Indexed PNG (\(indexedData.count)B) must be smaller than truecolor (\(truecolorData.count)B)")
    }

    // MARK: - PNGColorQuantizer: lossless on low-color input (Task 2)

    @Test("quantize round-trips a low-color image losslessly")
    func testQuantize_lowColorLossless() {
        let width = 4, height = 4
        // 3 distinct opaque colors arranged deterministically.
        let colors: [(UInt8, UInt8, UInt8)] = [(255, 0, 0), (0, 255, 0), (0, 0, 255)]
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        var expected = [(UInt8, UInt8, UInt8)]()
        for i in 0..<(width * height) {
            let c = colors[i % colors.count]
            let off = i * 4
            rgba[off] = c.0; rgba[off + 1] = c.1; rgba[off + 2] = c.2; rgba[off + 3] = 255
            expected.append(c)
        }
        guard let cg = makeCGImage(width: width, height: height, rgba: rgba) else {
            Issue.record("Could not build low-color CGImage")
            return
        }
        guard let q = PNGColorQuantizer.quantize(cgImage: cg, maxColors: 256) else {
            Issue.record("quantize returned nil for low-color image")
            return
        }
        #expect(q.palette.count == 3, "3 distinct colors must yield a 3-entry palette, got \(q.palette.count)")
        #expect(q.indices.count == width * height, "index map must cover all pixels")

        // Reconstruct through the palette and compare to expected source pixels exactly.
        for i in 0..<(width * height) {
            let entry = q.palette[Int(q.indices[i])]
            #expect(entry.0 == expected[i].0 && entry.1 == expected[i].1 && entry.2 == expected[i].2,
                    "Pixel \(i) must round-trip losslessly")
        }
    }

    // MARK: - PNGColorQuantizer: gradient -> 256 colors within tolerance (Task 2)

    @Test("quantize reduces a photographic gradient to maxColors and reconstructs within tolerance")
    func testQuantize_gradientToMaxColors() {
        let width = 64, height = 64
        // Smooth RGB gradient -> thousands of distinct colors.
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let off = (y * width + x) * 4
                rgba[off] = UInt8((x * 255) / (width - 1))
                rgba[off + 1] = UInt8((y * 255) / (height - 1))
                rgba[off + 2] = UInt8(((x + y) * 255) / (width + height - 2))
                rgba[off + 3] = 255
            }
        }
        guard let cg = makeCGImage(width: width, height: height, rgba: rgba) else {
            Issue.record("Could not build gradient CGImage")
            return
        }
        guard let q = PNGColorQuantizer.quantize(cgImage: cg, maxColors: 256) else {
            Issue.record("quantize returned nil for gradient")
            return
        }
        #expect(q.palette.count == 256, "Gradient must quantize to exactly 256 colors, got \(q.palette.count)")
        #expect(q.indices.count == width * height, "index map must cover all pixels")
        #expect(q.palette.count <= 256, "Palette must never exceed 256 entries")

        // Reconstruction error must be bounded (smooth gradient over 256 colors).
        var maxErr = 0
        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                let entry = q.palette[Int(q.indices[i])]
                let off = i * 4
                maxErr = max(maxErr, abs(Int(entry.0) - Int(rgba[off])))
                maxErr = max(maxErr, abs(Int(entry.1) - Int(rgba[off + 1])))
                maxErr = max(maxErr, abs(Int(entry.2) - Int(rgba[off + 2])))
            }
        }
        #expect(maxErr <= 48, "Max per-channel reconstruction error \(maxErr) must be within tolerance")
    }

    // MARK: - PNGColorQuantizer: alpha preserved (Task 2)

    @Test("quantize preserves transparency through the palette")
    func testQuantize_preservesAlpha() {
        let width = 4, height = 4
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        // Half the pixels transparent (alpha 0), half opaque red.
        // Use premultipliedLast: transparent pixels must have premultiplied RGB == 0.
        for i in 0..<(width * height) {
            let off = i * 4
            if i % 2 == 0 {
                rgba[off] = 0; rgba[off + 1] = 0; rgba[off + 2] = 0; rgba[off + 3] = 0   // transparent
            } else {
                rgba[off] = 200; rgba[off + 1] = 0; rgba[off + 2] = 0; rgba[off + 3] = 255 // opaque
            }
        }
        guard let cg = makeCGImage(width: width, height: height, rgba: rgba) else {
            Issue.record("Could not build alpha CGImage")
            return
        }
        guard let q = PNGColorQuantizer.quantize(cgImage: cg, maxColors: 256) else {
            Issue.record("quantize returned nil for alpha image")
            return
        }
        #expect(q.alpha.count == q.palette.count, "alpha array must align to palette")
        // There must be at least one palette entry with alpha < 255 (the transparent class).
        #expect(q.alpha.contains(where: { $0 < 128 }), "A transparent palette entry must exist")
        // And at least one fully/near opaque entry.
        #expect(q.alpha.contains(where: { $0 > 128 }), "An opaque palette entry must exist")
    }

    // MARK: - PNGColorQuantizer: degenerate input (INFRA-17, Task 2)

    @Test("quantize handles 1x1 and uniform images without crashing (INFRA-17)")
    func testQuantize_edgeImages() {
        // 1x1 single pixel.
        if let cg = makeCGImage(width: 1, height: 1, rgba: [123, 45, 67, 255]) {
            let q = PNGColorQuantizer.quantize(cgImage: cg, maxColors: 256)
            #expect(q != nil, "1x1 image must quantize")
            if let q {
                #expect(q.palette.count == 1, "1x1 yields a 1-color palette")
                #expect(q.indices.count == 1, "1x1 yields a 1-entry index map")
            }
        } else {
            Issue.record("Could not build 1x1 CGImage")
        }

        // Fully uniform 8x8 image (single color).
        let rgba = [UInt8](repeating: 0, count: 8 * 8 * 4).enumerated().map { idx, _ in
            idx % 4 == 3 ? UInt8(255) : UInt8(77)
        }
        if let cg = makeCGImage(width: 8, height: 8, rgba: rgba) {
            let q = PNGColorQuantizer.quantize(cgImage: cg, maxColors: 256)
            #expect(q != nil, "uniform image must quantize")
            #expect(q?.palette.count == 1, "uniform image yields a 1-color palette")
        } else {
            Issue.record("Could not build uniform CGImage")
        }
    }

    // MARK: - End-to-end: quantize -> encode -> valid, smaller PNG (Task 2)

    @Test("quantize output feeds IndexedPNGEncoder into a valid PNG smaller than truecolor")
    func testEndToEnd_quantizeThenEncode() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let width = 64, height = 64
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let off = (y * width + x) * 4
                rgba[off] = UInt8((x * 255) / (width - 1))
                rgba[off + 1] = UInt8((y * 255) / (height - 1))
                rgba[off + 2] = UInt8(((x * y) % 256))
                rgba[off + 3] = 255
            }
        }
        guard let cg = makeCGImage(width: width, height: height, rgba: rgba) else {
            Issue.record("Could not build gradient CGImage")
            return
        }
        guard let q = PNGColorQuantizer.quantize(cgImage: cg, maxColors: 256) else {
            Issue.record("quantize returned nil")
            return
        }
        guard let indexedData = IndexedPNGEncoder.encode(
            width: q.width, height: q.height,
            palette: q.palette,
            alpha: q.alpha,
            indices: q.indices
        ) else {
            Issue.record("encode returned nil for quantizer output")
            return
        }

        // Must open as a valid public.png with matching dimensions.
        guard let decoded = decodeViaImageIO(indexedData, in: dir) else {
            Issue.record("End-to-end PNG did not decode via ImageIO")
            return
        }
        #expect(decoded.type == UTType.png.identifier)
        #expect(decoded.width == width && decoded.height == height)

        // Must be smaller than a truecolor RGBA re-encode of the source.
        guard let truecolor = truecolorPNGData(cg) else {
            Issue.record("Could not build truecolor baseline")
            return
        }
        #expect(indexedData.count < truecolor.count,
                "End-to-end indexed PNG (\(indexedData.count)B) must beat truecolor (\(truecolor.count)B)")
    }
}
