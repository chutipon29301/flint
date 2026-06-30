// Tools/ImageCompress/ImageCompressTransformer.swift
// Pure ImageIO round-trip compress + path disambiguation + size delta.
// NO SwiftUI/AppKit imports — pure transformer (thumbnail/NSImage work belongs in ViewModel/View).
// D-02: same-format-in same-format-out via CGImageSourceGetType.
// D-05: lossy formats (JPEG/HEIC/HEIF) get a quality prop. PNG takes the quantization path
//       (PNGColorQuantizer + IndexedPNGEncoder → indexed color-type-3 PNG, which ImageIO cannot
//       emit) to achieve pngquant-class savings on photographic content (UAT Test 8). TIFF and any
//       other lossless format keep the nil-props truecolor re-encode.
// D-06: honest reporting — the PNG path never hands the user a file larger than a plain truecolor
//       re-encode (it keeps whichever of {quantized, truecolor} is smaller).
// D-07/D-08: writes beside original as -compressed, disambiguates with -1/-2/… on collision.
// INFRA-17: every ImageIO/quantize/encode call guard-gated; function never throws; corrupt input
//           → typed .failure; any nil mid-path falls back to the truecolor re-encode.

import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

enum ImageCompressTransformer {

    // MARK: - Types

    enum CompressError: Error {
        case notAnImage
        case unsupportedType
        case writeFailed
    }

    struct CompressedImage {
        let destURL: URL
        let originalBytes: Int
        let compressedBytes: Int

        /// Percentage of bytes saved. Returns 0 when originalBytes is 0 (honest reporting, D-06).
        var percentSaved: Double {
            guard originalBytes > 0 else { return 0 }
            return (1.0 - Double(compressedBytes) / Double(originalBytes)) * 100
        }
    }

    // MARK: - Core compress function

    /// Re-encodes the image at `url` using the same source UTI (D-02 same-format-out),
    /// writing a collision-safe `-compressed` copy beside the original (D-07/D-08).
    /// Returns a typed Result — NEVER throws across the UI boundary (INFRA-17).
    ///
    /// - Parameters:
    ///   - url: Source image file URL (any ImageIO-decodable format).
    ///   - quality: 0.0–1.0 lossy compression quality. Applied only for JPEG/HEIC/HEIF;
    ///              PNG/TIFF receive `nil` props (D-05 lossless formats, quality not applicable).
    static func compress(url: URL, quality: Double) -> Result<CompressedImage, CompressError> {
        // 1. Decodable-image gate (corrupt/non-image → graceful failure, not crash — INFRA-17)
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return .failure(.notAnImage)
        }

        // 2. Read the SOURCE format → guarantees same-format-out (D-02). nil = undecodable data.
        guard let uti = CGImageSourceGetType(src) else {
            return .failure(.unsupportedType)
        }

        // 3. Verify there is at least one image frame (detects 0-byte / header-only files)
        guard CGImageSourceGetCount(src) > 0 else {
            return .failure(.notAnImage)
        }

        // 4. Collision-safe destination path beside the original (D-07/D-08)
        let destURL = disambiguatedCompressedURL(for: url)

        // 5. PNG takes the quantization path; everything else takes the ImageIO re-encode path.
        let utType = UTType(uti as String)
        let isPNG = utType?.conforms(to: .png) == true

        if isPNG {
            // Quantize → indexed-PNG encode → never-larger guard (D-06). Any nil falls back to
            // the truecolor re-encode; the function still returns a typed Result (INFRA-17).
            guard writePNGCompressed(src: src, source: url, uti: uti, destURL: destURL) else {
                try? FileManager.default.removeItem(at: destURL)
                return .failure(.writeFailed)
            }
        } else {
            // 5a. Destination uses the SOURCE's UTI — no format-mapping table needed (D-02)
            guard let dst = CGImageDestinationCreateWithURL(destURL as CFURL, uti, 1, nil) else {
                return .failure(.writeFailed)
            }

            // 5b. Quality only applies to lossy formats (JPEG/HEIC/HEIF). TIFF/other → nil props (D-05).
            let isLossy = utType?.conforms(to: .jpeg) == true
                || utType?.conforms(to: .heic) == true
                || utType == UTType("public.heif")
            let props: CFDictionary? = isLossy
                ? [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
                : nil

            // 5c. AddImageFromSource (NOT AddImage) → carries EXIF, ICC profile, orientation forward.
            //     Prevents the "re-encoded photo rotated 90°" orientation-loss bug (RESEARCH Pitfall 1).
            CGImageDestinationAddImageFromSource(dst, src, 0, props)

            // 5d. Finalize returns false on failure — gate it, clean up partial write.
            guard CGImageDestinationFinalize(dst) else {
                try? FileManager.default.removeItem(at: destURL) // clean up partial write
                return .failure(.writeFailed)
            }
        }

        // 9. Size delta for the hero "% saved" metric — never Data(contentsOf:) for large files
        let origBytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let newBytes  = (try? destURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

        return .success(CompressedImage(
            destURL: destURL,
            originalBytes: origBytes,
            compressedBytes: newBytes
        ))
    }

    // MARK: - PNG quantization path (UAT Test 8)

    /// Writes a compressed PNG to `destURL` using quantization, with a truecolor-re-encode fallback
    /// and a never-larger guard (D-06). Returns false only if NO output could be written at all
    /// (so the caller can surface a typed .writeFailed without throwing — INFRA-17).
    ///
    /// Strategy:
    ///   1. Decode frame 0 → CGImage. nil → truecolor re-encode (never fail outright).
    ///   2. PNGColorQuantizer.quantize → IndexedPNGEncoder.encode → indexed PNG `Data`.
    ///      Any nil at this stage → truecolor re-encode.
    ///   3. Compare the quantized byte count against the original source file size. If the quantized
    ///      output is NOT smaller than the original, also produce the plain truecolor re-encode and
    ///      keep whichever of {quantized, truecolor} is smaller (D-06: never hand back a bigger file).
    ///   4. Write the chosen bytes to destURL.
    private static func writePNGCompressed(src: CGImageSource, source: URL, uti: CFString, destURL: URL) -> Bool {
        // 1. Decode the source image. On failure, fall back to a plain truecolor re-encode.
        guard let cgImage = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            return truecolorReencode(src: src, uti: uti, destURL: destURL)
        }

        // 2. Quantize → indexed-PNG encode. Any nil → truecolor re-encode.
        guard let quantized = PNGColorQuantizer.quantize(cgImage: cgImage),
              let indexedData = IndexedPNGEncoder.encode(
                width: quantized.width,
                height: quantized.height,
                palette: quantized.palette,
                alpha: quantized.alpha,
                indices: quantized.indices
              )
        else {
            return truecolorReencode(src: src, uti: uti, destURL: destURL)
        }

        // 3. Never-larger guard (D-06). The common photographic case wins outright and skips the
        //    truecolor re-encode entirely (cheap in-memory / file-size comparison, no huge reads).
        let origBytes = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? Int.max
        if indexedData.count < origBytes {
            // Quantized output already beats the source — write it directly.
            return (try? indexedData.write(to: destURL)) != nil
        }

        // Quantized output did NOT beat the source: produce the plain truecolor re-encode and keep
        // whichever of {quantized, truecolor} is smaller, so the user never gets a bigger file.
        let truecolorURL = destURL.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString)-truecolor.png")
        defer { try? FileManager.default.removeItem(at: truecolorURL) }

        if truecolorReencode(src: src, uti: uti, destURL: truecolorURL),
           let truecolorBytes = try? truecolorURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            if truecolorBytes <= indexedData.count {
                // Truecolor wins — move it into place.
                return (try? FileManager.default.moveItem(at: truecolorURL, to: destURL)) != nil
            }
        }
        // Quantized is the smaller (or only) option — write it.
        return (try? indexedData.write(to: destURL)) != nil
    }

    /// Plain truecolor PNG re-encode via ImageIO (carries metadata forward), written to `destURL`.
    /// Returns true on success.
    private static func truecolorReencode(src: CGImageSource, uti: CFString, destURL: URL) -> Bool {
        guard let dst = CGImageDestinationCreateWithURL(destURL as CFURL, uti, 1, nil) else {
            return false
        }
        CGImageDestinationAddImageFromSource(dst, src, 0, nil)
        return CGImageDestinationFinalize(dst)
    }

    // MARK: - Path disambiguation helper

    /// Computes a destination URL beside `original` that never overwrites an existing file.
    ///
    /// Examples:
    ///   `photo.jpg` → `photo-compressed.jpg`  (if that doesn't exist)
    ///   `photo.jpg` → `photo-compressed-1.jpg` (if photo-compressed.jpg already exists)
    ///
    /// Pure path math — fully unit-testable without touching disk for the base case.
    ///
    /// Note: A best-effort TOCTOU window exists between the `fileExists` check and the write.
    /// Acceptable for a single-user, non-sandboxed desktop tool (RESEARCH A3).
    static func disambiguatedCompressedURL(for original: URL) -> URL {
        let dir  = original.deletingLastPathComponent()
        let ext  = original.pathExtension                   // preserve original extension (D-02)
        let stem = original.deletingPathExtension().lastPathComponent

        let fm = FileManager.default

        func candidate(_ suffix: String) -> URL {
            dir.appendingPathComponent("\(stem)-compressed\(suffix)")
               .appendingPathExtension(ext)
        }

        var url = candidate("")
        var n = 1
        while fm.fileExists(atPath: url.path) {             // never clobber (D-08)
            url = candidate("-\(n)")
            n += 1
        }
        return url
    }
}
