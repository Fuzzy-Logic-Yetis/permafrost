import AppKit
import PermafrostCore

enum PermafrostVersion {
    static let string = "0.1.0"
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
        statusItem.button?.image = NSImage(
            systemSymbolName: "snowflake", accessibilityDescription: "Permafrost")

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
            settingsWindowController = SettingsWindowController()
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
        if alert.runModal() == .alertFirstButtonReturn {
            try? store.clearHistory(keepPinned: true)
        }
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
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
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
