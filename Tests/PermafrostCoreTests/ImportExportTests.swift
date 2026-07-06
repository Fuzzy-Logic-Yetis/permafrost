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
        let source = try ClipboardStore.inMemory()
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

        let destination = try ClipboardStore.inMemory()
        let imported = try ImportExport.importArchive(from: dir, into: destination)
        #expect(imported == 3)

        let items = try destination.allItems()
        #expect(items.count == 3)

        let text = items.first { $0.isPinned }
        #expect(text?.text == "pinned text")
        #expect(text?.sourceApp == "TextEdit")
        #expect(text?.createdAt.timeIntervalSince1970 == created.timeIntervalSince1970)

        #expect(items.contains { $0.isConcealed && $0.text == "secret" })

        let image = items.first { $0.kind == .image }
        #expect(image?.imageData == TestImages.png(width: 64, height: 32))
        #expect(image?.thumbnail != nil)
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
}
