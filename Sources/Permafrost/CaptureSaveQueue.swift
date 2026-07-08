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
    private let textRecognizer: any TextRecognizing
    private let queue = DispatchQueue(label: "com.fuzzylogicyetis.Permafrost.capture-save")

    init(store: ClipboardStore, textRecognizer: any TextRecognizing = VisionTextRecognizer()) {
        self.store = store
        self.textRecognizer = textRecognizer
    }

    func enqueue(_ pending: PendingCapture) {
        queue.async { [store, textRecognizer] in
            do {
                let item = try store.save(pending.capture, now: pending.capturedAt)
                if pending.capture.kind == .image,
                    pending.capture.ocrText == nil,
                    let id = item.id,
                    let imageData = pending.capture.imageData,
                    let recognizedText = textRecognizer.recognizeText(in: imageData),
                    !recognizedText.isEmpty
                {
                    try store.setOCRText(recognizedText, id: id)
                    Log.capture.info("OCR text saved for image item \(id)")
                }
                try store.purge(with: pending.retentionPolicy, now: pending.capturedAt)
            } catch {
                Log.store.error("save failed: \(error.localizedDescription)")
            }
        }
    }

    func waitUntilIdle() {
        queue.sync {}
    }
}
