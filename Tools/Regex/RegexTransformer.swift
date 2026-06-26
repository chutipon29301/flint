// Tools/Regex/RegexTransformer.swift
// Pure regex transformer — NO SwiftUI/AppKit imports (testable without UI).
// RGX-01..04: pattern+flags, matches with named/numbered groups, substitute.
// INFRA-17: Returns Result, never force-unwraps, never crashes on bad input.
// T-02-RGX-IV: Invalid pattern → Result.failure; 50MB input guard; empty/garbage tested.

import Foundation

// MARK: - RegexFlag

/// Flags supported by the Regex Tester (RGX-01).
/// Note: `g` (global) is NOT an NSRegularExpression.Options flag — it selects
/// enumerate-all vs first-only at the call site, not via Options.
enum RegexFlag: CaseIterable, Hashable, Sendable {
    case g  // global: enumerate all matches (vs first only)
    case i  // caseInsensitive
    case m  // anchorsMatchLines (multiline)
    case s  // dotMatchesLineSeparators
    case x  // allowCommentsAndWhitespace (verbose)
}

// MARK: - RegexMatch

/// A single match result returned by RegexTransformer.matches.
/// Carries the full-match range + string, all capture group ranges (numbered + named),
/// and the match index/position in the source string.
struct RegexMatch: Sendable {
    /// 0-based index within the list of all matches returned (first match = 0).
    let index: Int
    /// Character offset of the full match's start in the source string (UTF-16 NSRange.location).
    let position: Int
    /// NSRange of the full match in the source string (UTF-16 code units).
    let range: NSRange
    /// The full-match substring.
    let matchedString: String
    /// Numbered capture group strings, 0-indexed (group 1 → [0], group 2 → [1], …).
    let numberedGroups: [String]
    /// Named capture group strings keyed by name.
    let namedGroups: [String: String]
}

// MARK: - RegexTransformer

enum RegexTransformer {

    enum TransformError: LocalizedError, Sendable {
        case invalidPattern(String)
        case inputTooLarge
        case unknown(String)

        var errorDescription: String? {
            switch self {
            case .invalidPattern(let msg): return "Invalid pattern: \(msg)"
            case .inputTooLarge: return "Input too large (>50 MB)"
            case .unknown(let msg): return msg
            }
        }
    }

    // MARK: - Public API

    /// RGX-01/03: Find matches for `pattern` in `text`.
    /// If `.g` is in flags, returns all matches; otherwise first match only.
    /// `RegexMatch` carries full-match range, per-group ranges (numbered + named), index, position.
    /// Returns .failure for invalid patterns, .failure for oversized inputs, .success([]) for empty text.
    /// Never crashes on bad input (INFRA-17, T-02-RGX-IV).
    static func matches(
        pattern: String,
        flags: Set<RegexFlag>,
        in text: String
    ) -> Result<[RegexMatch], TransformError> {
        // INFRA-17: size guard — reject absurdly large inputs gracefully
        guard text.utf16.count <= 50_000_000 else {
            return .failure(.inputTooLarge)
        }

        let options = nsOptions(from: flags)
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            return .failure(.invalidPattern(error.localizedDescription))
        }

        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let global = flags.contains(.g)

        var rawMatches: [NSTextCheckingResult] = []
        if global {
            rawMatches = regex.matches(in: text, options: [], range: range)
        } else {
            if let first = regex.firstMatch(in: text, options: [], range: range) {
                rawMatches = [first]
            }
        }

        let result: [RegexMatch] = rawMatches.enumerated().compactMap { (idx, match) in
            let fullRange = match.range
            guard fullRange.location != NSNotFound else { return nil }
            let matchedString = nsText.substring(with: fullRange)

            // Numbered capture groups: 1-based in NSTextCheckingResult
            var numberedGroups: [String] = []
            let groupCount = regex.numberOfCaptureGroups
            for g in 1...max(1, groupCount) {
                guard g <= groupCount else { break }
                let gRange = match.range(at: g)
                if gRange.location != NSNotFound {
                    numberedGroups.append(nsText.substring(with: gRange))
                } else {
                    numberedGroups.append("")
                }
            }

            // Named capture groups: use named groups extracted from pattern
            let namedGroups = extractNamedGroups(from: match, in: nsText, regex: regex)

            return RegexMatch(
                index: idx,
                position: fullRange.location,
                range: fullRange,
                matchedString: matchedString,
                numberedGroups: numberedGroups,
                namedGroups: namedGroups
            )
        }

        return .success(result)
    }

    /// RGX-04: Replace matches of `pattern` in `text` with `template`.
    /// If `.g` is in flags, replaces all matches; otherwise only the first.
    /// Returns .failure for invalid patterns or oversized inputs. Never crashes (INFRA-17).
    static func substitute(
        pattern: String,
        flags: Set<RegexFlag>,
        in text: String,
        template: String
    ) -> Result<String, TransformError> {
        // INFRA-17: size guard
        guard text.utf16.count <= 50_000_000 else {
            return .failure(.inputTooLarge)
        }

        let options = nsOptions(from: flags)
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            return .failure(.invalidPattern(error.localizedDescription))
        }

        let nsText = NSMutableString(string: text)
        let range = NSRange(location: 0, length: nsText.length)
        let global = flags.contains(.g)

        if global {
            regex.replaceMatches(in: nsText, options: [], range: range, withTemplate: template)
        } else {
            // Replace only first match
            if let first = regex.firstMatch(in: text, options: [], range: range) {
                regex.replaceMatches(in: nsText, options: [], range: first.range, withTemplate: template)
            }
        }

        return .success(nsText as String)
    }

    // MARK: - Private Helpers

    /// Maps the Set<RegexFlag> to NSRegularExpression.Options.
    /// Note: `.g` is NOT an NSRegularExpression.Options value — it is handled at call site.
    private static func nsOptions(from flags: Set<RegexFlag>) -> NSRegularExpression.Options {
        var opts: NSRegularExpression.Options = []
        if flags.contains(.i) { opts.insert(.caseInsensitive) }
        if flags.contains(.m) { opts.insert(.anchorsMatchLines) }
        if flags.contains(.s) { opts.insert(.dotMatchesLineSeparators) }
        if flags.contains(.x) { opts.insert(.allowCommentsAndWhitespace) }
        return opts
    }

    /// Extracts named capture group results from a match using regex named group detection.
    private static func extractNamedGroups(
        from match: NSTextCheckingResult,
        in nsText: NSString,
        regex: NSRegularExpression
    ) -> [String: String] {
        // Extract named group names from the pattern using a meta-regex
        // Pattern: (?<name>...) — named group syntax in NSRegularExpression
        let namedGroupPattern = #"\(\?<([A-Za-z_][A-Za-z0-9_]*)>"#
        guard let metaRegex = try? NSRegularExpression(pattern: namedGroupPattern, options: []) else {
            return [:]
        }
        let patternStr = regex.pattern as NSString
        let patternRange = NSRange(location: 0, length: patternStr.length)
        let nameMatches = metaRegex.matches(in: regex.pattern, options: [], range: patternRange)
        let groupNames = nameMatches.compactMap { m -> String? in
            let r = m.range(at: 1)
            guard r.location != NSNotFound else { return nil }
            return patternStr.substring(with: r)
        }

        var result: [String: String] = [:]
        for name in groupNames {
            let groupRange = match.range(withName: name)
            if groupRange.location != NSNotFound {
                result[name] = nsText.substring(with: groupRange)
            }
        }
        return result
    }
}
