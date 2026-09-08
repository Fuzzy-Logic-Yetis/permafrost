import AppKit
import CoreImage
import Foundation
import PermafrostCore
import Testing
@testable import Permafrost

@Suite struct VisionQRTests {
    @Test func realVisionDecodesGeneratedOrdinaryAndSensitiveQRImages() throws {
        for payload in ["https://example.com/menu", "WIFI:T:WPA;S:Synthetic;P:test-only-password;;",
                        "otpauth://totp/Test?secret=JBSWY3DPEHPK3PXP"] {
            let filter = try #require(CIFilter(name: "CIQRCodeGenerator"))
            filter.setValue(Data(payload.utf8), forKey: "inputMessage")
            filter.setValue("M", forKey: "inputCorrectionLevel")
            let output = try #require(filter.outputImage).transformed(by: CGAffineTransform(scaleX: 10, y: 10))
            let cgImage = try #require(CIContext().createCGImage(output, from: output.extent))
            let png = try #require(NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]))
            #expect(VisionBarcodeDetector().detectQRPayloads(in: png) == [payload])
            let store = try ClipboardStore.inMemory()
            let queue = CaptureSaveQueue(store: store)
            queue.enqueue(.init(capture: ClipboardCapture(imageData: png), capturedAt: Date(),
                                retentionPolicy: RetentionPolicy(), recognizeTextInImages: false))
            queue.waitUntilIdle()
            let saved = try #require(store.allItems().first)
            switch QRPayloadClassifier.classify(payload) {
            case .ordinary: #expect(saved.ocrText == payload && saved.qrSensitiveStatus == nil)
            case .sensitive: #expect(saved.ocrText == nil && saved.qrSensitiveStatus == .omitted)
            }
        }
    }
}
