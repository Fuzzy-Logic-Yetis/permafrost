import Foundation
import Testing

@testable import PermafrostCore

@Suite struct SearchTests {
    let now = Date(timeIntervalSince1970: 2_000_000_000)

    func seededStore() throws -> ClipboardStore {
        let store = try ClipboardStore.inMemory()
        try store.save(ClipboardCapture(text: "Hello world"), now: now)
        try store.save(ClipboardCapture(text: "hello permafrost"), now: now.addingTimeInterval(1))
        try store.save(ClipboardCapture(text: "SELECT * FROM users"), now: now.addingTimeInterval(2))
        try store.save(
            ClipboardCapture(imageData: TestImages.png(width: 10, height: 10)),
            now: now.addingTimeInterval(3))
        return store
    }

    @Test func prefixMatching() throws {
        let store = try seededStore()
        let results = try store.items(matching: "hel").map(\.text)
        #expect(results.count == 2)
        #expect(results.contains("Hello world"))
        #expect(results.contains("hello permafrost"))
    }

    @Test func multiTokenQueryRequiresAllTokens() throws {
        let store = try seededStore()
        let results = try store.items(matching: "hello perma").map(\.text)
        #expect(results == ["hello permafrost"])
    }

    @Test func ftsHostileCharactersDoNotThrow() throws {
        let store = try seededStore()
        // Quotes, stars, parens — must not crash or throw, regardless of matches.
        _ = try store.items(matching: "\"")
        _ = try store.items(matching: "*(")
        let results = try store.items(matching: "SELECT *")
        #expect(results.map(\.text) == ["SELECT * FROM users"])
    }

    @Test func whitespaceQueryReturnsEverything() throws {
        let store = try seededStore()
        #expect(try store.items(matching: "   ").count == 4)
        #expect(try store.items(matching: nil).count == 4)
    }

    @Test func imagesWithoutOCRAppearUnfilteredButNeverMatchTextSearch() throws {
        let store = try seededStore()
        let all = try store.items()
        #expect(all.contains { $0.kind == .image })
        let searched = try store.items(matching: "hello")
        #expect(!searched.contains { $0.kind == .image })
    }

    @Test func imageRowsCanMatchOCRTextSearch() throws {
        let store = try ClipboardStore.inMemory()
        let image = try store.save(
            ClipboardCapture(
                imageData: TestImages.png(width: 10, height: 10),
                ocrText: "Receipt total cappuccino"),
            now: now)
        try store.save(ClipboardCapture(text: "plain receipt text"), now: now.addingTimeInterval(1))

        let results = try store.items(matching: "cappuccino")

        #expect(results.map(\.id) == [image.id])
        #expect(results[0].kind == .image)
        #expect(results[0].ocrText == "Receipt total cappuccino")
    }

    @Test func pinnedMatchesAppearAfterUnpinnedInSearchResults() throws {
        // ADR-012: pinning "Hello world" must not pull it ahead of the more
        // recently-used unpinned match, even within filtered search results.
        let store = try seededStore()
        let target = try store.items().first { $0.text == "Hello world" }!
        try store.setPinned(true, id: target.id!)
        let results = try store.items(matching: "hello").map(\.text)
        #expect(results == ["hello permafrost", "Hello world"])
    }

    // MARK: - Trigram substring matching and app: filtering (ADR-024)

    /// The exact bug report that drove ADR-024: a search for a fragment from the *middle*
    /// of a dense alphanumeric run (what a password or code looks like) found nothing under
    /// unicode61's prefix-only matching, even though the plaintext was sitting right there
    /// in the `text` column — unicode61 only matches from the start of a token.
    @Test func midTokenSubstringMatchesViaTrigram() throws {
        let store = try ClipboardStore.inMemory()
        try store.save(ClipboardCapture(text: "mY7C0ACO2h"), now: now)

        let results = try store.items(matching: "ACO")

        #expect(results.map(\.text) == ["mY7C0ACO2h"])
    }

    @Test func midTokenMatchIsCaseInsensitive() throws {
        let store = try ClipboardStore.inMemory()
        try store.save(ClipboardCapture(text: "mY7C0ACO2h"), now: now)

        #expect(try store.items(matching: "aco").map(\.text) == ["mY7C0ACO2h"])
    }

    /// Trigram indexes 3-character sequences, so a query under that length has no index
    /// entries to match against — documented in ADR-024 as an accepted limit, not a crash.
    @Test func queryShorterThanThreeCharsReturnsNoMatches() throws {
        let store = try ClipboardStore.inMemory()
        try store.save(ClipboardCapture(text: "mY7C0ACO2h"), now: now)

        #expect(try store.items(matching: "ac").isEmpty)
    }

    @Test func appFilterMatchesSourceApp() throws {
        let store = try ClipboardStore.inMemory()
        try store.save(ClipboardCapture(text: "from edge", sourceApp: "Microsoft Edge"), now: now)
        try store.save(
            ClipboardCapture(text: "from textedit", sourceApp: "TextEdit"),
            now: now.addingTimeInterval(1))

        let results = try store.items(matching: "app:edge")

        #expect(results.map(\.text) == ["from edge"])
    }

    @Test func appFilterPrefixIsCaseInsensitive() throws {
        let store = try ClipboardStore.inMemory()
        try store.save(ClipboardCapture(text: "from edge", sourceApp: "Microsoft Edge"), now: now)

        #expect(try store.items(matching: "APP:edge").map(\.text) == ["from edge"])
        #expect(try store.items(matching: "App:edge").map(\.text) == ["from edge"])
    }

    /// The design decision this whole feature hinges on: a bare content search must never
    /// surface an item just because it happened to come from an app whose name matches the
    /// query — otherwise "edge" would return every clipping ever copied from Microsoft Edge,
    /// unrelated content included, which is not what a content search means.
    @Test func bareQueryDoesNotMatchSourceApp() throws {
        let store = try ClipboardStore.inMemory()
        try store.save(
            ClipboardCapture(text: "unrelated content", sourceApp: "Microsoft Edge"), now: now)

        #expect(try store.items(matching: "edge").isEmpty)
    }

    /// The inverse: once scoped with `app:`, the term must not fall through to matching
    /// content text — `app:` means "search source_app," not "search everything."
    @Test func appFilterDoesNotMatchContentText() throws {
        let store = try ClipboardStore.inMemory()
        try store.save(
            ClipboardCapture(text: "I love Microsoft Edge", sourceApp: "TextEdit"), now: now)

        #expect(try store.items(matching: "app:edge").isEmpty)
    }

    /// A lone "app:" with nothing after it isn't a valid filter — falls back to a literal
    /// content search for the text "app:" rather than matching every item.
    @Test func appPrefixWithNoRemainderFallsBackToContentSearch() throws {
        let store = try ClipboardStore.inMemory()
        try store.save(ClipboardCapture(text: "see app: for details"), now: now)
        try store.save(ClipboardCapture(text: "unrelated"), now: now.addingTimeInterval(1))

        #expect(try store.items(matching: "app:").map(\.text) == ["see app: for details"])
    }

    // MARK: - Literal search escape (ADR-025)

    /// The bug a leading `\` exists to fix: content that genuinely starts with "app:" —
    /// a copied docker-compose.yml/Kubernetes label — must still be searchable as content.
    @Test func backslashEscapesAppFilterForLiteralContentSearch() throws {
        let store = try ClipboardStore.inMemory()
        try store.save(ClipboardCapture(text: "app: nginx"), now: now)
        try store.save(
            ClipboardCapture(text: "unrelated", sourceApp: "nginx"), now: now.addingTimeInterval(1))

        // `app:` needs its value attached (ADR-028), so `app: nginx` is already plain text.
        #expect(try store.items(matching: "app: nginx").map(\.text) == ["app: nginx"])
        #expect(try store.items(matching: "\\app: nginx").map(\.text) == ["app: nginx"])
        // The filter itself still works; escaped, the same words search content instead.
        #expect(try store.items(matching: "app:nginx").map(\.text) == ["unrelated"])
        #expect(try store.items(matching: "\\app:nginx").map(\.text) == ["app: nginx"])
    }

    // MARK: - is:concealed and source-app listing

    @Test func isConcealedFilterListsOnlyConcealedItems() throws {
        let store = try ClipboardStore.inMemory()
        try store.save(ClipboardCapture(text: "plain note"), now: now)
        try store.save(
            ClipboardCapture(text: "hunter2hunter2", isConcealed: true),
            now: now.addingTimeInterval(1))

        let results = try store.items(matching: "is:concealed")

        #expect(results.count == 1)
        #expect(results.first?.isConcealed == true)
        // Still redacted: the filter never surfaces plaintext.
        #expect(results.first?.text == nil)
        #expect(try store.items(matching: "  IS:Concealed ").count == 1)
    }

    @Test func isConcealedFilterKeepsPinnedItemsLast() throws {
        let store = try ClipboardStore.inMemory()
        let first = try store.save(
            ClipboardCapture(text: "secretone", isConcealed: true), now: now)
        try store.save(
            ClipboardCapture(text: "secrettwo", isConcealed: true), now: now.addingTimeInterval(1))
        try store.setPinned(true, id: try #require(first.id))

        let results = try store.items(matching: "is:concealed")

        #expect(results.map(\.isPinned) == [false, true])
    }

    @Test func isConcealedWithFreeTextMatchesNothingAndTheEscapeSearchesText() throws {
        let store = try ClipboardStore.inMemory()
        try store.save(ClipboardCapture(text: "is:concealed is a filter"), now: now)
        try store.save(
            ClipboardCapture(text: "hunter2hunter2", isConcealed: true),
            now: now.addingTimeInterval(1))

        #expect(try store.items(matching: "\\is:concealed").map(\.text) == ["is:concealed is a filter"])
        // A filter plus free text: concealed content is never searched, so nothing matches.
        #expect(try store.items(matching: "is:concealed filter").isEmpty)
    }

    @Test func distinctSourceAppsAreUniqueAndMostRecentFirst() throws {
        let store = try ClipboardStore.inMemory()
        try store.save(ClipboardCapture(text: "a", sourceApp: "TextEdit"), now: now)
        try store.save(
            ClipboardCapture(text: "b", sourceApp: "Microsoft Edge"), now: now.addingTimeInterval(1))
        try store.save(
            ClipboardCapture(text: "c", sourceApp: "TextEdit"), now: now.addingTimeInterval(2))
        try store.save(ClipboardCapture(text: "d"), now: now.addingTimeInterval(3))

        #expect(try store.distinctSourceApps() == ["TextEdit", "Microsoft Edge"])
    }

    // MARK: - is:pinned

    private func pinnedFixture() throws -> ClipboardStore {
        let store = try ClipboardStore.inMemory()
        let pinned = try store.save(
            ClipboardCapture(text: "login hunter22 for work", sourceApp: "Safari"), now: now)
        try store.save(
            ClipboardCapture(text: "login scratch note", sourceApp: "Safari"),
            now: now.addingTimeInterval(1))
        try store.save(
            ClipboardCapture(text: "unrelated", sourceApp: "TextEdit"),
            now: now.addingTimeInterval(2))
        let secret = try store.save(
            ClipboardCapture(text: "topsecretvalue", isConcealed: true),
            now: now.addingTimeInterval(3))
        try store.setPinned(true, id: try #require(pinned.id))
        try store.setPinned(true, id: try #require(secret.id))
        return store
    }

    @Test func isPinnedAloneListsOnlyPinnedItems() throws {
        let store = try pinnedFixture()

        #expect(try store.items(matching: "is:pinned").count == 2)
        #expect(try store.items(matching: "IS:Pinned").allSatisfy(\.isPinned))
    }

    @Test func isPinnedCombinesWithContentSearch() throws {
        let store = try pinnedFixture()

        // "login" also matches an unpinned note; only the pinned one may come back.
        #expect(try store.items(matching: "login").count == 2)
        #expect(
            try store.items(matching: "is:pinned login").map(\.text) == ["login hunter22 for work"])
        #expect(try store.items(matching: "is:pinned unrelated").isEmpty)
    }

    @Test func isPinnedCombinesWithAppAndConcealedFilters() throws {
        let store = try pinnedFixture()

        #expect(try store.items(matching: "is:pinned app:safari").count == 1)
        #expect(try store.items(matching: "is:pinned app:textedit").isEmpty)
        let concealed = try store.items(matching: "is:pinned is:concealed")
        #expect(concealed.count == 1)
        #expect(concealed.first?.isConcealed == true)
    }

    @Test func isPinnedMustBeAWholeWordAndHonorsTheLiteralEscape() throws {
        let store = try ClipboardStore.inMemory()
        try store.save(ClipboardCapture(text: "is:pinned is a filter"), now: now)
        try store.save(ClipboardCapture(text: "is:pinnedish thing"), now: now.addingTimeInterval(1))

        #expect(try store.items(matching: "\\is:pinned filter").map(\.text) == ["is:pinned is a filter"])
        // Not the filter: no pinned items exist, yet the content search still finds this.
        #expect(try store.items(matching: "is:pinnedish").map(\.text) == ["is:pinnedish thing"])
        #expect(try store.items(matching: "is:pinned").isEmpty)
    }

    // MARK: - Separate pinned limit (backlog H2)

    @Test func longUnpinnedHistoryCannotPushPinnedItemsOutOfTheResult() throws {
        let store = try ClipboardStore.inMemory()
        let old = try store.save(ClipboardCapture(text: "pinned login oldest"), now: now)
        try store.setPinned(true, id: try #require(old.id))
        for n in 1...6 {
            try store.save(
                ClipboardCapture(text: "recent \(n)"), now: now.addingTimeInterval(Double(n)))
        }

        let results = try store.items(limit: 3)

        // 3 newest unpinned, then the pinned item despite being the oldest row.
        #expect(results.map(\.text) == ["recent 6", "recent 5", "recent 4", "pinned login oldest"])
    }

    @Test func pinnedLimitCapsPinnedRowsKeepingMostRecentlyPinned() throws {
        let store = try ClipboardStore.inMemory()
        for n in 1...4 {
            let item = try store.save(
                ClipboardCapture(text: "pin \(n)"), now: now.addingTimeInterval(Double(n)))
            try store.setPinned(true, id: try #require(item.id))
        }

        #expect(try store.items(limit: 10, pinnedLimit: 2).map(\.text) == ["pin 4", "pin 3"])
        #expect(try store.items(matching: "is:pinned", limit: 1, pinnedLimit: 3).count == 3)
    }

    @Test func concealedPinsAreReachableBeyondTheUnpinnedLimit() throws {
        let store = try ClipboardStore.inMemory()
        let secret = try store.save(
            ClipboardCapture(text: "hunter2hunter2", isConcealed: true), now: now)
        try store.setPinned(true, id: try #require(secret.id))
        for n in 1...5 {
            try store.save(
                ClipboardCapture(text: "recent \(n)"), now: now.addingTimeInterval(Double(n)))
        }

        let results = try store.items(limit: 2)

        #expect(results.last?.isConcealed == true)
        #expect(results.last?.isPinned == true)
    }

    // MARK: - is:image / is:text / is:link

    private func kindFixture() throws -> ClipboardStore {
        let store = try ClipboardStore.inMemory()
        try store.save(ClipboardCapture(text: "plain note about invoice"), now: now)
        try store.save(ClipboardCapture(text: "https://example.com/a?b=1"), now: now.addingTimeInterval(1))
        try store.save(
            ClipboardCapture(text: "  http://example.org/path  \n"), now: now.addingTimeInterval(2))
        try store.save(
            ClipboardCapture(text: "see https://example.com for more"), now: now.addingTimeInterval(3))
        try store.save(ClipboardCapture(text: "mailto:a@b.co"), now: now.addingTimeInterval(4))
        try store.save(ClipboardCapture(text: "https://exa mple.com"), now: now.addingTimeInterval(5))
        try store.save(
            ClipboardCapture(text: "https://secret.example/token", isConcealed: true),
            now: now.addingTimeInterval(6))
        try store.save(
            ClipboardCapture(imageData: TestImages.png(width: 10, height: 10), ocrText: "invoice scan"),
            now: now.addingTimeInterval(7))
        return store
    }

    @Test func isImageListsOnlyImages() throws {
        let store = try kindFixture()

        let results = try store.items(matching: "is:image")

        #expect(results.count == 1)
        #expect(results.allSatisfy { $0.kind == .image })
    }

    @Test func isTextListsOnlyTextItems() throws {
        let store = try kindFixture()

        let results = try store.items(matching: "IS:Text")

        #expect(results.count == 7)
        #expect(results.allSatisfy { $0.kind == .text })
    }

    @Test func isLinkMatchesOnlyAWholeHTTPURL() throws {
        let store = try kindFixture()

        let texts = try store.items(matching: "is:link").map(\.text)

        #expect(
            Set(texts) == ["https://example.com/a?b=1", "  http://example.org/path  \n"])
    }

    @Test func concealedItemsNeverMatchIsLinkEvenWhenTheirPlaintextWasAURL() throws {
        let store = try kindFixture()

        let results = try store.items(matching: "is:link")

        #expect(results.allSatisfy { !$0.isConcealed })
        #expect(try store.items(matching: "is:link is:concealed").isEmpty)
    }

    @Test func kindFiltersComposeWithContentAppAndPinned() throws {
        let store = try kindFixture()
        // OCR text is content for images; a text-only note with the same word must not leak in.
        #expect(try store.items(matching: "is:image invoice").count == 1)
        #expect(try store.items(matching: "is:text invoice").map(\.text) == ["plain note about invoice"])
        #expect(try store.items(matching: "is:link example.org").count == 1)

        let pinned = try #require(try store.items(matching: "is:link").first)
        try store.setPinned(true, id: try #require(pinned.id))
        #expect(try store.items(matching: "is:pinned is:link").count == 1)
        #expect(try store.items(matching: "is:link is:pinned").count == 1)
        #expect(try store.items(matching: "is:pinned is:image").isEmpty)
    }

    @Test func kindFiltersHonorTheLiteralEscapeAndWholeWordRule() throws {
        let store = try ClipboardStore.inMemory()
        try store.save(ClipboardCapture(text: "is:image is a filter"), now: now)
        try store.save(ClipboardCapture(text: "is:imagery thing"), now: now.addingTimeInterval(1))

        #expect(try store.items(matching: "\\is:image filter").map(\.text) == ["is:image is a filter"])
        #expect(try store.items(matching: "is:imagery").map(\.text) == ["is:imagery thing"])
        #expect(try store.items(matching: "is:image").isEmpty)
    }

    @Test func kindFiltersKeepTheSeparatePinnedAndUnpinnedCaps() throws {
        let store = try ClipboardStore.inMemory()
        let old = try store.save(ClipboardCapture(text: "https://pinned.example"), now: now)
        try store.setPinned(true, id: try #require(old.id))
        for n in 1...4 {
            try store.save(
                ClipboardCapture(text: "https://recent.example/\(n)"),
                now: now.addingTimeInterval(Double(n)))
        }

        let results = try store.items(matching: "is:link", limit: 2)

        #expect(results.map(\.text) == [
            "https://recent.example/4", "https://recent.example/3", "https://pinned.example",
        ])
    }

    // MARK: - Filter suggestions

    @Test func isPrefixListsFiltersAndNarrowsAsYouType() {
        let all = SearchFilters.all.map(\.token)

        #expect(SearchFilters.suggestions(for: "is:", knownApps: []).map(\.label) == all)
        #expect(SearchFilters.suggestions(for: "IS:p", knownApps: []).map(\.label) == ["is:pinned"])
        #expect(SearchFilters.suggestions(for: "is:i", knownApps: []).map(\.label) == ["is:image"])
        #expect(SearchFilters.suggestions(for: "is:zzz", knownApps: []).isEmpty)
        // Complete word, trailing space, or not a filter prefix: nothing to suggest.
        #expect(SearchFilters.suggestions(for: "is:pinned", knownApps: []).isEmpty)
        #expect(SearchFilters.suggestions(for: "is:pinned ", knownApps: []).isEmpty)
        #expect(SearchFilters.suggestions(for: "", knownApps: []).isEmpty)
        #expect(SearchFilters.suggestions(for: "invoice", knownApps: []).isEmpty)
        // Filters work anywhere in the query, so they are suggested anywhere too.
        #expect(
            SearchFilters.suggestions(for: "login is:i", knownApps: []).map(\.query)
                == ["login is:image "])
        #expect(SearchFilters.suggestions(for: "\\is:", knownApps: []).isEmpty)  // literal escape
    }

    @Test func suggestionsSkipFiltersAlreadyUsedAndKeepTheEarlierWords() throws {
        let afterPinned = SearchFilters.suggestions(for: "is:pinned is:", knownApps: [])
        #expect(afterPinned.map(\.label) == ["is:concealed", "is:image", "is:text", "is:link"])
        #expect(afterPinned.first?.query == "is:pinned is:concealed ")

        let afterKind = SearchFilters.suggestions(for: "is:image is:", knownApps: [])
        #expect(afterKind.map(\.label) == ["is:pinned", "is:concealed"])
    }

    @Test func appSuggestionsFilterKnownAppsAndComposeAfterModifiers() {
        let apps = ["Microsoft Edge", "TextEdit", "Safari"]

        #expect(SearchFilters.suggestions(for: "app:", knownApps: apps).map(\.label) == apps)
        #expect(
            SearchFilters.suggestions(for: "APP:ed", knownApps: apps).map(\.label)
                == ["Microsoft Edge", "TextEdit"])
        #expect(SearchFilters.suggestions(for: "app:zzz", knownApps: apps).isEmpty)
        #expect(SearchFilters.suggestions(for: "app:safari", knownApps: apps).isEmpty)
        #expect(SearchFilters.suggestions(for: "app:", knownApps: apps, appLimit: 2).count == 2)
        #expect(SearchFilters.suggestions(for: "edge", knownApps: apps).isEmpty)
        let composed = SearchFilters.suggestions(for: "is:pinned app:saf", knownApps: apps)
        #expect(composed.map(\.query) == ["is:pinned app:Safari"])
    }

    @Test func appSuggestionsEndOnATrailingSpace() {
        let apps = ["Safari", "Safari Technology Preview"]

        #expect(SearchFilters.suggestions(for: "app:Safari ", knownApps: apps).isEmpty)
        #expect(SearchFilters.suggestions(for: "app:saf ", knownApps: apps).isEmpty)
        #expect(SearchFilters.suggestions(for: "is:pinned app:saf ", knownApps: apps).isEmpty)
    }

    /// Accepting `Safari` must dismiss the row even though a longer app name still contains it,
    /// or the arrow keys stay captured by the suggestions.
    @Test func acceptingAnAppThatIsAPrefixOfAnotherEndsTheSuggestions() throws {
        let apps = ["Safari", "Safari Technology Preview"]
        let typed = SearchFilters.suggestions(for: "app:saf", knownApps: apps)
        #expect(typed.map(\.label) == apps)

        let accepted = try #require(typed.first).query

        #expect(accepted == "app:Safari")
        #expect(SearchFilters.suggestions(for: accepted, knownApps: apps).isEmpty)
        // The longer name is still reachable by typing on or accepting it.
        #expect(
            SearchFilters.suggestions(for: "app:\"Safari T", knownApps: apps).map(\.query)
                == ["app:\"Safari Technology Preview\""])
    }

    // MARK: - One grammar (ADR-028)

    @Test func parserSeparatesFiltersFromFreeTextInAnyOrder() {
        typealias Q = SearchQuery
        #expect(Q.parse("") == Q())
        #expect(Q.parse("invoice") == Q(text: "invoice"))
        #expect(Q.parse("is:pinned") == Q(pinned: true))
        #expect(Q.parse("IS:Image invoice") == Q(kind: .image, text: "invoice"))
        #expect(Q.parse("invoice is:image") == Q(kind: .image, text: "invoice"))
        #expect(
            Q.parse("is:image app:safari invoice total")
                == Q(kind: .image, app: "safari", text: "invoice total"))
        #expect(
            Q.parse("login app:edge is:pinned is:concealed")
                == Q(pinned: true, concealed: true, app: "edge", text: "login"))
        #expect(Q.parse("is:text is:link") == Q(kind: .link))  // last kind wins
        #expect(Q.parse("app:a app:b") == Q(app: "b"))  // last app wins
    }

    @Test func parserTreatsUnknownOrIncompleteFiltersAsText() {
        typealias Q = SearchQuery
        #expect(Q.parse("is:pinnedx") == Q(text: "is:pinnedx"))
        #expect(Q.parse("is:foo bar") == Q(text: "is:foo bar"))
        #expect(Q.parse("app:") == Q(text: "app:"))  // lone app: is searchable text
        #expect(Q.parse("app: nginx") == Q(text: "app: nginx"))  // space after the colon
        #expect(Q.parse("application:edge") == Q(text: "application:edge"))
    }

    @Test func parserReadsQuotedAppNamesAndTheLiteralEscape() {
        typealias Q = SearchQuery
        #expect(Q.parse("app:\"Microsoft Edge\"") == Q(app: "Microsoft Edge"))
        #expect(
            Q.parse("is:pinned app:\"Microsoft Edge\" login")
                == Q(pinned: true, app: "Microsoft Edge", text: "login"))
        #expect(Q.parse("app:\"Microsoft Edge") == Q(app: "Microsoft Edge"))  // still typing
        #expect(Q.parse("\\is:pinned app:x") == Q(text: "is:pinned app:x"))
        #expect(Q.parse("\\") == Q())
    }

    @Test func everyListedFilterIsRecognizedByTheParser() throws {
        let store = try ClipboardStore.inMemory()
        for filter in SearchFilters.all {
            let parsed = SearchQuery.parse(filter.token)
            #expect(parsed != SearchQuery(text: filter.token), "\(filter.token) is listed but not parsed")
            #expect(parsed.text.isEmpty)
            #expect(filter.token.hasPrefix("is:"))
            #expect(!filter.summary.isEmpty)
            _ = try store.items(matching: filter.token)  // and it runs
        }
        #expect(Set(SearchFilters.all.map(\.token)).count == SearchFilters.all.count)
    }

    private func grammarFixture() throws -> ClipboardStore {
        let store = try ClipboardStore.inMemory()
        try store.save(
            ClipboardCapture(text: "invoice total 42", sourceApp: "Safari"), now: now)
        try store.save(
            ClipboardCapture(text: "invoice total 99", sourceApp: "TextEdit"),
            now: now.addingTimeInterval(1))
        try store.save(
            ClipboardCapture(text: "hello world", sourceApp: "Safari"),
            now: now.addingTimeInterval(2))
        try store.save(
            ClipboardCapture(
                imageData: TestImages.png(width: 10, height: 10), ocrText: "invoice scan",
                sourceApp: "Safari"),
            now: now.addingTimeInterval(3))
        try store.save(
            ClipboardCapture(text: "microsoft doc invoice", sourceApp: "Microsoft Edge"),
            now: now.addingTimeInterval(4))
        try store.save(
            ClipboardCapture(text: "hunter2hunter2", sourceApp: "Safari", isConcealed: true),
            now: now.addingTimeInterval(5))
        return store
    }

    @Test func appAndContentCombineInEitherOrder() throws {
        let store = try grammarFixture()

        #expect(try store.items(matching: "app:safari invoice").count == 2)  // text + image
        #expect(try store.items(matching: "invoice app:safari").count == 2)
        #expect(try store.items(matching: "app:textedit invoice").count == 1)
        #expect(try store.items(matching: "app:textedit hello").isEmpty)
        #expect(try store.items(matching: "app:safari").count == 4)  // incl. the concealed one
    }

    @Test func filtersCombineWithAppAndContentInAnyOrder() throws {
        let store = try grammarFixture()

        #expect(try store.items(matching: "is:image app:safari invoice").count == 1)
        #expect(try store.items(matching: "invoice is:image app:safari").count == 1)
        #expect(try store.items(matching: "app:safari is:text invoice").count == 1)
        #expect(try store.items(matching: "is:text invoice").count == 3)
    }

    @Test func quotedAppNamesMatchNamesWithSpaces() throws {
        let store = try grammarFixture()

        #expect(try store.items(matching: "app:\"Microsoft Edge\"").count == 1)
        #expect(try store.items(matching: "app:\"Microsoft Edge\" invoice").count == 1)
        #expect(try store.items(matching: "app:\"Microsoft Edge\" hello").isEmpty)
    }

    @Test func concealedComposesWithAppAndPinnedButFreeTextNeverMatchesIt() throws {
        let store = try grammarFixture()

        let concealed = try store.items(matching: "is:concealed app:safari")
        #expect(concealed.count == 1)
        #expect(concealed.first?.text == nil)  // still redacted
        #expect(try store.items(matching: "app:edge is:concealed").isEmpty)
        // Content is never searched inside concealed items (ADR-011/021).
        #expect(try store.items(matching: "is:concealed hunter2").isEmpty)
        #expect(try store.items(matching: "hunter2").isEmpty)
    }

    @Test func aFilterWordLaterInTheQueryIsAFilterAndTheEscapeMakesItText() throws {
        let store = try ClipboardStore.inMemory()
        let pinned = try store.save(ClipboardCapture(text: "login for work"), now: now)
        try store.setPinned(true, id: try #require(pinned.id))
        try store.save(ClipboardCapture(text: "login scratch"), now: now.addingTimeInterval(1))
        try store.save(
            ClipboardCapture(text: "login is:pinned how to"), now: now.addingTimeInterval(2))

        #expect(try store.items(matching: "login is:pinned").map(\.text) == ["login for work"])
        #expect(
            try store.items(matching: "\\login is:pinned").map(\.text) == ["login is:pinned how to"])
    }

    @Test func invalidOrHostileFilterValuesMatchNothingWithoutThrowing() throws {
        let store = try grammarFixture()

        #expect(try store.items(matching: "app:\"\"\"").isEmpty)
        // Punctuation-only words are dropped by the tokenizer rather than failing the query.
        _ = try store.items(matching: "app:safari ((( invoice")
        #expect(try store.items(matching: "is:image \"unterminated").isEmpty)
    }
}
