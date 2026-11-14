import Foundation

/// A parsed search query (ADR-028): filter words and free text, in any order.
///
/// Filter words are whole words, matched case-insensitively: `is:pinned`, `is:concealed`,
/// `is:image`, `is:text`, `is:link`, and `app:<name>` (or `app:"two words"`). Every other
/// word is free text, searched in item content. A leading `\` makes the whole query literal
/// free text (ADR-025). A repeated kind filter or `app:` keeps the last one.
struct SearchQuery: Equatable {
    enum KindFilter: Equatable {
        case image, text, link
    }

    var pinned = false
    var concealed = false
    var kind: KindFilter?
    var app: String?
    var text = ""

    /// A whitespace-separated word, except that `app:"..."` may contain spaces.
    struct Token {
        let range: Range<String.Index>
        let raw: Substring
    }

    static func parse(_ query: String) -> SearchQuery {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("\\") {
            return SearchQuery(text: String(trimmed.dropFirst()))
        }
        var parsed = SearchQuery()
        var words: [String] = []
        for token in tokens(in: trimmed) {
            let lowered = token.raw.lowercased()
            switch lowered {
            case "is:pinned": parsed.pinned = true
            case "is:concealed": parsed.concealed = true
            case "is:image": parsed.kind = .image
            case "is:text": parsed.kind = .text
            case "is:link": parsed.kind = .link
            default:
                if lowered.hasPrefix("app:"), let name = appName(in: token.raw) {
                    parsed.app = name
                } else {
                    words.append(String(token.raw))
                }
            }
        }
        parsed.text = words.joined(separator: " ")
        return parsed
    }

    /// The name after `app:` with optional surrounding quotes removed; nil when empty, so a
    /// lone `app:` stays ordinary text (it is something you might legitimately search for).
    static func appName(in word: Substring) -> String? {
        var name = word.dropFirst(4)
        if name.first == "\"" { name = name.dropFirst() }
        if name.last == "\"" { name = name.dropLast() }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func tokens(in string: String) -> [Token] {
        var result: [Token] = []
        var index = string.startIndex
        while index < string.endIndex {
            if string[index].isWhitespace {
                index = string.index(after: index)
                continue
            }
            let start = index
            var inQuote = false
            while index < string.endIndex {
                let character = string[index]
                if character == "\"" {
                    if inQuote {
                        inQuote = false
                    } else if string[start..<index].lowercased() == "app:" {
                        inQuote = true
                    }
                } else if character.isWhitespace, !inQuote {
                    break
                }
                index = string.index(after: index)
            }
            result.append(Token(range: start..<index, raw: string[start..<index]))
        }
        return result
    }
}
