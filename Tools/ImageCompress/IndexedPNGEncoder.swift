// Tools/ImageCompress/IndexedPNGEncoder.swift
// Pure-Swift indexed-color (color-type 3) PNG writer.
// Root-cause fix for UAT Test 8: Apple's CGImageDestination cannot emit palette PNGs,
// so a quantized image (PNGColorQuantizer) must be written by hand to achieve pngquant-class savings.
//
// NO SwiftUI/AppKit imports — pure transformer. Foundation + Compression (zlib deflate) + CoreGraphics only.
// INFRA-17: every input is validated up front; degenerate input returns nil (never crashes, never force-unwraps).
// Zero external dependencies (libimagequant/pngquant are GPL/LGPL and would block App Store v2 sandbox).

import Foundation
import Compression

/// Writes a palette + per-pixel index map as a valid color-type-3 (indexed) PNG.
///
/// PNG wire format produced:
///   - 8-byte signature
///   - IHDR (bit depth 8, color type 3, no interlace)
///   - PLTE (R,G,B per palette entry)
///   - tRNS (only when any palette alpha < 255)
///   - IDAT (zlib-deflated scanline stream; each row prefixed with filter byte 0x00 None)
///   - IEND
///
/// Every chunk is framed as: length(UInt32 BE) + 4-byte type + data + CRC-32(UInt32 BE over type+data).
enum IndexedPNGEncoder {

    /// Encodes a palette + index map into PNG `Data`.
    ///
    /// - Parameters:
    ///   - width: Image width in pixels. Must be > 0.
    ///   - height: Image height in pixels. Must be > 0.
    ///   - palette: Up to 256 RGB triples, in palette order. Must be non-empty.
    ///   - alpha: Optional per-palette-entry alpha (aligned to `palette`). When present and any
    ///            value < 255, a tRNS chunk is emitted. Pass nil for fully-opaque images.
    ///   - indices: Per-pixel palette indices, length == width*height, each < palette.count.
    /// - Returns: A valid PNG `Data`, or nil on any validation failure (INFRA-17, no crash).
    static func encode(
        width: Int,
        height: Int,
        palette: [(UInt8, UInt8, UInt8)],
        alpha: [UInt8]?,
        indices: [UInt8]
    ) -> Data? {
        // --- Input validation (INFRA-17: nil, never crash) ---
        guard width > 0, height > 0 else { return nil }
        guard !palette.isEmpty, palette.count <= 256 else { return nil }
        guard indices.count == width * height else { return nil }
        if let alpha, !alpha.isEmpty, alpha.count != palette.count { return nil }
        let paletteCount = palette.count
        for idx in indices where Int(idx) >= paletteCount { return nil }

        // Adaptive bit depth: an indexed PNG only needs enough bits to address the palette.
        // <=2 colors -> 1 bit/px, <=4 -> 2, <=16 -> 4, else 8. Packing ≤16-color images this way
        // shrinks the raw scanline stream 2-8x before DEFLATE (the flat-art / low-color win — a
        // 4-color image drops from 8-bit to 2-bit, ~74% smaller). 8-bit path is unchanged.
        let bitDepth = bitDepthFor(paletteCount)

        var png = Data()

        // 1. PNG signature.
        png.append(contentsOf: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

        // 2. IHDR.
        var ihdr = Data()
        ihdr.append(beUInt32(UInt32(width)))
        ihdr.append(beUInt32(UInt32(height)))
        ihdr.append(UInt8(bitDepth))  // adaptive: 1/2/4/8 (see bitDepthFor)
        ihdr.append(3)    // color type 3 = indexed-color
        ihdr.append(0)    // compression method (deflate)
        ihdr.append(0)    // filter method
        ihdr.append(0)    // interlace = none
        png.append(chunk(type: "IHDR", data: ihdr))

        // 3. PLTE — 3 bytes per palette entry.
        var plte = Data(capacity: paletteCount * 3)
        for (r, g, b) in palette {
            plte.append(r); plte.append(g); plte.append(b)
        }
        png.append(chunk(type: "PLTE", data: plte))

        // 4. tRNS — only when alpha is present and any entry is non-opaque.
        if let alpha, alpha.contains(where: { $0 < 255 }) {
            png.append(chunk(type: "tRNS", data: Data(alpha)))
        }

        // 5. IDAT — bit-packed scanlines, zlib-deflated. Two filter strategies are DEFLATED and the
        //    smaller IDAT wins:
        //      • all-None  (best for smooth/low-entropy index maps under a weak deflate)
        //      • per-row min-SAD choice of None/Sub/Up/Average/Paeth (best for structured images)
        //    We must pick by ACTUAL deflated size, not the SAD heuristic alone: Apple's Compression
        //    framework zlib is a fast/weak matcher, and on noisy data min-SAD filtering can inflate the
        //    stream (the filtered bytes have higher per-byte entropy than a strong matcher would exploit).
        //    Trial-deflating both — the honest measure — guarantees filtering never makes a file bigger.
        //    Sub-8-bit depths pack multiple pixels per byte where filtering rarely helps → None only.
        let packedNone = packedScanlines(width: width, height: height, bitDepth: bitDepth, indices: indices)
        guard let deflatedNone = zlibDeflate(packedNone) else { return nil }

        var bestIDAT = deflatedNone
        if bitDepth == 8, let filtered = filteredScanlines(width: width, height: height, indices: indices),
           let deflatedFiltered = zlibDeflate(filtered),
           deflatedFiltered.count < bestIDAT.count {
            bestIDAT = deflatedFiltered
        }
        png.append(chunk(type: "IDAT", data: bestIDAT))

        // 6. IEND (empty).
        png.append(chunk(type: "IEND", data: Data()))

        return png
    }

    // MARK: - Adaptive bit depth + scanline filtering

    /// Smallest PNG-legal indexed bit depth that can address `paletteCount` entries.
    private static func bitDepthFor(_ paletteCount: Int) -> Int {
        switch paletteCount {
        case ...2:  return 1
        case ...4:  return 2
        case ...16: return 4
        default:    return 8
        }
    }

    /// Raw scanlines with filter byte 0x00 (None) on every row, packing `8/bitDepth` pixels per byte
    /// for sub-8-bit depths (big-endian within the byte, final partial byte left-aligned per the PNG
    /// spec). The universal, always-valid stream — used directly for packed depths and as the baseline
    /// the 8-bit filtered stream must beat.
    private static func packedScanlines(width: Int, height: Int, bitDepth: Int, indices: [UInt8]) -> Data {
        let rowByteLen = (width * bitDepth + 7) / 8
        var out = Data(capacity: height * (rowByteLen + 1))
        if bitDepth == 8 {
            var cursor = 0
            for _ in 0..<height {
                out.append(0x00)
                out.append(contentsOf: indices[cursor..<(cursor + width)])
                cursor += width
            }
            return out
        }
        let ppb = 8 / bitDepth
        let mask = UInt8((1 << bitDepth) - 1)
        for y in 0..<height {
            out.append(0x00)
            let base = y * width
            var byte: UInt8 = 0
            var filled = 0
            for x in 0..<width {
                byte = (byte << bitDepth) | (indices[base + x] & mask)
                filled += 1
                if filled == ppb { out.append(byte); byte = 0; filled = 0 }
            }
            if filled > 0 { byte <<= (ppb - filled) * bitDepth; out.append(byte) }
        }
        return out
    }

    /// 8-bit-only scanlines where each row picks the min-SAD filter of None/Sub/Up/Average/Paeth
    /// (libpng's heuristic). bpp = 1 (one index byte per pixel) for the left/up-left taps. The caller
    /// trial-deflates this against `packedScanlines` and keeps whichever IDAT is actually smaller.
    private static func filteredScanlines(width: Int, height: Int, indices: [UInt8]) -> Data? {
        let rowByteLen = width
        var out = Data(capacity: height * (rowByteLen + 1))
        var prev = [UInt8](repeating: 0, count: rowByteLen)
        var cur  = [UInt8](repeating: 0, count: rowByteLen)
        var candidate = [UInt8](repeating: 0, count: rowByteLen)
        var best = [UInt8](repeating: 0, count: rowByteLen)

        for y in 0..<height {
            let base = y * width
            for x in 0..<rowByteLen { cur[x] = indices[base + x] }

            var bestType: UInt8 = 0
            var bestScore = Int.max
            for filter in UInt8(0)...4 {
                applyFilter(filter, cur: cur, prev: prev, bpp: 1, into: &candidate)
                let score = sumAbsDiff(candidate)
                if score < bestScore {
                    bestScore = score
                    bestType = filter
                    swap(&candidate, &best)            // keep the winning bytes without recomputing
                }
            }
            out.append(bestType)
            out.append(contentsOf: best)
            swap(&prev, &cur)
        }
        return out
    }

    /// PNG filter types 0-4 (None/Sub/Up/Average/Paeth), byte-wise, wrapping mod 256.
    private static func applyFilter(_ type: UInt8, cur: [UInt8], prev: [UInt8], bpp: Int, into out: inout [UInt8]) {
        let n = cur.count
        for i in 0..<n {
            let a = i >= bpp ? Int(cur[i - bpp]) : 0        // left
            let b = Int(prev[i])                            // up
            let c = i >= bpp ? Int(prev[i - bpp]) : 0       // up-left
            let x = Int(cur[i])
            let v: Int
            switch type {
            case 1:  v = x - a
            case 2:  v = x - b
            case 3:  v = x - (a + b) / 2
            case 4:  v = x - paeth(a, b, c)
            default: v = x                                   // 0 = None
            }
            out[i] = UInt8(v & 0xFF)
        }
    }

    private static func paeth(_ a: Int, _ b: Int, _ c: Int) -> Int {
        let p = a + b - c
        let pa = abs(p - a), pb = abs(p - b), pc = abs(p - c)
        if pa <= pb && pa <= pc { return a }
        if pb <= pc { return b }
        return c
    }

    /// Sum of absolute filtered values treated as signed bytes — libpng's filter-selection heuristic.
    private static func sumAbsDiff(_ bytes: [UInt8]) -> Int {
        var sum = 0
        for byte in bytes {
            let signed = byte < 128 ? Int(byte) : Int(byte) - 256
            sum += abs(signed)
        }
        return sum
    }

    // MARK: - Chunk framing

    /// Frames a chunk: length(BE) + type(ASCII) + data + CRC-32(BE over type+data).
    private static func chunk(type: String, data: Data) -> Data {
        var out = Data()
        let typeBytes = Array(type.utf8)
        out.append(beUInt32(UInt32(data.count)))
        out.append(contentsOf: typeBytes)
        out.append(data)

        var crcInput = Data(typeBytes)
        crcInput.append(data)
        out.append(beUInt32(crc32(crcInput)))
        return out
    }

    // MARK: - Big-endian serialization (PNG is network byte order)

    private static func beUInt32(_ value: UInt32) -> Data {
        Data([
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ])
    }

    // MARK: - PNG CRC-32 (polynomial 0xEDB88320, table-driven; NO zlib bridging dependency)

    private static let crcTable: [UInt32] = {
        var table = [UInt32](repeating: 0, count: 256)
        for n in 0..<256 {
            var c = UInt32(n)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            table[n] = c
        }
        return table
    }()

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = crcTable[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }

    // MARK: - zlib deflate (Compression framework) with header/checksum guarantee

    /// Deflates `input` into a zlib stream (header + DEFLATE + Adler-32) as PNG requires.
    /// COMPRESSION_ZLIB on Apple platforms emits a RAW deflate stream WITHOUT the 2-byte zlib
    /// header or trailing Adler-32, so we wrap it: 0x78 0x01 + <raw deflate> + Adler-32(BE).
    private static func zlibDeflate(_ input: Data) -> Data? {
        guard !input.isEmpty else { return nil }

        // Generous destination buffer: worst case for incompressible data is slightly larger than input.
        let dstCapacity = input.count + (input.count / 2) + 64
        var dst = [UInt8](repeating: 0, count: dstCapacity)

        let written = input.withUnsafeBytes { (srcPtr: UnsafeRawBufferPointer) -> Int in
            guard let srcBase = srcPtr.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return dst.withUnsafeMutableBufferPointer { dstBuf -> Int in
                compression_encode_buffer(
                    dstBuf.baseAddress!, dstCapacity,
                    srcBase, input.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0 else { return nil }

        let rawDeflate = dst[0..<written]

        // Determine whether the framework already produced a zlib container.
        // A zlib header is 0x78 followed by a flag byte whose (CMF*256+FLG) % 31 == 0.
        if rawDeflate.count >= 2 {
            let cmf = UInt16(rawDeflate[rawDeflate.startIndex])
            let flg = UInt16(rawDeflate[rawDeflate.startIndex + 1])
            let isZlibHeader = (cmf & 0x0F) == 0x08 && ((cmf << 8 | flg) % 31 == 0)
            if isZlibHeader {
                // Framework already framed it as zlib — use as-is.
                return Data(rawDeflate)
            }
        }

        // Wrap raw deflate as a zlib stream: header + deflate + Adler-32(BE).
        var out = Data()
        out.append(contentsOf: [0x78, 0x01]) // CMF=0x78 (32K window, deflate), FLG=0x01 (fastest, check passes)
        out.append(Data(rawDeflate))
        out.append(beUInt32(adler32(input)))
        return out
    }

    /// Adler-32 checksum over `data` (zlib trailer). MOD_ADLER = 65521.
    private static func adler32(_ data: Data) -> UInt32 {
        let modAdler: UInt32 = 65521
        var a: UInt32 = 1
        var b: UInt32 = 0
        for byte in data {
            a = (a + UInt32(byte)) % modAdler
            b = (b + a) % modAdler
        }
        return (b << 16) | a
    }
}
