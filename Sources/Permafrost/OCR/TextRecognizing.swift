import CoreGraphics
import Foundation
import ImageIO
import Vision

/// Recognizes text in image data using Apple's Vision framework, entirely on-device
/// (docs/SECURITY.md: no network code, ever — GitHub issue #6). `Vision`'s `perform` is
/// synchronous and blocks the calling thread until recognition finishes, so this must
/// never be called on the main actor: a large screen snip must not jank pasteboard
/// snapshotting or panel UI (docs/ARCHITECTURE.md Concurrency). The intended caller is a
/// background context such as `CaptureSaveQueue`'s serial queue, which persists recognized
/// text as image metadata after the original capture has been saved.
protocol TextRecognizing: Sendable {
    /// Normalized recognized text, or nil if nothing was recognized or the image data
    /// couldn't be decoded.
    func recognizeText(in imageData: Data) -> String?
}

/// Vision-backed implementation. Stateless and `Sendable` — safe to share across a
/// background queue.
struct VisionTextRecognizer: TextRecognizing {
    func recognizeText(in imageData: Data) -> String? {
        guard let cgImage = Self.cgImage(from: imageData) else { return nil }

        var lines: [RecognizedLine] = []
        let request = VNRecognizeTextRequest { request, error in
            if let error {
                Log.capture.error("OCR request failed: \(error.localizedDescription)")
                return
            }
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                return
            }
            lines = observations.compactMap { observation in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return RecognizedLine(text: candidate.string, boundingBox: observation.boundingBox)
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            Log.capture.error("OCR handler failed: \(error.localizedDescription)")
            return nil
        }

        guard !lines.isEmpty else { return nil }
        return OCRTextNormalizer.orderedText(from: lines)
    }

    private static func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
