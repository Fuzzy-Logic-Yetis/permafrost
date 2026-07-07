import CoreGraphics
import Foundation

/// A single recognized line of text with its bounding box in Vision's normalized,
/// bottom-left-origin coordinate space. Kept separate from `VNRecognizedTextObservation`
/// so reading-order/normalization logic is testable with plain values — the same seam
/// pattern as `PasteboardCapturePolicy` (docs/BACKLOG.md item 12).
struct RecognizedLine: Sendable, Equatable {
    var text: String
    var boundingBox: CGRect
}

enum OCRTextNormalizer {
    /// Vision does not guarantee reading order across observations, so lines are sorted
    /// top-to-bottom (Vision's Y axis is bottom-left origin, so descending Y is
    /// top-to-bottom) and then left-to-right, giving deterministic, stable output for the
    /// same image rather than whatever order Vision happened to return.
    static func orderedText(from lines: [RecognizedLine]) -> String {
        let ordered = lines.sorted { lhs, rhs in
            if abs(lhs.boundingBox.origin.y - rhs.boundingBox.origin.y) > 0.01 {
                return lhs.boundingBox.origin.y > rhs.boundingBox.origin.y
            }
            return lhs.boundingBox.origin.x < rhs.boundingBox.origin.x
        }
        return normalize(ordered.map(\.text))
    }

    /// Trims each line, strips leading/trailing blank lines, and collapses runs of 2+
    /// blank lines down to one — keeps intentional paragraph breaks (e.g. a screenshot of
    /// a document) without a wall of empty lines from Vision noise between text blocks.
    static func normalize(_ lines: [String]) -> String {
        let trimmed = lines.map { $0.trimmingCharacters(in: .whitespaces) }
        var collapsed: [String] = []
        for line in trimmed {
            if line.isEmpty && collapsed.last?.isEmpty == true { continue }
            collapsed.append(line)
        }
        while collapsed.first?.isEmpty == true { collapsed.removeFirst() }
        while collapsed.last?.isEmpty == true { collapsed.removeLast() }
        return collapsed.joined(separator: "\n")
    }
}
