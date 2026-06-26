// Vendored from https://github.com/turbolent/SwiftDiff
// Swift-6 patched: characters-API removed, substring(to:/from:) replaced
// Original Swift port by turbolent; Swift-6 migration by Flint project 2026-06-26

import Foundation

extension String {
    /// Returns a substring from the given scalar offset to the end.
    func scalarsFromOffset(_ offset: Int) -> String {
        let scalars = unicodeScalars
        guard offset >= 0, offset < scalars.count else {
            return offset == scalars.count ? "" : self
        }
        let start = scalars.index(scalars.startIndex, offsetBy: offset)
        return String(scalars[start...])
    }

    /// Returns a substring from the start up to (not including) the given scalar offset.
    func scalarsToOffset(_ offset: Int) -> String {
        let scalars = unicodeScalars
        guard offset > 0 else { return "" }
        guard offset < scalars.count else { return self }
        let end = scalars.index(scalars.startIndex, offsetBy: offset)
        return String(scalars[..<end])
    }

    /// Returns a substring spanning [start, end) in Unicode scalar offsets.
    func scalarsInRange(_ start: Int, _ end: Int) -> String {
        let scalars = unicodeScalars
        let count = scalars.count
        let safeStart = max(0, min(start, count))
        let safeEnd = max(safeStart, min(end, count))
        let startIdx = scalars.index(scalars.startIndex, offsetBy: safeStart)
        let endIdx = scalars.index(scalars.startIndex, offsetBy: safeEnd)
        return String(scalars[startIdx..<endIdx])
    }

    subscript(range: Range<Int>) -> String {
        return scalarsInRange(range.lowerBound, range.upperBound)
    }

    subscript(range: PartialRangeFrom<Int>) -> String {
        return scalarsFromOffset(range.lowerBound)
    }

    subscript(range: PartialRangeUpTo<Int>) -> String {
        return scalarsToOffset(range.upperBound)
    }
}
