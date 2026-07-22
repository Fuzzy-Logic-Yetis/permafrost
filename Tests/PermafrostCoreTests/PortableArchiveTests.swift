import Foundation
import Testing

@testable import PermafrostCore

@Suite struct PortableArchiveTests {
    private let passphrase = "correct horse battery staple"

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("permafrost-portable-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test func portableArchiveMovesConcealedTextToAnotherKeychainKey() throws {
        let source = try ClipboardStore.inMemory()
        try source.save(ClipboardCapture(text: "ordinary history"))
        try source.save(ClipboardCapture(text: "portable-secret", isConcealed: true))
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try PortableArchive.exportArchive(from: source, to: directory, passphrase: passphrase)
        #expect(try PortableArchive.requiresPassphrase(at: directory))
        let outerManifest = try String(
            contentsOf: directory.appendingPathComponent(ImportExport.manifestFileName), encoding: .utf8)
        #expect(!outerManifest.contains("portable-secret"))

        // A fresh store has a different per-machine cipher. Portable import must decrypt with
        // the passphrase then re-seal the concealed row using this destination cipher.
        let destination = try ClipboardStore.inMemory()
        #expect(try PortableArchive.importArchive(
            from: directory, into: destination, passphrase: passphrase) == 2)
        let secret = try #require(destination.allItems().first(where: { $0.isConcealed }))
        #expect(secret.text == nil)
        #expect(secret.encryptedData != nil)
        #expect(try destination.revealText(for: secret) == "portable-secret")
    }

    @Test func wrongPassphraseDoesNotImportAnything() throws {
        let source = try ClipboardStore.inMemory()
        try source.save(ClipboardCapture(text: "portable-secret", isConcealed: true))
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try PortableArchive.exportArchive(from: source, to: directory, passphrase: passphrase)

        let destination = try ClipboardStore.inMemory()
        #expect(throws: PortableArchiveCipher.Error.authenticationFailed) {
            try PortableArchive.importArchive(from: directory, into: destination, passphrase: "wrong passphrase")
        }
        #expect(try destination.count() == 0)
    }
}
