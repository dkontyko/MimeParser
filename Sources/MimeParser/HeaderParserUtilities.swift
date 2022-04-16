//
//  HeaderParserUtilities.swift
//  MimeParser
//
//  Created by miximka on 11.12.17.
//  Copyright © 2017 miximka. All rights reserved.
//

import Foundation

struct HeaderFieldLexer {
    
    /// Represents the possible valid special characters in a MIME message.
    enum Special : String, SpecialProtocol {
        case leftParentheses = "("
        case rightParentheses = ")"
        case leftAngleBracket = "<"
        case rightAngleBracket = ">"
        case atSign = "@"
        case comma = ","
        case semicolon = ";"
        case colon = ":"
        case backslash = "\\"
        case quotationMark = "\""
        case slash = "/"
        case leftSquareBracket = "["
        case rightSquareBracket = "]"
        case questionMark = "?"
        case equalitySign = "="
        
        static let all: [Special] = {
            return [.leftParentheses,
                    .rightParentheses,
                    .leftAngleBracket,
                    .rightAngleBracket,
                    .atSign,
                    .comma,
                    .semicolon,
                    .colon,
                    .backslash,
                    .quotationMark,
                    .slash,
                    .leftSquareBracket,
                    .rightSquareBracket,
                    .questionMark,
                    .equalitySign
            ]
        }()
        
        static let rawValues: [String] = {
            return all.map { $0.rawValue }
        }()
    }
    
    /// Represents the possible types of tokens into which a header field
    /// can be split.
    enum Token : Equatable {
        /// Represents an entire string (possibly including spaces) that was enclosed in quotes.
        case quotedString(String)
        /// Represents an unquoted textual string.
        case token(String)
        /// Represents an instance of one of the valid special characters.
        case special(Special)
        
        static func ==(lhs: Token, rhs: Token) -> Bool {
            switch (lhs, rhs) {
            case (.quotedString(let lhsS), .quotedString(let rhsS)): return lhsS == rhsS
            case (.token(let lhsS), .token(let rhsS)): return lhsS == rhsS
            case (.special(let lhsS), .special(let rhsS)): return lhsS == rhsS
            default: return false
            }
        }
    }
    
    /// Represents the characters that cannot be part of a standard, non-quoted textual string in the header.
    private let invalidTokenChars: CharacterSet = {
        var set = CharacterSet(charactersIn: " ")
        set.insert(charactersIn: Range<Unicode.Scalar>(uncheckedBounds: (lower: Unicode.Scalar(0), upper: Unicode.Scalar(31))))
        set.insert(charactersIn: Special.all.reduce("", { return $0 + $1.rawValue }))
        return set
    }()
    
    /// - Returns: The next ``Token`` in the header string, or nil is there are no more tokens.
    private func nextToken(withScanner scanner: StringScanner<Special>) -> Token? {
        /// Skips any starting whitespace
        scanner.trimWhiteSpaces()
        
        do {
            /// Checks if the next part of the string is enclosed in quotes; returns the quoted string if so.
            let str = try scanner.scanTextEnclosed(left: .quotationMark, right: .quotationMark, excludedCharacters: invalidQTextChars)
            return .quotedString(str)
        } catch {
        }
        
        do {
            /// If a quoted string was not found, checks for a non-quoted textual string and returns it if so.
            let str = try scanner.scanText(withExcludedCharacters: invalidTokenChars)
            return .token(str)
        } catch {
        }
        
        do {
            /// If neither type of string above was found, checks for a special character and returns it if so.
            let special = try scanner.scanSpecial()
            return .special(special)
        } catch {
        }
        
        return nil
    }
    
    /// Scans the given string and lexes it into a series of tokens
    /// based on the acceptable characters in a MIME header.
    ///
    /// - Returns: The lexed tokens in a ``Token`` array.
    func scan(_ string: String) -> [Token] {
        let scanner = StringScanner<Special>(string)
        var tokens = [Token]()
        
        repeat {
            if let token = nextToken(withScanner: scanner) {
                tokens.append(token)
            } else {
                break
            }
        } while true
        
        return tokens
    }
}

// MARK: -

class HeaderFieldTokenProcessor {
    
    enum Error : Swift.Error {
        case noMoreTokens
        case invalidSpecial
        case invalidQuotedString
        case invalidToken
        case invalidAtom
    }
    
    /// The tokens that this object will be processing.
    let tokens: [HeaderFieldLexer.Token]
    
    init(tokens: [HeaderFieldLexer.Token]) {
        self.tokens = tokens
    }
    
    /// The index of the current token in ``tokens``.
    private var cursor: Int = 0
    
    /// True if the cursor is at the end of ``tokens``.
    var isAtEnd: Bool {
        return cursor == tokens.count
    }
    
    /// Performs the given closure on the token at ``position`` index in the ``tokens`` array.
    /// Advances ``cursor`` if the operation is successful; leaves `cursor` unchanged otherwise.
    ///
    /// - Returns: The result of the given closure, if the operation is successful.
    ///
    /// - Throws:``Error.noMoreTokens`` if ``cursor`` is equal to the ``tokens`` array count.
    ///     `Error` if the closure results in an error.
    private func withNextToken<T>(_ probe: (HeaderFieldLexer.Token) throws -> T) throws -> T {
        guard cursor < tokens.count else { throw Error.noMoreTokens }
        let token = tokens[cursor]
        
        do {
            /// Advances the cursor to the next token before operating on the
            /// temporarily saved token.
            cursor += 1
            return try probe(token)
        } catch {
            /// Returns the cursor to its previous position if the operation was unsuccessful.
            cursor -= 1
            throw error
        }
    }
    
    /// Extracts the contents of the quoted string within the next token in the parser. Advances the
    /// parser's cursor by one index if the operation is successful.
    ///
    /// - Throws: ``Error.invalidQuotedString`` if the string extraction is unsuccessful.
    ///
    /// - Returns: The contents of the quoted string in the next token.
    func expectQuotedString() throws -> String {
        return try withNextToken { token -> String in
            guard case .quotedString(let value) = token else { throw Error.invalidQuotedString }
            return value
        }
    }
    
    /// Extracts the textual string from the next token in the parser if it's a valid token. Advances the parser's cursor
    /// by one index if the operation is successful.
    ///
    /// - Throws: ``Error.invalidToken`` if the string extraction fails.
    ///
    /// - Returns: The `String` value of the next token.
    func expectToken() throws -> String {
        return try withNextToken { token -> String in
            guard case .token(let value) = token else { throw Error.invalidToken }
            return value
        }
    }
    
    func expectSpecial(_ special: HeaderFieldLexer.Special) throws {
        try withNextToken { token in
            guard case .special(let value) = token, value == special else { throw Error.invalidSpecial }
        }
    }
}

// MARK: -

struct HeaderFieldParametersParser {
    
    enum Error : Swift.Error {
        case invalidParameterValue
        case trailingSemicolon
    }
    
    private struct Parameter {
        let name: String
        let value: String
    }
    
    private static func parseParameterName(with processor: HeaderFieldTokenProcessor) throws -> String {
        return try processor.expectToken()
    }
    
    private static func parseParameterValue(with processor: HeaderFieldTokenProcessor) throws -> String {
        do {
            return try processor.expectQuotedString()
        } catch {}
        
        do {
            return try processor.expectToken()
        } catch {}
        
        throw Error.invalidParameterValue
    }
    
    private static func parseParameter(with processor: HeaderFieldTokenProcessor) throws -> Parameter {
        try processor.expectSpecial(.semicolon)
        
        if processor.isAtEnd {
            throw Error.trailingSemicolon
        }
        
        let name = try parseParameterName(with: processor)
        try processor.expectSpecial(.equalitySign)
        let value = try parseParameterValue(with: processor)
        return Parameter(name: name, value: value)
    }
    
    static func parse(with processor: HeaderFieldTokenProcessor) throws -> [String : String] {
        var params: [String : String] = [:]
        while !processor.isAtEnd {
            do {
                let param = try parseParameter(with: processor)
                params[param.name] = param.value
            } catch let err as Error {
                if err != .trailingSemicolon {
                    throw err
                }
            }
        }
        return params
    }
}
