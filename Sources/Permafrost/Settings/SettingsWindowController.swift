import AppKit
import PermafrostCore
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let store: ClipboardStore
    private let clearHistory: (Bool) throws -> Void
    private var window: NSWindow?

    /// `clearHistory` runs on the capture queue so a clear can't race pending captures.
    init(store: ClipboardStore, clearHistory: @escaping (Bool) throws -> Void) {
        self.store = store
        self.clearHistory = clearHistory
    }

    func showWindow() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(store: store, clearHistory: clearHistory))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Permafrost Settings"
            // Resizable, and capped to fit the visible screen: SettingsView no longer
            // demands its full unbounded content height (which grew past the screen
            // bottom, behind the Dock, as Settings sections were added — 2026-07-07).
            // The Form scrolls internally if content exceeds this height.
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            let maxHeight = min(680, (NSScreen.main?.visibleFrame.height ?? 800) - 80)
            window.setContentSize(NSSize(width: 480, height: maxHeight))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
