import Foundation
import Testing

import PermafrostCore
@testable import Permafrost

@Suite struct CaptureSaveQueueTests {
    @Test func imageCaptureRunsOCRAndPersistsRecognizedText() throws {
        let store = try ClipboardStore.inMemory()
        let queue = CaptureSaveQueue(
            store: store,
            textRecognizer: FakeQueueTextRecognizer(result: "invoice total 42")
        )

        queue.enqueue(
            CaptureSaveQueue.PendingCapture(
                capture: ClipboardCapture(imageData: Data([1, 2, 3])),
                capturedAt: Date(timeIntervalSince1970: 2_000_000_000),
                retentionPolicy: RetentionPolicy()
            )
        )
        queue.waitUntilIdle()

        let item = try #require(store.allItems().first)
        #expect(item.ocrText == "invoice total 42")
        #expect(try store.items(matching: "invoice").map(\.id) == [item.id])
    }

    @Test func textCaptureDoesNotInvokeOCR() throws {
        let store = try ClipboardStore.inMemory()
        let recognizer = FakeQueueTextRecognizer(result: "should not run")
        let queue = CaptureSaveQueue(store: store, textRecognizer: recognizer)

        queue.enqueue(
            CaptureSaveQueue.PendingCapture(
                capture: ClipboardCapture(text: "plain text"),
                capturedAt: Date(timeIntervalSince1970: 2_000_000_000),
                retentionPolicy: RetentionPolicy()
            )
        )
        queue.waitUntilIdle()

        #expect(recognizer.callCount == 0)
        #expect(try store.allItems().first?.ocrText == nil)
    }
}

private final class FakeQueueTextRecognizer: TextRecognizing, @unchecked Sendable {
    private let lock = NSLock()
    private let result: String?
    private var _callCount = 0

    init(result: String?) {
        self.result = result
    }

    var callCount: Int {
        lock.withLock { _callCount }
    }

    func recognizeText(in imageData: Data) -> String? {
        lock.withLock { _callCount += 1 }
        return result
    }
}
