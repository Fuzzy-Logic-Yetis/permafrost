import CryptoKit
import Foundation
import GRDB

/// The single gateway to persistence. No SQL exists outside this module (CLAUDE.md).
public final class ClipboardStore: Sendable {
    private let dbQueue: DatabaseQueue
    /// Concealed-content encryption key, set once it's available (ADR-021 follow-up,
    /// 2026-07-21). Deliberately **not** required at construction and never defaulted to
    /// an ephemeral placeholder for `onDisk` — an earlier design did that, and a session
    /// that fell back to a throwaway key (because the real Keychain-backed key hit this
    /// project's ad-hoc-signature-mismatch prompt) silently encrypted real content with a
    /// key that could never survive that process exiting, destroying it permanently.
    /// `NSLock`-protected since it's now mutated after construction, from a background
    /// queue (`Permafrost`'s launch code), while `dbQueue.write`/`.read` may run
    /// concurrently on other threads.
    private let cipherLock = NSLock()
    // Manually synchronized via `cipherLock` (get/set both go through it below) — the
    // compiler can't verify that itself, hence `nonisolated(unsafe)`.
    nonisolated(unsafe) private var _cipher: ConcealedContentCipher?
    private var cipher: ConcealedContentCipher? {
        cipherLock.withLock { _cipher }
    }

    public enum ConcealedContentError: Error {
        /// The concealed-content key hasn't been set yet — thrown rather than silently
        /// using a placeholder, so concealed content is never encrypted (or decrypted)
        /// with anything but the one real, persistent key.
        case keyNotYetAvailable
        /// A concealed text row must contain either plaintext to be sealed during a legacy
        /// import, or ciphertext. A metadata-only row cannot safely be recovered.
        case invalidConcealedContent
    }

    public init(dbQueue: DatabaseQueue, concealedContentKey: SymmetricKey? = nil) {
        self.dbQueue = dbQueue
        if let concealedContentKey {
            self._cipher = ConcealedContentCipher(key: concealedContentKey)
        }
    }

    /// Called once the persistent key becomes available — however long that takes.
    /// Thread-safe: intended to be called from a background queue once a Keychain fetch
    /// resolves, with no bound on how long that may take (ADR-021 follow-up).
    public func setConcealedContentKey(_ key: SymmetricKey) throws {
        let cipher = ConcealedContentCipher(key: key)
        // v3 could add the ciphertext column before this asynchronously acquired key was
        // available. Backfill those legacy concealed rows before exposing the key so a
        // successful setup establishes the invariant for all concealed text.
        try migrateLegacyConcealedText(using: cipher)
        cipherLock.withLock { _cipher = cipher }
    }

    private func migrateLegacyConcealedText(using cipher: ConcealedContentCipher) throws {
        try dbQueue.write { db in
            let legacyRows = try ClipboardItem.fetchAll(
                db,
                sql: """
                    SELECT * FROM clipboard_item
                    WHERE kind = ? AND is_concealed = 1 AND encrypted_data IS NULL AND text IS NOT NULL
                    """,
                arguments: [ClipboardItemKind.text.rawValue]
            )
            for var item in legacyRows {
                item.encryptedData = try cipher.seal(item.text ?? "")
                item.text = nil
                item.richData = nil
                try item.update(db)
            }
        }
    }

    // MARK: - Opening

    /// Opens (creating if needed) the on-disk store with owner-only permissions. Does
    /// **not** take a concealed-content key — the real app sets one later via
    /// `setConcealedContentKey` once its background Keychain fetch resolves, so opening
    /// the store is never gated on that (ADR-021 follow-up).
    public static func onDisk(at url: URL) throws -> ClipboardStore {
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
        return ClipboardStore(dbQueue: dbQueue)
    }

    /// Test/throwaway stores get a key immediately by default, so existing call sites
    /// that don't care about concealed-content encryption need no changes.
    public static func inMemory(concealedContentKey: SymmetricKey = SymmetricKey(size: .bits256))
        throws -> ClipboardStore
    {
        let dbQueue = try DatabaseQueue()
        try migrator.migrate(dbQueue)
        return ClipboardStore(dbQueue: dbQueue, concealedContentKey: concealedContentKey)
    }

    /// Test-only: a store with no concealed-content key at all, matching the real app's
    /// state between launch and its background Keychain fetch resolving — exercises the
    /// key-not-yet-available paths (ADR-021 follow-up).
    static func inMemoryWithoutConcealedContentKey() throws -> ClipboardStore {
        let dbQueue = try DatabaseQueue()
        try migrator.migrate(dbQueue)
        return ClipboardStore(dbQueue: dbQueue)
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
                    // Never seal with anything but the one real key — if it isn't ready
                    // yet, this throws (propagates to CaptureSaveQueue's existing
                    // log-and-drop handling) rather than ever using a placeholder.
                    guard let cipher = self.cipher else {
                        throw ConcealedContentError.keyNotYetAvailable
                    }
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
            var encryptedData: Data?
            if sealForConcealment {
                guard let cipher = self.cipher else {
                    throw ConcealedContentError.keyNotYetAvailable
                }
                encryptedData = try cipher.seal(capture.text ?? "")
            }
            var item = ClipboardItem(
                id: nil,
                contentHash: hash,
                kind: capture.kind,
                text: sealForConcealment ? nil : capture.text,
                ocrText: capture.ocrText,
                richData: sealForConcealment ? nil : capture.richData,
                encryptedData: encryptedData,
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
        // Key not ready yet: nil, same as "nothing to show" rather than throwing — the
        // caller (reveal toggle, paste) already treats nil as "can't display this right
        // now," no special-casing needed.
        guard let cipher = self.cipher else { return nil }
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

    /// Retroactively encrypts an existing `.text` item that wasn't captured as concealed
    /// (ADR-021 follow-up) — the marker that flags a copy as concealed is set by the
    /// *source* app at capture time (`org.nspasteboard.ConcealedType`); plenty of real
    /// passwords never carry it (typed and ⌘C'd, copied from Notes, a password manager
    /// that doesn't implement the marker), so there's no way to protect them without a
    /// manual, deliberate opt-in after the fact. One-way, same as the automatic
    /// transition-to-concealed path in `save` — no "unmark" exists, matching
    /// `isConcealed`'s existing "sticky in the safer direction" rule. A no-op for
    /// `.image` items (concealed encryption is scoped to text, ADR-021) and for items
    /// already concealed.
    public func markConcealed(id: Int64) throws {
        guard let cipher = self.cipher else {
            throw ConcealedContentError.keyNotYetAvailable
        }
        try dbQueue.write { db in
            guard var item = try ClipboardItem.fetchOne(db, key: id),
                item.kind == .text, !item.isConcealed
            else { return }
            item.encryptedData = try cipher.seal(item.text ?? "")
            item.text = nil
            item.richData = nil
            item.isConcealed = true
            try item.update(db)
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
    /// Legacy archives may hold concealed plaintext; seal it here rather than allowing the
    /// metadata-import path to bypass the storage invariant. Returns false on duplicate hash.
    @discardableResult
    public func insertPreservingMetadata(_ item: ClipboardItem) throws -> Bool {
        try insertPreservingMetadata([item]) == 1
    }

    /// Validates/prepares every item before one database transaction, so an import cannot
    /// report failure after persisting only an arbitrary prefix of its archive.
    public func insertPreservingMetadata(_ items: [ClipboardItem]) throws -> Int {
        let prepared = try items.map { try prepareForMetadataInsertion($0) }
        return try dbQueue.write { db in
            var inserted = 0
            for var item in prepared {
                let exists =
                    try Bool.fetchOne(
                        db,
                        sql: "SELECT EXISTS(SELECT 1 FROM clipboard_item WHERE content_hash = ?)",
                        arguments: [item.contentHash]
                    ) ?? false
                guard !exists else { continue }
                item.id = nil
                try item.insert(db)
                inserted += 1
            }
            return inserted
        }
    }

    private func prepareForMetadataInsertion(_ item: ClipboardItem) throws -> ClipboardItem {
        var imported = item
        if imported.kind == .text, imported.isConcealed, imported.encryptedData == nil {
            guard let plaintext = imported.text else {
                throw ConcealedContentError.invalidConcealedContent
            }
            guard let cipher = cipher else { throw ConcealedContentError.keyNotYetAvailable }
            imported.encryptedData = try cipher.seal(plaintext)
            imported.text = nil
            imported.richData = nil
        }
        return imported
    }
}
