import AppKit
import Carbon.HIToolbox
import PermafrostCore
import SwiftUI

struct SettingsView: View {
    let store: ClipboardStore

    @AppStorage(AppSettings.Keys.retentionDays) private var retentionDays = 30
    @AppStorage(AppSettings.Keys.maxUnpinnedCount) private var maxUnpinnedCount = 2000
    @AppStorage(AppSettings.Keys.hotkeyPreset) private var hotkeyPreset =
        HotkeyPreset.optionCommandV.rawValue
    @AppStorage(AppSettings.Keys.capturePaused) private var capturePaused = false
    @AppStorage(AppSettings.Keys.recordConcealed) private var recordConcealed = false
    @AppStorage(AppSettings.Keys.maxImageMegabytes) private var maxImageMegabytes = 10
    @AppStorage(AppSettings.Keys.recognizeTextInImages) private var recognizeTextInImages = true

    @State private var launchAtLogin = AppSettings.shared.launchAtLogin
    @State private var showConcealedWarning = false
    @State private var accessibilityTrusted = PasteService.isTrusted
    @State private var inputMonitoringGranted = HotkeyManager.isInputMonitoringGranted
    @State private var showUnpinAllConfirm = false
    @State private var showClearUnpinnedConfirm = false
    @State private var showClearEverythingConfirm = false
    @State private var showResetPermissionsConfirm = false
    @State private var customHotkey = AppSettings.shared.customHotkey
    @State private var isRecordingHotkey = false
    @State private var hotkeyRecorderMessage: String?
    @State private var hotkeyRecorderMessageIsError = false
    @State private var pinnedCount = 0
    @State private var totalCount = 0
    @State private var excludedApps = AppSettings.shared.excludedApps
    @State private var operationErrorMessage: String?

    private let trustPoll = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    private let hotkeyRegistrationFailed = NotificationCenter.default.publisher(
        for: .hotkeyRegistrationFailed)

    private var imagesSection: some View {
        Section {
            Picker("Skip images larger than", selection: $maxImageMegabytes) {
                Text("5 MB").tag(5)
                Text("10 MB").tag(10)
                Text("25 MB").tag(25)
                Text("50 MB").tag(50)
            }
            Toggle("Recognize text in images", isOn: $recognizeTextInImages)
        } header: {
            Text("Images")
        } footer: {
            Text(
                "OCR runs locally with Apple's Vision framework. Recognized text is stored, searchable, shown in preview, and included in exports with the image."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    var body: some View {
        Form {
            Section("General") {
                Picker("Open panel with", selection: $hotkeyPreset) {
                    ForEach(HotkeyPreset.allCases, id: \.rawValue) { preset in
                        Text(preset.display).tag(preset.rawValue)
                    }
                }
                .onChange(of: hotkeyPreset) {
                    AppSettings.shared.customHotkey = nil
                    customHotkey = nil
                    isRecordingHotkey = false
                    hotkeyRecorderMessage = nil
                    hotkeyRecorderMessageIsError = false
                }
                LabeledContent("Active hotkey") {
                    Text(AppSettings.shared.hotkeyDisplay)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(customHotkey == nil ? .secondary : .primary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button(isRecordingHotkey ? "Press Shortcut…" : "Record Custom…") {
                            isRecordingHotkey = true
                            hotkeyRecorderMessage = "Press a key with ⌘, ⌥, or ⌃. Esc cancels."
                            hotkeyRecorderMessageIsError = false
                        }
                        .disabled(isRecordingHotkey)

                        if isRecordingHotkey {
                            Button("Cancel") {
                                isRecordingHotkey = false
                                hotkeyRecorderMessage = nil
                                hotkeyRecorderMessageIsError = false
                            }
                        }

                        if customHotkey != nil {
                            Button("Use Selected Preset") {
                                AppSettings.shared.customHotkey = nil
                                customHotkey = nil
                                isRecordingHotkey = false
                                hotkeyRecorderMessage = nil
                                hotkeyRecorderMessageIsError = false
                            }
                        }

                        Button("Reset to Default") {
                            hotkeyPreset = HotkeyPreset.optionCommandV.rawValue
                            AppSettings.shared.customHotkey = nil
                            customHotkey = nil
                            isRecordingHotkey = false
                            hotkeyRecorderMessage = nil
                            hotkeyRecorderMessageIsError = false
                        }
                        .disabled(
                            customHotkey == nil && hotkeyPreset == HotkeyPreset.optionCommandV.rawValue
                        )
                    }

                    if let hotkeyRecorderMessage {
                        Text(hotkeyRecorderMessage)
                            .font(.caption)
                            .foregroundStyle(hotkeyRecorderMessageIsError ? .red : .secondary)
                    }

                    HotkeyRecorderField(
                        isRecording: $isRecordingHotkey,
                        onRecord: { shortcut in
                            AppSettings.shared.customHotkey = shortcut
                            customHotkey = shortcut
                            isRecordingHotkey = false
                            hotkeyRecorderMessage = "Recorded custom shortcut: \(shortcut.display)"
                            hotkeyRecorderMessageIsError = false
                        },
                        onCancel: {
                            isRecordingHotkey = false
                            hotkeyRecorderMessage = nil
                            hotkeyRecorderMessageIsError = false
                        },
                        onInvalid: {
                            hotkeyRecorderMessage = "Use at least one of ⌘, ⌥, or ⌃ so the shortcut is safe globally."
                            hotkeyRecorderMessageIsError = true
                        }
                    )
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) {
                        AppSettings.shared.launchAtLogin = launchAtLogin
                    }
                Toggle("Pause capture", isOn: $capturePaused)
            }

            Section {
                Text(
                    capturePaused
                        ? "Clipboard changes are ignored until you resume capture."
                        : "Use the menu bar toggle to temporarily stop recording clipboard changes."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                Picker("Unpinned entries expire after", selection: $retentionDays) {
                    Text("1 day").tag(1)
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("Never").tag(0)
                }
                Picker("Keep at most", selection: $maxUnpinnedCount) {
                    Text("500 entries").tag(500)
                    Text("2,000 entries").tag(2000)
                    Text("10,000 entries").tag(10000)
                    Text("Unlimited").tag(0)
                }
            } header: {
                Text("Retention")
            } footer: {
                Text("Pinned entries never expire — that's the whole point.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            imagesSection

            Section {
                Toggle("Record concealed content (passwords)", isOn: concealedBinding)
                    .alert("Record passwords in clipboard history?", isPresented: $showConcealedWarning) {
                        Button("Cancel", role: .cancel) {}
                        Button("I Understand the Risk") { recordConcealed = true }
                    } message: {
                        Text(
                            """
                            Passwords you copy will be stored in plain text in Permafrost's \
                            local database, will appear in the history panel, can be pinned, \
                            and will be included in exports. Anyone with access to this Mac \
                            user account can read them.
                            """
                        )
                    }
            } header: {
                Text("Privacy")
            } footer: {
                Text("Recorded passwords are marked with a key icon in the panel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(excludedApps) { app in
                    HStack {
                        Text(app.displayName)
                        Spacer()
                        Button("Remove") { removeExcludedApp(app) }
                            .buttonStyle(.borderless)
                    }
                }
                Button("Add App…") { addExcludedApp() }
            } header: {
                Text("Excluded Apps")
            } footer: {
                Text("Clipboard content copied while one of these apps is frontmost is never recorded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Accessibility (paste-on-select)") {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(accessibilityTrusted ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(accessibilityTrusted ? "Granted" : "Not granted")
                            .foregroundStyle(.secondary)
                        if !accessibilityTrusted {
                            // Navigate only — don't also call requestTrust() here, or the
                            // native system prompt and this navigation both fire at once
                            // (confusing double-popup, found 2026-07-07). The passive
                            // isTrusted check elsewhere already gets Permafrost listed.
                            Button("Open System Settings") {
                                NSWorkspace.shared.open(
                                    URL(
                                        string:
                                            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                                    )!)
                            }
                        }
                    }
                }
                LabeledContent("Input Monitoring (global hotkey)") {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(inputMonitoringGranted ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(inputMonitoringGranted ? "Granted" : "Not granted")
                            .foregroundStyle(.secondary)
                        if !inputMonitoringGranted {
                            Button("Open System Settings") {
                                NSWorkspace.shared.open(
                                    URL(
                                        string:
                                            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
                                    )!)
                            }
                        }
                    }
                }
                Button("Reset Permissions…") { showResetPermissionsConfirm = true }
            } header: {
                Text("Permissions")
            } footer: {
                Text(
                    "Rebuilding Permafrost from source changes its code signature, which can "
                        + "leave System Settings showing a permission as granted when it no "
                        + "longer matches — reset clears the stale record so you can re-grant it."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("Clear Unpinned History…") { showClearUnpinnedConfirm = true }
                    Button("Unpin All…") { showUnpinAllConfirm = true }
                    Spacer()
                    Button("Clear Everything…", role: .destructive) {
                        showClearEverythingConfirm = true
                    }
                }
            } header: {
                Text("History Management")
            } footer: {
                Text("\(totalCount) items, \(pinnedCount) pinned")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .onReceive(trustPoll) { _ in
            accessibilityTrusted = PasteService.isTrusted
            inputMonitoringGranted = HotkeyManager.isInputMonitoringGranted
        }
        .onReceive(hotkeyRegistrationFailed) { notification in
            let failedDisplay = notification.userInfo?["failedShortcut"] as? String ?? "that shortcut"
            customHotkey = AppSettings.shared.customHotkey
            hotkeyPreset = AppSettings.shared.hotkeyPreset.rawValue
            isRecordingHotkey = false
            hotkeyRecorderMessage =
                "\(failedDisplay) couldn't be registered (already in use elsewhere) — "
                + "reverted to \(AppSettings.shared.hotkeyDisplay)."
            hotkeyRecorderMessageIsError = true
        }
        .onAppear { refreshCounts() }
        .alert("Clear unpinned history?", isPresented: $showClearUnpinnedConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                runHistoryOperation { try store.clearHistory(keepPinned: true) }
            }
        } message: {
            Text("Pinned entries are kept. This cannot be undone.")
        }
        .alert("Unpin all items?", isPresented: $showUnpinAllConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Unpin All") {
                runHistoryOperation { try store.unpinAll() }
            }
        } message: {
            Text(
                "Pinned entries become normal history and will expire per your retention "
                    + "setting above. Content is not deleted."
            )
        }
        .alert("Clear everything?", isPresented: $showClearEverythingConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Everything", role: .destructive) {
                runHistoryOperation { try store.clearHistory(keepPinned: false) }
            }
        } message: {
            Text("This deletes all clipboard history, including pinned items. This cannot be undone.")
        }
        .alert(
            "Operation failed",
            isPresented: Binding(
                get: { operationErrorMessage != nil },
                set: { if !$0 { operationErrorMessage = nil } }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(operationErrorMessage ?? "")
        }
        .alert("Reset permissions?", isPresented: $showResetPermissionsConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reset") {
                Task {
                    await PermissionReset.resetAccessibilityAndInputMonitoring()
                    accessibilityTrusted = PasteService.isTrusted
                    inputMonitoringGranted = HotkeyManager.isInputMonitoringGranted
                }
            }
        } message: {
            Text(
                "Clears Permafrost's Accessibility and Input Monitoring grants. You'll need "
                    + "to re-enable them above afterward — paste-on-select and the global "
                    + "hotkey fall back to degraded modes until you do."
            )
        }
    }

    private func refreshCounts() {
        totalCount = (try? store.count()) ?? 0
        pinnedCount = (try? store.pinnedCount()) ?? 0
    }

    /// Shared error path for destructive history actions (review M-3) — matches
    /// the status-menu behavior in App.swift so a failure never looks like success.
    private func runHistoryOperation(_ operation: () throws -> Void) {
        do {
            try operation()
        } catch {
            Log.store.error("history operation failed: \(error.localizedDescription)")
            operationErrorMessage = error.localizedDescription
        }
        refreshCounts()
    }

    private func addExcludedApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url,
            let bundleID = Bundle(url: url)?.bundleIdentifier
        else { return }
        let name = FileManager.default.displayName(atPath: url.path)
        AppSettings.shared.addExcludedApp(ExcludedApp(bundleID: bundleID, displayName: name))
        excludedApps = AppSettings.shared.excludedApps
    }

    private func removeExcludedApp(_ app: ExcludedApp) {
        AppSettings.shared.removeExcludedApp(bundleID: app.bundleID)
        excludedApps = AppSettings.shared.excludedApps
    }

    /// Turning the toggle ON routes through the risk acknowledgment (ADR-011);
    /// turning it OFF is immediate.
    private var concealedBinding: Binding<Bool> {
        Binding(
            get: { recordConcealed },
            set: { newValue in
                if newValue {
                    showConcealedWarning = true
                } else {
                    recordConcealed = false
                }
            }
        )
    }
}

private struct HotkeyRecorderField: NSViewRepresentable {
    @Binding var isRecording: Bool
    var onRecord: (HotkeyShortcut) -> Void
    var onCancel: () -> Void
    var onInvalid: () -> Void

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onRecord = onRecord
        view.onCancel = onCancel
        view.onInvalid = onInvalid
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.onRecord = onRecord
        view.onCancel = onCancel
        view.onInvalid = onInvalid
        view.isRecording = isRecording
        if isRecording {
            DispatchQueue.main.async {
                view.window?.makeFirstResponder(view)
            }
        }
    }

    final class RecorderView: NSView {
        var isRecording = false
        var onRecord: (HotkeyShortcut) -> Void = { _ in }
        var onCancel: () -> Void = {}
        var onInvalid: () -> Void = {}

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            guard isRecording else {
                super.keyDown(with: event)
                return
            }

            if Int(event.keyCode) == kVK_Escape {
                onCancel()
                return
            }

            guard let shortcut = HotkeyShortcut.fromEvent(
                keyCode: event.keyCode,
                modifiers: event.modifierFlags
            ) else {
                onInvalid()
                return
            }
            onRecord(shortcut)
        }
    }
}
