import CryptoKit
import Foundation
import GRDB

public enum ClipboardItemKind: String, Codable, Sendable {
    case text
    case image
}

/// A stored clipboard history entry.
public struct ClipboardItem: Identifiable, Equatable, Codable, Sendable {
    public var id: Int64?
    public var contentHash: String
    public var kind: ClipboardItemKind
    public var text: String?
    public var ocrText: String?
    public var richData: Data?
    /// AES-GCM sealed box (nonce+ciphertext+tag combined) for concealed `.text` items only
    /// (ADR-021) — never populated alongside `text`/`richData` for the same row.
    public var encryptedData: Data?
    public var imageData: Data?
    public var thumbnail: Data?
    public var sourceApp: String?
    public var createdAt: Date
    public var lastUsedAt: Date
    public var isPinned: Bool
    public var pinOrder: Int?
    public var isConcealed: Bool

    enum CodingKeys: String, CodingKey {
        case id, kind, text, thumbnail
        case ocrText = "ocr_text"
        case contentHash = "content_hash"
        case richData = "rich_data"
        case encryptedData = "encrypted_data"
        case imageData = "image_data"
        case sourceApp = "source_app"
        case createdAt = "created_at"
        case lastUsedAt = "last_used_at"
        case isPinned = "is_pinned"
        case pinOrder = "pin_order"
        case isConcealed = "is_concealed"
    }

    public init(
        id: Int64? = nil,
        contentHash: String,
        kind: ClipboardItemKind,
        text: String? = nil,
        ocrText: String? = nil,
        richData: Data? = nil,
        encryptedData: Data? = nil,
        imageData: Data? = nil,
        thumbnail: Data? = nil,
        sourceApp: String? = nil,
        createdAt: Date,
        lastUsedAt: Date,
        isPinned: Bool = false,
        pinOrder: Int? = nil,
        isConcealed: Bool = false
    ) {
        self.id = id
        self.contentHash = contentHash
        self.kind = kind
        self.text = text
        self.ocrText = ocrText
        self.richData = richData
        self.encryptedData = encryptedData
        self.imageData = imageData
        self.thumbnail = thumbnail
        self.sourceApp = sourceApp
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.isPinned = isPinned
        self.pinOrder = pinOrder
        self.isConcealed = isConcealed
    }
}

extension ClipboardItem: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "clipboard_item"

    public var hasOCRText: Bool {
        !(ocrText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// Content observed on the pasteboard, before it becomes a stored item.
public struct ClipboardCapture: Sendable {
    public var kind: ClipboardItemKind
    public var text: String?
    public var ocrText: String?
    public var richData: Data?
    /// Transient (ADR-019): raw `.html` pasteboard bytes, carried only until
    /// `CaptureSaveQueue` converts them to `richData` when no native `.rtf` was present.
    /// Never persisted — `ClipboardStore.save` doesn't read this field at all.
    public var htmlData: Data?
    public var imageData: Data?
    public var sourceApp: String?
    public var isConcealed: Bool

    public init(
        text: String, richData: Data? = nil, htmlData: Data? = nil, sourceApp: String? = nil,
        isConcealed: Bool = false
    ) {
        self.kind = .text
        self.text = text
        self.richData = richData
        self.htmlData = htmlData
        self.sourceApp = sourceApp
        self.isConcealed = isConcealed
    }

    public init(imageData: Data, ocrText: String? = nil, sourceApp: String? = nil, isConcealed: Bool = false) {
        self.kind = .image
        self.imageData = imageData
        self.ocrText = ocrText
        self.sourceApp = sourceApp
        self.isConcealed = isConcealed
    }

    /// Dedup key: identical content (per kind) always hashes identically.
    public var contentHash: String {
        var hasher = SHA256()
        hasher.update(data: Data((kind.rawValue + "\0").utf8))
        switch kind {
        case .text:
            hasher.update(data: Data((text ?? "").utf8))
        case .image:
            hasher.update(data: imageData ?? Data())
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
