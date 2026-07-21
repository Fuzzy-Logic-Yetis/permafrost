import CoreTransferable
import UniformTypeIdentifiers

/// Wraps image bytes so `.image` items can be dragged out of the panel (ADR-020) — unlike
/// `String`, raw PNG `Data` doesn't conform to `Transferable` on its own. Export-only: this
/// is only ever a drag *source*, never a drop target.
struct DraggableImageData: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.data }
    }
}
