import AppKit
import PermafrostCore
import SwiftUI

/// Borderless panel that can take key status without activating the app —
/// the target app keeps focus, so ⏎ pastes into it (ADR-002).
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    private let model: PanelModel
    private var keyMonitor: Any?

    init(model: PanelModel) {
        self.model = model
        panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 500),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.delegate = self

        let hosting = NSHostingView(rootView: PanelView(model: model))
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = 12
        hosting.layer?.masksToBounds = true
        panel.contentView = hosting

        model.onCommit = { [weak self] in self?.hide() }
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        model.prepareForShow()
        position(on: screenWithMouse())
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func hide() {
        removeKeyMonitor()
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    // MARK: - Placement

    private func screenWithMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    private func position(on screen: NSScreen?) {
        guard let screen else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        // Slightly above center, like Spotlight.
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2 + visible.height * 0.06
        )
        panel.setFrameOrigin(origin)
    }

    // MARK: - Keyboard routing (docs/UX.md keyboard map)

    /// Sendable snapshot of the key data we route on — NSEvent itself can't
    /// cross into MainActor.assumeIsolated under Swift 6.
    private struct KeyInput: Sendable {
        let keyCode: Int
        let modifiers: NSEvent.ModifierFlags
        let baseKey: String?
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let input = KeyInput(
                keyCode: Int(event.keyCode),
                modifiers: event.modifierFlags.intersection(.deviceIndependentFlagsMask),
                baseKey: event.charactersIgnoringModifiers?.lowercased()
            )
            let consumed = MainActor.assumeIsolated { self.handle(input) }
            return consumed ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    /// Returns true when the event was consumed.
    private func handle(_ input: KeyInput) -> Bool {
        guard panel.isKeyWindow else { return false }

        switch input.keyCode {
        case kVKUpArrow:
            model.moveSelection(by: -1)
            return true
        case kVKDownArrow:
            model.moveSelection(by: 1)
            return true
        case kVKReturn, kVKKeypadEnter:
            model.commitSelection()
            return true
        case kVKEscape:
            if model.isPreviewShown {
                model.closePreview()
            } else if model.query.isEmpty {
                hide()
            } else {
                model.query = ""
            }
            return true
        case kVKDelete where model.query.isEmpty:
            model.deleteSelected()
            return true
        case kVKSpace where model.query.isEmpty:
            model.togglePreview()
            return true
        default:
            break
        }

        if input.modifiers == .option, input.baseKey == "p" {
            model.togglePinSelected()
            return true
        }
        if input.modifiers == .command, let baseKey = input.baseKey, let digit = Int(baseKey),
            (1...9).contains(digit)
        {
            model.commitQuickPaste(number: digit)
            return true
        }
        return false
    }
}

// Virtual key codes (Carbon kVK_* values; named locally to avoid importing
// Carbon into UI code).
private let kVKReturn = 36
private let kVKKeypadEnter = 76
private let kVKEscape = 53
private let kVKDelete = 51
private let kVKUpArrow = 126
private let kVKDownArrow = 125
private let kVKSpace = 49
