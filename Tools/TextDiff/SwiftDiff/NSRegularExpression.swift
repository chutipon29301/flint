// Vendored from https://github.com/turbolent/SwiftDiff
// Swift-6 patched: characters-API removed
// Original Swift port by turbolent; Swift-6 migration by Flint project 2026-06-26

import Foundation

extension NSRegularExpression {
    func matches(in string: String) -> [String] {
        let nsString = string as NSString
        let results = matches(in: string, range: NSRange(location: 0, length: nsString.length))
        return results.map { nsString.substring(with: $0.range) }
    }

    func firstMatch(in string: String) -> String? {
        let nsString = string as NSString
        guard let match = firstMatch(in: string, range: NSRange(location: 0, length: nsString.length)) else {
            return nil
        }
        return nsString.substring(with: match.range)
    }
}
