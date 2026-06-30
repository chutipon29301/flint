// Tools/ImageCompress/ImageCompressTransformer.swift
// Pure ImageIO round-trip compress + path disambiguation + size delta.
// NO SwiftUI/AppKit imports — pure transformer (thumbnail/NSImage work belongs in ViewModel/View).
// D-02: same-format-in same-format-out via CGImageSourceGetType.
// D-05: lossy formats (JPEG/HEIC/HEIF) get quality prop; PNG/TIFF get nil props.
// D-07/D-08: writes beside original as -compressed, disambiguates with -1/-2/… on collision.
// INFRA-17: every ImageIO call guard-gated; function never throws; corrupt input → typed .failure.

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

        // 5. Destination uses the SOURCE's UTI — no format-mapping table needed (D-02)
        guard let dst = CGImageDestinationCreateWithURL(destURL as CFURL, uti, 1, nil) else {
            return .failure(.writeFailed)
        }

        // 6. Quality only applies to lossy formats (JPEG/HEIC/HEIF). PNG/TIFF → nil props (D-05).
        //    Re-encoded PNG/TIFF may grow slightly — that is honest reporting (Open Question 1, RESEARCH).
        let utType = UTType(uti as String)
        let isLossy = utType?.conforms(to: .jpeg) == true
            || utType?.conforms(to: .heic) == true
            || utType == UTType("public.heif")
        let props: CFDictionary? = isLossy
            ? [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
            : nil

        // 7. AddImageFromSource (NOT AddImage) → carries EXIF, ICC profile, orientation forward.
        //    Prevents the "re-encoded photo rotated 90°" orientation-loss bug (RESEARCH Pitfall 1).
        CGImageDestinationAddImageFromSource(dst, src, 0, props)

        // 8. Finalize returns false on failure — gate it, clean up partial write, never assume success
        guard CGImageDestinationFinalize(dst) else {
            try? FileManager.default.removeItem(at: destURL) // clean up partial write
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
