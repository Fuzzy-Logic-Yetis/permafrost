import Foundation
import PermafrostCore

/// Serial background saver for clipboard captures.
///
/// `PasteboardWatcher` still snapshots pasteboard/AppKit state on the main actor, but
/// hashing, thumbnail generation, SQLite blob writes, and retention purge happen here so
/// large image captures do not block the UI thread.
final class CaptureSaveQueue {
    struct PendingCapture: Sendable {
        var capture: ClipboardCapture
        var capturedAt: Date
        var retentionPolicy: RetentionPolicy
    }

    private let store: ClipboardStore
    private let queue = DispatchQueue(label: "com.fuzzylogicyetis.Permafrost.capture-save")

    init(store: ClipboardStore) {
        self.store = store
    }

    func enqueue(_ pending: PendingCapture) {
        queue.async { [store] in
            do {
                try store.save(pending.capture, now: pending.capturedAt)
                try store.purge(with: pending.retentionPolicy, now: pending.capturedAt)
            } catch {
                Log.store.error("save failed: \(error.localizedDescription)")
            }
        }
    }
}
