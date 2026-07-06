import AppKit
import PermafrostCore
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let store: ClipboardStore
    private var window: NSWindow?

    init(store: ClipboardStore) {
        self.store = store
    }

    func showWindow() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(store: store))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Permafrost Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
