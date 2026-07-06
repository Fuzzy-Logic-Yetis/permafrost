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

    @Test func imagesAppearUnfilteredButNeverMatchTextSearch() throws {
        let store = try seededStore()
        let all = try store.items()
        #expect(all.contains { $0.kind == .image })
        let searched = try store.items(matching: "hello")
        #expect(!searched.contains { $0.kind == .image })
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
}
