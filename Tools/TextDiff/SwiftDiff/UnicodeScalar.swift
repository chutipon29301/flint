// Vendored from https://github.com/turbolent/SwiftDiff
// Swift-6 patched: characters-API removed
// Original Swift port by turbolent; Swift-6 migration by Flint project 2026-06-26

import Foundation

extension String.UnicodeScalarView {
    /// Returns the count of Unicode scalars in this view (O(n) but stable).
    var scalarCount: Int {
        return count
    }
}
