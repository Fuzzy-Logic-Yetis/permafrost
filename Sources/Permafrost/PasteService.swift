import AppKit
import ApplicationServices
import Carbon.HIToolbox
import PermafrostCore

/// Distinguishes *why* `paste`/`pasteAsPlainText` didn't fully succeed, since the two
/// failure modes need different handling by the caller: `contentUnavailable` means nothing
/// was written to the pasteboard at all (e.g. a concealed item whose key isn't ready yet —
/// showing an Accessibility prompt for that would be actively misleading), while
/// `copiedOnly` means the content is on the pasteboard and only the automatic ⌘V keystroke
/// was skipped for lack of Accessibility permission.
enum PasteOutcome: Equatable {
    case pasted
    case copiedOnly
    case contentUnavailable
}

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

    @discardableResult
    func copyToPasteboard(_ item: ClipboardItem) -> Bool {
        let pasteboard = NSPasteboard.general
        switch item.kind {
        case .text:
            // Resolve before clearing the pasteboard. A missing Keychain key or corrupt
            // ciphertext must leave the user's current clipboard intact, not replace it
            // with "" — bound once via `guard let` so there is no later force-unwrap of
            // an optional the compiler can't prove is still non-nil at that point.
            guard let text = revealedText(for: item) else { return false }
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            if let rich = item.richData { pasteboard.setData(rich, forType: .rtf) }
        case .image:
            pasteboard.clearContents()
            if let data = item.imageData { pasteboard.setData(data, forType: .png) }
        }
        onPasteboardWritten()
        markUsed(item)
        return true
    }

    func copyOCRTextToPasteboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.ocrText ?? "", forType: .string)
        onPasteboardWritten()
        markUsed(item)
    }

    /// Unlike `copyToPasteboard(_:)`, never writes `.rtf` — ADR-018's "paste as plain text".
    @discardableResult
    func copyPlainTextToPasteboard(_ item: ClipboardItem) -> Bool {
        guard let text = revealedText(for: item) else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        onPasteboardWritten()
        markUsed(item)
        return true
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

    @discardableResult
    func paste(_ item: ClipboardItem) -> PasteOutcome {
        guard copyToPasteboard(item) else { return .contentUnavailable }
        return sendPasteKeystrokeIfTrusted() ? .pasted : .copiedOnly
    }

    @discardableResult
    func pasteAsPlainText(_ item: ClipboardItem) -> PasteOutcome {
        guard copyPlainTextToPasteboard(item) else { return .contentUnavailable }
        return sendPasteKeystrokeIfTrusted() ? .pasted : .copiedOnly
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
