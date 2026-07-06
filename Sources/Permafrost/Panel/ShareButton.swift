import AppKit
import SwiftUI

/// Bridges NSSharingServicePicker — the same share sheet macOS's own screenshot
/// panel uses — into SwiftUI, which has no native picker API on macOS.
struct ShareButton: NSViewRepresentable {
    let items: [Any]

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
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.items = items
        nsView.isEnabled = !items.isEmpty
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        var items: [Any] = []
        weak var button: NSButton?

        @objc func share(_ sender: NSButton) {
            guard !items.isEmpty else { return }
            let picker = NSSharingServicePicker(items: items)
            picker.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }
}
