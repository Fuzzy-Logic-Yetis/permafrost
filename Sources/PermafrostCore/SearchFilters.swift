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
    ]

    /// Suggestions for the word being typed at the end of `query`: matching `is:` filters not
    /// already used, or, after `app:`, known source apps (at most `appLimit`). Empty when the
    /// last word is neither, is already complete (including an `app:` name that exactly
    /// matches a known app), or the query ends in a space.
    public static func suggestions(
        for query: String, knownApps: [String], appLimit: Int = 4
    ) -> [SearchSuggestion] {
        let endsWithSpace = query.last?.isWhitespace == true
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let parsed = ClipboardStore.leadingFilters(in: q)
        let rest = parsed.rest
        let prefix = String(q.dropLast(rest.count))
        let lowered = rest.lowercased()

        if !endsWithSpace, !rest.contains(where: \.isWhitespace), lowered.hasPrefix("is:") {
            let matches = all.filter { filter in
                guard filter.token.hasPrefix(lowered) else { return false }
                switch filter.token {
                case "is:pinned": return !parsed.pinned
                case "is:image", "is:text", "is:link": return parsed.kind == nil
                default: return true
                }
            }
            if matches.count == 1, matches[0].token == lowered { return [] }
            return matches.map {
                SearchSuggestion(label: $0.token, detail: $0.summary, query: prefix + $0.token + " ")
            }
        }

        if !endsWithSpace, lowered.hasPrefix("app:") {
            let term = lowered.dropFirst(4).trimmingCharacters(in: .whitespaces)
            let matches = knownApps.filter { term.isEmpty || $0.lowercased().contains(term) }
            // A name typed or accepted in full ends the suggestions even when longer names
            // contain it (`Safari` vs `Safari Technology Preview`); otherwise ↑/↓ would stay
            // trapped in the row with no way out but Esc.
            if matches.contains(where: { $0.lowercased() == term }) { return [] }
            return matches.prefix(appLimit).map {
                SearchSuggestion(label: $0, detail: nil, query: prefix + "app:" + $0)
            }
        }
        return []
    }
}
