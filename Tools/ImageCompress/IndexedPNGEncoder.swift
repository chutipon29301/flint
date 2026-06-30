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

        var png = Data()

        // 1. PNG signature.
        png.append(contentsOf: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

        // 2. IHDR.
        var ihdr = Data()
        ihdr.append(beUInt32(UInt32(width)))
        ihdr.append(beUInt32(UInt32(height)))
        ihdr.append(8)    // bit depth
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

        // 5. IDAT — raw scanlines (filter byte 0x00 + one index byte per pixel), zlib-deflated.
        var raw = Data(capacity: height * (width + 1))
        var cursor = 0
        for _ in 0..<height {
            raw.append(0x00) // filter type None
            raw.append(contentsOf: indices[cursor..<(cursor + width)])
            cursor += width
        }
        guard let deflated = zlibDeflate(raw) else { return nil }
        png.append(chunk(type: "IDAT", data: deflated))

        // 6. IEND (empty).
        png.append(chunk(type: "IEND", data: Data()))

        return png
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
