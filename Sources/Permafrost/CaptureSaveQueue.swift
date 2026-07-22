import Foundation
import PermafrostCore

/// Serial background saver for clipboard captures.
///
/// `PasteboardWatcher` snapshots pasteboard/AppKit state on the main actor, but hashing,
/// thumbnail generation, SQLite blob writes, and retention purge happen here so large image
/// captures do not block the UI thread. Concealed captures that arrive while the persistent
/// Keychain key is pending are retained (bounded) only in this in-memory serial queue and
/// retried once the key is installed; a save that fails for any other reason gets a few
/// short retries before being logged and dropped.
final class CaptureSaveQueue: @unchecked Sendable {
    struct PendingCapture: Sendable {
        var capture: ClipboardCapture
        var capturedAt: Date
        var retentionPolicy: RetentionPolicy
        var recognizeTextInImages = true
    }

    /// Bounds in-memory retention of concealed plaintext awaiting a Keychain key. The
    /// launch-to-key-resolution window is normally sub-second, so this should never bind
    /// in practice — but an unbounded array would otherwise let concealed plaintext
    /// accumulate indefinitely in process memory for the rest of a session where the key
    /// never resolves, trading the old data-loss bug for a plaintext-retention one.
    /// Internal (not private) so tests can assert against the real cap rather than a
    /// hardcoded duplicate.
    static let maxPendingConcealedCaptures = 20
    /// A retry that fails for a reason other than the key being unavailable is a transient
    /// store error (the key is confirmed installed by the time retries run) — worth a
    /// couple of short-lived attempts before treating the capture as unrecoverable.
    static let maxSaveAttempts = 3
    static let retryDelay: TimeInterval = 0.1

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
        queue.async { [weak self] in self?.save(pending, retainIfKeyPending: true, attempt: 1) }
    }

    /// Called only after the app has installed a successfully read/persisted Keychain key.
    func retryPendingConcealedCaptures() {
        queue.async { [weak self] in
            guard let self else { return }
            let pending = self.pendingConcealedCaptures
            self.pendingConcealedCaptures.removeAll()
            pending.forEach { self.save($0, retainIfKeyPending: false, attempt: 1) }
        }
    }

    private func save(_ pending: PendingCapture, retainIfKeyPending: Bool, attempt: Int) {
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
            // plaintext and is discarded on app termination if no persistent key becomes
            // ready. Bounded so a session where the key never resolves can't accumulate
            // plaintext secrets in memory indefinitely — dropping the oldest is a last
            // resort expected to never trigger in practice.
            if pendingConcealedCaptures.count >= Self.maxPendingConcealedCaptures {
                Log.capture.error(
                    "dropping oldest pending concealed capture: exceeded cap of \(Self.maxPendingConcealedCaptures)"
                )
                pendingConcealedCaptures.removeFirst()
            }
            pendingConcealedCaptures.append(pending)
            Log.capture.info("concealed capture queued while Keychain key is unavailable")
        } catch {
            // Not a key-availability problem (the key is already installed by the time
            // retries run) — a transient store error. Worth a couple of short retries
            // before treating a capture the user already successfully copied as lost.
            guard attempt < Self.maxSaveAttempts else {
                Log.store.error("save failed after \(attempt) attempts: \(error.localizedDescription)")
                return
            }
            Log.store.error(
                "save attempt \(attempt) failed, retrying: \(error.localizedDescription)")
            queue.asyncAfter(deadline: .now() + Self.retryDelay) { [weak self] in
                self?.save(pending, retainIfKeyPending: retainIfKeyPending, attempt: attempt + 1)
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
