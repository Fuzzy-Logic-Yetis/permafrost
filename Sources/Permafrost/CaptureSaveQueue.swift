import Foundation
import PermafrostCore

/// Serial background saver for clipboard captures.
///
/// `PasteboardWatcher` snapshots pasteboard/AppKit state on the main actor, but hashing,
/// thumbnail generation, SQLite blob writes, and retention purge happen here so large image
/// captures do not block the UI thread. Concealed captures that arrive while the persistent
/// Keychain key is pending are retained only in this in-memory serial queue and retried once.
final class CaptureSaveQueue: @unchecked Sendable {
    struct PendingCapture: Sendable {
        var capture: ClipboardCapture
        var capturedAt: Date
        var retentionPolicy: RetentionPolicy
        var recognizeTextInImages = true
    }

    private let store: ClipboardStore
    private let textRecognizer: any TextRecognizing
    private let htmlRichTextConverter: any HTMLRichTextConverting
    private let queue = DispatchQueue(label: "com.fuzzylogicyetis.Permafrost.capture-save")
    private var pendingConcealedCaptures: [PendingCapture] = []

    init(
        store: ClipboardStore, textRecognizer: any TextRecognizing = VisionTextRecognizer(),
        htmlRichTextConverter: any HTMLRichTextConverting = HTMLRichTextConverter()
    ) {
        self.store = store
        self.textRecognizer = textRecognizer
        self.htmlRichTextConverter = htmlRichTextConverter
    }

    var onOCRTextSaved: @Sendable (Int64) -> Void = { _ in }

    func enqueue(_ pending: PendingCapture) {
        queue.async { [weak self] in self?.save(pending, retainIfKeyPending: true) }
    }

    /// Called only after the app has installed a successfully read/persisted Keychain key.
    /// A failed retry is logged and dropped; it can no longer be repaired by waiting for a key.
    func retryPendingConcealedCaptures() {
        queue.async { [weak self] in
            guard let self else { return }
            let pending = self.pendingConcealedCaptures
            self.pendingConcealedCaptures.removeAll()
            pending.forEach { self.save($0, retainIfKeyPending: false) }
        }
    }

    private func save(_ pending: PendingCapture, retainIfKeyPending: Bool) {
        do {
            var capture = pending.capture
            // ADR-019: prefer native .rtf (already in richData); only synthesize from
            // .html when there's no native rich data to lose fidelity from.
            if capture.kind == .text, capture.richData == nil, let html = capture.htmlData {
                capture.richData = htmlRichTextConverter.rtfData(fromHTML: html)
            }
            let item = try store.save(capture, now: pending.capturedAt)
            if pending.recognizeTextInImages,
                pending.capture.kind == .image,
                pending.capture.ocrText == nil,
                let id = item.id,
                let imageData = pending.capture.imageData,
                let recognizedText = textRecognizer.recognizeText(in: imageData),
                !recognizedText.isEmpty
            {
                try store.setOCRText(recognizedText, id: id)
                Log.capture.info("OCR text saved for image item \(id)")
                onOCRTextSaved(id)
            }
            try store.purge(with: pending.retentionPolicy, now: pending.capturedAt)
        } catch ClipboardStore.ConcealedContentError.keyNotYetAvailable where retainIfKeyPending {
            // Keep it only until the async Keychain request resolves; it never reaches disk
            // plaintext and is discarded on app termination if no persistent key becomes ready.
            pendingConcealedCaptures.append(pending)
            Log.capture.info("concealed capture queued while Keychain key is unavailable")
        } catch {
            Log.store.error("save failed: \(error.localizedDescription)")
        }
    }

    @discardableResult
    func waitUntilIdle(timeout: TimeInterval? = nil) -> Bool {
        if let timeout {
            let group = DispatchGroup()
            group.enter()
            queue.async { group.leave() }
            return group.wait(timeout: .now() + timeout) == .success
        }
        queue.sync {}
        return true
    }
}
