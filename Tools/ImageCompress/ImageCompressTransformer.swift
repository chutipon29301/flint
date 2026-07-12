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
            guard writePNGCompressed(src: src, source: url, uti: uti, destURL: destURL, quality: quality) else {
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

            // 5e. Never-larger-than-ORIGINAL guard (GAP 1). ImageIO can re-save a JPEG/HEIC/TIFF
            //     LARGER than the source. If the re-encode grew, replace it with a byte-identical
            //     copy of the original so the output is never larger than the input. Use try?
            //     throughout; on any copy failure leave the (valid, same-format) re-encode in place
            //     rather than failing the whole op (INFRA-17). Size via fileSizeKey only (T-05-06B);
            //     destURL is collision-disambiguated so copyItem targets a fresh path (T-05-06A).
            let origSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? Int.max
            let newSize  = (try? destURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if newSize > origSize {
                try? FileManager.default.removeItem(at: destURL)
                try? FileManager.default.copyItem(at: url, to: destURL)
            }
        }

        // GAP 5: a cancel mid-flight still leaves a written destURL (the quantizer bails to the
        // truecolor/copy-through fallback, which writes). Delete it so a cancelled compress leaves
        // no output file on disk. The ViewModel already discards this result on cancel.
        if Task.isCancelled {
            try? FileManager.default.removeItem(at: destURL)
            return .failure(.writeFailed)
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

    // MARK: - Off-main wrapper (INFRA-18 + T-05-07A/B)

    /// Off-main entry point for the ViewModel's per-image work Task.
    ///
    /// `nonisolated` is REQUIRED: it guarantees this does NOT inherit MainActor isolation, so when the
    /// @MainActor ViewModel creates a `Task { }` that calls it, the heavy quantization runs on a default
    /// (background) executor — INFRA-18 off-main is preserved (testOffMainProof). The cooperative
    /// `Task.isCancelled` checkpoint inside `PNGColorQuantizer.quantize` reads the calling work Task's
    /// cancellation flag, which the ViewModel sets by cancelling that work Task directly (T-05-07A).
    ///
    /// The `autoreleasepool` lives here (it previously lived in the inline Task.detached closure) so peak
    /// CGImage memory stays bounded per image (INFRA-18, Pitfall 4).
    nonisolated static func compressOffMain(url: URL, quality: Double) -> Result<CompressedImage, CompressError> {
        autoreleasepool {
            compress(url: url, quality: quality)
        }
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
    private static func writePNGCompressed(src: CGImageSource, source: URL, uti: CFString, destURL: URL, quality: Double) -> Bool {
        // 1. Decode the source image. On failure, fall back to a plain truecolor re-encode.
        guard let cgImage = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            return truecolorReencode(src: src, uti: uti, destURL: destURL)
        }

        // 2. Quantize (adaptive palette sized to the quality target) → indexed-PNG encode.
        //    Any nil → truecolor re-encode. The adaptive step is the largest byte lever: a photo that
        //    the fixed-256 path could not shrink below quality typically needs far fewer colors (e.g.
        //    ~31-64), and fewer palette entries + a smaller index range compress dramatically better.
        guard let quantized = PNGColorQuantizer.quantizeAdaptive(cgImage: cgImage, quality: quality),
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

        // 3. Never-larger-than-ORIGINAL guard (GAP 1). The ORIGINAL SOURCE FILE is a writable
        //    candidate alongside {quantized, truecolor}. The common photographic case still wins
        //    outright and skips the truecolor re-encode entirely (cheap fileSizeKey comparison,
        //    never Data(contentsOf:) — T-05-06B).
        let origBytes = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? Int.max
        if indexedData.count < origBytes {
            // Quantized output already beats the source — write it directly (fast path).
            return (try? indexedData.write(to: destURL)) != nil
        }

        // Quantized output did NOT beat the source. Produce the plain truecolor re-encode and then
        // pick the SMALLEST of {original, quantized, truecolor}, so the user never gets a bigger
        // file than the original (GAP 1) — not merely never bigger than a truecolor re-encode.
        let truecolorURL = destURL.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString)-truecolor.png")
        defer { try? FileManager.default.removeItem(at: truecolorURL) }

        // truecolor byte count (Int.max if the re-encode could not be produced → never selected).
        var truecolorBytes = Int.max
        let truecolorOK = truecolorReencode(src: src, uti: uti, destURL: truecolorURL)
        if truecolorOK,
           let tb = try? truecolorURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            truecolorBytes = tb
        }

        // If the ORIGINAL is the smallest (or ties), copy it through byte-identically. destURL is
        // already collision-disambiguated (T-05-06A), so copyItem targets a fresh path.
        if origBytes <= indexedData.count && origBytes <= truecolorBytes {
            return (try? FileManager.default.copyItem(at: source, to: destURL)) != nil
        }

        // Original is not smallest. Keep whichever of {truecolor, quantized} is smaller.
        if truecolorOK && truecolorBytes <= indexedData.count {
            // Truecolor wins — move it into place.
            return (try? FileManager.default.moveItem(at: truecolorURL, to: destURL)) != nil
        }
        // Quantized is the smaller (or only) writable option — write it.
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
