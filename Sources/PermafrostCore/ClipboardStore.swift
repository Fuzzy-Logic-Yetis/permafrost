import CryptoKit
import Foundation
import GRDB

/// The single gateway to persistence. No SQL exists outside this module (CLAUDE.md).
public final class ClipboardStore: Sendable {
    private let dbQueue: DatabaseQueue
    private let cipher: ConcealedContentCipher

    public init(dbQueue: DatabaseQueue, concealedContentKey: SymmetricKey) {
        self.dbQueue = dbQueue
        self.cipher = ConcealedContentCipher(key: concealedContentKey)
    }

    // MARK: - Opening

    /// Opens (creating if needed) the on-disk store with owner-only permissions.
    /// `concealedContentKey` is required (not defaulted) deliberately (ADR-021) — the real
    /// app must be explicit about passing its persistent, Keychain-backed key here, so a
    /// missing key can't silently fall back to something ephemeral and lose future
    /// decryptability of already-recorded concealed items.
    public static func onDisk(at url: URL, concealedContentKey: SymmetricKey) throws -> ClipboardStore {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        try fm.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let dbQueue = try DatabaseQueue(path: url.path)
        try migrator.migrate(dbQueue)
        for suffix in ["", "-wal", "-shm", "-journal"] {
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path + suffix)
        }
        return ClipboardStore(dbQueue: dbQueue, concealedContentKey: concealedContentKey)
    }

    /// Test/throwaway stores don't need a persistent key — an ephemeral one is generated
    /// by default so existing call sites that don't care about concealed-content
    /// encryption need no changes.
    public static func inMemory(concealedContentKey: SymmetricKey = SymmetricKey(size: .bits256))
        throws -> ClipboardStore
    {
        let dbQueue = try DatabaseQueue()
        try migrator.migrate(dbQueue)
        return ClipboardStore(dbQueue: dbQueue, concealedContentKey: concealedContentKey)
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "clipboard_item") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("content_hash", .text).notNull().unique()
                t.column("kind", .text).notNull()
                t.column("text", .text)
                t.column("rich_data", .blob)
                t.column("image_data", .blob)
                t.column("thumbnail", .blob)
                t.column("source_app", .text)
                t.column("created_at", .datetime).notNull()
                t.column("last_used_at", .datetime).notNull().indexed()
                t.column("is_pinned", .boolean).notNull().defaults(to: false)
                t.column("pin_order", .integer)
                t.column("is_concealed", .boolean).notNull().defaults(to: false)
            }
            try db.create(virtualTable: "clipboard_item_fts", using: FTS5()) { t in
                t.synchronize(withTable: "clipboard_item")
                t.column("text")
                t.tokenizer = .unicode61()
            }
        }
        migrator.registerMigration("v2_ocr_text") { db in
            try db.alter(table: "clipboard_item") { t in
                t.add(column: "ocr_text", .text)
            }
            try db.execute(sql: "DROP TRIGGER IF EXISTS __clipboard_item_fts_ai")
            try db.execute(sql: "DROP TRIGGER IF EXISTS __clipboard_item_fts_ad")
            try db.execute(sql: "DROP TRIGGER IF EXISTS __clipboard_item_fts_au")
            try db.drop(table: "clipboard_item_fts")
            try db.create(virtualTable: "clipboard_item_fts", using: FTS5()) { t in
                t.synchronize(withTable: "clipboard_item")
                t.column("text")
                t.column("ocr_text")
                t.tokenizer = .unicode61()
            }
            try db.execute(sql: "INSERT INTO clipboard_item_fts(clipboard_item_fts) VALUES ('rebuild')")
        }
        migrator.registerMigration("v3_concealed_encryption") { db in
            try db.alter(table: "clipboard_item") { t in
                t.add(column: "encrypted_data", .blob)
            }
        }
        return migrator
    }

    // MARK: - Capture

    /// Saves a capture. Identical content (same hash) is deduplicated: the existing
    /// row keeps its pin state, but `sourceApp` and `richData` are refreshed to this
    /// copy's context (stale formatting/app captions would otherwise survive
    /// indefinitely), and `isConcealed` is OR'd rather than replaced — once content
    /// has been recorded as sensitive, a later coincidental non-concealed copy of the
    /// same text must not un-mark it.
    ///
    /// ADR-021: whenever a `.text` row is (or becomes) concealed, its content is sealed
    /// into `encrypted_data` and `text`/`rich_data` are never populated in cleartext — this
    /// applies identically whether the row is brand new or was previously stored as
    /// plaintext and only just became concealed, so old plaintext can never linger under a
    /// newly-true flag.
    @discardableResult
    public func save(_ capture: ClipboardCapture, now: Date = Date()) throws -> ClipboardItem {
        let hash = capture.contentHash
        let thumbnail: Data? =
            if capture.kind == .image, let imageData = capture.imageData {
                Thumbnailer.pngThumbnail(from: imageData)
            } else {
                nil
            }
        return try dbQueue.write { db in
            if var existing = try ClipboardItem
                .filter(Column("content_hash") == hash)
                .fetchOne(db)
            {
                existing.lastUsedAt = now
                existing.sourceApp = capture.sourceApp
                let isConcealed = existing.isConcealed || capture.isConcealed
                if capture.kind == .text, isConcealed {
                    existing.encryptedData = try cipher.seal(capture.text ?? "")
                    existing.text = nil
                    existing.richData = nil
                } else {
                    existing.richData = capture.richData
                }
                if capture.ocrText != nil {
                    existing.ocrText = capture.ocrText
                }
                existing.isConcealed = isConcealed
                try existing.update(db)
                return existing
            }
            let sealForConcealment = capture.kind == .text && capture.isConcealed
            var item = ClipboardItem(
                id: nil,
                contentHash: hash,
                kind: capture.kind,
                text: sealForConcealment ? nil : capture.text,
                ocrText: capture.ocrText,
                richData: sealForConcealment ? nil : capture.richData,
                encryptedData: sealForConcealment ? try cipher.seal(capture.text ?? "") : nil,
                imageData: capture.imageData,
                thumbnail: thumbnail,
                sourceApp: capture.sourceApp,
                createdAt: now,
                lastUsedAt: now,
                isPinned: false,
                pinOrder: nil,
                isConcealed: capture.isConcealed
            )
            try item.insert(db)
            return item
        }
    }

    // MARK: - Reading

    /// Decrypts a concealed item's content for display/paste (ADR-021). A no-op passthrough
    /// for anything that isn't concealed-and-encrypted, so callers (panel reveal toggle,
    /// paste) can call this uniformly without checking `isConcealed` first.
    public func revealText(for item: ClipboardItem) throws -> String? {
        guard item.kind == .text, item.isConcealed, let encryptedData = item.encryptedData else {
            return item.text
        }
        return try cipher.open(encryptedData)
    }

    /// Unpinned entries first (by recency), pinned entries in their own section at
    /// the bottom (most-recently-pinned first). This ordering is a product
    /// guarantee (ADR-012): pinning something never displaces your latest copy from
    /// the front of the list or from the `⌘1`–`⌘9` quick-paste slots, which address
    /// only the unpinned prefix. A non-empty query filters via FTS5 prefix matching;
    /// text rows match their body and image rows match recognized OCR metadata when present.
    public func items(matching query: String? = nil, limit: Int = 500) throws -> [ClipboardItem] {
        let trimmed = (query ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return try dbQueue.read { db in
            let ordering = """
                ORDER BY is_pinned ASC,
                         CASE WHEN is_pinned = 0 THEN last_used_at END DESC,
                         CASE WHEN is_pinned = 1 THEN pin_order END DESC
                LIMIT ?
                """
            if trimmed.isEmpty {
                return try ClipboardItem.fetchAll(
                    db,
                    sql: "SELECT * FROM clipboard_item \(ordering)",
                    arguments: [limit]
                )
            }
            guard let pattern = FTS5Pattern(matchingAllPrefixesIn: trimmed) else {
                return []
            }
            return try ClipboardItem.fetchAll(
                db,
                sql: """
                    SELECT clipboard_item.* FROM clipboard_item
                    JOIN clipboard_item_fts
                      ON clipboard_item_fts.rowid = clipboard_item.id
                     AND clipboard_item_fts MATCH ?
                    \(ordering)
                    """,
                arguments: [pattern, limit]
            )
        }
    }

    public func count() throws -> Int {
        try dbQueue.read { db in
            try ClipboardItem.fetchCount(db)
        }
    }

    public func pinnedCount() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM clipboard_item WHERE is_pinned = 1")
                ?? 0
        }
    }

    public func allItems() throws -> [ClipboardItem] {
        try dbQueue.read { db in
            try ClipboardItem.order(Column("id")).fetchAll(db)
        }
    }

    // MARK: - Mutations

    public func setPinned(_ pinned: Bool, id: Int64) throws {
        try dbQueue.write { db in
            if pinned {
                let maxOrder =
                    try Int.fetchOne(db, sql: "SELECT MAX(pin_order) FROM clipboard_item") ?? 0
                try db.execute(
                    sql: "UPDATE clipboard_item SET is_pinned = 1, pin_order = ? WHERE id = ?",
                    arguments: [maxOrder + 1, id]
                )
            } else {
                try db.execute(
                    sql: "UPDATE clipboard_item SET is_pinned = 0, pin_order = NULL WHERE id = ?",
                    arguments: [id]
                )
            }
        }
    }

    public func markUsed(id: Int64, now: Date = Date()) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE clipboard_item SET last_used_at = ? WHERE id = ?",
                arguments: [now, id]
            )
        }
    }

    public func setOCRText(_ ocrText: String?, id: Int64) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE clipboard_item SET ocr_text = ? WHERE id = ? AND kind = ?",
                arguments: [ocrText, id, ClipboardItemKind.image.rawValue]
            )
        }
    }

    public func delete(id: Int64) throws {
        try dbQueue.write { db in
            _ = try ClipboardItem.deleteOne(db, key: id)
        }
    }

    /// Clears history. Pinned entries survive unless `keepPinned` is false.
    public func clearHistory(keepPinned: Bool = true) throws {
        try dbQueue.write { db in
            if keepPinned {
                try db.execute(sql: "DELETE FROM clipboard_item WHERE is_pinned = 0")
            } else {
                _ = try ClipboardItem.deleteAll(db)
            }
        }
    }

    /// Converts every pinned item back to normal history. Non-destructive: content
    /// is kept, it simply stops being exempt from retention (ADR-012).
    public func unpinAll() throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE clipboard_item SET is_pinned = 0, pin_order = NULL WHERE is_pinned = 1"
            )
        }
    }

    // MARK: - Retention

    /// Applies the retention policy. The `is_pinned = 0` predicate is the product
    /// guarantee: pinned entries are structurally untouchable here.
    @discardableResult
    public func purge(with policy: RetentionPolicy, now: Date = Date()) throws -> Int {
        try dbQueue.write { db in
            var deleted = 0
            if let cutoff = policy.cutoffDate(now: now) {
                try db.execute(
                    sql: "DELETE FROM clipboard_item WHERE is_pinned = 0 AND last_used_at < ?",
                    arguments: [cutoff]
                )
                deleted += db.changesCount
            }
            if let cap = policy.maxUnpinnedCount {
                try db.execute(
                    sql: """
                        DELETE FROM clipboard_item
                        WHERE is_pinned = 0 AND id NOT IN (
                            SELECT id FROM clipboard_item
                            WHERE is_pinned = 0
                            ORDER BY last_used_at DESC
                            LIMIT ?
                        )
                        """,
                    arguments: [cap]
                )
                deleted += db.changesCount
            }
            return deleted
        }
    }

    // MARK: - Import

    /// Inserts an item keeping its original metadata (dates, pin state, flags).
    /// Returns false when content with the same hash already exists.
    @discardableResult
    public func insertPreservingMetadata(_ item: ClipboardItem) throws -> Bool {
        try dbQueue.write { db in
            let exists =
                try Bool.fetchOne(
                    db,
                    sql: "SELECT EXISTS(SELECT 1 FROM clipboard_item WHERE content_hash = ?)",
                    arguments: [item.contentHash]
                ) ?? false
            if exists { return false }
            var copy = item
            copy.id = nil
            try copy.insert(db)
            return true
        }
    }
}
