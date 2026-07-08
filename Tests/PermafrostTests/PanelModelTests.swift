import Foundation
import Testing

import PermafrostCore
@testable import Permafrost

@MainActor
@Suite struct PanelModelTests {
    let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func makeModel(pasteResult: Bool = true) throws -> (
        ClipboardStore, PanelModel, FakePasteService
    ) {
        let store = try ClipboardStore.inMemory()
        let pasteService = FakePasteService(result: pasteResult)
        let model = PanelModel(store: store, pasteService: pasteService)
        return (store, model, pasteService)
    }

    @Test func prepareForShowResetsQuerySelectionAndRefocuses() throws {
        let (store, model, _) = try makeModel()
        try store.save(ClipboardCapture(text: "first"), now: now)
        try store.save(ClipboardCapture(text: "second"), now: now.addingTimeInterval(1))
        model.prepareForShow()
        model.moveSelection(by: 1)
        model.togglePreview()
        model.query = "first"
        let focusBefore = model.focusToken

        model.prepareForShow()

        #expect(model.query == "")
        #expect(model.selectedIndex == 0)
        #expect(model.items.map(\.text) == ["second", "first"])
        #expect(model.isPreviewShown == false)
        #expect(model.focusToken != focusBefore)
    }

    @Test func previewTogglesAndFollowsSelectedItem() throws {
        let (store, model, _) = try makeModel()
        try store.save(ClipboardCapture(text: "older"), now: now)
        try store.save(ClipboardCapture(text: "newer"), now: now.addingTimeInterval(1))
        model.prepareForShow()

        model.togglePreview()
        #expect(model.isPreviewShown == true)
        #expect(model.selectedItem?.text == "newer")

        model.moveSelection(by: 1)
        #expect(model.isPreviewShown == true)
        #expect(model.selectedItem?.text == "older")

        model.togglePreview()
        #expect(model.isPreviewShown == false)
    }

    @Test func searchReloadsAndClampsSelection() throws {
        let (store, model, _) = try makeModel()
        try store.save(ClipboardCapture(text: "alpha"), now: now)
        try store.save(ClipboardCapture(text: "beta"), now: now.addingTimeInterval(1))
        try store.save(ClipboardCapture(text: "alphabet"), now: now.addingTimeInterval(2))
        model.prepareForShow()
        model.moveSelection(by: 2)

        model.query = "alph"

        #expect(model.selectedIndex == 0)
        #expect(model.items.map(\.text) == ["alphabet", "alpha"])
    }

    @Test func moveAndSelectClampToAvailableItems() throws {
        let (store, model, _) = try makeModel()
        try store.save(ClipboardCapture(text: "a"), now: now)
        try store.save(ClipboardCapture(text: "b"), now: now.addingTimeInterval(1))
        model.prepareForShow()

        model.moveSelection(by: 99)
        #expect(model.selectedIndex == 1)

        model.moveSelection(by: -99)
        #expect(model.selectedIndex == 0)

        model.select(index: 1)
        #expect(model.selectedItem?.text == "a")

        model.select(index: 99)
        #expect(model.selectedIndex == 1)
    }

    @Test func quickPasteAddressesOnlyUnpinnedPrefix() throws {
        let (store, model, pasteService) = try makeModel()
        let pinned = try store.save(ClipboardCapture(text: "pinned"), now: now)
        try store.setPinned(true, id: pinned.id!)
        try store.save(ClipboardCapture(text: "recent one"), now: now.addingTimeInterval(1))
        try store.save(ClipboardCapture(text: "recent two"), now: now.addingTimeInterval(2))
        model.prepareForShow()

        model.commitQuickPaste(number: 1)
        model.commitQuickPaste(number: 2)
        model.commitQuickPaste(number: 3)
        model.commitQuickPaste(number: 0)
        model.commitQuickPaste(number: 10)

        #expect(pasteService.pastedTexts == ["recent two", "recent one"])
    }

    @Test func quickPasteWhilePreviewShownStillAddressesRecentPrefix() throws {
        let (store, model, pasteService) = try makeModel()
        let pinned = try store.save(ClipboardCapture(text: "pinned"), now: now)
        try store.setPinned(true, id: pinned.id!)
        try store.save(ClipboardCapture(text: "recent"), now: now.addingTimeInterval(1))
        model.prepareForShow()
        model.select(index: 1)
        model.togglePreview()

        model.commitQuickPaste(number: 1)
        model.commitQuickPaste(number: 2)

        #expect(model.isPreviewShown == true)
        #expect(model.selectedItem?.text == "pinned")
        #expect(pasteService.pastedTexts == ["recent"])
    }

    @Test func commitClosesBeforePasteAndReportsAccessibilityFallback() throws {
        let (store, model, pasteService) = try makeModel(pasteResult: false)
        try store.save(ClipboardCapture(text: "needs accessibility"), now: now)
        var events: [String] = []
        model.onCommit = { events.append("close") }
        model.onAccessibilityNeeded = { events.append("accessibility") }
        pasteService.onPaste = { events.append("paste") }
        model.prepareForShow()

        model.commitSelection()

        #expect(pasteService.pastedTexts == ["needs accessibility"])
        #expect(events == ["close", "paste", "accessibility"])
    }

    @Test func commitWhilePreviewShownPastesSelectedItem() throws {
        let (store, model, pasteService) = try makeModel()
        try store.save(ClipboardCapture(text: "not selected"), now: now)
        try store.save(ClipboardCapture(text: "previewed"), now: now.addingTimeInterval(1))
        var didClose = false
        model.onCommit = { didClose = true }
        model.prepareForShow()
        model.togglePreview()

        model.commitSelection()

        #expect(didClose == true)
        #expect(model.isPreviewShown == true)
        #expect(pasteService.pastedTexts == ["previewed"])
    }

    @Test func togglePinSelectedMovesItemToPinnedSection() throws {
        let (store, model, _) = try makeModel()
        try store.save(ClipboardCapture(text: "older"), now: now)
        try store.save(ClipboardCapture(text: "newer"), now: now.addingTimeInterval(1))
        model.prepareForShow()
        model.select(index: 1)

        model.togglePinSelected()

        #expect(model.items.map(\.text) == ["newer", "older"])
        #expect(model.items[0].isPinned == false)
        #expect(model.items[1].isPinned == true)
        #expect(try store.pinnedCount() == 1)
    }

    @Test func togglePinWhilePreviewShownKeepsPreviewedItemSelected() throws {
        let (store, model, _) = try makeModel()
        try store.save(ClipboardCapture(text: "older"), now: now)
        try store.save(ClipboardCapture(text: "previewed"), now: now.addingTimeInterval(1))
        model.prepareForShow()
        model.togglePreview()

        model.togglePinSelected()

        #expect(model.isPreviewShown == true)
        #expect(model.items.map(\.text) == ["older", "previewed"])
        #expect(model.selectedItem?.text == "previewed")
        #expect(model.selectedItem?.isPinned == true)
    }

    @Test func deleteSelectedReloadsAndKeepsSelectionInBounds() throws {
        let (store, model, _) = try makeModel()
        try store.save(ClipboardCapture(text: "oldest"), now: now)
        try store.save(ClipboardCapture(text: "middle"), now: now.addingTimeInterval(1))
        try store.save(ClipboardCapture(text: "newest"), now: now.addingTimeInterval(2))
        model.prepareForShow()
        model.select(index: 2)

        model.deleteSelected()

        #expect(model.items.map(\.text) == ["newest", "middle"])
        #expect(model.selectedIndex == 1)
    }

    @Test func copySelectedOCRTextCopiesRecognizedTextWithoutClosingPreview() throws {
        let (store, model, pasteService) = try makeModel()
        try store.save(
            ClipboardCapture(imageData: Data([1, 2, 3]), ocrText: "serial number 123"),
            now: now)
        model.prepareForShow()
        model.togglePreview()

        model.copySelectedOCRText()

        #expect(pasteService.copiedOCRTexts == ["serial number 123"])
        #expect(model.isPreviewShown == true)
    }

    @Test func pasteSelectedOCRTextClosesAndReportsAccessibilityFallback() throws {
        let (store, model, pasteService) = try makeModel(pasteResult: false)
        var commitCount = 0
        var accessibilityPromptCount = 0
        model.onCommit = { commitCount += 1 }
        model.onAccessibilityNeeded = { accessibilityPromptCount += 1 }
        try store.save(
            ClipboardCapture(imageData: Data([1, 2, 3]), ocrText: "paste me"),
            now: now)
        model.prepareForShow()

        model.pasteSelectedOCRText()

        #expect(pasteService.pastedOCRTexts == ["paste me"])
        #expect(commitCount == 1)
        #expect(accessibilityPromptCount == 1)
    }

    @Test func ocrActionsIgnoreImagesWithoutRecognizedText() throws {
        let (store, model, pasteService) = try makeModel()
        try store.save(ClipboardCapture(imageData: Data([1, 2, 3])), now: now)
        model.prepareForShow()

        model.copySelectedOCRText()
        model.pasteSelectedOCRText()

        #expect(pasteService.copiedOCRTexts.isEmpty)
        #expect(pasteService.pastedOCRTexts.isEmpty)
    }

    @Test func deleteWhilePreviewShownRemovesPreviewedItemAndClosesPreview() throws {
        let (store, model, _) = try makeModel()
        try store.save(ClipboardCapture(text: "older"), now: now)
        try store.save(ClipboardCapture(text: "previewed"), now: now.addingTimeInterval(1))
        model.prepareForShow()
        model.togglePreview()

        model.deleteSelected()

        #expect(model.isPreviewShown == false)
        #expect(model.items.map(\.text) == ["older"])
        #expect(model.selectedItem?.text == "older")
    }
}

@MainActor
private final class FakePasteService: PanelPasteServing {
    var result: Bool
    var pastedTexts: [String] = []
    var copiedOCRTexts: [String] = []
    var pastedOCRTexts: [String] = []
    var onPaste: () -> Void = {}

    init(result: Bool) {
        self.result = result
    }

    func paste(_ item: ClipboardItem) -> Bool {
        pastedTexts.append(item.text ?? "")
        onPaste()
        return result
    }

    func copyOCRTextToPasteboard(_ item: ClipboardItem) {
        copiedOCRTexts.append(item.ocrText ?? "")
    }

    func pasteOCRText(_ item: ClipboardItem) -> Bool {
        pastedOCRTexts.append(item.ocrText ?? "")
        onPaste()
        return result
    }
}
