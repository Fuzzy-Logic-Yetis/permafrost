import AppKit
import SwiftUI

/// Bridges NSSharingServicePicker — the same share sheet macOS's own screenshot
/// panel uses — into SwiftUI, which has no native picker API on macOS.
extension Notification.Name {
    static let sharePickerWillOpen = Notification.Name("PermafrostSharePickerWillOpen")
    static let sharePickerDidClose = Notification.Name("PermafrostSharePickerDidClose")
}

struct ShareButton: NSViewRepresentable {
    let items: [Any]
    var onPresentationChanged: (Bool) -> Void = { _ in }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(
            image: NSImage(
                systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Share")!,
            target: context.coordinator,
            action: #selector(Coordinator.share(_:))
        )
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = .secondaryLabelColor
        context.coordinator.button = button
        context.coordinator.items = items
        context.coordinator.onPresentationChanged = onPresentationChanged
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.items = items
        context.coordinator.onPresentationChanged = onPresentationChanged
        nsView.isEnabled = !items.isEmpty
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator: NSObject {
        var items: [Any] = []
        var onPresentationChanged: (Bool) -> Void = { _ in }
        weak var button: NSButton?
        private var picker: NSSharingServicePicker?

        @objc func share(_ sender: NSButton) {
            guard !items.isEmpty else { return }
            onPresentationChanged(true)
            NotificationCenter.default.post(name: .sharePickerWillOpen, object: nil)
            let picker = NSSharingServicePicker(items: items)
            picker.delegate = self
            self.picker = picker
            picker.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }

        private func finishSharing() {
            picker = nil
            onPresentationChanged(false)
            NotificationCenter.default.post(name: .sharePickerDidClose, object: nil)
        }
    }
}

extension ShareButton.Coordinator: @preconcurrency NSSharingServicePickerDelegate {
    func sharingServicePicker(
        _ sharingServicePicker: NSSharingServicePicker,
        didChoose service: NSSharingService?
    ) {
        finishSharing()
    }
}
