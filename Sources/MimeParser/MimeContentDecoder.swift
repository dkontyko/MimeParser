//
//  MimeContentDecoder.swift
//  MimeParser
//
//  Created by miximka on 10.12.17.
//  Copyright © 2017 miximka. All rights reserved.
//

import Foundation

struct MimeContentDecoder {
    
    enum Error : Swift.Error {
        case decodingFailed
        case unsupportedEncoding
    }

    /// Decodes the given Base64 string using `Data`'s built-in Base64 constructor after removing
    /// all CRLFs.
    ///
    /// - Returns: The data decoded from the given Base64 string.
    static func decodeBase64(_ string: String) throws -> Data {
        let concatenated = string.replacingOccurrences(of: "\r?\n", with: "", options: .regularExpression, range: string.range)
        guard let data = Data(base64Encoded: concatenated) else {
            throw Error.decodingFailed
        }
        return data
    }

    /// Transforms a given `String` into a `Data` object based on the string's encoding type.
    ///
    ///  * 7bit, 8bit, and binary: uses `String`'s built-in data method using the ASCII encoding scheme.
    ///  * Quoted Printable: calls ``String.decodedQuotedPrintable`` and returns the result.
    ///  * Base64: calls ``decodeBase64`` and returns the result.
    ///
    ///  - Throws: An error if decoding fails or if the encoding type does not match one of the above.
    static func decode(_ raw: String, encoding: ContentTransferEncoding) throws -> Data {
        switch encoding {
        case .sevenBit: fallthrough
        case .eightBit: fallthrough
        case .binary:
            guard let decoded = raw.data(using: .ascii) else { throw Error.decodingFailed }
            return decoded
        case .quotedPrintable:
            return try raw.decodedQuotedPrintable()
        case .base64:
            return try decodeBase64(raw)
        case .other(_):
            throw Error.unsupportedEncoding
        }
    }
    
}
