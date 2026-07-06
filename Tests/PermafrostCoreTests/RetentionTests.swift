import Foundation
import Testing

@testable import PermafrostCore

@Suite struct RetentionTests {
    let now = Date(timeIntervalSince1970: 2_000_000_000)

    func makeStore() throws -> ClipboardStore {
        try ClipboardStore.inMemory()
    }

    @Test func pinnedSurvivesPurgeThatRemovesEverythingElse() throws {
        let store = try makeStore()
        let old = now.addingTimeInterval(-100 * 24 * 3600)
        let pinned = try store.save(ClipboardCapture(text: "keep me"), now: old)
        try store.save(ClipboardCapture(text: "expire me"), now: old)
        try store.setPinned(true, id: pinned.id!)

        let deleted = try store.purge(
            with: RetentionPolicy(maxAge: 30 * 24 * 3600), now: now)

        #expect(deleted == 1)
        let remaining = try store.items()
        #expect(remaining.count == 1)
        #expect(remaining[0].text == "keep me")
        #expect(remaining[0].isPinned)
    }

    @Test func unpinnedYoungerThanTTLSurvives() throws {
        let store = try makeStore()
        try store.save(ClipboardCapture(text: "fresh"), now: now.addingTimeInterval(-3600))
        try store.save(
            ClipboardCapture(text: "stale"), now: now.addingTimeInterval(-10 * 24 * 3600))

        try store.purge(with: RetentionPolicy(maxAge: 7 * 24 * 3600), now: now)

        let texts = try store.items().map(\.text)
        #expect(texts == ["fresh"])
    }

    @Test func expiryMeasuredFromLastUseNotCreation() throws {
        let store = try makeStore()
        let created = now.addingTimeInterval(-100 * 24 * 3600)
        let item = try store.save(ClipboardCapture(text: "old but loved"), now: created)
        try store.markUsed(id: item.id!, now: now.addingTimeInterval(-60))

        try store.purge(with: RetentionPolicy(maxAge: 30 * 24 * 3600), now: now)

        #expect(try store.count() == 1)
    }

    @Test func countCapKeepsNewestUnpinnedAndNeverTouchesPinned() throws {
        let store = try makeStore()
        for i in 0..<10 {
            try store.save(
                ClipboardCapture(text: "item \(i)"),
                now: now.addingTimeInterval(TimeInterval(i)))
        }
        let pinnedItem = try store.items().last!  // oldest
        try store.setPinned(true, id: pinnedItem.id!)

        try store.purge(with: RetentionPolicy(maxUnpinnedCount: 3), now: now)

        let remaining = try store.items()
        #expect(remaining.count == 4)  // 3 newest unpinned + the pinned oldest
        #expect(remaining.contains { $0.isPinned && $0.text == "item 0" })
        let unpinnedTexts = remaining.filter { !$0.isPinned }.map(\.text)
        #expect(unpinnedTexts == ["item 9", "item 8", "item 7"])
    }

    @Test func nilMaxAgeNeverDeletes() throws {
        let store = try makeStore()
        try store.save(
            ClipboardCapture(text: "ancient"),
            now: now.addingTimeInterval(-3650 * 24 * 3600))

        let deleted = try store.purge(with: RetentionPolicy(), now: now)

        #expect(deleted == 0)
        #expect(try store.count() == 1)
    }

    @Test func clearHistoryKeepsPinnedByDefault() throws {
        let store = try makeStore()
        let a = try store.save(ClipboardCapture(text: "a"), now: now)
        try store.save(ClipboardCapture(text: "b"), now: now)
        try store.setPinned(true, id: a.id!)

        try store.clearHistory()

        let remaining = try store.items()
        #expect(remaining.map(\.text) == ["a"])

        try store.clearHistory(keepPinned: false)
        #expect(try store.count() == 0)
    }
}
