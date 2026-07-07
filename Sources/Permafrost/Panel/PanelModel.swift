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
    /// Quick-look style: shows the full text/image of `selectedItem`. Follows
    /// selection changes rather than pinning to one item.
    @Published private(set) var isPreviewShown = false

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
        isPreviewShown = false
        reload(resetSelection: true)
        focusToken = UUID()
    }

    func togglePreview() {
        guard selectedItem != nil else { return }
        isPreviewShown.toggle()
    }

    func closePreview() {
        isPreviewShown = false
    }

    /// The panel loads at most this many rows; `countLabel` reflects that cap
    /// rather than implying it's showing your entire history (review L-1).
    static let pageLimit = 200

    func reload(resetSelection: Bool = false) {
        do {
            items = try store.items(matching: query, limit: Self.pageLimit)
        } catch {
            Log.store.error("reload failed: \(error.localizedDescription)")
            items = []
        }
        if resetSelection || selectedIndex >= items.count {
            selectedIndex = 0
        }
    }

    var countLabel: String {
        items.count >= Self.pageLimit ? "\(Self.pageLimit)+" : "\(items.count)"
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

    /// `⌘1`–`⌘9` address only the recent (unpinned) section (ADR-012) — computed
    /// from the live unpinned prefix rather than assumed, so pinning something can
    /// never cause a number key to paste it as if it were your latest copy.
    func commitQuickPaste(number: Int) {
        let recentCount = items.prefix(while: { !$0.isPinned }).count
        guard (1...9).contains(number), number <= recentCount else { return }
        commit(index: number - 1)
    }

    func togglePinSelected() {
        guard let id = selectedItem?.id else { return }
        togglePin(id: id)
    }

    func deleteSelected() {
        guard let id = selectedItem?.id else { return }
        deleteItem(id: id)
    }

    /// Used by both the keyboard shortcut (via *Selected above) and the per-card
    /// hover buttons, which act on whichever item the mouse is over, not the
    /// keyboard selection.
    func togglePin(id: Int64) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        do {
            try store.setPinned(!item.isPinned, id: id)
        } catch {
            // Panel actions stay non-blocking (no alert) — logged so a failing
            // database is still diagnosable, per docs/DECISIONS.md ADR-012 review.
            Log.store.error("pin toggle failed: \(error.localizedDescription)")
        }
        reload()
    }

    func deleteItem(id: Int64) {
        do {
            try store.delete(id: id)
        } catch {
            Log.store.error("delete failed: \(error.localizedDescription)")
        }
        reload()
        if selectedIndex >= items.count {
            selectedIndex = max(items.count - 1, 0)
        }
    }
}
