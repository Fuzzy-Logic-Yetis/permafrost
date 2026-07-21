import AppKit
import PermafrostCore

enum PermafrostVersion {
    static let string = "0.3.0"
}

extension Notification.Name {
    /// Posted when Carbon rejects a shortcut and Permafrost falls back to a
    /// preset (review M-1). userInfo["failedShortcut"] is the display string
    /// of the shortcut that failed to register.
    static let hotkeyRegistrationFailed = Notification.Name("PermafrostHotkeyRegistrationFailed")
    static let ocrTextSaved = Notification.Name("PermafrostOCRTextSaved")
}

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var store: ClipboardStore!
    private var watcher: PasteboardWatcher!
    private var captureSaveQueue: CaptureSaveQueue!
    private var pasteService: PasteService!
    private var panelController: PanelController!
    private let hotkeyManager = HotkeyManager()
    private let settings = AppSettings.shared
    private lazy var hotkeyRegistrationCoordinator = HotkeyRegistrationCoordinator(
        settings: settings,
        registrar: hotkeyManager
    )
    private var cleanupTimer: Timer?
    private var settingsWindowController: SettingsWindowController?
    private var statusIconState: StatusIconState = .normal
    private var lastRegisteredHotkey: HotkeyShortcut?

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

        captureSaveQueue = CaptureSaveQueue(store: store)
        captureSaveQueue.onOCRTextSaved = { itemID in
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .ocrTextSaved,
                    object: nil,
                    userInfo: ["itemID": itemID]
                )
            }
        }
        // Never blocks launch or falls back to a throwaway key. Pending concealed captures
        // are retried only after a successfully persisted Keychain key is installed.
        ConcealedContentKeychain.loadOrCreateKey { [weak self, weak store] result in
            switch result {
            case .success(let key):
                do {
                    try store?.setConcealedContentKey(key)
                    DispatchQueue.main.async { [weak self] in
                        self?.captureSaveQueue.retryPendingConcealedCaptures()
                    }
                } catch {
                    Log.store.error("concealed-content setup failed: \(error.localizedDescription)")
                }
            case .failure(let error):
                Log.store.error("concealed-content key unavailable: \(error.localizedDescription)")
            }
        }
        pasteService = PasteService(
            store: store,
            onPasteboardWritten: { [weak self] in self?.watcher.ignoreOwnWrite() }
        )
        let model = PanelModel(store: store, pasteService: pasteService)
        model.onAccessibilityNeeded = { [weak self] in self?.showAccessibilityPrompt() }
        panelController = PanelController(model: model)

        watcher = PasteboardWatcher()
        watcher.onCapture = { [weak self] capture in
            guard let self else { return }
            self.captureSaveQueue.enqueue(
                CaptureSaveQueue.PendingCapture(
                    capture: capture,
                    capturedAt: Date(),
                    retentionPolicy: self.settings.retentionPolicy,
                    recognizeTextInImages: self.settings.recognizeTextInImages
                )
            )
        }
        watcher.start()

        HotkeyManager.requestInputMonitoringAccessIfNeeded()
        hotkeyManager.onHotkey = { [weak self] in self?.panelController.toggle() }
        registerEffectiveHotkey()
        observeSettingsChanges()
        observeFrontmostAppChanges()

        let timer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.purge() }
        }
        RunLoop.main.add(timer, forMode: .common)
        cleanupTimer = timer

        setupStatusItem()
        showWelcomeIfNeeded()
        Log.app.info("Permafrost \(PermafrostVersion.string, privacy: .public) started")
    }

    func applicationWillTerminate(_ notification: Notification) {
        prepareForShutdown()
    }

    static func databaseURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Permafrost/store.sqlite")
    }

    private func prepareForShutdown() {
        watcher?.stop()
        guard let captureSaveQueue else { return }
        if !captureSaveQueue.waitUntilIdle(timeout: 2.0) {
            Log.capture.error("timed out waiting for pending captures before shutdown")
        }
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
                if self.settings.effectiveHotkey != self.lastRegisteredHotkey {
                    self.registerEffectiveHotkey()
                }
                self.refreshCaptureIndicatorState()
            }
        }
    }

    /// Registers the currently configured hotkey; if Carbon rejects it (review
    /// M-1 — e.g. a reserved or already-claimed combination), rolls back to the
    /// previous working shortcut and tells Settings why.
    private func registerEffectiveHotkey() {
        hotkeyRegistrationCoordinator.registerEffectiveHotkey { failedDisplay in
            Log.app.error("hotkey \(failedDisplay, privacy: .public) rejected; rolling back")
            NotificationCenter.default.post(
                name: .hotkeyRegistrationFailed,
                object: nil,
                userInfo: ["failedShortcut": failedDisplay]
            )
        }
        lastRegisteredHotkey = settings.effectiveHotkey
        refreshOpenMenuItemTitle()
    }

    private func observeFrontmostAppChanges() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshCaptureIndicatorState() }
        }
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        let image = statusIconImage(for: .normal)
        statusItem.button?.image = image
        statusItem.button?.imagePosition = .imageOnly
        statusItem.isVisible = true
        Log.app.info("status item set up; image loaded: \(image != nil)")
        refreshCaptureIndicatorState()

        let menu = NSMenu()
        let openItem = NSMenuItem(
            title: "Open Permafrost  (\(settings.hotkeyDisplay))",
            action: #selector(openPanel), keyEquivalent: "")
        openItem.target = self
        openItem.tag = MenuTag.open.rawValue
        menu.addItem(openItem)

        let captureItem = NSMenuItem(
            title: "Pause Capture", action: #selector(toggleCapturePaused), keyEquivalent: "")
        captureItem.target = self
        captureItem.tag = MenuTag.capturePaused.rawValue
        captureItem.state = settings.capturePaused ? .on : .off
        menu.addItem(captureItem)
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
        let restartItem = NSMenuItem(
            title: "Restart Permafrost", action: #selector(restartApp), keyEquivalent: "r")
        restartItem.target = self
        menu.addItem(restartItem)

        let quitItem = NSMenuItem(
            title: "Quit Permafrost",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        menu.addItem(quitItem)

        // macOS auto-decorates items whose title/selector match standard system commands
        // (found 2026-07-21: "Settings…"+⌘, and "Quit …"+terminate: silently got a gear/power
        // glyph neither of us set) while every other item stays icon-less, so the reserved
        // icon gutter only shows up under some rows and the menu reads as misaligned. Claiming
        // every item's image slot with an explicit blank placeholder overrides that decoration
        // menu-wide instead of fighting it item by item.
        let blankIcon = NSImage(size: NSSize(width: 16, height: 16))
        for item in menu.items where !item.isSeparatorItem {
            item.image = blankIcon
        }

        statusItem.menu = menu
    }

    private enum MenuTag: Int {
        case open = 1
        case capturePaused = 2
    }

    private enum StatusIconState: Equatable {
        case normal
        case paused
        case excluded

        var tint: NSColor? {
            switch self {
            case .normal: nil
            case .paused: .systemOrange
            case .excluded: .systemPurple
            }
        }
    }

    private func refreshOpenMenuItemTitle() {
        statusItem?.menu?.item(withTag: MenuTag.open.rawValue)?.title =
            "Open Permafrost  (\(settings.hotkeyDisplay))"
    }

    private func refreshCaptureIndicatorState() {
        statusItem?.menu?.item(withTag: MenuTag.capturePaused.rawValue)?.state =
            settings.capturePaused ? .on : .off

        let newState: StatusIconState
        if settings.capturePaused {
            newState = .paused
        } else if settings.isExcluded(
            bundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        {
            newState = .excluded
        } else {
            newState = .normal
        }

        guard newState != statusIconState else { return }
        statusIconState = newState
        statusItem?.button?.image = statusIconImage(for: newState)
        statusItem?.button?.contentTintColor = newState.tint
    }

    private func statusIconImage(for state: StatusIconState) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        guard let image = NSImage(systemSymbolName: "snowflake", accessibilityDescription: "Permafrost")?
            .withSymbolConfiguration(config)
        else { return nil }

        guard let tint = state.tint else {
            image.isTemplate = true
            return image
        }

        let tinted = NSImage(size: image.size)
        tinted.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: image.size))
        tint.set()
        NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        tinted.isTemplate = false
        return tinted
    }

    @objc private func toggleCapturePaused() {
        settings.capturePaused.toggle()
        refreshCaptureIndicatorState()
    }

    @objc private func openPanel() {
        panelController.show()
    }

    @objc private func restartApp() {
        let bundleURL = Bundle.main.bundleURL
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "sleep 0.4; /usr/bin/open \"$0\"",
            bundleURL.path,
        ]
        do {
            prepareForShutdown()
            try process.run()
            NSApp.terminate(nil)
        } catch {
            presentOperationFailure(error)
        }
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
            // Navigate only — calling PasteService.requestTrust() here too would fire
            // the native system prompt on top of this navigation (redundant double-popup,
            // found 2026-07-07). PasteService.isTrusted is already checked elsewhere,
            // which is enough to get Permafrost listed in System Settings.
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
