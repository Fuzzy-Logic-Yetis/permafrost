import PermafrostCore
import SwiftUI

/// The Win+V panel content. Interaction spec: docs/UX.md.
struct PanelView: View {
    @ObservedObject var model: PanelModel
    @FocusState private var searchFocused: Bool

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
                PreviewPane(item: item)
            }
        }
        .frame(width: 440, height: 500)
        .background(.regularMaterial)
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
                        ItemCard(
                            item: item,
                            isSelected: index == model.selectedIndex,
                            quickPasteIndex: index < recentCount && index < 9 ? index + 1 : nil,
                            onTogglePin: { if let id = item.id { model.togglePin(id: id) } },
                            onDelete: { if let id = item.id { model.deleteItem(id: id) } }
                        )
                        .id(item.id)
                        .onTapGesture { model.commit(index: index) }
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
        HStack(spacing: 14) {
            KeyHint(key: "⏎", label: "paste")
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
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3).fill(.quaternary)
                )
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ItemCard: View {
    let item: ClipboardItem
    let isSelected: Bool
    let quickPasteIndex: Int?
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            content
            Spacer(minLength: 0)
            // Fixed width regardless of hover state: the badge column (at rest) and
            // the 3-button row (on hover) have very different natural widths, and
            // without pinning this slot, `content` would reflow/re-wrap every time
            // the mouse moved onto a different card.
            trailing
                .frame(width: 60, alignment: .trailing)
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
        if isHovering {
            HStack(spacing: 6) {
                Button(action: onTogglePin) {
                    Image(systemName: item.isPinned ? "pin.slash" : "pin")
                }
                .buttonStyle(.plain)
                .help(item.isPinned ? "Unpin" : "Pin")

                ShareButton(items: item.shareableItems)
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
                TextPreview(text: item.text ?? "")
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
            }
            caption
        }
    }

    private var caption: some View {
        Text(captionText)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var captionText: String {
        var parts: [String] = []
        if let app = item.sourceApp { parts.append(app) }
        parts.append(item.lastUsedAt.formatted(.relative(presentation: .named)))
        if item.kind == .image, let data = item.imageData,
            let size = Thumbnailer.pixelSize(of: data)
        {
            parts.append("\(size.width)×\(size.height)")
        }
        return parts.joined(separator: " · ")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(captionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
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
            TextPreview(text: item.text ?? "", lineLimit: nil, selectable: true)
        case .image:
            if let data = item.imageData, let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Label("Image unavailable", systemImage: "photo")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var captionText: String {
        var parts: [String] = []
        if let app = item.sourceApp { parts.append(app) }
        parts.append(item.lastUsedAt.formatted(.relative(presentation: .named)))
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
