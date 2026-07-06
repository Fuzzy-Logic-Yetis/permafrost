import PermafrostCore
import SwiftUI

/// The Win+V panel content. Interaction spec: docs/UX.md.
struct PanelView: View {
    @ObservedObject var model: PanelModel
    @FocusState private var searchFocused: Bool

    var body: some View {
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
        ScrollViewReader { proxy in
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
                            quickPasteIndex: index < 9 ? index + 1 : nil
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
        if items[index - 1].isPinned && !items[index].isPinned {
            return "RECENT"
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
            KeyHint(key: "⌥P", label: "pin")
            KeyHint(key: "⌫", label: "delete")
            KeyHint(key: "esc", label: "close")
            Spacer()
            Text("\(model.items.count)")
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

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            content
            Spacer(minLength: 0)
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
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch item.kind {
            case .text:
                Text(item.text ?? "")
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .truncationMode(.tail)
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
