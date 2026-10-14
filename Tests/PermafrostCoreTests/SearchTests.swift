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

    @Test func appFilterTermParsing() {
        #expect(ClipboardStore.appFilterTerm(in: "app:edge") == "edge")
        #expect(ClipboardStore.appFilterTerm(in: "app: edge") == "edge")
        #expect(ClipboardStore.appFilterTerm(in: "APP:Edge") == "Edge")
        #expect(ClipboardStore.appFilterTerm(in: "app:") == nil)
        #expect(ClipboardStore.appFilterTerm(in: "app:   ") == nil)
        #expect(ClipboardStore.appFilterTerm(in: "application:edge") == nil)
        #expect(ClipboardStore.appFilterTerm(in: "edge") == nil)
    }

    // MARK: - Literal search escape (ADR-025)

    /// The bug a leading `\` exists to fix: content that genuinely starts with "app:" —
    /// a copied docker-compose.yml/Kubernetes label — must still be searchable as content.
    @Test func backslashEscapesAppFilterForLiteralContentSearch() throws {
        let store = try ClipboardStore.inMemory()
        try store.save(ClipboardCapture(text: "app: nginx"), now: now)
        try store.save(
            ClipboardCapture(text: "unrelated", sourceApp: "nginx"), now: now.addingTimeInterval(1))

        // Unescaped: hijacked into an app: filter, matches the Edge-equivalent row only.
        #expect(try store.items(matching: "app: nginx").map(\.text) == ["unrelated"])
        // Escaped: literal content search, matches the docker-compose-style line instead.
        #expect(try store.items(matching: "\\app: nginx").map(\.text) == ["app: nginx"])
    }

    @Test func stripLiteralSearchEscapeParsing() {
        #expect(ClipboardStore.stripLiteralSearchEscape(from: "\\app: nginx").text == "app: nginx")
        #expect(ClipboardStore.stripLiteralSearchEscape(from: "\\app: nginx").isLiteral == true)
        #expect(ClipboardStore.stripLiteralSearchEscape(from: "app:edge").text == "app:edge")
        #expect(ClipboardStore.stripLiteralSearchEscape(from: "app:edge").isLiteral == false)
        // A bare backslash still forces literal mode, even though nothing remains after it —
        // same degenerate-but-sane fallback as a lone "app:".
        #expect(ClipboardStore.stripLiteralSearchEscape(from: "\\").text == "")
        #expect(ClipboardStore.stripLiteralSearchEscape(from: "\\").isLiteral == true)
    }
}
