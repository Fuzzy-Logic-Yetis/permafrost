import AppKit
import PermafrostCore

enum PermafrostVersion {
    static let string = "0.2.0"
}

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var store: ClipboardStore!
    private var watcher: PasteboardWatcher!
    private var pasteService: PasteService!
    private var panelController: PanelController!
    private let hotkeyManager = HotkeyManager()
    private let settings = AppSettings.shared
    private var cleanupTimer: Timer?
    private var settingsWindowController: SettingsWindowController?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            store = try ClipboardStore.onDisk(at: Self.databaseURL())
        } catch {
            presentFatalError(error)
            return
        }
        purge()

        pasteService = PasteService(store: store)
        let model = PanelModel(store: store, pasteService: pasteService)
        model.onAccessibilityNeeded = { [weak self] in self?.showAccessibilityPrompt() }
        panelController = PanelController(model: model)

        watcher = PasteboardWatcher()
        watcher.onCapture = { [weak self] capture in
            guard let self else { return }
            do {
                try self.store.save(capture)
                try self.store.purge(with: self.settings.retentionPolicy)
            } catch {
                Log.store.error("save failed: \(error.localizedDescription)")
            }
        }
        watcher.start()

        hotkeyManager.onHotkey = { [weak self] in self?.panelController.toggle() }
        hotkeyManager.register(preset: settings.hotkeyPreset)
        observeSettingsChanges()

        let timer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.purge() }
        }
        RunLoop.main.add(timer, forMode: .common)
        cleanupTimer = timer

        setupStatusItem()
        showWelcomeIfNeeded()
        Log.app.info("Permafrost \(PermafrostVersion.string, privacy: .public) started")
    }

    static func databaseURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Permafrost/store.sqlite")
    }

    private func purge() {
        do {
            let removed = try store.purge(with: settings.retentionPolicy)
            if removed > 0 {
                Log.store.info("retention purge removed \(removed) items")
            }
        } catch {
            Log.store.error("purge failed: \(error.localizedDescription)")
        }
    }

    /// Hotkey preset can change in Settings; re-register and refresh the menu title.
    private func observeSettingsChanges() {
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.hotkeyManager.register(preset: self.settings.hotkeyPreset)
                self.refreshOpenMenuItemTitle()
            }
        }
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        Log.app.info("status item created; button is nil: \(self.statusItem.button == nil)")
        let image = NSImage(systemSymbolName: "snowflake", accessibilityDescription: "Permafrost")
        Log.app.info("snowflake image loaded: \(image != nil)")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.isVisible = true
        Log.app.info("status item isVisible: \(self.statusItem.isVisible)")

        let menu = NSMenu()
        let openItem = NSMenuItem(
            title: "Open Permafrost  (\(settings.hotkeyPreset.display))",
            action: #selector(openPanel), keyEquivalent: "")
        openItem.target = self
        openItem.tag = MenuTag.open.rawValue
        menu.addItem(openItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let exportItem = NSMenuItem(
            title: "Export History…", action: #selector(exportHistory), keyEquivalent: "")
        exportItem.target = self
        menu.addItem(exportItem)

        let importItem = NSMenuItem(
            title: "Import History…", action: #selector(importHistory), keyEquivalent: "")
        importItem.target = self
        menu.addItem(importItem)

        menu.addItem(.separator())
        let clearItem = NSMenuItem(
            title: "Clear Unpinned History…", action: #selector(clearHistory), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)

        let unpinAllItem = NSMenuItem(
            title: "Unpin All Items…", action: #selector(unpinAll), keyEquivalent: "")
        unpinAllItem.target = self
        menu.addItem(unpinAllItem)

        let clearEverythingItem = NSMenuItem(
            title: "Clear Everything…", action: #selector(clearEverything), keyEquivalent: "")
        clearEverythingItem.target = self
        menu.addItem(clearEverythingItem)

        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: "Quit Permafrost",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private enum MenuTag: Int {
        case open = 1
    }

    private func refreshOpenMenuItemTitle() {
        statusItem?.menu?.item(withTag: MenuTag.open.rawValue)?.title =
            "Open Permafrost  (\(settings.hotkeyPreset.display))"
    }

    @objc private func openPanel() {
        panelController.show()
    }

    @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(store: store)
        }
        settingsWindowController?.showWindow()
    }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear unpinned history?"
        alert.informativeText = "Pinned entries are kept. This cannot be undone."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try store.clearHistory(keepPinned: true)
        } catch {
            presentOperationFailure(error)
        }
    }

    @objc private func unpinAll() {
        let alert = NSAlert()
        alert.messageText = "Unpin all items?"
        alert.informativeText =
            "Pinned entries become normal history and will expire per your retention setting. "
            + "Content is not deleted."
        alert.addButton(withTitle: "Unpin All")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try store.unpinAll()
        } catch {
            presentOperationFailure(error)
        }
    }

    @objc private func clearEverything() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Clear everything?"
        alert.informativeText =
            "This deletes all clipboard history, including pinned items. This cannot be undone."
        alert.addButton(withTitle: "Clear Everything")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try store.clearHistory(keepPinned: false)
        } catch {
            presentOperationFailure(error)
        }
    }

    /// Destructive history operations fail loudly (an alert), not silently
    /// (review M-3) — a swallowed failure here would let a user believe data
    /// was cleared/unpinned when it wasn't.
    private func presentOperationFailure(_ error: Error) {
        Log.store.error("history operation failed: \(error.localizedDescription)")
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Operation failed"
        alert.informativeText = error.localizedDescription
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func exportHistory() {
        ImportExportUI.runExport(store: store)
    }

    @objc private func importHistory() {
        ImportExportUI.runImport(store: store)
    }

    // MARK: - Onboarding

    private func showWelcomeIfNeeded() {
        guard !settings.didShowWelcome else { return }
        settings.didShowWelcome = true
        let alert = NSAlert()
        alert.messageText = "Permafrost is running"
        alert.informativeText = """
            Press \(settings.hotkeyPreset.display) to open your clipboard history — \
            the macOS answer to Win+V.

            Pinned entries never expire. Everything stays on this Mac.
            """
        alert.addButton(withTitle: "Got It")
        alert.addButton(withTitle: "Enable Launch at Login")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn {
            settings.launchAtLogin = true
        }
    }

    private func showAccessibilityPrompt() {
        let alert = NSAlert()
        alert.messageText = "Allow Permafrost to paste for you?"
        alert.informativeText = """
            Your selection is on the clipboard — press ⌘V to paste it.

            To make ⏎ paste directly (like Win+V), grant Permafrost Accessibility \
            permission: it is needed to press ⌘V on your behalf, nothing else.
            """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            PasteService.requestTrust()
            let url = URL(
                string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            )!
            NSWorkspace.shared.open(url)
        }
    }

    private func presentFatalError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Permafrost cannot start"
        alert.informativeText = "The clipboard database could not be opened.\n\n\(error)"
        alert.addButton(withTitle: "Quit")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        NSApp.terminate(nil)
    }
}
