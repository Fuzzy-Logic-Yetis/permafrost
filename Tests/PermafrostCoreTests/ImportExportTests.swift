import CryptoKit
import Foundation
import Testing

@testable import PermafrostCore

@Suite struct ImportExportTests {
    let now = Date(timeIntervalSince1970: 2_000_000_000)

    func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("permafrost-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func roundTripPreservesContentPinsAndTimestamps() throws {
        // Same key on both ends simulates the real scenario: import/export happens on the
        // same machine against the same Keychain-backed key (ADR-021).
        let key = SymmetricKey(size: .bits256)
        let source = try ClipboardStore.inMemory(concealedContentKey: key)
        let created = now.addingTimeInterval(-5 * 24 * 3600)
        let pinned = try source.save(
            ClipboardCapture(text: "pinned text", sourceApp: "TextEdit"), now: created)
        try source.setPinned(true, id: pinned.id!)
        try source.save(
            ClipboardCapture(text: "secret", isConcealed: true), now: created)
        try source.save(
            ClipboardCapture(imageData: TestImages.png(width: 64, height: 32)), now: created)

        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try ImportExport.exportArchive(from: source, to: dir)

        // ADR-021: the export manifest must never contain a concealed item's plaintext —
        // this was a real, pre-existing leak (every item's `text` was written verbatim)
        // that adding encryption elsewhere would be pointless to leave unfixed.
        let manifestText = try String(
            contentsOf: dir.appendingPathComponent(ImportExport.manifestFileName),
            encoding: .utf8)
        #expect(!manifestText.contains("secret"))

        let destination = try ClipboardStore.inMemory(concealedContentKey: key)
        let imported = try ImportExport.importArchive(from: dir, into: destination)
        #expect(imported == 3)

        let items = try destination.allItems()
        #expect(items.count == 3)

        let text = items.first { $0.isPinned }
        #expect(text?.text == "pinned text")
        #expect(text?.sourceApp == "TextEdit")
        #expect(text?.createdAt.timeIntervalSince1970 == created.timeIntervalSince1970)

        let concealed = try #require(items.first { $0.isConcealed })
        #expect(concealed.text == nil)
        #expect(try destination.revealText(for: concealed) == "secret")

        let image = items.first { $0.kind == .image }
        #expect(image?.imageData == TestImages.png(width: 64, height: 32))
        #expect(image?.thumbnail != nil)
    }

    @Test func roundTripPreservesImageOCRText() throws {
        let source = try ClipboardStore.inMemory()
        let image = TestImages.png(width: 64, height: 32)
        try source.save(
            ClipboardCapture(imageData: image, ocrText: "Boarding pass gate B12"), now: now)

        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try ImportExport.exportArchive(from: source, to: dir)

        let destination = try ClipboardStore.inMemory()
        let imported = try ImportExport.importArchive(from: dir, into: destination)

        #expect(imported == 1)
        let item = try #require(destination.allItems().first)
        #expect(item.kind == .image)
        #expect(item.ocrText == "Boarding pass gate B12")
        #expect(try destination.items(matching: "gate").map(\.id) == [item.id])
    }

    @Test func importSkipsExistingContent() throws {
        let source = try ClipboardStore.inMemory()
        try source.save(ClipboardCapture(text: "shared"), now: now)
        try source.save(ClipboardCapture(text: "unique to source"), now: now)

        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try ImportExport.exportArchive(from: source, to: dir)

        let destination = try ClipboardStore.inMemory()
        try destination.save(ClipboardCapture(text: "shared"), now: now)

        let imported = try ImportExport.importArchive(from: dir, into: destination)
        #expect(imported == 1)
        #expect(try destination.count() == 2)
    }

    @Test func legacyConcealedPlaintextImportIsSealedBeforeStorage() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let secret = "legacy archive secret"
        let hash = ClipboardCapture(text: secret).contentHash
        let manifest = """
            {"version": 1, "exportedAt": "2026-07-05T00:00:00Z", "items": [
                {"contentHash": "\(hash)", "kind": "text", "text": "\(secret)",
                 "ocrText": null, "sourceApp": null, "createdAt": "2026-07-05T00:00:00Z",
                 "lastUsedAt": "2026-07-05T00:00:00Z", "isPinned": false, "pinOrder": null,
                 "isConcealed": true, "imageFile": null, "thumbnailFile": null,
                 "richDataFile": null, "encryptedDataFile": null}
            ]}
            """
        try manifest.write(to: dir.appendingPathComponent(ImportExport.manifestFileName), atomically: true, encoding: .utf8)

        let store = try ClipboardStore.inMemory()
        #expect(try ImportExport.importArchive(from: dir, into: store) == 1)
        let imported = try #require(store.allItems().first)
        #expect(imported.text == nil)
        #expect(imported.richData == nil)
        #expect(imported.encryptedData != nil)
        #expect(try store.revealText(for: imported) == secret)
    }

    @Test func encryptedArchiveWithDifferentKeyFailsLoudly() throws {
        let source = try ClipboardStore.inMemory()
        try source.save(ClipboardCapture(text: "secret", isConcealed: true), now: now)
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try ImportExport.exportArchive(from: source, to: dir)

        let destination = try ClipboardStore.inMemory()
        #expect(throws: ImportExport.ImportError.concealedContentCannotBeImported(
            ClipboardCapture(text: "secret").contentHash
        )) {
            try ImportExport.importArchive(from: dir, into: destination)
        }
    }

    @Test func unknownManifestVersionFailsLoudly() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manifest = """
            {"version": 999, "exportedAt": "2026-07-05T00:00:00Z", "items": []}
            """
        try manifest.write(
            to: dir.appendingPathComponent(ImportExport.manifestFileName),
            atomically: true, encoding: .utf8)

        let store = try ClipboardStore.inMemory()
        #expect(throws: ImportExport.ImportError.unsupportedVersion(999)) {
            try ImportExport.importArchive(from: dir, into: store)
        }
    }

    @Test func missingManifestFailsLoudly() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try ClipboardStore.inMemory()
        #expect(throws: ImportExport.ImportError.missingManifest) {
            try ImportExport.importArchive(from: dir, into: store)
        }
    }

    /// Review M-4: manifest blob paths are untrusted input and must not escape
    /// the archive directory via traversal or an absolute path.
    private func writeHostileManifest(imageFile: String, in dir: URL) throws {
        let manifest = """
            {"version": 1, "exportedAt": "2026-07-05T00:00:00Z", "items": [
                {"contentHash": "abc", "kind": "text", "text": null, "sourceApp": null,
                 "createdAt": "2026-07-05T00:00:00Z", "lastUsedAt": "2026-07-05T00:00:00Z",
                 "isPinned": false, "pinOrder": null, "isConcealed": false,
                 "imageFile": "\(imageFile)", "thumbnailFile": null, "richDataFile": null}
            ]}
            """
        try manifest.write(
            to: dir.appendingPathComponent(ImportExport.manifestFileName),
            atomically: true, encoding: .utf8)
    }

    @Test func hostileManifestPathWithTraversalIsRejected() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeHostileManifest(imageFile: "../outside.png", in: dir)

        let store = try ClipboardStore.inMemory()
        #expect(throws: ImportExport.ImportError.unsafeBlobPath("../outside.png")) {
            try ImportExport.importArchive(from: dir, into: store)
        }
    }

    @Test func hostileManifestPathWithAbsolutePathIsRejected() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeHostileManifest(imageFile: "/etc/passwd", in: dir)

        let store = try ClipboardStore.inMemory()
        #expect(throws: ImportExport.ImportError.unsafeBlobPath("/etc/passwd")) {
            try ImportExport.importArchive(from: dir, into: store)
        }
    }

    /// Review M-2: manifest fields must actually match the declared kind — a
    /// text row can't carry an image blob (and vice versa).
    @Test func textKindWithImageBlobIsRejected() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let blobs = dir.appendingPathComponent("blobs", isDirectory: true)
        try FileManager.default.createDirectory(at: blobs, withIntermediateDirectories: true)
        try TestImages.png(width: 4, height: 4).write(to: blobs.appendingPathComponent("x.png"))
        try writeHostileManifest(imageFile: "blobs/x.png", in: dir)

        let store = try ClipboardStore.inMemory()
        #expect(throws: ImportExport.ImportError.kindFieldMismatch("abc")) {
            try ImportExport.importArchive(from: dir, into: store)
        }
    }

    @Test func imageKindWithoutImageDataIsRejected() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manifest = """
            {"version": 1, "exportedAt": "2026-07-05T00:00:00Z", "items": [
                {"contentHash": "abc", "kind": "image", "text": null, "ocrText": null, "sourceApp": null,
                 "createdAt": "2026-07-05T00:00:00Z", "lastUsedAt": "2026-07-05T00:00:00Z",
                 "isPinned": false, "pinOrder": null, "isConcealed": false,
                 "imageFile": null, "thumbnailFile": null, "richDataFile": null}
            ]}
            """
        try manifest.write(
            to: dir.appendingPathComponent(ImportExport.manifestFileName),
            atomically: true, encoding: .utf8)

        let store = try ClipboardStore.inMemory()
        #expect(throws: ImportExport.ImportError.kindFieldMismatch("abc")) {
            try ImportExport.importArchive(from: dir, into: store)
        }
    }

    @Test func textKindWithOCRTextIsRejected() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manifest = """
            {"version": 1, "exportedAt": "2026-07-05T00:00:00Z", "items": [
                {"contentHash": "abc", "kind": "text", "text": "hello", "ocrText": "not for text", "sourceApp": null,
                 "createdAt": "2026-07-05T00:00:00Z", "lastUsedAt": "2026-07-05T00:00:00Z",
                 "isPinned": false, "pinOrder": null, "isConcealed": false,
                 "imageFile": null, "thumbnailFile": null, "richDataFile": null}
            ]}
            """
        try manifest.write(
            to: dir.appendingPathComponent(ImportExport.manifestFileName),
            atomically: true, encoding: .utf8)

        let store = try ClipboardStore.inMemory()
        #expect(throws: ImportExport.ImportError.kindFieldMismatch("abc")) {
            try ImportExport.importArchive(from: dir, into: store)
        }
    }

    /// Review M-2: a manifest can't lie about its content hash — it must match
    /// what actually hashing the entry's text/image content produces.
    @Test func mismatchedContentHashIsRejected() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manifest = """
            {"version": 1, "exportedAt": "2026-07-05T00:00:00Z", "items": [
                {"contentHash": "not-the-real-hash", "kind": "text", "text": "hello",
                 "sourceApp": null, "createdAt": "2026-07-05T00:00:00Z",
                 "lastUsedAt": "2026-07-05T00:00:00Z", "isPinned": false, "pinOrder": null,
                 "isConcealed": false, "imageFile": null, "thumbnailFile": null,
                 "richDataFile": null}
            ]}
            """
        try manifest.write(
            to: dir.appendingPathComponent(ImportExport.manifestFileName),
            atomically: true, encoding: .utf8)

        let store = try ClipboardStore.inMemory()
        #expect(throws: ImportExport.ImportError.contentHashMismatch("not-the-real-hash")) {
            try ImportExport.importArchive(from: dir, into: store)
        }
    }

    @Test func symlinkedBlobIsRejected() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let blobs = dir.appendingPathComponent("blobs", isDirectory: true)
        try FileManager.default.createDirectory(at: blobs, withIntermediateDirectories: true)

        let outsideSecret = dir.deletingLastPathComponent()
            .appendingPathComponent("permafrost-secret-\(UUID().uuidString).png")
        try TestImages.png(width: 4, height: 4).write(to: outsideSecret)
        defer { try? FileManager.default.removeItem(at: outsideSecret) }
        let link = blobs.appendingPathComponent("x.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outsideSecret)

        try writeHostileManifest(imageFile: "blobs/x.png", in: dir)

        let store = try ClipboardStore.inMemory()
        #expect(throws: ImportExport.ImportError.unsafeBlobPath("blobs/x.png")) {
            try ImportExport.importArchive(from: dir, into: store)
        }
    }
}
