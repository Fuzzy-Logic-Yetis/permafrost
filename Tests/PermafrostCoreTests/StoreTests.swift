import CryptoKit
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

    @Test func dedupRefreshesSourceAppAndRichDataToLatestCopy() throws {
        // Review H-1: stale metadata from the first copy must not survive a recopy —
        // otherwise old RTF formatting or a wrong source-app caption lingers forever.
        let store = try ClipboardStore.inMemory()
        _ = try store.save(
            ClipboardCapture(
                text: "same", richData: Data("rich-v1".utf8), sourceApp: "AppOne"),
            now: now)

        let second = try store.save(
            ClipboardCapture(
                text: "same", richData: Data("rich-v2".utf8), sourceApp: "AppTwo"),
            now: now.addingTimeInterval(60))

        #expect(try store.count() == 1)
        #expect(second.sourceApp == "AppTwo")
        #expect(second.richData == Data("rich-v2".utf8))
    }

    @Test func dedupClearsRichDataWhenLatestCopyHasNone() throws {
        let store = try ClipboardStore.inMemory()
        _ = try store.save(
            ClipboardCapture(text: "same", richData: Data("rich".utf8)), now: now)

        let second = try store.save(
            ClipboardCapture(text: "same"), now: now.addingTimeInterval(60))

        #expect(second.richData == nil)
    }

    @Test func dedupIsConcealedIsStickyInSaferDirection() throws {
        // Review H-1: once content has been recorded as sensitive, a later
        // coincidental non-concealed copy of the same text must not un-mark it.
        let store = try ClipboardStore.inMemory()
        _ = try store.save(ClipboardCapture(text: "secretish"), now: now)
        let second = try store.save(
            ClipboardCapture(text: "secretish", isConcealed: true),
            now: now.addingTimeInterval(1))
        #expect(second.isConcealed)

        let third = try store.save(
            ClipboardCapture(text: "secretish", isConcealed: false),
            now: now.addingTimeInterval(2))
        #expect(third.isConcealed)
    }

    @Test func orderingIsRecentFirstThenPinnedAtBottom() throws {
        // ADR-012: pinning must never displace the most recent copy from the
        // front of the list or steal its ⌘1 quick-paste slot.
        let store = try ClipboardStore.inMemory()
        for i in 0..<4 {
            try store.save(
                ClipboardCapture(text: "t\(i)"), now: now.addingTimeInterval(TimeInterval(i)))
        }
        // Pin t1 then t0: within the pinned section, most-recently-pinned is first.
        let all = try store.items()
        try store.setPinned(true, id: all.first { $0.text == "t1" }!.id!)
        try store.setPinned(true, id: all.first { $0.text == "t0" }!.id!)

        let ordered = try store.items().map(\.text)
        #expect(ordered == ["t3", "t2", "t0", "t1"])
    }

    @Test func unpinnedAlwaysPrecedePinnedRegardlessOfRecency() throws {
        let store = try ClipboardStore.inMemory()
        let old = try store.save(
            ClipboardCapture(text: "ancient"), now: now.addingTimeInterval(-1000))
        try store.setPinned(true, id: old.id!)
        try store.save(ClipboardCapture(text: "brand new"), now: now)

        #expect(try store.items().map(\.text) == ["brand new", "ancient"])
    }

    @Test func unpinAllConvertsPinnedToUnpinnedWithoutDeleting() throws {
        let store = try ClipboardStore.inMemory()
        let a = try store.save(ClipboardCapture(text: "a"), now: now)
        let b = try store.save(
            ClipboardCapture(text: "b"), now: now.addingTimeInterval(1))
        try store.setPinned(true, id: a.id!)
        try store.setPinned(true, id: b.id!)
        #expect(try store.pinnedCount() == 2)

        try store.unpinAll()

        #expect(try store.pinnedCount() == 0)
        let items = try store.items()
        #expect(items.count == 2)
        #expect(items.allSatisfy { !$0.isPinned && $0.pinOrder == nil })
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

    @Test func imageCapturePersistsOCRTextWithoutChangingContentHash() throws {
        let store = try ClipboardStore.inMemory()
        let png = TestImages.png(width: 800, height: 600)
        let withoutOCR = ClipboardCapture(imageData: png)
        let withOCR = ClipboardCapture(imageData: png, ocrText: "Invoice total $42.00")

        let item = try store.save(withOCR, now: now)

        #expect(item.kind == .image)
        #expect(item.ocrText == "Invoice total $42.00")
        #expect(withOCR.contentHash == withoutOCR.contentHash)
    }

    @Test func imageDedupRefreshesOCRTextToLatestCopy() throws {
        let store = try ClipboardStore.inMemory()
        let png = TestImages.png(width: 100, height: 100)
        _ = try store.save(
            ClipboardCapture(imageData: png, ocrText: "old recognition"), now: now)

        let second = try store.save(
            ClipboardCapture(imageData: png, ocrText: "new recognition"),
            now: now.addingTimeInterval(5))

        #expect(try store.count() == 1)
        #expect(second.ocrText == "new recognition")
    }

    @Test func imageDedupDoesNotClearOCRTextWhenLatestCaptureHasNone() throws {
        let store = try ClipboardStore.inMemory()
        let png = TestImages.png(width: 100, height: 100)
        _ = try store.save(
            ClipboardCapture(imageData: png, ocrText: "recognized text"), now: now)

        let second = try store.save(ClipboardCapture(imageData: png), now: now.addingTimeInterval(5))

        #expect(try store.count() == 1)
        #expect(second.ocrText == "recognized text")
    }

    @Test func largeImageCaptureStoresOriginalAndBoundedThumbnail() throws {
        let store = try ClipboardStore.inMemory()
        let png = TestImages.png(width: 4096, height: 3072)

        let item = try store.save(ClipboardCapture(imageData: png), now: now)

        #expect(item.kind == .image)
        #expect(item.imageData == png)
        let originalData = try #require(item.imageData)
        let originalSize = try #require(Thumbnailer.pixelSize(of: originalData))
        #expect(originalSize.width == 4096)
        #expect(originalSize.height == 3072)
        let thumbnail = try #require(item.thumbnail)
        let size = try #require(Thumbnailer.pixelSize(of: thumbnail))
        #expect(size.width <= 480)
        #expect(size.height <= 480)
    }

    @Test func identicalImagesDedup() throws {
        let store = try ClipboardStore.inMemory()
        let png = TestImages.png(width: 100, height: 100)
        try store.save(ClipboardCapture(imageData: png), now: now)
        try store.save(ClipboardCapture(imageData: png), now: now.addingTimeInterval(5))
        #expect(try store.count() == 1)
    }

    @Test func identicalLargeImagesDedupAndKeepThumbnail() throws {
        let store = try ClipboardStore.inMemory()
        let png = TestImages.png(width: 4096, height: 3072)

        let first = try store.save(ClipboardCapture(imageData: png), now: now)
        let second = try store.save(
            ClipboardCapture(imageData: png), now: now.addingTimeInterval(5))

        #expect(try store.count() == 1)
        #expect(first.id == second.id)
        #expect(second.lastUsedAt > first.lastUsedAt)
        #expect(second.imageData == png)
        let thumbnail = try #require(second.thumbnail)
        let size = try #require(Thumbnailer.pixelSize(of: thumbnail))
        #expect(size.width <= 480 && size.height <= 480)
    }

    @Test func largeImageOrderingStaysRecentFirstThenPinned() throws {
        let store = try ClipboardStore.inMemory()
        let oldText = try store.save(ClipboardCapture(text: "old text"), now: now)
        let largeImage = try store.save(
            ClipboardCapture(imageData: TestImages.png(width: 4096, height: 3072)),
            now: now.addingTimeInterval(1))

        #expect(try store.items().map(\.id) == [largeImage.id, oldText.id])

        try store.setPinned(true, id: largeImage.id!)
        let newText = try store.save(
            ClipboardCapture(text: "new text"), now: now.addingTimeInterval(2))

        let items = try store.items()
        #expect(items.map(\.id) == [newText.id, oldText.id, largeImage.id])
        #expect(items.map(\.kind) == [.text, .text, .image])
        #expect(items[2].isPinned)
    }

    @Test func corruptImageDataDoesNotCrashThumbnailer() throws {
        #expect(Thumbnailer.pngThumbnail(from: Data([0xde, 0xad, 0xbe, 0xef])) == nil)
        #expect(Thumbnailer.pngThumbnail(from: Data()) == nil)
    }

    // MARK: - Concealed-content encryption (ADR-021, planned before implementation)
    //
    // These reference `ClipboardItem.encryptedData` and `ClipboardStore.revealText(for:)`,
    // neither of which exist yet — intentionally red on this branch
    // (feat/concealed-encryption) until implemented.

    @Test func concealedTextIsEncryptedNotStoredInPlaintext() throws {
        let store = try ClipboardStore.inMemory()
        let item = try store.save(
            ClipboardCapture(
                text: "hunter2-but-longer", richData: Data("rich".utf8), isConcealed: true),
            now: now)

        #expect(item.text == nil)
        #expect(item.richData == nil)
        #expect(item.encryptedData != nil)
        #expect(try store.revealText(for: item) == "hunter2-but-longer")
    }

    @Test func nonConcealedTextIsNeverEncrypted() throws {
        let store = try ClipboardStore.inMemory()
        let item = try store.save(ClipboardCapture(text: "ordinary text"), now: now)

        #expect(item.text == "ordinary text")
        #expect(item.encryptedData == nil)
        #expect(try store.revealText(for: item) == "ordinary text")
    }

    @Test func concealedDedupStaysDecryptableAfterRecopy() throws {
        let store = try ClipboardStore.inMemory()
        _ = try store.save(
            ClipboardCapture(text: "same secret", isConcealed: true), now: now)
        let second = try store.save(
            ClipboardCapture(text: "same secret", isConcealed: true),
            now: now.addingTimeInterval(60))

        #expect(try store.count() == 1)
        #expect(try store.revealText(for: second) == "same secret")
    }

    @Test func transitioningToConcealedWipesExistingPlaintext() throws {
        // A row already stored in cleartext (never concealed) must not keep its plaintext
        // sitting around once a later copy of the same content is flagged concealed —
        // the flag flipping true is exactly the moment the old plaintext must go.
        let store = try ClipboardStore.inMemory()
        _ = try store.save(ClipboardCapture(text: "secretish"), now: now)

        let second = try store.save(
            ClipboardCapture(text: "secretish", isConcealed: true),
            now: now.addingTimeInterval(60))

        #expect(try store.count() == 1)
        #expect(second.isConcealed)
        #expect(second.text == nil)
        #expect(second.encryptedData != nil)
        #expect(try store.revealText(for: second) == "secretish")
    }

    @Test func concealedContentIsExcludedFromTextSearchButStillBrowsable() throws {
        let store = try ClipboardStore.inMemory()
        try store.save(
            ClipboardCapture(text: "unfindable-secret-value", isConcealed: true), now: now)

        #expect(try store.items().count == 1)
        #expect(try store.items(matching: "unfindable-secret-value").isEmpty)
    }

    @Test func markConcealedEncryptsAnExistingPlaintextItem() throws {
        // ADR-021 follow-up: a password captured without the source app's concealed
        // marker (typed and ⌘C'd, copied from Notes, etc.) sits in plaintext until
        // manually flagged after the fact.
        let store = try ClipboardStore.inMemory()
        let item = try store.save(
            ClipboardCapture(text: "wY72^C$FMfZeE@j", richData: Data("rich".utf8)), now: now)
        try store.setPinned(true, id: item.id!)

        try store.markConcealed(id: item.id!)

        let updated = try #require(try store.items().first)
        #expect(updated.isConcealed)
        #expect(updated.text == nil)
        #expect(updated.richData == nil)
        #expect(updated.isPinned)
        #expect(try store.revealText(for: updated) == "wY72^C$FMfZeE@j")
        #expect(try store.items(matching: "wY72").isEmpty)
    }

    @Test func markConcealedIsANoOpForImageItems() throws {
        let store = try ClipboardStore.inMemory()
        let png = TestImages.png(width: 10, height: 10)
        let item = try store.save(ClipboardCapture(imageData: png), now: now)

        try store.markConcealed(id: item.id!)

        let updated = try #require(try store.items().first)
        #expect(!updated.isConcealed)
        #expect(updated.imageData == png)
    }

    @Test func markConcealedIsANoOpForAlreadyConcealedItems() throws {
        let store = try ClipboardStore.inMemory()
        let item = try store.save(
            ClipboardCapture(text: "already secret", isConcealed: true), now: now)

        // Should not throw or double-encrypt; still decrypts to the same original text.
        try store.markConcealed(id: item.id!)

        let updated = try #require(try store.items().first)
        #expect(try store.revealText(for: updated) == "already secret")
    }

    // MARK: - Concealed-content key durability (ADR-021 follow-up)
    //
    // Found live 2026-07-21: an earlier design fell back to a fresh, never-persisted key
    // when the real Keychain-backed key wasn't available yet, silently encrypting real
    // content with a key that couldn't survive that process exiting — destroying it
    // permanently. These lock in the fix: concealed-content operations must fail
    // (not silently use a placeholder) until the real key is set.

    @Test func savingConcealedCaptureThrowsWhenKeyNotYetAvailable() throws {
        let store = try ClipboardStore.inMemoryWithoutConcealedContentKey()

        #expect(throws: ClipboardStore.ConcealedContentError.keyNotYetAvailable) {
            try store.save(ClipboardCapture(text: "secret", isConcealed: true), now: now)
        }
        #expect(try store.count() == 0)
    }

    @Test func markConcealedThrowsWhenKeyNotYetAvailable() throws {
        let store = try ClipboardStore.inMemoryWithoutConcealedContentKey()
        let item = try store.save(ClipboardCapture(text: "plain for now"), now: now)

        #expect(throws: ClipboardStore.ConcealedContentError.keyNotYetAvailable) {
            try store.markConcealed(id: item.id!)
        }
        // Untouched — still plain, not left half-converted.
        let unchanged = try #require(try store.items().first)
        #expect(unchanged.text == "plain for now")
        #expect(!unchanged.isConcealed)
    }

    @Test func revealTextReturnsNilRatherThanThrowingWhenKeyNotYetAvailable() throws {
        // A concealed item saved earlier (with a key), then read back by a store that
        // doesn't have one yet -- e.g. the real app, right after launch, before its
        // background Keychain fetch resolves.
        let key = SymmetricKey(size: .bits256)
        let seededStore = try ClipboardStore.inMemory(concealedContentKey: key)
        let item = try seededStore.save(
            ClipboardCapture(text: "secret", isConcealed: true), now: now)

        let store = try ClipboardStore.inMemoryWithoutConcealedContentKey()
        #expect(try store.revealText(for: item) == nil)
    }

    @Test func settingKeyLaterEnablesConcealedOperations() throws {
        let store = try ClipboardStore.inMemoryWithoutConcealedContentKey()
        let item = try store.save(ClipboardCapture(text: "plain for now"), now: now)

        try store.setConcealedContentKey(SymmetricKey(size: .bits256))
        try store.markConcealed(id: item.id!)

        let updated = try #require(try store.items().first)
        #expect(updated.isConcealed)
        #expect(try store.revealText(for: updated) == "plain for now")
    }
}
