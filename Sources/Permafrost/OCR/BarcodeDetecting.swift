import CoreGraphics
import Foundation
import ImageIO
import Vision

/// Decodes QR codes in image data using Apple's Vision framework, entirely on-device
/// (docs/SECURITY.md: no network code, ever). Like `TextRecognizing`, Vision's `perform`
/// is synchronous and blocks the calling thread, so this must never be called on the main
/// actor — the intended caller is `CaptureSaveQueue`'s serial background queue.
///
/// Deliberately QR-only rather than every symbology Vision supports: the product need is
/// screen snips of QR codes (ADR-022), and every extra symbology is another payload shape
/// the sensitive-payload classifier would have to reason about.
protocol BarcodeDetecting: Sendable {
    /// Decoded QR payloads in stable reading order (top-to-bottom, then left-to-right),
    /// or an empty array if the image holds no QR codes or couldn't be decoded.
    func detectQRPayloads(in imageData: Data) -> [String]
}

/// Vision-backed implementation. Stateless and `Sendable` — safe to share across a
/// background queue.
struct VisionBarcodeDetector: BarcodeDetecting {
    func detectQRPayloads(in imageData: Data) -> [String] {
        guard let cgImage = Self.cgImage(from: imageData) else { return [] }

        var found: [RecognizedLine] = []
        let request = VNDetectBarcodesRequest { request, error in
            if let error {
                Log.capture.error("QR request failed: \(error.localizedDescription)")
                return
            }
            guard let observations = request.results as? [VNBarcodeObservation] else { return }
            found = observations.compactMap { observation in
                guard let payload = observation.payloadStringValue, !payload.isEmpty else {
                    return nil
                }
                return RecognizedLine(text: payload, boundingBox: observation.boundingBox)
            }
        }
        request.symbologies = [.qr]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            Log.capture.error("QR handler failed: \(error.localizedDescription)")
            return []
        }

        // Same ordering rule as OCR so a snip with several codes yields deterministic
        // output rather than whatever order Vision happened to return.
        return OCRTextNormalizer.ordered(found).map(\.text)
    }

    private static func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
