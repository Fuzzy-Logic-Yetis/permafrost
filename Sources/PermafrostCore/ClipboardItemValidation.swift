import Foundation

/// Shared by `ImportExport` and `PortableArchive`: verifies a decoded archive entry's kind
/// matches its populated fields and that recomputing the content hash from the actual
/// content matches what the archive claims. Both import formats need this exact integrity
/// check (Review M-2) — they only differ in how they represent blobs on disk (separate
/// blob files vs. inline `Data`), which the caller resolves to plain values before calling
/// this, so the security-relevant validation logic itself lives in exactly one place.
enum ClipboardItemValidation {
    enum Error: Swift.Error {
        case kindFieldMismatch
        case contentHashMismatch
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
