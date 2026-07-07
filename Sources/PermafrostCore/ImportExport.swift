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
        case unsafeBlobPath(String)
        /// Review M-2: a manifest entry's declared kind doesn't match its populated
        /// fields (e.g. a text row with an image blob, or an image row with no image data).
        case kindFieldMismatch(String)
        /// Review M-2: recomputing the hash from the entry's actual content didn't
        /// match the manifest's claimed `contentHash` — the archive is malformed or hostile.
        case contentHashMismatch(String)
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

        // Manifest paths are untrusted input (M-4): reject anything that could
        // resolve outside the archive directory before touching the filesystem.
        let root = directory.standardizedFileURL.path
        func blob(_ relativePath: String?) throws -> Data? {
            guard let relativePath else { return nil }
            guard !relativePath.hasPrefix("/"), !relativePath.split(separator: "/").contains("..")
            else {
                throw ImportError.unsafeBlobPath(relativePath)
            }
            let url = directory.appendingPathComponent(relativePath).standardizedFileURL
            guard url.path == root || url.path.hasPrefix(root + "/") else {
                throw ImportError.unsafeBlobPath(relativePath)
            }
            // A symlink inside the archive could point outside it despite the
            // string-only checks above (review M-2) — refuse to follow one.
            let resourceValues = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
            if resourceValues?.isSymbolicLink == true {
                throw ImportError.unsafeBlobPath(relativePath)
            }
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw ImportError.missingBlob(relativePath)
            }
            return try Data(contentsOf: url)
        }

        var imported = 0
        for entry in manifest.items {
            let richData = try blob(entry.richDataFile)
            let imageData = try blob(entry.imageFile)
            let thumbnail = try blob(entry.thumbnailFile)

            // Review M-2: don't trust the manifest's kind/hash claims — recompute
            // the hash from the actual content using the same logic that produced
            // it at capture time, and reject fields that don't match the kind.
            let capture: ClipboardCapture
            switch entry.kind {
            case .text:
                guard let text = entry.text, imageData == nil else {
                    throw ImportError.kindFieldMismatch(entry.contentHash)
                }
                capture = ClipboardCapture(
                    text: text, richData: richData, sourceApp: entry.sourceApp,
                    isConcealed: entry.isConcealed)
            case .image:
                guard let imageData, entry.text == nil else {
                    throw ImportError.kindFieldMismatch(entry.contentHash)
                }
                capture = ClipboardCapture(
                    imageData: imageData, sourceApp: entry.sourceApp, isConcealed: entry.isConcealed)
            }
            guard capture.contentHash == entry.contentHash else {
                throw ImportError.contentHashMismatch(entry.contentHash)
            }

            let item = ClipboardItem(
                id: nil,
                contentHash: entry.contentHash,
                kind: entry.kind,
                text: entry.text,
                richData: richData,
                imageData: imageData,
                thumbnail: thumbnail,
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
