import CoreGraphics
import Foundation
import Testing

@testable import Permafrost

@Suite struct OCRTextNormalizerTests {
    @Test func ordersLinesTopToBottom() {
        // Vision's Y axis is bottom-left origin: a larger Y is higher on the page.
        let lines = [
            RecognizedLine(text: "second", boundingBox: CGRect(x: 0, y: 0.2, width: 0.5, height: 0.1)),
            RecognizedLine(text: "first", boundingBox: CGRect(x: 0, y: 0.8, width: 0.5, height: 0.1)),
        ]
        #expect(OCRTextNormalizer.orderedText(from: lines) == "first\nsecond")
    }

    @Test func breaksTopToBottomTiesLeftToRight() {
        let sameRow: CGFloat = 0.5
        let lines = [
            RecognizedLine(text: "right", boundingBox: CGRect(x: 0.6, y: sameRow, width: 0.3, height: 0.1)),
            RecognizedLine(text: "left", boundingBox: CGRect(x: 0.0, y: sameRow, width: 0.3, height: 0.1)),
        ]
        #expect(OCRTextNormalizer.orderedText(from: lines) == "left\nright")
    }

    @Test func normalizeTrimsEachLine() {
        #expect(OCRTextNormalizer.normalize(["  hello  ", " world "]) == "hello\nworld")
    }

    @Test func normalizeCollapsesRunsOfBlankLines() {
        let lines = ["heading", "", "", "", "body"]
        #expect(OCRTextNormalizer.normalize(lines) == "heading\n\nbody")
    }

    @Test func normalizeStripsLeadingAndTrailingBlankLines() {
        let lines = ["", "  ", "content", "", ""]
        #expect(OCRTextNormalizer.normalize(lines) == "content")
    }

    @Test func normalizeOfEmptyInputIsEmptyString() {
        #expect(OCRTextNormalizer.normalize([]) == "")
    }
}

/// Demonstrates the fake-recognizer seam future UI/pipeline tests can rely on, the same
/// way `PanelPasteServing`'s `FakePasteService` lets `PanelModel` be tested without
/// AppKit — `TextRecognizing` lets OCR-dependent code be tested without Vision.
private struct FakeTextRecognizer: TextRecognizing {
    var result: String?

    func recognizeText(in imageData: Data) -> String? {
        result
    }
}

@Suite struct FakeTextRecognizerTests {
    @Test func returnsConfiguredResult() {
        let recognizer = FakeTextRecognizer(result: "hello world")
        #expect(recognizer.recognizeText(in: Data()) == "hello world")
    }

    @Test func returnsNilWhenConfiguredEmpty() {
        let recognizer = FakeTextRecognizer(result: nil)
        #expect(recognizer.recognizeText(in: Data()) == nil)
    }
}
