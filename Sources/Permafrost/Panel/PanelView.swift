import AppKit
import PermafrostCore
import SwiftUI

/// The Win+V panel content. Interaction spec: docs/UX.md.
struct PanelView: View {
    @ObservedObject var model: PanelModel
    @FocusState private var searchFocused: Bool
    @State private var isSharePickerOpen = false
    @State private var suppressCardCommitsUntil: Date?

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                searchBar
                Divider()
                if model.items.isEmpty {
                    emptyState
                } else {
                    itemList
                }
                Divider()
                footer
            }
            if model.isPreviewShown, let item = model.selectedItem {
                PreviewPane(
                    item: item,
                    onCopyOCRText: { model.copySelectedOCRText() },
                    onPasteOCRText: { model.pasteSelectedOCRText() },
                    onCopyOCRSelection: { model.scheduleReloadAfterExternalCopy() },
                    revealConcealedText: { model.revealConcealedText(for: item) }
                )
            }
        }
        .frame(width: 440, height: 500)
        .background(.regularMaterial)
        .onReceive(NotificationCenter.default.publisher(for: .sharePickerWillOpen)) { _ in
            isSharePickerOpen = true
            suppressCardCommitsUntil = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .sharePickerDidClose)) { _ in
            isSharePickerOpen = false
            suppressCardCommitsUntil = Date().addingTimeInterval(0.35)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search clipboard history", text: $model.query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
        }
        .font(.title3)
        .padding(12)
        .onAppear { searchFocused = true }
        .onChange(of: model.focusToken) {
            searchFocused = true
        }
    }

    private var itemList: some View {
        // Quick-paste numbers address only the unpinned prefix (ADR-012); pinned
        // items never carry a stale ⌘N badge even though they share this list.
        let recentCount = model.items.prefix(while: { !$0.isPinned }).count
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                        if let header = sectionHeader(at: index) {
                            Text(header)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.top, index == 0 ? 2 : 8)
                                .padding(.leading, 6)
                        }
                        let card = ItemCard(
                            item: item,
                            isSelected: index == model.selectedIndex,
                            quickPasteIndex: index < recentCount && index < 9 ? index + 1 : nil,
                            onTogglePin: { if let id = item.id { model.togglePin(id: id) } },
                            onDelete: { if let id = item.id { model.deleteItem(id: id) } },
                            onPreviewOCR: { model.showPreview(index: index) },
                            onPasteAsPlainText: { model.commit(index: index, asPlainText: true) },
                            revealConcealedText: { model.revealConcealedText(for: item) }
                        )
                        // ADR-020: drag as plain text/PNG, mirroring the existing
                        // shareableItems/share-sheet precedent rather than carrying RTF.
                        // Verified via spike that .draggable() needs no custom gesture code
                        // to coexist with the onTapGesture commit below. ADR-021: a concealed
                        // item's `.text` is nil (encrypted) — decrypt on demand for the drag
                        // payload too, same as paste already does, rather than silently
                        // dragging an empty string.
                        Group {
                            if item.kind == .text {
                                // Inlined (not a `let`) so `.draggable`'s @autoclosure
                                // defers the decrypt to actual drag start, not every render.
                                card.draggable(
                                    item.isConcealed
                                        ? (model.revealConcealedText(for: item) ?? "")
                                        : (item.text ?? ""))
                            } else if let imageData = item.imageData {
                                card.draggable(DraggableImageData(data: imageData))
                            } else {
                                card
                            }
                        }
                        .id(item.id)
                        .onTapGesture {
                            guard canCommitCardTap else { return }
                            model.commit(index: index)
                        }
                        .contextMenu {
                            // ADR-021 follow-up: retroactive concealment for content
                            // captured without the source app's concealed marker.
                            if item.kind == .text, !item.isConcealed, let id = item.id {
                                Button("Mark as Concealed") {
                                    model.markConcealed(id: id)
                                }
                            }
                        }
                    }
                }
                .padding(8)
            }
            .onChange(of: model.selectedIndex) {
                if let id = model.selectedItem?.id {
                    proxy.scrollTo(id, anchor: nil)
                }
            }
        }
    }

    private var canCommitCardTap: Bool {
        guard !isSharePickerOpen else { return false }
        if let suppressCardCommitsUntil, Date() < suppressCardCommitsUntil {
            return false
        }
        return true
    }

    private func sectionHeader(at index: Int) -> String? {
        let items = model.items
        if index == 0 {
            return items[0].isPinned ? "PINNED" : "RECENT"
        }
        // Store ordering is always unpinned → pinned (ADR-012); this is the only
        // transition that can occur in a mixed list.
        if !items[index - 1].isPinned && items[index].isPinned {
            return "PINNED"
        }
        return nil
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "snowflake")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text(model.query.isEmpty ? "Nothing copied yet" : "No matches")
                .foregroundStyle(.secondary)
            if model.query.isEmpty {
                Text("Copy something anywhere — it shows up here.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            KeyHint(key: "⏎", label: "paste")
            KeyHint(key: "⇧⏎", label: "plain")
            KeyHint(key: "␣", label: "preview")
            KeyHint(key: "⌥P", label: "pin")
            KeyHint(key: "⌫", label: "delete")
            KeyHint(key: "esc", label: "close")
            Spacer()
            Text(model.countLabel)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}

private struct KeyHint: View {
    let key: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3).fill(.quaternary)
                )
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct ItemCard: View {
    let item: ClipboardItem
    let isSelected: Bool
    let quickPasteIndex: Int?
    let onTogglePin: () -> Void
    let onDelete: () -> Void
    let onPreviewOCR: () -> Void
    let onPasteAsPlainText: () -> Void
    let revealConcealedText: () -> String?

    @State private var isHovering = false
    @State private var isSharing = false
    /// ADR-021: redacted by default, not persisted across panel sessions — a fresh
    /// `ItemCard` (new panel open) always starts back at `false`.
    @State private var revealedText: String?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            content
            Spacer(minLength: 0)
            // Fixed width regardless of hover state: the badge column (at rest) and
            // the hover button row have different natural widths, and without pinning
            // this slot, `content` would reflow/re-wrap every time the mouse moved onto
            // a different card.
            trailing
                .frame(width: 78, alignment: .trailing)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    /// State badges (pin/concealed/quick-number) at rest; mouse-first actions
    /// (pin, share, delete) on hover — the same affordance as macOS's own
    /// screenshot share panel, so the panel doesn't require the keyboard.
    @ViewBuilder
    private var trailing: some View {
        if isHovering || isSharing {
            HStack(spacing: 6) {
                if item.hasOCRText {
                    Button(action: onPreviewOCR) {
                        Image(systemName: "text.viewfinder")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    .help("Open recognized text")
                }

                // ADR-018: text-only — `.image` items have no plain-text representation
                // of their own (OCR text is the separate, already-existing action above).
                if item.kind == .text {
                    Button(action: onPasteAsPlainText) {
                        Image(systemName: "doc.plaintext")
                    }
                    .buttonStyle(.plain)
                    .help("Paste as Plain Text")
                }

                // ADR-021: redact-by-default, reveal-on-demand — a dedicated toggle so
                // revealing is a deliberate click, never a side effect of hovering or of
                // the card's own click-to-paste.
                if item.kind == .text, item.isConcealed {
                    Button {
                        revealedText = (revealedText == nil) ? revealConcealedText() : nil
                    } label: {
                        Image(systemName: revealedText == nil ? "eye" : "eye.slash")
                    }
                    .buttonStyle(.plain)
                    .help(revealedText == nil ? "Reveal" : "Hide")
                }

                Button(action: onTogglePin) {
                    Image(systemName: item.isPinned ? "pin.slash" : "pin")
                }
                .buttonStyle(.plain)
                .help(item.isPinned ? "Unpin" : "Pin")

                ShareButton(
                    items: item.shareableItems,
                    onPresentationChanged: { isSharing = $0 }
                )
                .frame(width: 15, height: 15)
                .help("Share")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("Delete")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .trailing, spacing: 4) {
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                if item.isConcealed {
                    Image(systemName: "key.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
                if item.hasOCRText {
                    Button(action: onPreviewOCR) {
                        Label("OCR", systemImage: "text.viewfinder")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundStyle(.blue)
                    .help("Open recognized text")
                }
                if let quickPasteIndex {
                    Text("⌘\(quickPasteIndex)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch item.kind {
            case .text:
                if item.isConcealed {
                    Text(revealedText ?? "••••••••••••")
                        .font(revealedText == nil ? .body : .system(.body, design: .monospaced))
                } else {
                    TextPreview(text: item.text ?? "")
                }
            case .image:
                if let thumbnail = item.thumbnail, let nsImage = NSImage(data: thumbnail) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 110, alignment: .leading)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Label("Image", systemImage: "photo")
                        .foregroundStyle(.secondary)
                }
                if let snippet = ocrSnippet {
                    Label {
                        Text(snippet)
                            .lineLimit(2)
                            .truncationMode(.tail)
                    } icon: {
                        Image(systemName: "text.viewfinder")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            caption
        }
    }

    private var ocrSnippet: String? {
        guard item.kind == .image, let text = item.ocrText else { return nil }
        let collapsed = text
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.isEmpty ? nil : collapsed
    }

    private var caption: some View {
        Text(captionText)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var captionText: String {
        var parts: [String] = []
        if let app = item.sourceApp { parts.append(app) }
        parts.append(ClipboardTimestampFormatter.caption(for: item))
        if item.kind == .image, let data = item.imageData,
            let size = Thumbnailer.pixelSize(of: data)
        {
            parts.append("\(size.width)×\(size.height)")
        }
        return parts.joined(separator: " · ")
    }
}

private struct SelectablePlainTextView: NSViewRepresentable {
    let text: String
    var onCopySelection: (String) -> Void = { _ in }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = CopyingTextView()
        textView.onCopySelection = onCopySelection
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.font = NSFont.preferredFont(forTextStyle: .body)
        textView.textColor = .labelColor
        textView.string = text
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: .greatestFiniteMagnitude
        )
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? CopyingTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.font = NSFont.preferredFont(forTextStyle: .body)
        textView.textColor = .labelColor
        textView.onCopySelection = onCopySelection
    }
}

private final class CopyingTextView: NSTextView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "c" {
            copySelectionToPasteboard()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func copy(_ sender: Any?) {
        copySelectionToPasteboard()
    }

    private func copySelectionToPasteboard() {
        let selected = selectedRange()
        guard selected.length > 0, let range = Range(selected, in: string) else {
            NSSound.beep()
            return
        }
        let selection = String(string[range])
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(selection, forType: .string)
        onCopySelection(selection)
    }

    var onCopySelection: (String) -> Void = { _ in }
}

private enum ClipboardTimestampFormatter {
    static func caption(for item: ClipboardItem) -> String {
        let created = item.createdAt.formatted(.relative(presentation: .named))
        let lastUsed = item.lastUsedAt.formatted(.relative(presentation: .named))
        guard abs(item.lastUsedAt.timeIntervalSince(item.createdAt)) >= 60 else {
            return "copied \(lastUsed)"
        }
        return "first copied \(created) · last used/copied \(lastUsed)"
    }
}

private struct TextPreview: View {
    let text: String
    var lineLimit: Int? = 3
    var selectable: Bool = false

    private var isCodeLike: Bool {
        TextPreviewClassifier.isCodeLike(text)
    }

    var body: some View {
        let text = Text(displayText)
            .font(isCodeLike ? .system(.body, design: .monospaced) : .body)
            .foregroundStyle(.primary)
            .lineLimit(lineLimit)
            .multilineTextAlignment(.leading)
            .truncationMode(.tail)
        if selectable {
            text.textSelection(.enabled)
        } else {
            text
        }
    }

    private var displayText: AttributedString {
        guard isCodeLike else {
            return AttributedString(text)
        }
        return WhitespaceVisualizer.attributedPreview(for: text)
    }
}

/// Space-bar quick look (docs/UX.md): the full text or full-resolution image of
/// the selected item, reusing the same 440×500 panel footprint rather than
/// growing the window — the default panel stays compact, this is opt-in.
private struct PreviewPane: View {
    let item: ClipboardItem
    let onCopyOCRText: () -> Void
    let onPasteOCRText: () -> Void
    let onCopyOCRSelection: () -> Void
    let revealConcealedText: () -> String?

    @State private var copiedSelectionMessage: String?
    /// ADR-021: redacted by default, same as the card — a fresh preview open (new
    /// selection, or the panel reopening) always starts back at `nil`.
    @State private var revealedText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(captionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if item.kind == .text, item.isConcealed {
                    Button(revealedText == nil ? "Reveal" : "Hide") {
                        revealedText = (revealedText == nil) ? revealConcealedText() : nil
                    }
                }
                KeyHint(key: "␣ / esc", label: "close")
            }
            .padding(12)
            Divider()
            ScrollView {
                content
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .text:
            if item.isConcealed {
                TextPreview(
                    text: revealedText ?? "••••••••••••", lineLimit: nil, selectable: revealedText != nil)
            } else {
                TextPreview(text: item.text ?? "", lineLimit: nil, selectable: true)
            }
        case .image:
            VStack(alignment: .leading, spacing: 12) {
                if let data = item.imageData, let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Label("Image unavailable", systemImage: "photo")
                        .foregroundStyle(.secondary)
                }
                if item.hasOCRText, let ocrText = item.ocrText {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Recognized Text", systemImage: "text.viewfinder")
                                .font(.headline)
                            Spacer()
                            if let copiedSelectionMessage {
                                Text(copiedSelectionMessage)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.green)
                            } else {
                                Text("Scroll/select below; ⌘C copies selection.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Button("Copy All", action: onCopyOCRText)
                            Button("Paste All", action: onPasteOCRText)
                        }
                        HStack(spacing: 12) {
                            KeyHint(key: "⌘C", label: "copy selection")
                            KeyHint(key: "⌥⌘C", label: "copy all")
                            KeyHint(key: "⇧⏎", label: "paste all")
                        }
                        SelectablePlainTextView(
                            text: ocrText,
                            onCopySelection: { selection in
                                copiedSelectionMessage = "Copied \(selection.count) characters"
                                onCopyOCRSelection()
                            }
                        )
                        .frame(height: 170)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(.separator, lineWidth: 1)
                            )
                    }
                } else {
                    Text("OCR text will appear here after recognition finishes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var captionText: String {
        var parts: [String] = []
        if let app = item.sourceApp { parts.append(app) }
        parts.append(ClipboardTimestampFormatter.caption(for: item))
        if item.kind == .image, let data = item.imageData,
            let size = Thumbnailer.pixelSize(of: data)
        {
            parts.append("\(size.width)×\(size.height)")
        }
        return parts.joined(separator: " · ")
    }
}

private enum TextPreviewClassifier {
    static func isCodeLike(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 6 else { return false }

        let lines = text.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).map(String.init)

        var score = 0
        if text.contains("\t") { score += 2 }
        if lines.count > 1 { score += 1 }
        if lines.contains(where: hasCodeIndentation) { score += 2 }
        if containsCodePunctuation(trimmed) { score += 1 }
        if containsCodeKeyword(trimmed) { score += 2 }
        if looksLikeSQL(trimmed) { score += 3 }
        if looksLikeShellCommand(trimmed) { score += 3 }
        if looksLikeStructuredData(trimmed) { score += 2 }

        return score >= 3
    }

    private static func hasCodeIndentation(_ line: String) -> Bool {
        guard let first = line.first, first == " " || first == "\t" else {
            return false
        }
        return !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func containsCodePunctuation(_ text: String) -> Bool {
        let punctuation = ["{", "}", ";", "=>", "==", "&&", "||", "</", "/>", "::"]
        return punctuation.contains { text.contains($0) }
    }

    private static func containsCodeKeyword(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        let keywords = [
            "func ", "let ", "var ", "class ", "struct ", "enum ", "import ",
            "return ", "const ", "function ", "select ", "insert ", "update ",
            "delete from ", "where ", "def ", "package ", "public ", "private ",
        ]
        return keywords.contains { lowercased.contains($0) }
    }

    private static func looksLikeSQL(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return lowercased.contains("select ") && lowercased.contains(" from ")
    }

    private static func looksLikeShellCommand(_ text: String) -> Bool {
        text.hasPrefix("$ ") || text.hasPrefix("> ")
    }

    private static func looksLikeStructuredData(_ text: String) -> Bool {
        (text.hasPrefix("{") && text.hasSuffix("}"))
            || (text.hasPrefix("[") && text.hasSuffix("]"))
            || (text.hasPrefix("<") && text.hasSuffix(">"))
    }
}

private enum WhitespaceVisualizer {
    static func attributedPreview(for text: String) -> AttributedString {
        var result = AttributedString()
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)

        for (index, line) in lines.enumerated() {
            if index > 0 {
                result += AttributedString("\n")
            }
            result += attributedLine(String(line))
        }

        return result
    }

    private static func attributedLine(_ line: String) -> AttributedString {
        var output = AttributedString()
        let characters = Array(line)
        let leadingCount = characters.prefix { $0 == " " || $0 == "\t" }.count
        let trailingCount = characters.dropFirst(leadingCount).reversed()
            .prefix { $0 == " " || $0 == "\t" }
            .count
        let bodyStart = leadingCount
        let bodyEnd = characters.count - trailingCount

        output += markerString(for: characters.prefix(leadingCount))
        if bodyStart < bodyEnd {
            output += AttributedString(String(characters[bodyStart..<bodyEnd]))
        }
        output += markerString(for: characters.suffix(trailingCount))
        return output
    }

    private static func markerString<S: Sequence>(for characters: S) -> AttributedString
    where S.Element == Character {
        var markers = AttributedString(
            characters.map { character in
                character == "\t" ? "→" : "·"
            }.joined()
        )
        markers.foregroundColor = .secondary
        return markers
    }
}
