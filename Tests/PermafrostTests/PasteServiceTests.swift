import AppKit
import Foundation
import PermafrostCore
import Testing
@testable import Permafrost

@MainActor
@Suite struct PasteServiceTests {
    @Test func sensitiveCopyWritesConcealedMarkerAndNotifiesOwnWrite() throws {
        let board = NSPasteboard(name: .init("PermafrostTest-" + UUID().uuidString))
        defer { board.releaseGlobally() }
        let store = try ClipboardStore.inMemory()
        var writes = 0
        let service = PasteService(store: store, pasteboard: board, onPasteboardWritten: { writes += 1 })
        let item = try store.save(
            ClipboardCapture(imageData: Data([1, 2, 3])),
            now: Date(timeIntervalSince1970: 0))
        service.copySensitiveTextToPasteboard("WIFI:P:synthetic-only;;", item: item)
        #expect(board.string(forType: .string) == "WIFI:P:synthetic-only;;")
        #expect(board.types?.contains(.init(PasteboardCapturePolicy.concealedType)) == true)
        #expect(writes == 1)
        // ADR-025: revealing/copying a sensitive QR secret must mark the item used, the
        // same as every other copy/paste action -- otherwise retention can purge a secret
        // the user is actively relying on.
        #expect(try store.allItems().first { $0.id == item.id }?.lastUsedAt != item.lastUsedAt)
        #expect(PasteboardCapturePolicy.decide(.init(
            types: Set((board.types ?? []).map(\.rawValue)), isPaused: false,
            isExcludedApp: false, recordConcealed: false)) == .skip(.concealedNotOptedIn))
        let ordinary = try store.save(ClipboardCapture(text: "ordinary"))
        #expect(service.copyToPasteboard(ordinary))
        #expect(board.string(forType: .string) == "ordinary")
        #expect(board.types?.contains(.init(PasteboardCapturePolicy.concealedType)) == false)
        #expect(writes == 2)
    }
}
