// Tools/URLEncoder/URLTransformer.swift
// Pure URL encode/decode transformer — zero UI imports.
// Source: Foundation addingPercentEncoding / URLComponents [VERIFIED]
// Covers: URL-01 (percent encode/decode), URL-02 (parse), URL-03 (rebuild after edit)
// INFRA-17: returns Result types, never force-unwraps.

import Foundation

enum URLTransformer {

    // MARK: - Errors

    enum TransformError: LocalizedError {
        case encodingFailed
        case decodingFailed
        case invalidURL(String)

        var errorDescription: String? {
            switch self {
            case .encodingFailed:
                return "Could not percent-encode the input"
            case .decodingFailed:
                return "Could not percent-decode the input"
            case .invalidURL(let reason):
                return "Could not parse URL — \(reason)"
            }
        }
    }

    // MARK: - Parsed URL Model

    /// Represents a fully parsed URL with editable components.
    struct ParsedURL: Equatable {
        var scheme: String?
        var host: String?
        var port: Int?
        var path: String?
        var queryItems: [QueryItem]
        var fragment: String?

        /// Returns a rebuilt URL string from the current component values.
        /// - Returns: A valid URL string, or nil if the components are not a valid URL.
        func rebuild() -> String? {
            var components = URLComponents()
            components.scheme = scheme.flatMap { $0.isEmpty ? nil : $0 }
            components.host = host.flatMap { $0.isEmpty ? nil : $0 }
            components.port = port
            components.path = path ?? ""
            if !queryItems.isEmpty {
                components.queryItems = queryItems.map {
                    URLQueryItem(name: $0.name, value: $0.value)
                }
            }
            components.fragment = fragment.flatMap { $0.isEmpty ? nil : $0 }
            return components.url?.absoluteString ?? components.string
        }
    }

    /// A key-value query parameter with stable identity for list editing.
    struct QueryItem: Identifiable, Equatable {
        let id: UUID
        var name: String
        var value: String?

        init(id: UUID = UUID(), name: String, value: String?) {
            self.id = id
            self.name = name
            self.value = value
        }
    }

    // MARK: - Percent Encode (URL-01)

    /// Percent-encodes a string for use as a query parameter value.
    /// Uses `.urlQueryAllowed` minus `+`, `&`, `=`, `?` to produce RFC 3986-safe encoding.
    /// - Parameter text: The raw string to encode.
    /// - Returns: Percent-encoded string, or failure.
    static func percentEncode(_ text: String) -> Result<String, Error> {
        guard !text.isEmpty else { return .success("") }
        // Build a custom character set: urlQueryAllowed minus the characters that have
        // special meaning inside a query string (& = + ? #).
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: allowed) else {
            return .failure(TransformError.encodingFailed)
        }
        return .success(encoded)
    }

    // MARK: - Percent Decode (URL-01)

    /// Decodes a percent-encoded string.
    /// - Parameter text: The percent-encoded string to decode.
    /// - Returns: Decoded string, or failure.
    static func percentDecode(_ text: String) -> Result<String, Error> {
        guard !text.isEmpty else { return .success("") }
        guard let decoded = text.removingPercentEncoding else {
            return .failure(TransformError.decodingFailed)
        }
        return .success(decoded)
    }

    // MARK: - Parse URL (URL-02)

    /// Parses a URL string into its component parts using `URLComponents`.
    /// - Parameter urlString: The URL string to parse.
    /// - Returns: A `ParsedURL` on success, or failure with "Could not parse URL" message.
    static func parse(_ urlString: String) -> Result<ParsedURL, Error> {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(TransformError.invalidURL("empty input"))
        }

        // URLComponents can parse relative URLs too; for a meaningful parse we need a scheme.
        guard let components = URLComponents(string: trimmed) else {
            return .failure(TransformError.invalidURL("check scheme and formatting"))
        }

        let queryItems: [QueryItem] = (components.queryItems ?? []).map {
            QueryItem(name: $0.name, value: $0.value)
        }

        let parsed = ParsedURL(
            scheme: components.scheme,
            host: components.host,
            port: components.port,
            path: components.path.isEmpty ? nil : components.path,
            queryItems: queryItems,
            fragment: components.fragment
        )
        return .success(parsed)
    }

    // MARK: - Rebuild from ParsedURL (URL-03)

    /// Rebuilds a URL string from a `ParsedURL` (after editing query params, etc.).
    /// - Parameter parsed: The parsed URL with potentially-modified components.
    /// - Returns: A valid URL string, or failure.
    static func rebuild(_ parsed: ParsedURL) -> Result<String, Error> {
        guard let urlString = parsed.rebuild() else {
            return .failure(TransformError.invalidURL("components do not form a valid URL"))
        }
        return .success(urlString)
    }
}
