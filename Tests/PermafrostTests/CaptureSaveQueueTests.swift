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

    @Test func imageCaptureSkipsOCRWhenDisabled() throws {
        let store = try ClipboardStore.inMemory()
        let recognizer = FakeQueueTextRecognizer(result: "should not run")
        let queue = CaptureSaveQueue(store: store, textRecognizer: recognizer)

        queue.enqueue(
            CaptureSaveQueue.PendingCapture(
                capture: ClipboardCapture(imageData: Data([1, 2, 3])),
                capturedAt: Date(timeIntervalSince1970: 2_000_000_000),
                retentionPolicy: RetentionPolicy(),
                recognizeTextInImages: false
            )
        )
        queue.waitUntilIdle()

        #expect(recognizer.callCount == 0)
        #expect(try store.allItems().first?.ocrText == nil)
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

    // MARK: - HTML→RTF conversion (ADR-019, planned before implementation)
    //
    // These reference `ClipboardCapture.htmlData`, `HTMLRichTextConverting`, and the
    // `htmlRichTextConverter` init parameter, none of which exist yet — intentionally red
    // on this branch until ADR-019 is implemented (see ADR-019 test plan).

    @Test func textCaptureWithNoNativeRTFFallsBackToConvertingHTML() throws {
        let store = try ClipboardStore.inMemory()
        let converter = FakeHTMLRichTextConverter(result: Data("converted rtf".utf8))
        let queue = CaptureSaveQueue(store: store, htmlRichTextConverter: converter)

        queue.enqueue(
            CaptureSaveQueue.PendingCapture(
                capture: ClipboardCapture(
                    text: "plain text", htmlData: Data("<b>plain text</b>".utf8)),
                capturedAt: Date(timeIntervalSince1970: 2_000_000_000),
                retentionPolicy: RetentionPolicy()
            )
        )
        queue.waitUntilIdle()

        #expect(converter.callCount == 1)
        #expect(try store.allItems().first?.richData == Data("converted rtf".utf8))
    }

    @Test func textCaptureWithNativeRTFNeverInvokesHTMLConverter() throws {
        let store = try ClipboardStore.inMemory()
        let converter = FakeHTMLRichTextConverter(result: Data("should not be used".utf8))
        let queue = CaptureSaveQueue(store: store, htmlRichTextConverter: converter)
        let nativeRTF = Data("native rtf".utf8)

        queue.enqueue(
            CaptureSaveQueue.PendingCapture(
                capture: ClipboardCapture(
                    text: "plain text", richData: nativeRTF,
                    htmlData: Data("<b>plain text</b>".utf8)),
                capturedAt: Date(timeIntervalSince1970: 2_000_000_000),
                retentionPolicy: RetentionPolicy()
            )
        )
        queue.waitUntilIdle()

        #expect(converter.callCount == 0)
        #expect(try store.allItems().first?.richData == nativeRTF)
    }

    @Test func textCaptureWithNeitherRTFNorHTMLIsUnaffected() throws {
        let store = try ClipboardStore.inMemory()
        let converter = FakeHTMLRichTextConverter(result: Data("should not be used".utf8))
        let queue = CaptureSaveQueue(store: store, htmlRichTextConverter: converter)

        queue.enqueue(
            CaptureSaveQueue.PendingCapture(
                capture: ClipboardCapture(text: "plain text"),
                capturedAt: Date(timeIntervalSince1970: 2_000_000_000),
                retentionPolicy: RetentionPolicy()
            )
        )
        queue.waitUntilIdle()

        #expect(converter.callCount == 0)
        #expect(try store.allItems().first?.richData == nil)
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

private final class FakeHTMLRichTextConverter: HTMLRichTextConverting, @unchecked Sendable {
    private let lock = NSLock()
    private let result: Data?
    private var _callCount = 0

    init(result: Data?) {
        self.result = result
    }

    var callCount: Int {
        lock.withLock { _callCount }
    }

    func rtfData(fromHTML html: Data) -> Data? {
        lock.withLock { _callCount += 1 }
        return result
    }
}
