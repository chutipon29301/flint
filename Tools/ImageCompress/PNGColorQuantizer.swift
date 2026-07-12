// Tools/ImageCompress/PNGColorQuantizer.swift
// Pure-Swift median-cut color quantizer: truecolor RGBA CGImage -> <=256-color palette + per-pixel index map.
// Root-cause fix for UAT Test 8: photographic PNGs barely shrink because the transformer re-encodes them
// as truecolor RGBA. Reducing to an 8-bit colormap (this quantizer) + an indexed PNG (IndexedPNGEncoder)
// reproduces pngquant-class savings with ZERO external dependencies (libimagequant/pngquant are GPL/LGPL,
// blocking App Store v2 sandbox — locked decision).
//
// NO SwiftUI/AppKit imports — pure transformer. CoreGraphics (CGImage input) + Foundation only.
// INFRA-17: zero/huge dimensions and failed context creation return nil; no force-unwraps on pixel reads.

import Foundation
import CoreGraphics

/// Reduces a truecolor image to a <=256-entry palette using classic median-cut.
enum PNGColorQuantizer {

    /// Result of quantization: a palette + alpha aligned to it + a per-pixel index map.
    struct QuantizedImage {
        let width: Int
        let height: Int
        let palette: [(UInt8, UInt8, UInt8)]
        let alpha: [UInt8]          // aligned to `palette`
        let indices: [UInt8]        // length width*height, each < palette.count
        /// True mean-squared error (averaged over R,G,B) between each source pixel and its assigned
        /// palette color — the real fidelity signal the adaptive-palette search ranks on. 0 = lossless.
        var mse: Double = 0
    }

    /// Quantizes with an ADAPTIVE palette sized to a perceptual-quality target (like pngquant's
    /// `--quality` floor). Instead of always emitting 256 colors, it tries a descending ladder of
    /// palette sizes and returns the SMALLEST palette whose reconstruction still meets `quality`.
    /// Fewer colors → a smaller index range → far better DEFLATE (the #1 size lever on photos).
    ///
    /// - Parameters:
    ///   - quality: 0.0–1.0 from the app's quality slider. Maps to a max-allowed mean-squared error:
    ///              quality 1.0 ⇒ tightest (near-lossless, keeps 256); lower quality ⇒ tolerates more
    ///              error ⇒ accepts smaller palettes. A flat/low-color image naturally lands on a tiny
    ///              palette regardless (its error is ~0 at few colors).
    /// - Returns: A `QuantizedImage`, or nil on degenerate input / decode failure / cancellation.
    static func quantizeAdaptive(cgImage: CGImage, quality: Double) -> QuantizedImage? {
        // Per-channel RMS error budget in 0–255 units. quality 1.0 → ~2 (near-lossless),
        // quality 0.0 → ~24 (aggressive). Squared → MSE budget compared against the candidate below.
        let q = min(max(quality, 0), 1)
        let rmsBudget = 2.0 + (1.0 - q) * 22.0
        let mseBudget = rmsBudget * rmsBudget

        // Palette ladder, smallest first. Return the first (smallest) palette within the error budget;
        // fall back to the largest (best-quality) candidate if none qualifies. Each rung reuses the
        // existing median-cut `quantize`, so cancellation + INFRA-17 nil-safety are inherited.
        let ladder = [16, 32, 64, 128, 256]
        var best: QuantizedImage?   // largest tried, used if nothing meets the budget
        for colors in ladder {
            if Task.isCancelled { return nil }
            guard let candidate = quantize(cgImage: cgImage, maxColors: colors) else { continue }
            best = candidate
            if candidate.mse <= mseBudget {
                return candidate    // smallest palette that is "good enough" (real per-pixel MSE)
            }
        }
        return best                 // none met the budget → keep the highest-fidelity one
    }

    /// Quantizes `cgImage` into at most `maxColors` (capped at 256) palette entries.
    ///
    /// - Returns: A `QuantizedImage`, or nil on degenerate input / decode failure (INFRA-17).
    static func quantize(cgImage: CGImage, maxColors: Int = 256) -> QuantizedImage? {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        let cap = max(1, min(maxColors, 256))

        // --- 1. Decode into a tightly-packed RGBA8 buffer (premultipliedLast, matching test helpers). ---
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ok: Bool = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let ctx = CGContext(
                    data: base,
                    width: width, height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return false }
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { return nil }

        let pixelCount = width * height

        // --- 2. Collect pixels as packed RGBA UInt32 keys; tally counts for representative averaging. ---
        // Each pixel: (r,g,b,a). Pack as r<<24 | g<<16 | b<<8 | a.
        var pixelKeys = [UInt32](repeating: 0, count: pixelCount)
        for i in 0..<pixelCount {
            let o = i * 4
            let r = UInt32(pixels[o])
            let g = UInt32(pixels[o + 1])
            let b = UInt32(pixels[o + 2])
            let a = UInt32(pixels[o + 3])
            pixelKeys[i] = (r << 24) | (g << 16) | (b << 8) | a
        }

        // Unique colors with occurrence counts (median-cut splits on unique colors, weighted by count).
        var counts: [UInt32: Int] = [:]
        counts.reserveCapacity(min(pixelCount, 4096))
        for (i, key) in pixelKeys.enumerated() {
            // Cooperative cancellation checkpoint (T-05-07A). For a many-unique-color image this
            // dictionary build over ~pixelCount entries is itself heavy and precedes median-cut.
            // Checked every 4096 entries → amortized O(1). Returning nil routes through the
            // transformer's truecolor fallback / typed Result (INFRA-17).
            if i & 0xFFF == 0 && Task.isCancelled { return nil }
            counts[key, default: 0] += 1
        }

        // --- 3. Median-cut on RGB; carry alpha along for per-box averaging. ---
        struct ColorEntry { let r, g, b, a: UInt8; let count: Int }
        var allColors: [ColorEntry] = []
        allColors.reserveCapacity(counts.count)
        for (key, c) in counts {
            allColors.append(ColorEntry(
                r: UInt8((key >> 24) & 0xFF),
                g: UInt8((key >> 16) & 0xFF),
                b: UInt8((key >> 8) & 0xFF),
                a: UInt8(key & 0xFF),
                count: c
            ))
        }

        // Box = a slice of the color list. Split the box with the widest color axis at its median.
        struct Box { var colors: [ColorEntry] }

        // widest axis range for a box
        func axisRanges(_ colors: [ColorEntry]) -> (rRange: Int, gRange: Int, bRange: Int) {
            var rMin = 255, rMax = 0, gMin = 255, gMax = 0, bMin = 255, bMax = 0
            for c in colors {
                rMin = min(rMin, Int(c.r)); rMax = max(rMax, Int(c.r))
                gMin = min(gMin, Int(c.g)); gMax = max(gMax, Int(c.g))
                bMin = min(bMin, Int(c.b)); bMax = max(bMax, Int(c.b))
            }
            return (rMax - rMin, gMax - gMin, bMax - bMin)
        }

        var boxes: [Box] = [Box(colors: allColors)]

        // Split until we reach `cap` boxes or no box can be split further.
        while boxes.count < cap {
            // Cooperative cancellation checkpoint (T-05-07A). Median-cut over a many-unique-color
            // image (each iteration sorts a large color slice) can dominate runtime, so the per-pixel
            // mapping loop alone is not responsive enough — check here too. O(1), outside the inner
            // sort. Returning nil routes through the transformer's truecolor fallback (INFRA-17).
            if Task.isCancelled { return nil }
            // Pick the splittable box with the largest single-axis range.
            var targetIndex = -1
            var bestRange = 0
            for (i, box) in boxes.enumerated() where box.colors.count > 1 {
                let (rr, gr, br) = axisRanges(box.colors)
                let m = max(rr, max(gr, br))
                if m > bestRange { bestRange = m; targetIndex = i }
            }
            if targetIndex == -1 { break } // nothing left to split

            var box = boxes[targetIndex]
            let (rr, gr, br) = axisRanges(box.colors)
            // Sort along the widest axis, then split at the median position.
            if rr >= gr && rr >= br {
                box.colors.sort { $0.r < $1.r }
            } else if gr >= br {
                box.colors.sort { $0.g < $1.g }
            } else {
                box.colors.sort { $0.b < $1.b }
            }
            let mid = box.colors.count / 2
            let lower = Box(colors: Array(box.colors[0..<mid]))
            let upper = Box(colors: Array(box.colors[mid...]))
            boxes[targetIndex] = lower
            boxes.append(upper)
        }

        // --- 4. Build palette + alpha from per-box (count-weighted) averages. ---
        var palette: [(UInt8, UInt8, UInt8)] = []
        var paletteAlpha: [UInt8] = []
        palette.reserveCapacity(boxes.count)
        paletteAlpha.reserveCapacity(boxes.count)
        for box in boxes where !box.colors.isEmpty {
            var sumR = 0, sumG = 0, sumB = 0, sumA = 0, total = 0
            for c in box.colors {
                let w = c.count
                sumR += Int(c.r) * w
                sumG += Int(c.g) * w
                sumB += Int(c.b) * w
                sumA += Int(c.a) * w
                total += w
            }
            guard total > 0 else { continue }
            palette.append((
                UInt8(clamping: (sumR + total / 2) / total),
                UInt8(clamping: (sumG + total / 2) / total),
                UInt8(clamping: (sumB + total / 2) / total)
            ))
            paletteAlpha.append(UInt8(clamping: (sumA + total / 2) / total))
        }
        guard !palette.isEmpty else { return nil }

        // --- 5. Map each pixel to the nearest palette entry (RGB squared distance), cached by RGBA key. ---
        var lookupCache: [UInt32: UInt8] = [:]
        lookupCache.reserveCapacity(min(counts.count, 4096))

        func nearestIndex(r: Int, g: Int, b: Int) -> UInt8 {
            var best = 0
            var bestDist = Int.max
            for (i, p) in palette.enumerated() {
                let dr = r - Int(p.0)
                let dg = g - Int(p.1)
                let db = b - Int(p.2)
                let dist = dr * dr + dg * dg + db * db
                if dist < bestDist { bestDist = dist; best = i; if dist == 0 { break } }
            }
            return UInt8(best)
        }

        var indices = [UInt8](repeating: 0, count: pixelCount)
        for i in 0..<pixelCount {
            // Cooperative cancellation checkpoint (T-05-07A): this per-pixel nearest-palette mapping
            // is the other long loop. Checked every 4096 pixels → amortized O(1). Returning nil routes
            // through the transformer's truecolor fallback / typed Result — never a crash (INFRA-17).
            if i & 0xFFF == 0 && Task.isCancelled { return nil }
            let key = pixelKeys[i]
            if let cached = lookupCache[key] {
                indices[i] = cached
            } else {
                let o = i * 4
                let idx = nearestIndex(r: Int(pixels[o]), g: Int(pixels[o + 1]), b: Int(pixels[o + 2]))
                lookupCache[key] = idx
                indices[i] = idx
            }
        }

        // --- 6. Exact reconstruction MSE (over R,G,B,A), iterating UNIQUE colors only. ---
        //   Every unique RGBA already has its assigned palette index in `lookupCache` and its pixel
        //   frequency in `counts`, so this is one pass over the (small) unique-color set — not all pixels.
        //   ALPHA is included: a palette entry carries one alpha (tRNS), so shrinking the palette also
        //   coarsens the alpha gradient. Folding alpha error in here stops quantizeAdaptive from picking
        //   a tiny palette that looks fine in RGB but destroys a soft alpha edge (bug found on radial-
        //   alpha images). Averaged over 4 channels. Used by quantizeAdaptive for the quality search.
        var sqErr = 0.0
        for (key, freq) in counts {
            guard let pi = lookupCache[key] else { continue }
            let r = Int((key >> 24) & 0xFF), g = Int((key >> 16) & 0xFF)
            let b = Int((key >> 8) & 0xFF),  a = Int(key & 0xFF)
            let p = palette[Int(pi)]
            let dr = r - Int(p.0), dg = g - Int(p.1), db = b - Int(p.2), da = a - Int(paletteAlpha[Int(pi)])
            sqErr += Double((dr*dr + dg*dg + db*db + da*da) * freq)
        }
        let mse = sqErr / (Double(max(pixelCount, 1)) * 4.0)

        return QuantizedImage(
            width: width,
            height: height,
            palette: palette,
            alpha: paletteAlpha,
            indices: indices,
            mse: mse
        )
    }
}
