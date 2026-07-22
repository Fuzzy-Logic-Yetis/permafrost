import Foundation

/// A portable archive encrypts every clipboard field with an export passphrase. Unlike the
/// normal archive, it does not depend on the source Mac's Keychain key after export.
public enum PortableArchive {
    private static let version = 2
    private static let format = "permafrost-portable-passphrase"
    private static let payloadFile = "payload.encrypted"

    public enum Error: LocalizedError, Equatable {
        case missingManifest
        case notPortableArchive
        case malformedArchive
        case passphraseRequired
        case sourceKeyUnavailable
        case contentHashMismatch(String)
        case kindFieldMismatch(String)

        public var errorDescription: String? {
            switch self {
            case .missingManifest: return "The archive has no manifest."
            case .notPortableArchive: return "This is not a portable encrypted Permafrost archive."
            case .malformedArchive: return "The portable archive is malformed."
            case .passphraseRequired: return "This archive requires its export passphrase."
            case .sourceKeyUnavailable: return "Concealed content is unavailable until its Keychain key can be opened."
            case .contentHashMismatch: return "The archive failed an integrity check."
            case .kindFieldMismatch: return "The archive contains an invalid clipboard item."
            }
        }
    }

    private struct Header: Codable {
        var version: Int
    }

    private struct Manifest: Codable {
        var version: Int
        var format: String
        var exportedAt: Date
        var payloadFile: String
        var salt: Data
        var iterations: UInt32
    }

    private struct Payload: Codable {
        var items: [Item]
    }

    private struct Item: Codable {
        var contentHash: String
        var kind: ClipboardItemKind
        var text: String?
        var ocrText: String?
        var richData: Data?
        var imageData: Data?
        var thumbnail: Data?
        var sourceApp: String?
        var createdAt: Date
        var lastUsedAt: Date
        var isPinned: Bool
        var pinOrder: Int?
        var isConcealed: Bool
    }

    public static func requiresPassphrase(at directory: URL) throws -> Bool {
        let manifestURL = directory.appendingPathComponent(ImportExport.manifestFileName)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw Error.missingManifest
        }
        let header = try JSONDecoder().decode(Header.self, from: Data(contentsOf: manifestURL))
        return header.version == version
    }

    public static func exportArchive(from store: ClipboardStore, to directory: URL, passphrase: String) throws {
        let salt = PortableArchiveCipher.makeSalt()
        var items: [Item] = []
        for item in try store.allItems() {
            let text: String?
            if item.kind == .text {
                // Exporting requires the source Keychain key; never make a portable archive
                // that claims success while silently omitting a concealed value.
                guard let revealed = try store.revealText(for: item) else {
                    throw Error.sourceKeyUnavailable
                }
                text = revealed
            } else {
                text = nil
            }
            items.append(Item(
                contentHash: item.contentHash, kind: item.kind, text: text, ocrText: item.ocrText,
                richData: item.richData, imageData: item.imageData, thumbnail: item.thumbnail,
                sourceApp: item.sourceApp, createdAt: item.createdAt, lastUsedAt: item.lastUsedAt,
                isPinned: item.isPinned, pinOrder: item.pinOrder, isConcealed: item.isConcealed))
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encrypted = try PortableArchiveCipher.seal(
            encoder.encode(Payload(items: items)), passphrase: passphrase, salt: salt,
            iterations: PortableArchiveCipher.iterations)
        try encrypted.write(to: directory.appendingPathComponent(payloadFile), options: .atomic)
        let manifest = Manifest(
            version: version, format: format, exportedAt: Date(), payloadFile: payloadFile,
            salt: salt, iterations: PortableArchiveCipher.iterations)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(
            to: directory.appendingPathComponent(ImportExport.manifestFileName), options: .atomic)
    }

    @discardableResult
    public static func importArchive(from directory: URL, into store: ClipboardStore, passphrase: String?) throws -> Int {
        guard let passphrase else { throw Error.passphraseRequired }
        let manifestURL = directory.appendingPathComponent(ImportExport.manifestFileName)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { throw Error.missingManifest }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(Manifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.version == version, manifest.format == format,
            manifest.payloadFile == payloadFile, manifest.salt.count == PortableArchiveCipher.saltByteCount,
            manifest.iterations >= PortableArchiveCipher.iterations
        else { throw Error.notPortableArchive }
        let encryptedURL = directory.appendingPathComponent(manifest.payloadFile)
        guard FileManager.default.fileExists(atPath: encryptedURL.path) else { throw Error.malformedArchive }
        let plaintext = try PortableArchiveCipher.open(
            Data(contentsOf: encryptedURL), passphrase: passphrase, salt: manifest.salt,
            iterations: manifest.iterations)
        let payload: Payload
        do {
            payload = try decoder.decode(Payload.self, from: plaintext)
        } catch {
            throw Error.malformedArchive
        }
        let items = try payload.items.map { try validatedClipboardItem(from: $0) }
        // The store seals concealed plaintext with this Mac's Keychain-backed cipher inside
        // one transaction. Nothing is inserted if decryption/validation failed above.
        return try store.insertPreservingMetadata(items)
    }

    private static func validatedClipboardItem(from entry: Item) throws -> ClipboardItem {
        do {
            try ClipboardItemValidation.validate(
                kind: entry.kind, text: entry.text, ocrText: entry.ocrText,
                imageData: entry.imageData, richData: entry.richData, sourceApp: entry.sourceApp,
                isConcealed: entry.isConcealed, expectedContentHash: entry.contentHash)
        } catch ClipboardItemValidation.Error.kindFieldMismatch {
            throw Error.kindFieldMismatch(entry.contentHash)
        } catch ClipboardItemValidation.Error.contentHashMismatch {
            throw Error.contentHashMismatch(entry.contentHash)
        }
        return ClipboardItem(
            contentHash: entry.contentHash, kind: entry.kind, text: entry.text,
            ocrText: entry.ocrText, richData: entry.richData, imageData: entry.imageData,
            thumbnail: entry.thumbnail, sourceApp: entry.sourceApp, createdAt: entry.createdAt,
            lastUsedAt: entry.lastUsedAt, isPinned: entry.isPinned, pinOrder: entry.pinOrder,
            isConcealed: entry.isConcealed)
    }
}
