import Foundation

/// Shared by `ImportExport` and `PortableArchive`: verifies a decoded archive entry's kind
/// matches its populated fields and that recomputing the content hash from the actual
/// content matches what the archive claims. Both import formats need this exact integrity
/// check (Review M-2) — they only differ in how they represent blobs on disk (separate
/// blob files vs. inline `Data`), which the caller resolves to plain values before calling
/// this, so the security-relevant validation logic itself lives in exactly one place.
/// `validateQRMetadata` (ADR-025) extends that same "one place" to QR consistency checks,
/// which previously lived as a second, parallel validator on `ClipboardStore`.
enum ClipboardItemValidation {
    enum Error: Swift.Error {
        case kindFieldMismatch
        case contentHashMismatch
    }

    /// A row claiming `.encrypted` status must carry ciphertext, and vice versa; QR status
    /// only makes sense on an image row. Throws `ConcealedContentError.invalidConcealedContent`
    /// (not a local error) since this is the same "this data can't be trusted" condition
    /// `ClipboardStore.revealSensitiveQRText` throws for a tampered row.
    static func validateQRMetadata(_ item: ClipboardItem) throws {
        guard item.qrSensitiveStatus != nil || item.encryptedQRData != nil else { return }
        guard item.kind == .image,
            (item.qrSensitiveStatus == .encrypted) == (item.encryptedQRData != nil)
        else { throw ClipboardStore.ConcealedContentError.invalidConcealedContent }
    }

    @discardableResult
    static func validate(
        kind: ClipboardItemKind,
        text: String?,
        ocrText: String?,
        imageData: Data?,
        richData: Data?,
        sourceApp: String?,
        isConcealed: Bool,
        expectedContentHash: String
    ) throws -> ClipboardCapture {
        let capture: ClipboardCapture
        switch kind {
        case .text:
            guard let text, ocrText == nil, imageData == nil else {
                throw Error.kindFieldMismatch
            }
            capture = ClipboardCapture(
                text: text, richData: richData, sourceApp: sourceApp, isConcealed: isConcealed)
        case .image:
            guard let imageData, text == nil else {
                throw Error.kindFieldMismatch
            }
            capture = ClipboardCapture(
                imageData: imageData, ocrText: ocrText, sourceApp: sourceApp,
                isConcealed: isConcealed)
        }
        guard capture.contentHash == expectedContentHash else {
            throw Error.contentHashMismatch
        }
        return capture
    }
}
