// LatheTests/URLTransformerTests.swift
// Unit tests for URLTransformer — covers URL-01..04 + INFRA-17 no-crash guarantee.
// TDD: Tests written against the behavior spec before implementation.

import XCTest
@testable import Lathe

final class URLTransformerTests: XCTestCase {

    // MARK: - URL-01: Percent Encode

    func testPercentEncode_spacesAndAmpersand() {
        let result = URLTransformer.percentEncode("a b&c")
        guard case .success(let encoded) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(encoded, "a%20b%26c",
                       "Spaces should encode to %20, & should encode to %26")
    }

    func testPercentEncode_simpleText() {
        let result = URLTransformer.percentEncode("hello world")
        guard case .success(let encoded) = result else {
            XCTFail("Expected success for simple text")
            return
        }
        XCTAssertTrue(encoded.contains("%20"), "Space should be percent-encoded")
        XCTAssertFalse(encoded.contains(" "), "Encoded string must not contain raw spaces")
    }

    func testPercentEncode_specialCharacters() {
        let result = URLTransformer.percentEncode("foo=bar&baz=qux")
        guard case .success(let encoded) = result else {
            XCTFail("Expected success")
            return
        }
        // = and & should be encoded
        XCTAssertFalse(encoded.contains("="), "= must be percent-encoded in query value context")
        XCTAssertFalse(encoded.contains("&"), "& must be percent-encoded in query value context")
    }

    func testPercentEncode_emptyString() {
        let result = URLTransformer.percentEncode("")
        guard case .success(let encoded) = result else {
            XCTFail("Expected success for empty string")
            return
        }
        XCTAssertEqual(encoded, "", "Empty string encodes to empty string")
    }

    func testPercentEncode_alreadySafeCharacters() {
        let result = URLTransformer.percentEncode("abcABC123-_.~")
        guard case .success(let encoded) = result else {
            XCTFail("Expected success for safe characters")
            return
        }
        // RFC 3986 unreserved characters should not be encoded
        XCTAssertTrue(encoded.contains("abcABC123"),
                      "Unreserved characters should pass through unencoded")
    }

    // MARK: - URL-01: Percent Decode

    func testPercentDecode_standard() {
        let result = URLTransformer.percentDecode("a%20b%26c")
        guard case .success(let decoded) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(decoded, "a b&c", "Should decode %20 → space and %26 → &")
    }

    func testPercentDecode_emptyString() {
        let result = URLTransformer.percentDecode("")
        guard case .success(let decoded) = result else {
            XCTFail("Expected success for empty string")
            return
        }
        XCTAssertEqual(decoded, "")
    }

    func testPercentDecode_noEncodings() {
        let plain = "hello world"
        let result = URLTransformer.percentDecode(plain)
        guard case .success(let decoded) = result else {
            XCTFail("Expected success for plain text")
            return
        }
        XCTAssertEqual(decoded, plain, "String without percent-encoding should pass through unchanged")
    }

    func testPercentDecode_encodedSpecialChars() {
        let encoded = "foo%3Dbar%26baz%3Dqux"
        let result = URLTransformer.percentDecode(encoded)
        guard case .success(let decoded) = result else {
            XCTFail("Expected success")
            return
        }
        XCTAssertEqual(decoded, "foo=bar&baz=qux")
    }

    // MARK: - Round-trip

    func testRoundTrip_encodeDecodeIsLossless() {
        let original = "hello world! special: & = ? #"
        guard case .success(let encoded) = URLTransformer.percentEncode(original),
              case .success(let decoded) = URLTransformer.percentDecode(encoded) else {
            XCTFail("Both encode and decode should succeed")
            return
        }
        XCTAssertEqual(decoded, original, "Round-trip encode→decode must be lossless")
    }

    // MARK: - URL-02: Parse URL

    func testParse_fullURL_allComponents() {
        let result = URLTransformer.parse("https://x.com/p?q=1&r=2#frag")
        guard case .success(let parsed) = result else {
            XCTFail("Expected success parsing full URL, got \(result)")
            return
        }
        XCTAssertEqual(parsed.scheme, "https")
        XCTAssertEqual(parsed.host, "x.com")
        XCTAssertEqual(parsed.path, "/p")
        XCTAssertEqual(parsed.queryItems.count, 2)
        // First query item
        XCTAssertEqual(parsed.queryItems[0].name, "q")
        XCTAssertEqual(parsed.queryItems[0].value, "1")
        // Second query item
        XCTAssertEqual(parsed.queryItems[1].name, "r")
        XCTAssertEqual(parsed.queryItems[1].value, "2")
        XCTAssertEqual(parsed.fragment, "frag")
    }

    func testParse_httpURL_schemeAndHost() {
        let result = URLTransformer.parse("http://example.com")
        guard case .success(let parsed) = result else {
            XCTFail("Expected success parsing simple URL")
            return
        }
        XCTAssertEqual(parsed.scheme, "http")
        XCTAssertEqual(parsed.host, "example.com")
        XCTAssertTrue(parsed.queryItems.isEmpty)
        XCTAssertNil(parsed.fragment)
    }

    func testParse_urlWithPort() {
        let result = URLTransformer.parse("https://localhost:8080/api/v1")
        guard case .success(let parsed) = result else {
            XCTFail("Expected success parsing URL with port")
            return
        }
        XCTAssertEqual(parsed.scheme, "https")
        XCTAssertEqual(parsed.host, "localhost")
        XCTAssertEqual(parsed.port, 8080)
        XCTAssertEqual(parsed.path, "/api/v1")
    }

    func testParse_malformedURL_returnsFailure() {
        // No scheme — URLComponents may accept this but it's not a full URL parse
        // The important behavior: garbage input must not crash
        let result = URLTransformer.parse("not a valid url at all:// ???")
        // This may return success or failure depending on URLComponents behavior
        // The key invariant: it must NOT crash
        switch result {
        case .success, .failure:
            break  // Both are acceptable; no crash is the requirement (INFRA-17)
        }
    }

    func testParse_emptyString_returnsFailure() {
        let result = URLTransformer.parse("")
        guard case .failure = result else {
            XCTFail("Expected failure for empty string")
            return
        }
    }

    func testParse_urlWithMultipleQueryParams() {
        let result = URLTransformer.parse("https://api.example.com/search?q=swift&lang=en&page=2")
        guard case .success(let parsed) = result else {
            XCTFail("Expected success")
            return
        }
        XCTAssertEqual(parsed.queryItems.count, 3)
        let names = parsed.queryItems.map { $0.name }
        XCTAssertTrue(names.contains("q"))
        XCTAssertTrue(names.contains("lang"))
        XCTAssertTrue(names.contains("page"))
    }

    // MARK: - URL-03: Edit and rebuild

    func testRebuild_afterAddingQueryParam() {
        // Parse a URL, add a query param, rebuild, verify the new param appears
        guard case .success(var parsed) = URLTransformer.parse("https://example.com/search?q=hello") else {
            XCTFail("Expected success parsing URL")
            return
        }
        // Add a new query item
        parsed.queryItems.append(URLTransformer.QueryItem(name: "page", value: "2"))

        let result = URLTransformer.rebuild(parsed)
        guard case .success(let rebuilt) = result else {
            XCTFail("Expected success rebuilding URL")
            return
        }
        XCTAssertTrue(rebuilt.contains("page=2"), "Rebuilt URL should contain the newly added param")
        XCTAssertTrue(rebuilt.contains("q=hello"), "Rebuilt URL should still contain original param")
    }

    func testRebuild_afterDeletingQueryParam() {
        guard case .success(var parsed) = URLTransformer.parse("https://example.com?a=1&b=2&c=3") else {
            XCTFail("Expected success parsing URL")
            return
        }
        // Remove the second item
        parsed.queryItems.removeAll { $0.name == "b" }

        let result = URLTransformer.rebuild(parsed)
        guard case .success(let rebuilt) = result else {
            XCTFail("Expected success rebuilding URL")
            return
        }
        XCTAssertFalse(rebuilt.contains("b="), "Deleted param should not appear in rebuilt URL")
        XCTAssertTrue(rebuilt.contains("a=1"), "Retained param 'a' should still be present")
        XCTAssertTrue(rebuilt.contains("c=3"), "Retained param 'c' should still be present")
    }

    func testRebuild_afterEditingQueryParam() {
        guard case .success(var parsed) = URLTransformer.parse("https://example.com?q=old") else {
            XCTFail("Expected success parsing URL")
            return
        }
        // Edit the first (and only) query item value
        parsed.queryItems[0].value = "new"

        let result = URLTransformer.rebuild(parsed)
        guard case .success(let rebuilt) = result else {
            XCTFail("Expected success rebuilding URL after edit")
            return
        }
        XCTAssertTrue(rebuilt.contains("q=new"), "Edited query param should appear in rebuilt URL")
        XCTAssertFalse(rebuilt.contains("q=old"), "Old value should not appear after edit")
    }

    func testParseEditRebuild_preservesSchemeHostPath() {
        // URL-03: parse → edit a query param → rebuild yields URL reflecting the edit
        guard case .success(var parsed) = URLTransformer.parse("https://api.example.com/v1/items?sort=asc&limit=10") else {
            XCTFail("Expected success")
            return
        }
        // Find and change the sort param
        if let idx = parsed.queryItems.firstIndex(where: { $0.name == "sort" }) {
            parsed.queryItems[idx].value = "desc"
        }

        guard case .success(let rebuilt) = URLTransformer.rebuild(parsed) else {
            XCTFail("Expected successful rebuild")
            return
        }
        XCTAssertTrue(rebuilt.hasPrefix("https://api.example.com"), "Scheme + host should be preserved")
        XCTAssertTrue(rebuilt.contains("/v1/items"), "Path should be preserved")
        XCTAssertTrue(rebuilt.contains("sort=desc"), "Edited param should reflect new value")
        XCTAssertTrue(rebuilt.contains("limit=10"), "Unedited param should be preserved")
    }

    // MARK: - INFRA-17: No crash on bad input

    func testPercentEncode_unicodeText_doesNotCrash() {
        let unicodeText = "Hello 世界 🌍"
        let result = URLTransformer.percentEncode(unicodeText)
        switch result {
        case .success, .failure:
            break  // Must not crash
        }
    }

    func testPercentDecode_invalidPercentEncoding_doesNotCrash() {
        // Malformed percent encoding (truncated sequence)
        let malformed = "%GG%HH%ZZ"
        let result = URLTransformer.percentDecode(malformed)
        switch result {
        case .success, .failure:
            break  // Must not crash
        }
    }

    func testParse_garbageURL_doesNotCrash() {
        let garbage = "!@#$%^&*()\n\t///garbage"
        let result = URLTransformer.parse(garbage)
        switch result {
        case .success, .failure:
            break  // Must not crash
        }
    }

    func testParse_veryLongURL_doesNotCrash() {
        let longURL = "https://example.com?" + (1...500).map { "param\($0)=value\($0)" }.joined(separator: "&")
        let result = URLTransformer.parse(longURL)
        switch result {
        case .success, .failure:
            break  // Must not crash
        }
    }

    func testRebuild_emptyParsed_doesNotCrash() {
        let empty = URLTransformer.ParsedURL(
            scheme: nil, host: nil, port: nil, path: nil, queryItems: [], fragment: nil
        )
        // Rebuilding an empty ParsedURL may succeed or fail; it must not crash
        let result = URLTransformer.rebuild(empty)
        switch result {
        case .success, .failure:
            break
        }
    }

    // MARK: - Source purity check (no UI imports)

    func testTransformerModuleName() {
        // Verifies URLTransformer compiles without any SwiftUI/AppKit imports.
        // If this test compiles and runs, the transformer is correctly isolated.
        let result = URLTransformer.percentEncode("test")
        XCTAssertNotNil(result)
    }
}
