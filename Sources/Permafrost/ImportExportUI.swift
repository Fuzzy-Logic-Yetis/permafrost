import AppKit
import PermafrostCore
import UniformTypeIdentifiers

/// Save/open panels + zip handling around core's directory-based archive format.
/// Zipping uses /usr/bin/ditto — present on every macOS install, no dependency.
@MainActor
enum ImportExportUI {
    struct ToolError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func runExport(store: ClipboardStore) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.zip]
        savePanel.nameFieldStringValue = "permafrost-export-\(dateStamp()).zip"
        NSApp.activate(ignoringOtherApps: true)
        guard savePanel.runModal() == .OK, let destination = savePanel.url else { return }

        do {
            let staging = FileManager.default.temporaryDirectory
                .appendingPathComponent("permafrost-export-\(UUID().uuidString)")
            try FileManager.default.createDirectory(
                at: staging, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: staging) }

            let portable = chooseExportKind()
            guard let portable else { return }
            if portable {
                guard let passphrase = promptForPassphrase(confirm: true) else { return }
                try PortableArchive.exportArchive(from: store, to: staging, passphrase: passphrase)
            } else {
                try ImportExport.exportArchive(from: store, to: staging)
            }
            try? FileManager.default.removeItem(at: destination)
            try runDitto(["-c", "-k", staging.path, destination.path])
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch {
            presentError(title: "Export failed", error: error)
        }
    }

    static func runImport(store: ClipboardStore) {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.allowedContentTypes = [.zip, .folder]
        openPanel.message = "Choose a Permafrost export (.zip or unpacked folder)"
        NSApp.activate(ignoringOtherApps: true)
        guard openPanel.runModal() == .OK, let source = openPanel.url else { return }

        do {
            var directory = source
            var staging: URL?
            if source.pathExtension.lowercased() == "zip" {
                let unpacked = FileManager.default.temporaryDirectory
                    .appendingPathComponent("permafrost-import-\(UUID().uuidString)")
                try runDitto(["-x", "-k", source.path, unpacked.path])
                staging = unpacked
                directory = unpacked
            }
            defer { if let staging { try? FileManager.default.removeItem(at: staging) } }

            let imported: Int
            if try PortableArchive.requiresPassphrase(at: directory) {
                guard let passphrase = promptForPassphrase(confirm: false) else { return }
                imported = try PortableArchive.importArchive(
                    from: directory, into: store, passphrase: passphrase)
            } else {
                imported = try ImportExport.importArchive(from: directory, into: store)
            }
            let alert = NSAlert()
            alert.messageText = "Import complete"
            alert.informativeText =
                imported == 1
                ? "1 entry imported." : "\(imported) entries imported (existing content skipped)."
            alert.runModal()
        } catch {
            presentError(title: "Import failed", error: error)
        }
    }

    /// `true` selects a portable backup; `false` retains the existing same-Mac archive.
    private static func chooseExportKind() -> Bool? {
        let alert = NSAlert()
        alert.messageText = "Export Clipboard History"
        alert.informativeText = "Portable backups require a passphrase and can be imported on another Mac. This Mac Only backups keep concealed entries tied to this Mac's Keychain."
        alert.addButton(withTitle: "Portable Encrypted Backup")
        alert.addButton(withTitle: "This Mac Only")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return true
        case .alertSecondButtonReturn: return false
        default: return nil
        }
    }

    private static func promptForPassphrase(confirm: Bool) -> String? {
        let alert = NSAlert()
        alert.messageText = confirm ? "Protect Portable Backup" : "Unlock Portable Backup"
        alert.informativeText = confirm
            ? "Choose a passphrase with at least 12 characters. It cannot be recovered."
            : "Enter the passphrase used when this backup was created."
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        let passphrase = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        passphrase.placeholderString = "Passphrase"
        stack.addArrangedSubview(passphrase)
        let confirmation = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        if confirm {
            confirmation.placeholderString = "Confirm passphrase"
            stack.addArrangedSubview(confirmation)
        }
        alert.accessoryView = stack
        alert.addButton(withTitle: confirm ? "Export" : "Import")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = passphrase.stringValue
        guard !confirm || value == confirmation.stringValue else {
            let mismatch = NSAlert()
            mismatch.messageText = "Passphrases do not match"
            mismatch.runModal()
            return nil
        }
        return value
    }

    private static func runDitto(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ToolError(message: "ditto exited with status \(process.terminationStatus)")
        }
    }

    private static func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private static func presentError(title: String, error: Error) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
