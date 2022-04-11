//
//  MimeLexer.swift
//  MimeParser
//
//  Created by miximka on 06.12.17.
//  Copyright © 2017 miximka. All rights reserved.
//

import Foundation

let invalidQTextChars: CharacterSet = CharacterSet(charactersIn: "\"\\")
let invalidDTextChars: CharacterSet = CharacterSet(charactersIn: "[]\\")
let invalidCTextChars: CharacterSet = CharacterSet(charactersIn: "()\\")

/**
 Structure that represents an RFC 822 header field of the form `name`: `body`.
 */
public struct RFC822HeaderField : Equatable {
    public let name: String
    public let body: String
    
    public static func ==(lhs: RFC822HeaderField, rhs: RFC822HeaderField) -> Bool {
        return lhs.name == rhs.name && lhs.body == rhs.body
    }
}

struct RFC822HeaderFieldsUnfolder {
    
    /**
     Unfolds an RFC 822 header into a single line by replacing any whitespace in the given string
     matching the regex `\r?\n[[:blank:]]+` with a single space for each occurrence.
     
     - Returns: A string with the whitespace modified as described above.
     */
    func unfold(in string: String) -> String {
        let regex = try! NSRegularExpression(pattern: "\r?\n[[:blank:]]+", options: [])
        let result = regex.stringByReplacingMatches(in: string, options: [], range: string.nsRange, withTemplate: " ")
        return result
    }
}

struct RFC822HeaderFieldsPartitioner {
    
    enum Error : Swift.Error {
        case invalidFieldStructure
    }
    
    /**
     Parses the given string into an ``RFC822HeaderField`` array using the regex `(.+?):\\s*(.+)`.
     For each match, the content in the first capture group is place in the header name, and the content in the second
     capture group is placed in the header body.
     
     - Returns: an ``RFC822HeaderField`` array with the header fields from the given string.
     
     - Throws: ``Error.invalidFieldStructure`` if a match does not have exactly two capture groups
     or the name or body range is invalid.
     */
    func fields(in string: String) throws -> [RFC822HeaderField] {
        // dot will not match line by default, thus stopping at the 822-defined separator
        let regex = try! NSRegularExpression(pattern: "(.+?):\\s*(.+)", options: [])
        
        // each header will be a separate result in the result array
        let results = regex.matches(in: string, options: [], range: string.nsRange)
        
        return try results.map { result in
            // verifying that the result has exactly 2 capture groups (plus the entire match)
            guard result.numberOfRanges == 3,
                  let nameRange = Range<String.Index>(result.range(at: 1), in: string),
                  let bodyRange = Range<String.Index>(result.range(at: 2), in: string) else {
                throw Error.invalidFieldStructure
            }
            
            let name = String(string[nameRange])
            let body = String(string[bodyRange])
            return RFC822HeaderField(name: name, body: body)
        }
    }
}

enum RFC822Special : String, SpecialProtocol {
    case period = "."
    case comma = ","
    case colon = ":"
    case semicolon = ";"
    case leftParentheses = "("
    case rightParentheses = ")"
    case leftAngleBracket = "<"
    case rightAngleBracket = ">"
    case leftSquareBracket = "["
    case rightSquareBracket = "]"
    case atSign = "@"
    case backslash = "\\"
    case quotationMark = "\""

    static let all: [RFC822Special] = {
        return [.period,
                .comma,
                .colon,
                .semicolon,
                .leftParentheses,
                .rightParentheses,
                .leftAngleBracket,
                .rightAngleBracket,
                .leftSquareBracket,
                .rightSquareBracket,
                .atSign,
                .backslash,
                .quotationMark]
    }()
    
    static let rawValues: [String] = {
        return all.map { $0.rawValue }
    }()
}

// MARK: -

protocol SpecialProtocol : RawRepresentable {
    static var all: [Self] { get }
}

class StringScanner<Special: SpecialProtocol> where Special.RawValue == String {
    
    enum Error : LocalizedError {
        case endOfString
        case invalidCharacter
        case invalidSpecial
        case invalidText
    }
    
    /// The string that this scanner is scanning.
    let string: String
    let startIndex: String.Index
    let endIndex: String.Index
    
    /**
     - Parameters:
        - string: The string to be scanned.
        - startIndex: The index of the given string to start scanning at. If this argument is nil, the corresponding class variable is set to the starting index of ``string``.
        - endIndex: The index of the given string to stop scanning at. If this argument is nil, the corresponding class variable is set to the ending index of ``string``.
     */
    init(_ string: String, startIndex: String.Index? = nil, endIndex: String.Index? = nil) {
        self.string = string
        self.startIndex = startIndex ?? string.startIndex
        self.endIndex = endIndex ?? string.endIndex
        self.position = self.startIndex
    }
    
    /// The current index of this scanner within ``string``. This is updated in within the various scanning methods.
    private var position: String.Index
    
    private let whitespace = Character(" ")
    
    /**
     Advances ``position`` by one index position unless its index does not point at a space.
     */
    func trimWhiteSpaces() {
        while position != endIndex && string[position] == whitespace {
            position = string.index(after: position)
        }
    }

    /**
     Updates ``position`` to the index of the next character as long as no errors are thrown.
     
     - Throws: ``Error.invalidSpecial`` if a `Special` object cannot be created from the raw value
     of the String representation of the character. ``Error.endOfString`` if ``position`` is equal to ``endIndex``.
     
     - Returns: A `Special` representation of the character at ``position`` if it points to a
     special character.
     */
    func scanSpecial() throws -> Special {
        guard position != endIndex else { throw Error.endOfString }
        let char = string[position]
        guard let special = Special(rawValue: String(char)) else { throw Error.invalidSpecial }
        position = string.index(after: position)
        return special
    }
    
    /**
     Advances ``position`` by one character if no errors are thrown.
     
     - Throws: ``Error.invalidCharacter`` if the character at ``position`` is contained in ``withExcludedCharacters``.
     ``Error.endOfString`` if ``position`` is equal to ``endIndex``.
     
     - Returns: The character at ``position`` as long as it is not contained in the given ``CharacterSet``.
     */
    private func scanTextChar(withExcludedCharacters excluded: CharacterSet) throws -> Character {
        guard position != endIndex else { throw Error.endOfString }
        let char = string[position]
        guard let unicodeScalar = char.unicodeScalars.first, !excluded.contains(unicodeScalar) else { throw Error.invalidCharacter }
        position = string.index(after: position)
        return char
    }
    
    func scanText(withExcludedCharacters excluded: CharacterSet) throws -> String {
        let startPosition = position
        
        repeat {
            do {
                let _ = try scanTextChar(withExcludedCharacters: excluded)
            } catch let err as Error {
                if startPosition != position {
                    break
                } else {
                    throw err
                }
            }
        } while true
        
        return String(string[startPosition..<position])
    }

    func scanTextEnclosed(left: Special, right: Special, excludedCharacters: CharacterSet) throws -> String {
        let position = self.position
        do {
            let leftSpecial = try scanSpecial()
            if leftSpecial != left {
                throw Error.invalidText
            }
            
            let str = try scanText(withExcludedCharacters: excludedCharacters)
            
            let rightSpecial = try scanSpecial()
            if rightSpecial != right {
                throw Error.invalidText
            }
            
            return str
        } catch {
            self.position = position
            throw error
        }
    }
    
    private let invalidAtomChars: CharacterSet = {
        var set = CharacterSet(charactersIn: " ")
        set.insert(charactersIn: Special.all.reduce("", { return $0 + $1.rawValue }))
        set.insert(charactersIn: Range<Unicode.Scalar>(uncheckedBounds: (lower: Unicode.Scalar(0), upper: Unicode.Scalar(31))))
        return set
    }()
    
    func scanAtom() throws -> String {
        return try scanText(withExcludedCharacters: invalidAtomChars)
    }
}
