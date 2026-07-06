import Foundation
import Testing

@testable import PermafrostCore

@Suite struct StoreTests {
    let now = Date(timeIntervalSince1970: 2_000_000_000)

    @Test func dedupBumpsLastUsedInsteadOfDuplicating() throws {
        let store = try ClipboardStore.inMemory()
        let first = try store.save(ClipboardCapture(text: "same"), now: now)
        let second = try store.save(
            ClipboardCapture(text: "same"), now: now.addingTimeInterval(60))

        #expect(try store.count() == 1)
        #expect(first.id == second.id)
        #expect(second.lastUsedAt > first.createdAt)
    }

    @Test func dedupPreservesPinState() throws {
        let store = try ClipboardStore.inMemory()
        let item = try store.save(ClipboardCapture(text: "pinned content"), now: now)
        try store.setPinned(true, id: item.id!)

        let again = try store.save(
            ClipboardCapture(text: "pinned content"), now: now.addingTimeInterval(60))

        #expect(again.isPinned)
        #expect(try store.count() == 1)
    }

    @Test func orderingIsPinnedFirstThenRecency() throws {
        let store = try ClipboardStore.inMemory()
        for i in 0..<4 {
            try store.save(
                ClipboardCapture(text: "t\(i)"), now: now.addingTimeInterval(TimeInterval(i)))
        }
        // Pin t1 then t0: pin order must be stable (t1 pinned first).
        let all = try store.items()
        try store.setPinned(true, id: all.first { $0.text == "t1" }!.id!)
        try store.setPinned(true, id: all.first { $0.text == "t0" }!.id!)

        let ordered = try store.items().map(\.text)
        #expect(ordered == ["t1", "t0", "t3", "t2"])
    }

    @Test func deleteRemovesRow() throws {
        let store = try ClipboardStore.inMemory()
        let item = try store.save(ClipboardCapture(text: "goner"), now: now)
        try store.delete(id: item.id!)
        #expect(try store.count() == 0)
    }

    @Test func concealedFlagPersists() throws {
        let store = try ClipboardStore.inMemory()
        try store.save(
            ClipboardCapture(text: "hunter2", isConcealed: true), now: now)
        let items = try store.items()
        #expect(items.count == 1)
        #expect(items[0].isConcealed)
    }

    @Test func imageCaptureStoresDataAndThumbnail() throws {
        let store = try ClipboardStore.inMemory()
        let png = TestImages.png(width: 800, height: 600)
        let item = try store.save(ClipboardCapture(imageData: png), now: now)

        #expect(item.kind == .image)
        #expect(item.imageData == png)
        let thumbnail = try #require(item.thumbnail)
        let size = try #require(Thumbnailer.pixelSize(of: thumbnail))
        #expect(size.width <= 480 && size.height <= 480)
    }

    @Test func identicalImagesDedup() throws {
        let store = try ClipboardStore.inMemory()
        let png = TestImages.png(width: 100, height: 100)
        try store.save(ClipboardCapture(imageData: png), now: now)
        try store.save(ClipboardCapture(imageData: png), now: now.addingTimeInterval(5))
        #expect(try store.count() == 1)
    }

    @Test func corruptImageDataDoesNotCrashThumbnailer() throws {
        #expect(Thumbnailer.pngThumbnail(from: Data([0xde, 0xad, 0xbe, 0xef])) == nil)
        #expect(Thumbnailer.pngThumbnail(from: Data()) == nil)
    }
}
