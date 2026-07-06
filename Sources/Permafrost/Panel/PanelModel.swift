import Foundation
import PermafrostCore
import SwiftUI

/// View state for the panel. All mutations funnel through here; the view is dumb.
@MainActor
final class PanelModel: ObservableObject {
    @Published var query = "" {
        didSet { if query != oldValue { reload(resetSelection: true) } }
    }
    @Published private(set) var items: [ClipboardItem] = []
    @Published private(set) var selectedIndex = 0
    /// Bumped on every show so the view can re-focus the search field.
    @Published private(set) var focusToken = UUID()

    var onCommit: () -> Void = {}
    var onAccessibilityNeeded: () -> Void = {}

    private let store: ClipboardStore
    private let pasteService: PasteService

    init(store: ClipboardStore, pasteService: PasteService) {
        self.store = store
        self.pasteService = pasteService
    }

    var selectedItem: ClipboardItem? {
        items.indices.contains(selectedIndex) ? items[selectedIndex] : nil
    }

    func prepareForShow() {
        query = ""
        reload(resetSelection: true)
        focusToken = UUID()
    }

    func reload(resetSelection: Bool = false) {
        do {
            items = try store.items(matching: query, limit: 200)
        } catch {
            Log.store.error("reload failed: \(error.localizedDescription)")
            items = []
        }
        if resetSelection || selectedIndex >= items.count {
            selectedIndex = 0
        }
    }

    func moveSelection(by delta: Int) {
        guard !items.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), items.count - 1)
    }

    func select(index: Int) {
        guard items.indices.contains(index) else { return }
        selectedIndex = index
    }

    func commitSelection() {
        commit(index: selectedIndex)
    }

    func commit(index: Int) {
        guard items.indices.contains(index) else { return }
        let item = items[index]
        onCommit()  // close the panel first so focus is back in the target app
        if !pasteService.paste(item) {
            onAccessibilityNeeded()
        }
    }

    func togglePinSelected() {
        guard let item = selectedItem, let id = item.id else { return }
        try? store.setPinned(!item.isPinned, id: id)
        reload()
    }

    func deleteSelected() {
        guard let item = selectedItem, let id = item.id else { return }
        try? store.delete(id: id)
        reload()
        if selectedIndex >= items.count {
            selectedIndex = max(items.count - 1, 0)
        }
    }
}
