// Vendored from https://github.com/turbolent/SwiftDiff
// Swift-6 patched: characters-API removed, substring(to:/from:) replaced with subscript
// Original algorithm: Google Diff Match and Patch by Neil Fraser
// Swift port by turbolent; Swift-6 migration by Flint project 2026-06-26
//
// Public API preserved exactly:
//   public func diff(text1: String, text2: String, timeout: CFTimeInterval? = nil) -> [Diff]
//   public enum Diff: Equatable { case equal(String); case insert(String); case delete(String); var text: String }

import Foundation

/// A single edit in a diff result.
public enum Diff: Equatable, CustomStringConvertible {
    case equal(String)
    case insert(String)
    case delete(String)

    /// The text payload of this diff segment.
    public var text: String {
        switch self {
        case .equal(let t): return t
        case .insert(let t): return t
        case .delete(let t): return t
        }
    }

    public var description: String {
        switch self {
        case .equal(let t): return "equal(\"\(t)\")"
        case .insert(let t): return "insert(\"\(t)\")"
        case .delete(let t): return "delete(\"\(t)\")"
        }
    }
}

/// Compute the diff between two strings.
///
/// Returns a list of `Diff` segments. The segments cover all characters of both
/// `text1` and `text2`: concatenating `.equal` + `.insert` segments reconstructs
/// `text2`; concatenating `.equal` + `.delete` segments reconstructs `text1`.
///
/// - Parameters:
///   - text1: Old string.
///   - text2: New string.
///   - timeout: Maximum seconds to spend computing; nil means no limit.
public func diff(text1: String, text2: String, timeout: CFTimeInterval? = nil) -> [Diff] {
    let deadline: CFAbsoluteTime? = timeout.map { CFAbsoluteTimeGetCurrent() + $0 }

    // Shortcut: identical
    if text1 == text2 {
        if text1.isEmpty { return [] }
        return [.equal(text1)]
    }

    // Shortcut: one empty
    if text1.isEmpty { return [.insert(text2)] }
    if text2.isEmpty { return [.delete(text1)] }

    // Trim common prefix
    let prefixLen = commonPrefixLength(text1, text2)
    let scalars1 = text1.unicodeScalars
    let scalars2 = text2.unicodeScalars
    let count1 = scalars1.count
    let count2 = scalars2.count

    let commonPrefix = prefixLen > 0 ? text1[0..<prefixLen] : ""

    // Trim common suffix
    let suffixLen = commonSuffixLength(
        text1[prefixLen..<count1],
        text2[prefixLen..<count2]
    )
    let commonSuffix = suffixLen > 0 ? text1[(count1 - suffixLen)..<count1] : ""

    let mid1 = text1[prefixLen..<(count1 - suffixLen)]
    let mid2 = text2[prefixLen..<(count2 - suffixLen)]

    var diffs = computeDiff(mid1, mid2, deadline: deadline)

    if !commonPrefix.isEmpty { diffs.insert(.equal(commonPrefix), at: 0) }
    if !commonSuffix.isEmpty { diffs.append(.equal(commonSuffix)) }

    cleanupMerge(&diffs)
    return diffs
}

// MARK: - Core diff computation

private func computeDiff(_ text1: String, _ text2: String, deadline: CFAbsoluteTime?) -> [Diff] {
    if text1.isEmpty { return [.insert(text2)] }
    if text2.isEmpty { return [.delete(text1)] }

    let scalars1 = text1.unicodeScalars
    let scalars2 = text2.unicodeScalars
    let len1 = scalars1.count
    let len2 = scalars2.count

    // Substring detection: does one string contain the other?
    if len1 == 1 || len2 == 1 {
        // Single-character — fall through to Myers
    } else if let range = text2.range(of: text1) {
        // text1 is inside text2
        let before = String(text2[text2.startIndex..<range.lowerBound])
        let after = String(text2[range.upperBound..<text2.endIndex])
        var result: [Diff] = []
        if !before.isEmpty { result.append(.insert(before)) }
        result.append(.equal(text1))
        if !after.isEmpty { result.append(.insert(after)) }
        return result
    } else if let range = text1.range(of: text2) {
        let before = String(text1[text1.startIndex..<range.lowerBound])
        let after = String(text1[range.upperBound..<text1.endIndex])
        var result: [Diff] = []
        if !before.isEmpty { result.append(.delete(before)) }
        result.append(.equal(text2))
        if !after.isEmpty { result.append(.delete(after)) }
        return result
    }

    // Myers diff via bisect
    return bisect(text1, text2, deadline: deadline)
}

// MARK: - Myers diff (bisect)

private func bisect(_ text1: String, _ text2: String, deadline: CFAbsoluteTime?) -> [Diff] {
    let scalars1 = Array(text1.unicodeScalars)
    let scalars2 = Array(text2.unicodeScalars)
    let len1 = scalars1.count
    let len2 = scalars2.count
    let maxD = (len1 + len2 + 1) / 2
    let vLen = 2 * maxD
    var v1 = [Int](repeating: -1, count: vLen)
    var v2 = [Int](repeating: -1, count: vLen)
    v1[maxD + 1] = 0
    v2[maxD + 1] = 0
    let delta = len1 - len2
    let front = (delta % 2 != 0)

    var k1start = 0
    var k1end = 0
    var k2start = 0
    var k2end = 0

    for d in 0..<maxD {
        if let dl = deadline, CFAbsoluteTimeGetCurrent() > dl {
            break
        }

        // Forward path
        var k1 = -d + k1start
        while k1 <= d - k1end {
            let k1Offset = maxD + k1
            var x1: Int
            if k1 == -d || (k1 != d && v1[k1Offset - 1] < v1[k1Offset + 1]) {
                x1 = v1[k1Offset + 1]
            } else {
                x1 = v1[k1Offset - 1] + 1
            }
            var y1 = x1 - k1
            while x1 < len1 && y1 < len2 && scalars1[x1] == scalars2[y1] {
                x1 += 1
                y1 += 1
            }
            v1[k1Offset] = x1
            if x1 > len1 {
                k1end += 2
            } else if y1 > len2 {
                k1start += 2
            } else if front {
                let k2Offset = maxD + delta - k1
                if k2Offset >= 0 && k2Offset < vLen && v2[k2Offset] != -1 {
                    let x2 = len1 - v2[k2Offset]
                    if x1 >= x2 {
                        return bisectSplit(text1, text2, x1, y1, deadline: deadline)
                    }
                }
            }
            k1 += 2
        }

        // Reverse path
        var k2 = -d + k2start
        while k2 <= d - k2end {
            let k2Offset = maxD + k2
            var x2: Int
            if k2 == -d || (k2 != d && v2[k2Offset - 1] < v2[k2Offset + 1]) {
                x2 = v2[k2Offset + 1]
            } else {
                x2 = v2[k2Offset - 1] + 1
            }
            var y2 = x2 - k2
            while x2 < len1 && y2 < len2 && scalars1[len1 - x2 - 1] == scalars2[len2 - y2 - 1] {
                x2 += 1
                y2 += 1
            }
            v2[k2Offset] = x2
            if x2 > len1 {
                k2end += 2
            } else if y2 > len2 {
                k2start += 2
            } else if !front {
                let k1Offset = maxD + delta - k2
                if k1Offset >= 0 && k1Offset < vLen && v1[k1Offset] != -1 {
                    let x1 = v1[k1Offset]
                    let y1 = x1 - (k1Offset - maxD)
                    let x2Mirror = len1 - x2
                    if x1 >= x2Mirror {
                        return bisectSplit(text1, text2, x1, y1, deadline: deadline)
                    }
                }
            }
            k2 += 2
        }
    }

    // Timeout: no common middle found
    return [.delete(text1), .insert(text2)]
}

private func bisectSplit(_ text1: String, _ text2: String,
                         _ x: Int, _ y: Int,
                         deadline: CFAbsoluteTime?) -> [Diff] {
    let len1 = text1.unicodeScalars.count
    let len2 = text2.unicodeScalars.count
    let text1a = text1[0..<x]
    let text2a = text2[0..<y]
    let text1b = text1[x..<len1]
    let text2b = text2[y..<len2]
    var diffs = computeDiff(text1a, text2a, deadline: deadline)
    diffs += computeDiff(text1b, text2b, deadline: deadline)
    return diffs
}

// MARK: - Cleanup merge

/// Reorder and merge like-edit sections. Merge equalities.
private func cleanupMerge(_ diffs: inout [Diff]) {
    diffs.append(.equal(""))  // sentinel
    var pointer = 0
    var countDelete = 0
    var countInsert = 0
    var textDelete = ""
    var textInsert = ""

    while pointer < diffs.count {
        switch diffs[pointer] {
        case .insert(let text):
            countInsert += 1
            textInsert += text
            pointer += 1
        case .delete(let text):
            countDelete += 1
            textDelete += text
            pointer += 1
        case .equal(let text):
            // Upon reaching an equality, check for prior redundancies.
            if countDelete + countInsert > 1 {
                if countDelete != 0 && countInsert != 0 {
                    // Factor out common prefix
                    let prefixLen = commonPrefixLength(textInsert, textDelete)
                    if prefixLen != 0 {
                        let offset = pointer - countDelete - countInsert - 1
                        if offset >= 0, case .equal(let prev) = diffs[offset] {
                            diffs[offset] = .equal(prev + textInsert[0..<prefixLen])
                        } else {
                            diffs.insert(.equal(textInsert[0..<prefixLen]), at: 0)
                            pointer += 1
                        }
                        textInsert = textInsert[prefixLen...]
                        textDelete = textDelete[prefixLen...]
                    }
                    // Factor out common suffix
                    let suffixLen = commonSuffixLength(textInsert, textDelete)
                    if suffixLen != 0 {
                        let insLen = textInsert.unicodeScalars.count
                        let delLen = textDelete.unicodeScalars.count
                        if case .equal(let next) = diffs[pointer] {
                            diffs[pointer] = .equal(textInsert[(insLen - suffixLen)..<insLen] + next)
                        }
                        textInsert = textInsert[0..<(insLen - suffixLen)]
                        textDelete = textDelete[0..<(delLen - suffixLen)]
                    }
                }
                // Delete the offending records and add the merged ones.
                let start = pointer - countDelete - countInsert
                diffs.removeSubrange(start..<pointer)
                pointer = start
                if !textDelete.isEmpty {
                    diffs.insert(.delete(textDelete), at: pointer)
                    pointer += 1
                }
                if !textInsert.isEmpty {
                    diffs.insert(.insert(textInsert), at: pointer)
                    pointer += 1
                }
            } else if pointer != 0, case .equal(let prev) = diffs[pointer - 1] {
                // Merge this equality with the previous one.
                diffs[pointer - 1] = .equal(prev + text)
                diffs.remove(at: pointer)
                pointer -= 1
            }
            countInsert = 0
            countDelete = 0
            textDelete = ""
            textInsert = ""
            pointer += 1
        }
    }

    if diffs.last?.text == "" {
        diffs.removeLast()
    }

    // Second pass: look for single edits surrounded on both sides by equalities
    // which can be shifted sideways to eliminate an equality.
    var changes = false
    pointer = 1
    while pointer < diffs.count - 1 {
        if case .equal = diffs[pointer - 1], case .equal = diffs[pointer + 1] {
            let prev = diffs[pointer - 1].text
            let curr = diffs[pointer].text
            let next = diffs[pointer + 1].text

            if curr.hasSuffix(prev) {
                let currLen = curr.unicodeScalars.count
                let prevLen = prev.unicodeScalars.count
                let nextLen = next.unicodeScalars.count

                let newCurr = prev + curr[0..<(currLen - prevLen)]
                switch diffs[pointer] {
                case .insert: diffs[pointer] = .insert(newCurr)
                case .delete: diffs[pointer] = .delete(newCurr)
                default: break
                }
                diffs[pointer + 1] = .equal(prev + next)
                diffs.remove(at: pointer - 1)
                changes = true
            } else if curr.hasPrefix(next) {
                let currLen = curr.unicodeScalars.count
                let nextLen = next.unicodeScalars.count

                diffs[pointer - 1] = .equal(prev + next)
                let newCurr = curr[nextLen..<currLen] + next
                switch diffs[pointer] {
                case .insert: diffs[pointer] = .insert(newCurr)
                case .delete: diffs[pointer] = .delete(newCurr)
                default: break
                }
                diffs.remove(at: pointer + 1)
                changes = true
            }
        }
        pointer += 1
    }

    if changes {
        cleanupMerge(&diffs)
    }
}
