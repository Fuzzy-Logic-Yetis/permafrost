import AppKit
import PermafrostCore

/// AppKit-only concerns stay out of PermafrostCore (CLAUDE.md architecture rule),
/// so the NSSharingServicePicker item conversion lives here instead.
extension ClipboardItem {
    var shareableItems: [Any] {
        switch kind {
        case .text:
            return [text ?? ""]
        case .image:
            guard let data = imageData, let image = NSImage(data: data) else { return [] }
            return [image]
        }
    }
}
