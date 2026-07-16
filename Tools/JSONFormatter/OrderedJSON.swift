// Tools/JSONFormatter/OrderedJSON.swift
// Order-preserving JSON parser + serializer.
// JSONSerialization returns an unordered NSDictionary, so pretty-printing without
// .sortedKeys scrambles object keys. This parser remembers insertion order.
// INFRA-17: never crashes on bad input — throws JSONParseError instead.

import Foundation

/// A JSON value that preserves object key order.
indirect enum OrderedJSON {
    case null
    case bool(Bool)
    case number(String)      // kept as the original literal so 1.0 / 1e3 / big ints round-trip
    case string(String)
    case array([OrderedJSON])
    case object([(String, OrderedJSON)])
}

struct JSONParseError: Error {
    let charOffset: Int      // byte/scalar offset into the input where parsing failed
}

extension OrderedJSON {
    /// Parse JSON text, preserving object key order. Throws JSONParseError on malformed input.
    static func parse(_ text: String) throws -> OrderedJSON {
        var p = Parser(scalars: Array(text.unicodeScalars))
        p.skipWhitespace()
        let value = try p.parseValue()
        p.skipWhitespace()
        guard p.isAtEnd else { throw JSONParseError(charOffset: p.pos) }
        return value
    }

    private struct Parser {
        let scalars: [Unicode.Scalar]
        var pos = 0

        var isAtEnd: Bool { pos >= scalars.count }
        func peek() -> Unicode.Scalar? { pos < scalars.count ? scalars[pos] : nil }

        mutating func skipWhitespace() {
            while pos < scalars.count {
                switch scalars[pos] {
                case " ", "\t", "\n", "\r": pos += 1
                default: return
                }
            }
        }

        mutating func parseValue() throws -> OrderedJSON {
            skipWhitespace()
            guard let c = peek() else { throw JSONParseError(charOffset: pos) }
            switch c {
            case "{": return try parseObject()
            case "[": return try parseArray()
            case "\"": return .string(try parseString())
            case "t", "f": return try parseBool()
            case "n": return try parseNull()
            case "-", "0"..."9": return .number(try parseNumber())
            default: throw JSONParseError(charOffset: pos)
            }
        }

        mutating func expect(_ s: Unicode.Scalar) throws {
            guard peek() == s else { throw JSONParseError(charOffset: pos) }
            pos += 1
        }

        mutating func parseObject() throws -> OrderedJSON {
            try expect("{")
            var pairs: [(String, OrderedJSON)] = []
            skipWhitespace()
            if peek() == "}" { pos += 1; return .object(pairs) }
            while true {
                skipWhitespace()
                guard peek() == "\"" else { throw JSONParseError(charOffset: pos) }
                let key = try parseString()
                skipWhitespace()
                try expect(":")
                let value = try parseValue()
                pairs.append((key, value))
                skipWhitespace()
                switch peek() {
                case ",": pos += 1
                case "}": pos += 1; return .object(pairs)
                default: throw JSONParseError(charOffset: pos)
                }
            }
        }

        mutating func parseArray() throws -> OrderedJSON {
            try expect("[")
            var items: [OrderedJSON] = []
            skipWhitespace()
            if peek() == "]" { pos += 1; return .array(items) }
            while true {
                let value = try parseValue()
                items.append(value)
                skipWhitespace()
                switch peek() {
                case ",": pos += 1
                case "]": pos += 1; return .array(items)
                default: throw JSONParseError(charOffset: pos)
                }
            }
        }

        mutating func parseString() throws -> String {
            try expect("\"")
            var result = String.UnicodeScalarView()
            while let c = peek() {
                pos += 1
                switch c {
                case "\"":
                    return String(result)
                case "\\":
                    guard let esc = peek() else { throw JSONParseError(charOffset: pos) }
                    pos += 1
                    switch esc {
                    case "\"": result.append("\"")
                    case "\\": result.append("\\")
                    case "/": result.append("/")
                    case "b": result.append(Unicode.Scalar(0x08))
                    case "f": result.append(Unicode.Scalar(0x0C))
                    case "n": result.append("\n")
                    case "r": result.append("\r")
                    case "t": result.append("\t")
                    case "u": result.append(try parseUnicodeEscape())
                    default: throw JSONParseError(charOffset: pos)
                    }
                default:
                    // control chars must be escaped per spec
                    if c.value < 0x20 { throw JSONParseError(charOffset: pos) }
                    result.append(c)
                }
            }
            throw JSONParseError(charOffset: pos)
        }

        /// Parses \uXXXX (already consumed the "u"), handling surrogate pairs.
        mutating func parseUnicodeEscape() throws -> Unicode.Scalar {
            let hi = try parseHex4()
            if hi >= 0xD800 && hi <= 0xDBFF {
                // high surrogate — expect a following \uXXXX low surrogate
                guard peek() == "\\" else { throw JSONParseError(charOffset: pos) }
                pos += 1
                guard peek() == "u" else { throw JSONParseError(charOffset: pos) }
                pos += 1
                let lo = try parseHex4()
                guard lo >= 0xDC00 && lo <= 0xDFFF else { throw JSONParseError(charOffset: pos) }
                let combined = 0x10000 + ((hi - 0xD800) << 10) + (lo - 0xDC00)
                guard let s = Unicode.Scalar(combined) else { throw JSONParseError(charOffset: pos) }
                return s
            }
            guard let s = Unicode.Scalar(hi) else { throw JSONParseError(charOffset: pos) }
            return s
        }

        mutating func parseHex4() throws -> Int {
            var value = 0
            for _ in 0..<4 {
                guard let c = peek(), let digit = hexDigit(c) else { throw JSONParseError(charOffset: pos) }
                value = value * 16 + digit
                pos += 1
            }
            return value
        }

        func hexDigit(_ c: Unicode.Scalar) -> Int? {
            switch c {
            case "0"..."9": return Int(c.value - 48)
            case "a"..."f": return Int(c.value - 97 + 10)
            case "A"..."F": return Int(c.value - 65 + 10)
            default: return nil
            }
        }

        mutating func parseNumber() throws -> String {
            let start = pos
            if peek() == "-" { pos += 1 }
            while let c = peek(), c >= "0" && c <= "9" { pos += 1 }
            if peek() == "." {
                pos += 1
                while let c = peek(), c >= "0" && c <= "9" { pos += 1 }
            }
            if peek() == "e" || peek() == "E" {
                pos += 1
                if peek() == "+" || peek() == "-" { pos += 1 }
                while let c = peek(), c >= "0" && c <= "9" { pos += 1 }
            }
            let literal = String(String.UnicodeScalarView(scalars[start..<pos]))
            // Reject a bare "-" or empty run — must contain at least one digit.
            guard literal.contains(where: { $0.isNumber }) else { throw JSONParseError(charOffset: start) }
            return literal
        }

        mutating func parseBool() throws -> OrderedJSON {
            if match("true") { return .bool(true) }
            if match("false") { return .bool(false) }
            throw JSONParseError(charOffset: pos)
        }

        mutating func parseNull() throws -> OrderedJSON {
            if match("null") { return .null }
            throw JSONParseError(charOffset: pos)
        }

        mutating func match(_ word: String) -> Bool {
            let w = Array(word.unicodeScalars)
            guard pos + w.count <= scalars.count else { return false }
            for (i, s) in w.enumerated() where scalars[pos + i] != s { return false }
            pos += w.count
            return true
        }
    }

    /// Serialize with the given indent unit (e.g. "  ", "    ", or "\t").
    /// `sortKeys` sorts object keys alphabetically; otherwise insertion order is kept.
    func serialize(indentUnit: String, sortKeys: Bool) -> String {
        var out = ""
        write(into: &out, indentUnit: indentUnit, level: 0, sortKeys: sortKeys)
        return out
    }

    private func write(into out: inout String, indentUnit: String, level: Int, sortKeys: Bool) {
        switch self {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .number(let n): out += n
        case .string(let s): out += OrderedJSON.encodeString(s)
        case .array(let items):
            if items.isEmpty { out += "[]"; return }
            out += "[\n"
            let pad = String(repeating: indentUnit, count: level + 1)
            for (i, item) in items.enumerated() {
                out += pad
                item.write(into: &out, indentUnit: indentUnit, level: level + 1, sortKeys: sortKeys)
                out += i < items.count - 1 ? ",\n" : "\n"
            }
            out += String(repeating: indentUnit, count: level) + "]"
        case .object(let pairs):
            if pairs.isEmpty { out += "{}"; return }
            let ordered = sortKeys ? pairs.sorted { $0.0 < $1.0 } : pairs
            out += "{\n"
            let pad = String(repeating: indentUnit, count: level + 1)
            for (i, pair) in ordered.enumerated() {
                out += pad + OrderedJSON.encodeString(pair.0) + " : "
                pair.1.write(into: &out, indentUnit: indentUnit, level: level + 1, sortKeys: sortKeys)
                out += i < ordered.count - 1 ? ",\n" : "\n"
            }
            out += String(repeating: indentUnit, count: level) + "}"
        }
    }

    /// Serialize with no whitespace (minify).
    func minified() -> String {
        var out = ""
        writeMinified(into: &out)
        return out
    }

    private func writeMinified(into out: inout String) {
        switch self {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .number(let n): out += n
        case .string(let s): out += OrderedJSON.encodeString(s)
        case .array(let items):
            out += "["
            for (i, item) in items.enumerated() {
                item.writeMinified(into: &out)
                if i < items.count - 1 { out += "," }
            }
            out += "]"
        case .object(let pairs):
            out += "{"
            for (i, pair) in pairs.enumerated() {
                out += OrderedJSON.encodeString(pair.0) + ":"
                pair.1.writeMinified(into: &out)
                if i < pairs.count - 1 { out += "," }
            }
            out += "}"
        }
    }

    /// Encode a string as a JSON string literal. Does NOT escape forward slashes
    /// (matches the .withoutEscapingSlashes behavior the tool used before).
    static func encodeString(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case Unicode.Scalar(0x08): out += "\\b"
            case Unicode.Scalar(0x0C): out += "\\f"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
        return out
    }
}
