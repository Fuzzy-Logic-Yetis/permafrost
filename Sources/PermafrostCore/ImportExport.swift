import Foundation

/// Versioned archive layout:
///   <dir>/manifest.json          — metadata + inline text
///   <dir>/blobs/<hash>.png       — original image data
///   <dir>/blobs/<hash>.thumb.png — thumbnail
///   <dir>/blobs/<hash>.rich      — rich text alternate representation
/// The app layer zips/unzips the directory; core stays filesystem-only for testability.
public enum ImportExport {
    public static let manifestVersion = 3
    public static let manifestFileName = "manifest.json"

    public enum ImportError: LocalizedError, Equatable {
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
        /// Ciphertext (concealed text or sensitive QR) is unreadable for a reason other
        /// than the Keychain key being unavailable — genuine corruption, not a timing
        /// issue. Distinct from sourceKeyUnavailable (ADR-025): failing loudly here is
        /// preferable to reporting a misleading successful import with silently skipped
        /// secrets, but it should not be confused with a retry-and-it'll-work condition.
        case concealedContentCannotBeImported(String)
        /// The Keychain key needed to verify a sensitive QR payload wasn't ready yet —
        /// transient (ADR-025), e.g. an import triggered in the brief window right after
        /// launch before the async key fetch resolves. Distinct from
        /// concealedContentCannotBeImported so the user gets "try again in a moment"
        /// instead of a message implying the archive itself is broken.
        case sourceKeyUnavailable(String)

        public var errorDescription: String? {
            switch self {
            case .missingManifest: return "The archive has no manifest."
            case .unsupportedVersion(let version):
                return "This archive (format version \(version)) isn't supported by this version of Permafrost."
            case .missingBlob(let name): return "The archive is missing an expected file: \(name)."
            case .unsafeBlobPath(let name): return "The archive references an unsafe file path: \(name)."
            case .kindFieldMismatch: return "The archive contains an invalid clipboard item."
            case .contentHashMismatch: return "The archive failed an integrity check."
            case .concealedContentCannotBeImported:
                return "Concealed content in this archive could not be verified and was not imported."
            case .sourceKeyUnavailable:
                return "Permafrost's Keychain key isn't ready yet. Wait a moment and try the import again."
            }
        }
    }

    public enum ExportError: LocalizedError {
        case unsafeConcealedContent

        public var errorDescription: String? {
            "Concealed history is not ready for a safe export. Wait for Keychain access and restart Permafrost if necessary, then try again."
        }
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
        var ocrText: String?
        var sourceApp: String?
        var createdAt: Date
        var lastUsedAt: Date
        var isPinned: Bool
        var pinOrder: Int?
        var isConcealed: Bool
        var imageFile: String?
        var thumbnailFile: String?
        var richDataFile: String?
        /// ADR-021: concealed items export their ciphertext here, `text`/`richDataFile`
        /// stay nil for them — the manifest must never carry a concealed item's plaintext.
        var encryptedDataFile: String?
        var qrSensitiveStatus: QRSensitiveStatus?
        var encryptedQRDataFile: String?
    }

    // MARK: - Export

    public static func exportArchive(from store: ClipboardStore, to directory: URL) throws {
        // Preflight the same immutable snapshot we serialize, before writing any files.
        // Legacy rows can remain plaintext while the asynchronous key migration is pending.
        let items = try store.allItems()
        do {
            for item in items { try ClipboardItemValidation.validateQRMetadata(item) }
        } catch {
            throw ExportError.unsafeConcealedContent
        }
        for item in items where item.kind == .text && item.isConcealed {
            guard let encrypted = item.encryptedData, !encrypted.isEmpty,
                item.text == nil, item.richData == nil, item.ocrText == nil,
                item.imageData == nil, item.thumbnail == nil
            else { throw ExportError.unsafeConcealedContent }
        }
        let fm = FileManager.default
        let blobs = directory.appendingPathComponent("blobs", isDirectory: true)
        try fm.createDirectory(at: blobs, withIntermediateDirectories: true)

        var manifestItems: [ManifestItem] = []
        for item in items {
            var entry = ManifestItem(
                contentHash: item.contentHash,
                kind: item.kind,
                text: item.text,
                ocrText: item.ocrText,
                sourceApp: item.sourceApp,
                createdAt: item.createdAt,
                lastUsedAt: item.lastUsedAt,
                isPinned: item.isPinned,
                pinOrder: item.pinOrder,
                isConcealed: item.isConcealed,
                imageFile: nil,
                thumbnailFile: nil,
                richDataFile: nil,
                encryptedDataFile: nil,
                qrSensitiveStatus: item.qrSensitiveStatus,
                encryptedQRDataFile: nil
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
            if let encryptedData = item.encryptedData {
                let name = "\(item.contentHash).encrypted"
                try encryptedData.write(to: blobs.appendingPathComponent(name))
                entry.encryptedDataFile = "blobs/\(name)"
            }
            if let data = item.encryptedQRData {
                let name = "\(item.contentHash).qr-encrypted"
                try data.write(to: blobs.appendingPathComponent(name))
                entry.encryptedQRDataFile = "blobs/\(name)"
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
        guard [1, manifestVersion].contains(manifest.version) else {
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

        // Every entry is validated/decrypted into a plain `ClipboardItem` here, with
        // nothing written to the store yet — only after every entry in the archive checks
        // out does the single batch insert below run, itself one transaction. This makes
        // the whole import atomic: an archive that fails partway through (e.g. one
        // concealed entry from a different Keychain key) leaves the store exactly as it
        // was, rather than the entries before the failure already being permanently
        // committed while the user sees a single "Import failed" alert that doesn't
        // reflect that partial state.
        var itemsToInsert: [ClipboardItem] = []
        for entry in manifest.items {
            let richData = try blob(entry.richDataFile)
            let imageData = try blob(entry.imageFile)
            let thumbnail = try blob(entry.thumbnailFile)
            let encryptedData = try blob(entry.encryptedDataFile)
            let encryptedQRData = try blob(entry.encryptedQRDataFile)

            // ADR-021: a concealed text item is exported as ciphertext, never plaintext.
            // Verify its decrypted plaintext before inserting. A different-machine/key archive
            // is reported to the user rather than silently skipping its sensitive entries.
            if entry.kind == .text, entry.isConcealed, let encryptedData {
                guard entry.text == nil, entry.ocrText == nil, imageData == nil else {
                    throw ImportError.kindFieldMismatch(entry.contentHash)
                }
                // Built once, as the real item to insert — also what revealText checks
                // against, since it only reads kind/isConcealed/encryptedData, all already
                // populated with their final values here.
                let item = ClipboardItem(
                    id: nil, contentHash: entry.contentHash, kind: .text, text: nil,
                    ocrText: nil, richData: nil, encryptedData: encryptedData, imageData: nil,
                    thumbnail: nil, sourceApp: entry.sourceApp, createdAt: entry.createdAt,
                    lastUsedAt: entry.lastUsedAt, isPinned: entry.isPinned,
                    pinOrder: entry.pinOrder, isConcealed: true)
                let plaintext: String?
                do {
                    plaintext = try store.revealText(for: item)
                } catch {
                    throw ImportError.concealedContentCannotBeImported(entry.contentHash)
                }
                guard let plaintext else {
                    throw ImportError.concealedContentCannotBeImported(entry.contentHash)
                }
                guard ClipboardCapture(text: plaintext).contentHash == entry.contentHash else {
                    throw ImportError.contentHashMismatch(entry.contentHash)
                }
                itemsToInsert.append(item)
                continue
            }

            // Review M-2: don't trust the manifest's kind/hash claims — recompute
            // the hash from the actual content using the same logic that produced
            // it at capture time, and reject fields that don't match the kind.
            do {
                try ClipboardItemValidation.validate(
                    kind: entry.kind, text: entry.text, ocrText: entry.ocrText,
                    imageData: imageData, richData: richData, sourceApp: entry.sourceApp,
                    isConcealed: entry.isConcealed, expectedContentHash: entry.contentHash)
            } catch ClipboardItemValidation.Error.kindFieldMismatch {
                throw ImportError.kindFieldMismatch(entry.contentHash)
            } catch ClipboardItemValidation.Error.contentHashMismatch {
                throw ImportError.contentHashMismatch(entry.contentHash)
            }

            // Built once — the real item to insert, and also what the QR checks below
            // verify, instead of a separate throwaway instance built just for that check.
            let item = ClipboardItem(
                id: nil, contentHash: entry.contentHash, kind: entry.kind, text: entry.text,
                ocrText: entry.ocrText, qrSensitiveStatus: entry.qrSensitiveStatus,
                encryptedQRData: encryptedQRData, richData: richData, imageData: imageData,
                thumbnail: thumbnail, sourceApp: entry.sourceApp, createdAt: entry.createdAt,
                lastUsedAt: entry.lastUsedAt, isPinned: entry.isPinned,
                pinOrder: entry.pinOrder, isConcealed: entry.isConcealed)

            do {
                try ClipboardItemValidation.validateQRMetadata(item)
            } catch {
                throw ImportError.kindFieldMismatch(entry.contentHash)
            }

            if encryptedQRData != nil {
                // nil here unambiguously means "this Mac's Keychain key isn't ready yet"
                // (revealSensitiveQRText's only nil-producing path once kind/data are
                // already known non-nil) — transient, distinct from a thrown error, which
                // means the ciphertext itself is unreadable (ADR-025).
                let revealed: String?
                do {
                    revealed = try store.revealSensitiveQRText(for: item)
                } catch {
                    throw ImportError.concealedContentCannotBeImported(entry.contentHash)
                }
                guard revealed != nil else {
                    throw ImportError.sourceKeyUnavailable(entry.contentHash)
                }
            }

            itemsToInsert.append(item)
        }
        return try store.insertPreservingMetadata(itemsToInsert)
    }
}
