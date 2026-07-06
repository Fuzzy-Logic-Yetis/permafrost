import Foundation

/// Versioned archive layout:
///   <dir>/manifest.json          — metadata + inline text
///   <dir>/blobs/<hash>.png       — original image data
///   <dir>/blobs/<hash>.thumb.png — thumbnail
///   <dir>/blobs/<hash>.rich      — rich text alternate representation
/// The app layer zips/unzips the directory; core stays filesystem-only for testability.
public enum ImportExport {
    public static let manifestVersion = 1
    public static let manifestFileName = "manifest.json"

    public enum ImportError: Error, Equatable {
        case missingManifest
        case unsupportedVersion(Int)
        case missingBlob(String)
    }

    struct Manifest: Codable {
        var version: Int
        var exportedAt: Date
        var items: [ManifestItem]
    }

    struct ManifestItem: Codable {
        var contentHash: String
        var kind: ClipboardItemKind
        var text: String?
        var sourceApp: String?
        var createdAt: Date
        var lastUsedAt: Date
        var isPinned: Bool
        var pinOrder: Int?
        var isConcealed: Bool
        var imageFile: String?
        var thumbnailFile: String?
        var richDataFile: String?
    }

    // MARK: - Export

    public static func exportArchive(from store: ClipboardStore, to directory: URL) throws {
        let fm = FileManager.default
        let blobs = directory.appendingPathComponent("blobs", isDirectory: true)
        try fm.createDirectory(at: blobs, withIntermediateDirectories: true)

        var manifestItems: [ManifestItem] = []
        for item in try store.allItems() {
            var entry = ManifestItem(
                contentHash: item.contentHash,
                kind: item.kind,
                text: item.text,
                sourceApp: item.sourceApp,
                createdAt: item.createdAt,
                lastUsedAt: item.lastUsedAt,
                isPinned: item.isPinned,
                pinOrder: item.pinOrder,
                isConcealed: item.isConcealed,
                imageFile: nil,
                thumbnailFile: nil,
                richDataFile: nil
            )
            if let imageData = item.imageData {
                let name = "\(item.contentHash).png"
                try imageData.write(to: blobs.appendingPathComponent(name))
                entry.imageFile = "blobs/\(name)"
            }
            if let thumbnail = item.thumbnail {
                let name = "\(item.contentHash).thumb.png"
                try thumbnail.write(to: blobs.appendingPathComponent(name))
                entry.thumbnailFile = "blobs/\(name)"
            }
            if let richData = item.richData {
                let name = "\(item.contentHash).rich"
                try richData.write(to: blobs.appendingPathComponent(name))
                entry.richDataFile = "blobs/\(name)"
            }
            manifestItems.append(entry)
        }

        let manifest = Manifest(
            version: manifestVersion,
            exportedAt: Date(),
            items: manifestItems
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest)
            .write(to: directory.appendingPathComponent(manifestFileName))
    }

    // MARK: - Import

    /// Merges an archive into the store. Existing content (same hash) is skipped.
    /// Returns the number of imported items.
    @discardableResult
    public static func importArchive(from directory: URL, into store: ClipboardStore) throws -> Int {
        let manifestURL = directory.appendingPathComponent(manifestFileName)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw ImportError.missingManifest
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(Manifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.version == manifestVersion else {
            throw ImportError.unsupportedVersion(manifest.version)
        }

        func blob(_ relativePath: String?) throws -> Data? {
            guard let relativePath else { return nil }
            let url = directory.appendingPathComponent(relativePath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw ImportError.missingBlob(relativePath)
            }
            return try Data(contentsOf: url)
        }

        var imported = 0
        for entry in manifest.items {
            let item = ClipboardItem(
                id: nil,
                contentHash: entry.contentHash,
                kind: entry.kind,
                text: entry.text,
                richData: try blob(entry.richDataFile),
                imageData: try blob(entry.imageFile),
                thumbnail: try blob(entry.thumbnailFile),
                sourceApp: entry.sourceApp,
                createdAt: entry.createdAt,
                lastUsedAt: entry.lastUsedAt,
                isPinned: entry.isPinned,
                pinOrder: entry.pinOrder,
                isConcealed: entry.isConcealed
            )
            if try store.insertPreservingMetadata(item) {
                imported += 1
            }
        }
        return imported
    }
}
