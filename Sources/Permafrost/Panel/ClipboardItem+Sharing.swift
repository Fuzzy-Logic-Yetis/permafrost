import AppKit
import PermafrostCore

/// AppKit-only concerns stay out of PermafrostCore (CLAUDE.md architecture rule),
/// so the NSSharingServicePicker item conversion lives here instead.
extension ClipboardItem {
    /// `text` is nil for a concealed item — only `encryptedData` is populated, so a caller
    /// must supply the already-revealed plaintext to share one. Returns nil (rather than a
    /// silent empty string) when a concealed item's text hasn't been revealed, so it's
    /// impossible for a caller to overlook that dependency and hand the share sheet nothing
    /// while believing it shared the real content.
    func shareableItems(revealedText: String? = nil) -> [Any]? {
        switch kind {
        case .text:
            if isConcealed {
                guard let revealedText else { return nil }
                return [revealedText]
            }
            return [text ?? ""]
        case .image:
            guard let data = imageData, let image = NSImage(data: data) else { return nil }
            return [image]
        }
    }
}
