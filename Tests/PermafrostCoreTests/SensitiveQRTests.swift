import CryptoKit
import Foundation
import GRDB
import Testing
@testable import PermafrostCore

@Suite struct SensitiveQRTests {
    private let secret = "WIFI:T:WPA;S:synthetic;P:qr-private-value;;"

    private func image(in store: ClipboardStore, byte: UInt8 = 1) throws -> ClipboardItem {
        try store.save(ClipboardCapture(imageData: Data([byte, 2, 3])))
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func encryptedQRIsSeparateFromSearchableAndCopyableText() throws {
        let store = try ClipboardStore.inMemory()
        let item = try image(in: store)
        try store.setImageRecognition(ocrText: "ordinary menu", sensitiveQRText: secret,
                                      detectedSensitiveQR: true, id: #require(item.id))
        let saved = try #require(store.allItems().first)
        #expect(saved.qrSensitiveStatus == .encrypted)
        #expect(saved.ocrText == "ordinary menu")
        #expect(saved.text == nil)
        #expect(saved.encryptedQRData != nil)
        #expect(try store.revealSensitiveQRText(for: saved) == secret)
        #expect(try store.items(matching: "qr-private-value").isEmpty)
        #expect(try store.items(matching: "menu").count == 1)
        #expect(saved.imageData == item.imageData)
    }

    @Test func omittedAndUnavailableStatusesNeverBecomeOCRContent() throws {
        for keyAvailable in [false, true] {
            let store = try ClipboardStore.inMemoryWithoutConcealedContentKey()
            let item = try image(in: store)
            if keyAvailable { store.setConcealedContentKey(SymmetricKey(size: .bits256)) }
            try store.setImageRecognition(ocrText: nil, sensitiveQRText: keyAvailable ? nil : secret,
                                          detectedSensitiveQR: true, id: #require(item.id))
            let saved = try #require(store.allItems().first)
            #expect(saved.qrSensitiveStatus == (keyAvailable ? .omitted : .keyUnavailable))
            #expect(saved.ocrText == nil)
            #expect(saved.encryptedQRData == nil)
            #expect(!saved.hasOCRText)
        }
    }

    @Test func recopyAfterKeyBecomesAvailableEncryptsAndLaterOptOutPreservesHistory() throws {
        let store = try ClipboardStore.inMemoryWithoutConcealedContentKey()
        let item = try image(in: store)
        let id = try #require(item.id)
        try store.setImageRecognition(ocrText: nil, sensitiveQRText: secret, detectedSensitiveQR: true, id: id)
        store.setConcealedContentKey(SymmetricKey(size: .bits256))
        try store.setImageRecognition(ocrText: nil, sensitiveQRText: secret, detectedSensitiveQR: true, id: id)
        try store.setImageRecognition(ocrText: nil, sensitiveQRText: nil, detectedSensitiveQR: true, id: id)
        let saved = try #require(store.allItems().first)
        #expect(saved.qrSensitiveStatus == .encrypted)
        #expect(try store.revealSensitiveQRText(for: saved) == secret)
        #expect(try store.count() == 1)
    }

    @Test func sensitiveQRCiphertextCannotBeMovedToAnotherImage() throws {
        let store = try ClipboardStore.inMemory()
        let original = try image(in: store)
        try store.setImageRecognition(ocrText: nil, sensitiveQRText: secret,
                                      detectedSensitiveQR: true, id: #require(original.id))
        let saved = try #require(store.allItems().first)
        var substituted = try image(in: store, byte: 9)
        substituted.encryptedQRData = saved.encryptedQRData
        substituted.qrSensitiveStatus = .encrypted
        #expect(throws: ClipboardStore.ConcealedContentError.invalidConcealedContent) {
            try store.revealSensitiveQRText(for: substituted)
        }
    }

    @Test func sameMacArchivePreservesQRAndForeignKeyFailsAtomically() throws {
        let key = SymmetricKey(size: .bits256)
        let source = try ClipboardStore.inMemory(concealedContentKey: key)
        try source.save(ClipboardCapture(text: "ordinary-first"))
        let item = try image(in: source)
        try source.setImageRecognition(ocrText: "public", sensitiveQRText: secret,
                                       detectedSensitiveQR: true, id: #require(item.id))
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try ImportExport.exportArchive(from: source, to: dir)
        let manifest = try String(contentsOf: dir.appendingPathComponent("manifest.json"), encoding: .utf8)
        #expect(!manifest.contains(secret))
        #expect(manifest.contains("qr-encrypted"))
        let same = try ClipboardStore.inMemory(concealedContentKey: key)
        #expect(try ImportExport.importArchive(from: dir, into: same) == 2)
        let restored = try #require(same.allItems().first(where: { $0.kind == .image }))
        #expect(try same.revealSensitiveQRText(for: restored) == secret)
        let foreign = try ClipboardStore.inMemory()
        #expect(throws: ImportExport.ImportError.self) {
            try ImportExport.importArchive(from: dir, into: foreign)
        }
        #expect(try foreign.count() == 0)
    }

    @Test func portableBackupReencryptsQRForDestinationAndRequiresSourceKey() throws {
        let source = try ClipboardStore.inMemory()
        let item = try image(in: source)
        try source.setImageRecognition(ocrText: "public", sensitiveQRText: secret,
                                       detectedSensitiveQR: true, id: #require(item.id))
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let passphrase = "synthetic secure passphrase"
        try PortableArchive.exportArchive(from: source, to: dir, passphrase: passphrase)
        let target = try ClipboardStore.inMemory()
        #expect(try PortableArchive.importArchive(from: dir, into: target, passphrase: passphrase) == 1)
        let restored = try #require(target.allItems().first)
        #expect(restored.qrSensitiveStatus == .encrypted)
        #expect(try target.revealSensitiveQRText(for: restored) == secret)
        #expect(try restored.encryptedQRData != source.allItems().first?.encryptedQRData)
        let keyless = try ClipboardStore.inMemoryWithoutConcealedContentKey()
        try keyless.insertPreservingMetadata(restored)
        #expect(throws: PortableArchive.Error.sourceKeyUnavailable) {
            try PortableArchive.exportArchive(from: keyless, to: dir, passphrase: passphrase)
        }
        #expect(throws: ClipboardStore.ConcealedContentError.keyNotYetAvailable) {
            try PortableArchive.importArchive(from: dir, into: keyless, passphrase: passphrase)
        }
        #expect(try keyless.count() == 1)
    }

    @Test func archivesPreserveOmissionStatusAndLegacyVersionsStillImport() throws {
        for portable in [false, true] {
            let store = try ClipboardStore.inMemory()
            let item = try image(in: store)
            try store.setImageRecognition(ocrText: nil, sensitiveQRText: nil,
                                          detectedSensitiveQR: true, id: #require(item.id))
            let dir = try directory()
            defer { try? FileManager.default.removeItem(at: dir) }
            let password = "synthetic passphrase"
            if portable { try PortableArchive.exportArchive(from: store, to: dir, passphrase: password) }
            else { try ImportExport.exportArchive(from: store, to: dir) }
            let target = try ClipboardStore.inMemory()
            if portable { try PortableArchive.importArchive(from: dir, into: target, passphrase: password) }
            else { try ImportExport.importArchive(from: dir, into: target) }
            #expect(try target.allItems().first?.qrSensitiveStatus == .omitted)
            // Legacy version headers remain accepted; missing optional QR fields decode to nil.
            let manifestURL = dir.appendingPathComponent("manifest.json")
            var json = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as! [String: Any]
            json["version"] = portable ? 2 : 1
            if portable {
                let salt = Data(base64Encoded: json["salt"] as! String)!
                let iterations = UInt32(json["iterations"] as! Int)
                let payloadURL = dir.appendingPathComponent("payload.encrypted")
                let plain = try PortableArchiveCipher.open(Data(contentsOf: payloadURL), passphrase: password,
                                                           salt: salt, iterations: iterations)
                var payload = try JSONSerialization.jsonObject(with: plain) as! [String: Any]
                var entries = payload["items"] as! [[String: Any]]
                entries[0].removeValue(forKey: "qrSensitiveStatus")
                entries[0].removeValue(forKey: "sensitiveQRText")
                payload["items"] = entries
                try PortableArchiveCipher.seal(JSONSerialization.data(withJSONObject: payload),
                                                passphrase: password, salt: salt, iterations: iterations).write(to: payloadURL)
            } else {
                var entries = json["items"] as! [[String: Any]]
                entries[0].removeValue(forKey: "qrSensitiveStatus")
                json["items"] = entries
            }
            try JSONSerialization.data(withJSONObject: json).write(to: manifestURL)
            let legacy = try ClipboardStore.inMemory()
            if portable { #expect(try PortableArchive.importArchive(from: dir, into: legacy, passphrase: password) == 1) }
            else { #expect(try ImportExport.importArchive(from: dir, into: legacy) == 1) }
        }
    }

    @Test func malformedQRMetadataFailsWithoutPartialImport() throws {
        let source = try ClipboardStore.inMemory()
        try source.save(ClipboardCapture(text: "ordinary first"))
        _ = try image(in: source)
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try ImportExport.exportArchive(from: source, to: dir)
        let manifestURL = dir.appendingPathComponent("manifest.json")
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as! [String: Any]
        var items = json["items"] as! [[String: Any]]
        items[1]["qrSensitiveStatus"] = "encrypted"
        json["items"] = items
        try JSONSerialization.data(withJSONObject: json).write(to: manifestURL)
        let target = try ClipboardStore.inMemory()
        #expect(throws: ClipboardStore.ConcealedContentError.invalidConcealedContent) {
            try ImportExport.importArchive(from: dir, into: target)
        }
        #expect(try target.count() == 0)
    }

    @Test func portableMalformedQRStatusFailsAtomically() throws {
        let source = try ClipboardStore.inMemory()
        try source.save(ClipboardCapture(text: "ordinary first"))
        let item = try image(in: source)
        try source.setImageRecognition(ocrText: nil, sensitiveQRText: secret,
                                      detectedSensitiveQR: true, id: #require(item.id))
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let password = "synthetic portable password"
        try PortableArchive.exportArchive(from: source, to: dir, passphrase: password)
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("manifest.json"))) as! [String: Any]
        let salt = Data(base64Encoded: manifest["salt"] as! String)!
        let iterations = UInt32(manifest["iterations"] as! Int)
        let url = dir.appendingPathComponent("payload.encrypted")
        let plain = try PortableArchiveCipher.open(Data(contentsOf: url), passphrase: password, salt: salt, iterations: iterations)
        var payload = try JSONSerialization.jsonObject(with: plain) as! [String: Any]
        var entries = payload["items"] as! [[String: Any]]
        entries[1].removeValue(forKey: "sensitiveQRText")
        payload["items"] = entries
        try PortableArchiveCipher.seal(JSONSerialization.data(withJSONObject: payload), passphrase: password,
                                      salt: salt, iterations: iterations).write(to: url)
        let target = try ClipboardStore.inMemory()
        #expect(throws: PortableArchive.Error.malformedArchive) {
            try PortableArchive.importArchive(from: dir, into: target, passphrase: password)
        }
        #expect(try target.count() == 0)
    }

    @Test func migrationPreservesExistingRowsAndPins() throws {
        let db = try DatabaseQueue()
        try ClipboardStore.migrator.migrate(db, upTo: "v3_concealed_encryption")
        try db.write { db in
            try db.execute(sql: "INSERT INTO clipboard_item (content_hash,kind,text,created_at,last_used_at,is_pinned) VALUES ('legacy','text','kept',CURRENT_TIMESTAMP,CURRENT_TIMESTAMP,1)")
        }
        try ClipboardStore.migrator.migrate(db)
        let store = ClipboardStore(dbQueue: db)
        let item = try #require(store.allItems().first)
        #expect(item.text == "kept" && item.isPinned)
        #expect(item.qrSensitiveStatus == nil && item.encryptedQRData == nil)
    }
}
