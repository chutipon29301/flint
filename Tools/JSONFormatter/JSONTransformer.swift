// Tools/JSONFormatter/JSONTransformer.swift
// Pure JSON transformer — NO SwiftUI/AppKit imports (testable without UI).
// Source: RESEARCH.md § "Native API Recipes" → "JSON Tool (JSON-01..06)" [VERIFIED]
// INFRA-17: Returns Result, never force-unwraps, never crashes on bad input.

import Foundation

enum JSONTransformer {
    struct JSONError: Error, Equatable {
        let message: String
        let line: Int?
        let column: Int?

        var displayMessage: String {
            if let line, let column {
                return "Invalid JSON at line \(line), column \(column)"
            } else if let line {
                return "Invalid JSON at line \(line)"
            }
            return message
        }
    }

    // MARK: - Public API

    /// JSON-01: Pretty-print with configurable indent, preserving object key order.
    /// `indent`: 2 = two spaces, 4 = four spaces, 0 = tab character.
    static func prettyPrint(_ input: String, indent: Int = 2) -> Result<String, JSONError> {
        format(input) { $0.serialize(indentUnit: indentUnit(for: indent), sortKeys: false) }
    }

    /// JSON-02: Minify JSON (remove all whitespace), preserving key order.
    static func minify(_ input: String) -> Result<String, JSONError> {
        format(input) { $0.minified() }
    }

    /// JSON-04: Pretty-print with keys sorted alphabetically.
    static func prettyPrintSorted(_ input: String, indent: Int = 2) -> Result<String, JSONError> {
        format(input) { $0.serialize(indentUnit: indentUnit(for: indent), sortKeys: true) }
    }

    // MARK: - Private Helpers

    /// Shared parse → guard → serialize pipeline. INFRA-17: never crashes.
    private static func format(_ input: String, _ render: (OrderedJSON) -> String) -> Result<String, JSONError> {
        // INFRA-17: size guard — reject absurdly large inputs gracefully
        guard input.utf8.count <= 50_000_000 else {   // 50 MB limit
            return .failure(JSONError(message: "Input too large (>50 MB)", line: nil, column: nil))
        }
        do {
            let value = try OrderedJSON.parse(input)
            return .success(render(value))
        } catch let error as JSONParseError {
            return .failure(parseError(error, in: input))
        } catch {
            return .failure(JSONError(message: error.localizedDescription, line: nil, column: nil))
        }
    }

    private static func indentUnit(for indent: Int) -> String {
        switch indent {
        case 4: return "    "
        case 0: return "\t"
        default: return "  "
        }
    }

    /// JSON-03: Map a parser char offset to line + column (1-based).
    private static func parseError(_ error: JSONParseError, in source: String) -> JSONError {
        let scalars = Array(source.unicodeScalars)
        let offset = min(error.charOffset, scalars.count)
        var line = 1
        var column = 1
        for i in 0..<offset {
            if scalars[i] == "\n" {
                line += 1
                column = 1
            } else {
                column += 1
            }
        }
        return JSONError(message: "Invalid JSON", line: line, column: column)
    }

}
