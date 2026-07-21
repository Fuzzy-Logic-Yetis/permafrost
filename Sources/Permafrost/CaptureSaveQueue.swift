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
        var recognizeTextInImages = true
    }

    private let store: ClipboardStore
    private let textRecognizer: any TextRecognizing
    private let htmlRichTextConverter: any HTMLRichTextConverting
    private let queue = DispatchQueue(label: "com.fuzzylogicyetis.Permafrost.capture-save")

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
        queue.async { [store, textRecognizer, htmlRichTextConverter, onOCRTextSaved] in
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
            } catch {
                Log.store.error("save failed: \(error.localizedDescription)")
            }
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
