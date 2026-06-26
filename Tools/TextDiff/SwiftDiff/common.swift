// Vendored from https://github.com/turbolent/SwiftDiff
// Swift-6 patched: characters-API removed, substring(to:/from:) replaced
// Original algorithm: Google Diff Match and Patch by Neil Fraser
// Swift port by turbolent; Swift-6 migration by Flint project 2026-06-26

import Foundation

/// Returns the number of Unicode scalars common to the beginning of both strings.
func commonPrefixLength(_ text1: String, _ text2: String) -> Int {
    let scalars1 = text1.unicodeScalars
    let scalars2 = text2.unicodeScalars
    var i1 = scalars1.startIndex
    var i2 = scalars2.startIndex
    var count = 0
    while i1 != scalars1.endIndex && i2 != scalars2.endIndex {
        if scalars1[i1] != scalars2[i2] { break }
        scalars1.formIndex(after: &i1)
        scalars2.formIndex(after: &i2)
        count += 1
    }
    return count
}

/// Returns the number of Unicode scalars common to the end of both strings.
func commonSuffixLength(_ text1: String, _ text2: String) -> Int {
    let scalars1 = text1.unicodeScalars
    let scalars2 = text2.unicodeScalars
    var i1 = scalars1.endIndex
    var i2 = scalars2.endIndex
    var count = 0
    while i1 != scalars1.startIndex && i2 != scalars2.startIndex {
        scalars1.formIndex(before: &i1)
        scalars2.formIndex(before: &i2)
        if scalars1[i1] != scalars2[i2] { break }
        count += 1
    }
    return count
}

/// Split two texts into an array of strings. Reduce texts to hashes of lines.
func linesToChars(_ text1: String, _ text2: String) -> (String, String, [String]) {
    var lineArray: [String] = [""]
    var lineHash: [String: Int] = [:]

    func linesTo(_ text: String) -> String {
        var chars = ""
        var lineStart = text.startIndex
        while lineStart < text.endIndex {
            let lineEnd: String.Index
            if let nlRange = text.range(of: "\n", range: lineStart..<text.endIndex) {
                lineEnd = nlRange.upperBound
            } else {
                lineEnd = text.endIndex
            }
            let line = String(text[lineStart..<lineEnd])
            if let existing = lineHash[line] {
                if let scalar = Unicode.Scalar(existing) {
                    chars.append(Character(scalar))
                }
            } else {
                lineArray.append(line)
                let idx = lineArray.count - 1
                lineHash[line] = idx
                if let scalar = Unicode.Scalar(idx) {
                    chars.append(Character(scalar))
                }
            }
            lineStart = lineEnd
        }
        return chars
    }

    let chars1 = linesTo(text1)
    let chars2 = linesTo(text2)
    return (chars1, chars2, lineArray)
}

/// Rehydrate the text in a diff from line hashes to real lines.
func charsToLines(_ diffs: inout [Diff], _ lineArray: [String]) {
    for i in 0..<diffs.count {
        let diff = diffs[i]
        let text = diff.text
        var newText = ""
        for char in text.unicodeScalars {
            let idx = Int(char.value)
            if idx < lineArray.count {
                newText += lineArray[idx]
            }
        }
        switch diff {
        case .equal: diffs[i] = .equal(newText)
        case .insert: diffs[i] = .insert(newText)
        case .delete: diffs[i] = .delete(newText)
        }
    }
}
