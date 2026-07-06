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

            try ImportExport.exportArchive(from: store, to: staging)
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

            let imported = try ImportExport.importArchive(from: directory, into: store)
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
