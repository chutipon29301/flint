// Vendored from https://github.com/turbolent/SwiftDiff
// Swift-6 patched: characters-API removed, substring(to:/from:) replaced
// Original algorithm: Google Diff Match and Patch by Neil Fraser
// Swift port by turbolent; Swift-6 migration by Flint project 2026-06-26

import Foundation

/// Reduce the number of edits by eliminating operationally trivial equalities.
public func cleanupEfficiency(_ diffs: inout [Diff]) {
    var changes = false
    var equalities: [Int] = []
    var lastEquality = ""
    var pointer = 0
    var preIns = false
    var preDel = false
    var postIns = false
    var postDel = false

    while pointer < diffs.count {
        switch diffs[pointer] {
        case .equal(let text):
            if text.unicodeScalars.count < 4 && (postIns || postDel) {
                equalities.append(pointer)
                preIns = postIns
                preDel = postDel
                lastEquality = text
            } else {
                equalities.removeAll()
                lastEquality = ""
            }
            postIns = false
            postDel = false
        case .insert:
            postIns = true
        case .delete:
            postDel = true
        }

        let fiveEditSurround = !lastEquality.isEmpty &&
            (preIns && preDel && postIns && postDel) ||
            ((lastEquality.unicodeScalars.count < 2) &&
             (preIns || preDel) && (postIns || postDel))

        if fiveEditSurround {
            // Duplicate record
            if let last = equalities.last {
                diffs.insert(.delete(lastEquality), at: last)
                if last + 1 < diffs.count, case .insert = diffs[last + 1] {
                    // already is insert
                } else {
                    diffs.insert(.insert(lastEquality), at: last + 1)
                }
            }
            // No-op replacement of equality
            equalities.removeLast()
            _ = equalities.popLast()
            pointer = equalities.last.map { $0 + 1 } ?? -1
            equalities.removeAll()
            preIns = false
            preDel = false
            postIns = false
            postDel = false
            lastEquality = ""
            changes = true
        }
        pointer += 1
    }

    if changes {
        var d = diffs
        cleanupMergePublic(&d)
        diffs = d
    }
}

/// Reduce the number of edits by eliminating semantically trivial equalities.
public func cleanupSemantic(_ diffs: inout [Diff]) {
    var changes = false
    var equalities: [Int] = []
    var lastEquality: String? = nil
    var pointer = 0
    var lengthInsertions1 = 0
    var lengthDeletions1 = 0
    var lengthInsertions2 = 0
    var lengthDeletions2 = 0

    while pointer < diffs.count {
        switch diffs[pointer] {
        case .equal(let text):
            equalities.append(pointer)
            lengthInsertions1 = lengthInsertions2
            lengthDeletions1 = lengthDeletions2
            lengthInsertions2 = 0
            lengthDeletions2 = 0
            lastEquality = text
        case .insert(let text):
            lengthInsertions2 += text.unicodeScalars.count
        case .delete(let text):
            lengthDeletions2 += text.unicodeScalars.count
        }

        if let eq = lastEquality {
            let eqLen = eq.unicodeScalars.count
            if eqLen <= max(lengthInsertions1, lengthDeletions1) &&
                eqLen <= max(lengthInsertions2, lengthDeletions2) {
                if let last = equalities.last {
                    diffs.insert(.delete(eq), at: last)
                    if last + 2 < diffs.count {
                        if case .insert = diffs[last + 1] {
                            // already has insert type
                        } else {
                            diffs.insert(.insert(eq), at: last + 1)
                        }
                    } else {
                        diffs.insert(.insert(eq), at: last + 1)
                    }
                    equalities.removeLast()
                    _ = equalities.popLast()
                    pointer = equalities.last.map { $0 + 1 } ?? -1
                    equalities.removeAll()
                    lengthInsertions1 = 0
                    lengthDeletions1 = 0
                    lengthInsertions2 = 0
                    lengthDeletions2 = 0
                    lastEquality = nil
                    changes = true
                }
            }
        }
        pointer += 1
    }

    if changes {
        var d = diffs
        cleanupMergePublic(&d)
        diffs = d
    }

    cleanupSemanticLossless(&diffs)
}

/// Look for single edits surrounded on both sides by equalities which can be
/// shifted sideways to align the edit to a word boundary.
private func cleanupSemanticLossless(_ diffs: inout [Diff]) {
    func score(_ one: String, _ two: String) -> Int {
        guard !one.isEmpty && !two.isEmpty else { return 6 }
        let char1 = one.unicodeScalars.last!
        let char2 = two.unicodeScalars.first!
        let nonAlpha1 = !CharacterSet.alphanumerics.contains(char1)
        let nonAlpha2 = !CharacterSet.alphanumerics.contains(char2)
        let whitespace1 = CharacterSet.whitespaces.contains(char1)
        let whitespace2 = CharacterSet.whitespaces.contains(char2)
        let lineBreak1 = char1 == Unicode.Scalar("\n") || char1 == Unicode.Scalar("\r")
        let lineBreak2 = char2 == Unicode.Scalar("\n") || char2 == Unicode.Scalar("\r")
        let blankLine1 = lineBreak1 && (one.hasSuffix("\n\n") || one.hasSuffix("\r\n\r\n"))
        let blankLine2 = lineBreak2 && (two.hasPrefix("\n\n") || two.hasPrefix("\r\n\r\n"))
        if blankLine1 || blankLine2 { return 5 }
        if lineBreak1 || lineBreak2 { return 4 }
        if nonAlpha1 && !whitespace1 && whitespace2 { return 3 }
        if whitespace1 || whitespace2 { return 2 }
        if nonAlpha1 || nonAlpha2 { return 1 }
        return 0
    }

    var pointer = 1
    while pointer < diffs.count - 1 {
        if case .equal(let prevText) = diffs[pointer - 1],
           case .equal(let nextText) = diffs[pointer + 1] {
            var equality1 = prevText
            var edit = diffs[pointer].text
            var equality2 = nextText

            // First shift the edit as far left as possible.
            let suffixLen = commonSuffixLength(equality1, edit)
            if suffixLen > 0 {
                let e1Len = equality1.unicodeScalars.count
                let eLen = edit.unicodeScalars.count
                let commonStr = equality1[(e1Len - suffixLen)..<e1Len]
                equality1 = equality1[0..<(e1Len - suffixLen)]
                edit = commonStr + edit[0..<(eLen - suffixLen)]
                equality2 = commonStr + equality2
            }

            // Second shift the edit as far right as possible.
            var bestEquality1 = equality1
            var bestEdit = edit
            var bestEquality2 = equality2
            var bestScore = score(equality1, edit) + score(edit, equality2)

            while !edit.isEmpty && !equality2.isEmpty {
                let editLen = edit.unicodeScalars.count
                let e2Len = equality2.unicodeScalars.count
                guard let editFirst = edit.unicodeScalars.first,
                      let eq2First = equality2.unicodeScalars.first,
                      editFirst == eq2First else { break }
                equality1 += String(editFirst)
                edit = edit[1..<editLen] + String(eq2First)
                equality2 = equality2[1..<e2Len]
                let thisScore = score(equality1, edit) + score(edit, equality2)
                if thisScore >= bestScore {
                    bestScore = thisScore
                    bestEquality1 = equality1
                    bestEdit = edit
                    bestEquality2 = equality2
                }
            }

            if prevText != bestEquality1 {
                if !bestEquality1.isEmpty {
                    diffs[pointer - 1] = .equal(bestEquality1)
                } else {
                    diffs.remove(at: pointer - 1)
                    pointer -= 1
                }
                switch diffs[pointer] {
                case .insert: diffs[pointer] = .insert(bestEdit)
                case .delete: diffs[pointer] = .delete(bestEdit)
                default: break
                }
                if !bestEquality2.isEmpty {
                    diffs[pointer + 1] = .equal(bestEquality2)
                } else {
                    diffs.remove(at: pointer + 1)
                    pointer -= 1
                }
            }
        }
        pointer += 1
    }
}

// Internal re-export so cleanup.swift can call the merge function from diff.swift
func cleanupMergePublic(_ diffs: inout [Diff]) {
    // Re-implement a basic merge here to avoid circular dependency issues
    // (diff.swift's cleanupMerge is private)
    var changed = false
    var i = 0
    while i < diffs.count - 1 {
        switch (diffs[i], diffs[i + 1]) {
        case (.equal(let a), .equal(let b)):
            diffs[i] = .equal(a + b)
            diffs.remove(at: i + 1)
            changed = true
        case (.insert(let a), .insert(let b)):
            diffs[i] = .insert(a + b)
            diffs.remove(at: i + 1)
            changed = true
        case (.delete(let a), .delete(let b)):
            diffs[i] = .delete(a + b)
            diffs.remove(at: i + 1)
            changed = true
        default:
            i += 1
        }
    }
    // Remove empty diffs
    diffs = diffs.filter { !$0.text.isEmpty }
}
