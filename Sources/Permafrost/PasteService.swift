import AppKit
import ApplicationServices
import Carbon.HIToolbox
import PermafrostCore

/// Loads an item onto the pasteboard and synthesizes ⌘V into the frontmost app
/// (ADR-006). Requires Accessibility; degrades to copy-only without it.
@MainActor
final class PasteService {
    private let store: ClipboardStore
    /// Notifies `PasteboardWatcher` that this pasteboard write was ours, not an incoming
    /// user copy — see `PasteboardWatcher.ignoreOwnWrite()` (found 2026-07-21: without this,
    /// every paste got re-captured as if it were new, which silently self-deduped for a
    /// normal rich paste but caused real data loss for plain-text paste).
    private let onPasteboardWritten: () -> Void

    init(store: ClipboardStore, onPasteboardWritten: @escaping () -> Void = {}) {
        self.store = store
        self.onPasteboardWritten = onPasteboardWritten
    }

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    func copyToPasteboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch item.kind {
        case .text:
            // ADR-021: concealed items store ciphertext, never plaintext, in `item.text` —
            // decrypt on demand right before writing to the pasteboard. Concealed items
            // never have `richData` (by design), so the rich-paste branch below is a no-op
            // for them regardless.
            pasteboard.setString(revealedText(for: item) ?? "", forType: .string)
            if let rich = item.richData {
                pasteboard.setData(rich, forType: .rtf)
            }
        case .image:
            if let data = item.imageData {
                pasteboard.setData(data, forType: .png)
            }
        }
        onPasteboardWritten()
        markUsed(item)
    }

    func copyOCRTextToPasteboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.ocrText ?? "", forType: .string)
        onPasteboardWritten()
        markUsed(item)
    }

    /// Unlike `copyToPasteboard(_:)`, never writes `.rtf` — ADR-018's "paste as plain text".
    func copyPlainTextToPasteboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(revealedText(for: item) ?? "", forType: .string)
        onPasteboardWritten()
        markUsed(item)
    }

    /// ADR-021: decrypts a concealed item's text for pasting; a plain passthrough for
    /// anything that isn't concealed, so both paste paths above can call this uniformly.
    private func revealedText(for item: ClipboardItem) -> String? {
        do {
            return try store.revealText(for: item)
        } catch {
            Log.store.error("reveal-for-paste failed: \(error.localizedDescription)")
            return item.text
        }
    }

    /// Returns false when Accessibility is missing — the item is on the pasteboard
    /// (copy-only fallback) but no keystroke was sent.
    @discardableResult
    func paste(_ item: ClipboardItem) -> Bool {
        copyToPasteboard(item)
        return sendPasteKeystrokeIfTrusted()
    }

    @discardableResult
    func pasteAsPlainText(_ item: ClipboardItem) -> Bool {
        copyPlainTextToPasteboard(item)
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
