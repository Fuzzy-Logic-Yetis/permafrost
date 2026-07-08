import AppKit
import ApplicationServices
import Carbon.HIToolbox
import PermafrostCore

/// Loads an item onto the pasteboard and synthesizes ⌘V into the frontmost app
/// (ADR-006). Requires Accessibility; degrades to copy-only without it.
@MainActor
final class PasteService {
    private let store: ClipboardStore

    init(store: ClipboardStore) {
        self.store = store
    }

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    func copyToPasteboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch item.kind {
        case .text:
            pasteboard.setString(item.text ?? "", forType: .string)
            if let rich = item.richData {
                pasteboard.setData(rich, forType: .rtf)
            }
        case .image:
            if let data = item.imageData {
                pasteboard.setData(data, forType: .png)
            }
        }
        markUsed(item)
    }

    func copyOCRTextToPasteboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.ocrText ?? "", forType: .string)
        markUsed(item)
    }

    /// Returns false when Accessibility is missing — the item is on the pasteboard
    /// (copy-only fallback) but no keystroke was sent.
    @discardableResult
    func paste(_ item: ClipboardItem) -> Bool {
        copyToPasteboard(item)
        return sendPasteKeystrokeIfTrusted()
    }

    @discardableResult
    func pasteOCRText(_ item: ClipboardItem) -> Bool {
        copyOCRTextToPasteboard(item)
        return sendPasteKeystrokeIfTrusted()
    }

    private func markUsed(_ item: ClipboardItem) {
        if let id = item.id {
            do {
                try store.markUsed(id: id)
            } catch {
                Log.store.error("markUsed failed: \(error.localizedDescription)")
            }
        }
    }

    private func sendPasteKeystrokeIfTrusted() -> Bool {
        guard Self.isTrusted else { return false }
        // Give the panel a beat to close so key focus is back in the target app.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            Self.sendCommandV()
        }
        return true
    }

    private static func sendCommandV() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let vKey = CGKeyCode(kVK_ANSI_V)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
