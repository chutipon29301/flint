// Tools/Hash/HashTransformer.swift
// Pure hash computation logic — NO SwiftUI/AppKit imports.
// Covers HASH-01..04, INFRA-17, pitfall #9 (chunked file hashing).
// CryptoKit: SHA family + HMAC; CommonCrypto: MD5; zlib: CRC32.

import Foundation
import CryptoKit
import CommonCrypto
import zlib

enum HashTransformer {

    // MARK: - Types

    struct HashResult {
        var md5: String = ""
        var sha1: String = ""
        var sha256: String = ""
        var sha384: String = ""
        var sha512: String = ""
        var crc32: String = ""
    }

    enum HMACAlgorithm {
        case sha256
        case sha384
        case sha512
    }

    // MARK: - HASH-01: Text hashing

    /// Hashes a UTF-8 text string using all six algorithms simultaneously.
    /// Returns empty HashResult (not a crash) for empty input or invalid UTF-8 (INFRA-17).
    static func hashText(_ input: String) -> HashResult {
        let data = Data(input.utf8)
        return hashData(data)
    }

    /// Hashes raw Data using all six algorithms simultaneously.
    static func hashData(_ data: Data) -> HashResult {
        var result = HashResult()

        // MD5 via CommonCrypto (CryptoKit Insecure.MD5 works but CC_MD5 is the canonical path)
        var md5bytes = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes { ptr in
            _ = CC_MD5(ptr.baseAddress, CC_LONG(data.count), &md5bytes)
        }
        result.md5 = md5bytes.hexString

        // SHA family via CryptoKit
        result.sha1 = Insecure.SHA1.hash(data: data).hexString
        result.sha256 = SHA256.hash(data: data).hexString
        result.sha384 = SHA384.hash(data: data).hexString
        result.sha512 = SHA512.hash(data: data).hexString

        // CRC32 via zlib (libz.tbd linked in Build Phases)
        var crcValue: uLong = crc32(0, nil, 0)  // initialize
        data.withUnsafeBytes { ptr in
            if let base = ptr.baseAddress?.assumingMemoryBound(to: Bytef.self) {
                crcValue = crc32(crcValue, base, uInt(data.count))
            }
        }
        result.crc32 = String(format: "%08x", crcValue)

        return result
    }

    // MARK: - HASH-02: Chunked async file hashing (pitfall #9 — never Data(contentsOf:))

    /// Hashes a file in 1 MB chunks without blocking the UI (Task.detached, progress callback).
    /// Returns empty HashResult on file read failure (INFRA-17 — no crash).
    static func hashFile(url: URL, progressHandler: @escaping @Sendable (Double) -> Void) async -> HashResult {
        return await Task.detached(priority: .utility) {
            guard let handle = try? FileHandle(forReadingFrom: url) else {
                return HashResult()
            }
            defer { try? handle.close() }

            let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 1

            // Initialize incremental contexts
            var md5ctx = CC_MD5_CTX()
            CC_MD5_Init(&md5ctx)

            var sha1ctx = Insecure.SHA1()
            var sha256ctx = SHA256()
            var sha384ctx = SHA384()
            var sha512ctx = SHA512()
            var crcValue: uLong = crc32(0, nil, 0)

            let chunkSize = 1_048_576  // 1 MB (pitfall #9)
            var bytesRead = 0

            while !Task.isCancelled {
                let chunk = handle.readData(ofLength: chunkSize)
                guard !chunk.isEmpty else { break }

                bytesRead += chunk.count
                let progress = Double(bytesRead) / Double(max(fileSize, 1))
                progressHandler(min(progress, 1.0))

                chunk.withUnsafeBytes { ptr in
                    if let base = ptr.baseAddress {
                        CC_MD5_Update(&md5ctx, base, CC_LONG(chunk.count))
                    }
                }
                chunk.withUnsafeBytes { ptr in
                    if let base = ptr.baseAddress?.assumingMemoryBound(to: Bytef.self) {
                        crcValue = crc32(crcValue, base, uInt(chunk.count))
                    }
                }
                sha1ctx.update(data: chunk)
                sha256ctx.update(data: chunk)
                sha384ctx.update(data: chunk)
                sha512ctx.update(data: chunk)
            }

            // Finalize MD5
            var md5digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
            CC_MD5_Final(&md5digest, &md5ctx)

            var result = HashResult()
            result.md5 = md5digest.hexString
            result.sha1 = sha1ctx.finalize().hexString
            result.sha256 = sha256ctx.finalize().hexString
            result.sha384 = sha384ctx.finalize().hexString
            result.sha512 = sha512ctx.finalize().hexString
            result.crc32 = String(format: "%08x", crcValue)
            return result
        }.value
    }

    // MARK: - HASH-03: HMAC (key parameter only — NEVER write key to history)

    /// Computes HMAC for the given text and key using the specified algorithm.
    /// The key is ONLY a function parameter — never stored, never passed to onSaveHistory.
    /// See HashViewModel for the SECURITY comment at the history-write call site.
    static func hmacText(_ input: String, key: String, algorithm: HMACAlgorithm) -> String {
        let messageData = Data(input.utf8)
        let keyData = Data(key.utf8)
        let symmetricKey = SymmetricKey(data: keyData)
        switch algorithm {
        case .sha256:
            return Data(HMAC<SHA256>.authenticationCode(for: messageData, using: symmetricKey)).map { String(format: "%02x", $0) }.joined()
        case .sha384:
            return Data(HMAC<SHA384>.authenticationCode(for: messageData, using: symmetricKey)).map { String(format: "%02x", $0) }.joined()
        case .sha512:
            return Data(HMAC<SHA512>.authenticationCode(for: messageData, using: symmetricKey)).map { String(format: "%02x", $0) }.joined()
        }
    }
}
