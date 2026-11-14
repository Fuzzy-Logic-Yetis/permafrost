import Foundation

/// One `is:` filter, as listed in the panel's suggestion row.
public struct SearchFilterInfo: Equatable, Sendable {
    public let token: String
    public let summary: String
}

/// One row in the panel's suggestion list: what to show, and the query to set when accepted.
public struct SearchSuggestion: Equatable, Sendable, Identifiable {
    public let label: String
    public let detail: String?
    public let query: String

    public var id: String { label }
}

public enum SearchFilters {
    /// Every `is:` filter, in the order suggested. Adding a filter to the search means adding
    /// an entry here too; `SearchTests.everyListedFilterIsRecognizedByTheParser` fails if an
    /// entry is not something the parser understands.
    public static let all: [SearchFilterInfo] = [
        SearchFilterInfo(token: "is:pinned", summary: "saved (pinned) items"),
        SearchFilterInfo(token: "is:concealed", summary: "passwords and other hidden items"),
        SearchFilterInfo(token: "is:image", summary: "screenshots and images"),
        SearchFilterInfo(token: "is:text", summary: "text items"),
        SearchFilterInfo(token: "is:link", summary: "items that are just a web link"),
        SearchFilterInfo(token: "is:today", summary: "last used today"),
    ]

    /// Examples offered once `age:` is typed. `age:<N>` takes any whole number with unit
    /// `m` (minutes), `h` (hours) or `d` (days); these are just the common ones.
    public static let ageExamples: [SearchFilterInfo] = [
        SearchFilterInfo(token: "age:<30m", summary: "used in the last 30 minutes"),
        SearchFilterInfo(token: "age:<2h", summary: "used in the last 2 hours"),
        SearchFilterInfo(token: "age:<1d", summary: "used in the last day"),
        SearchFilterInfo(token: "age:<7d", summary: "used in the last week"),
    ]

    /// Suggestions for the word being typed at the end of `query`: matching `is:` filters not
    /// already used, or, after `app:`, known source apps (at most `appLimit`). Empty when the
    /// last word is neither, is already complete (including an `app:` name that exactly
    /// matches a known app), the query ends in a space, or it starts with the `\` literal
    /// escape. A name with spaces is suggested as `app:"two words"`.
    public static func suggestions(
        for query: String, knownApps: [String], appLimit: Int = 4
    ) -> [SearchSuggestion] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("\\"),
            let last = SearchQuery.tokens(in: query).last,
            last.range.upperBound == query.endIndex
        else { return [] }
        let prefix = String(query[..<last.range.lowerBound])
        let used = SearchQuery.parse(prefix)
        let word = String(last.raw)
        let lowered = word.lowercased()

        if lowered.hasPrefix("is:"), !word.contains(where: \.isWhitespace) {
            let matches = all.filter { filter in
                guard filter.token.hasPrefix(lowered) else { return false }
                switch filter.token {
                case "is:pinned": return !used.pinned
                case "is:concealed": return !used.concealed
                case "is:today": return !used.today
                default: return used.kind == nil
                }
            }
            if matches.count == 1, matches[0].token == lowered { return [] }
            return matches.map {
                SearchSuggestion(label: $0.token, detail: $0.summary, query: prefix + $0.token + " ")
            }
        }

        if lowered.hasPrefix("age:"), !word.contains(where: \.isWhitespace) {
            let matches = ageExamples.filter { $0.token.hasPrefix(lowered) }
            if matches.count == 1, matches[0].token == lowered { return [] }
            if SearchQuery.ageSeconds(in: lowered) != nil { return [] }  // a valid value typed
            return matches.map {
                SearchSuggestion(label: $0.token, detail: $0.summary, query: prefix + $0.token + " ")
            }
        }

        if lowered.hasPrefix("app:") {
            var term = Substring(lowered.dropFirst(4))
            if term.first == "\"" { term = term.dropFirst() }
            if term.last == "\"" { term = term.dropLast() }
            let needle = term.trimmingCharacters(in: .whitespaces)
            let matches = knownApps.filter { needle.isEmpty || $0.lowercased().contains(needle) }
            // A name typed or accepted in full ends the suggestions even when longer names
            // contain it (`Safari` vs `Safari Technology Preview`); otherwise ↑/↓ would stay
            // trapped in the row with no way out but Esc.
            if matches.contains(where: { $0.lowercased() == needle }) { return [] }
            return matches.prefix(appLimit).map { name in
                let token = name.contains(where: \.isWhitespace) ? "app:\"\(name)\"" : "app:\(name)"
                return SearchSuggestion(label: name, detail: nil, query: prefix + token)
            }
        }
        return []
    }
}
