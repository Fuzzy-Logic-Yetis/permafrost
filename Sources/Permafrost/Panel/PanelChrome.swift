import AppKit
import PermafrostCore
import SwiftUI

/// The panel's width comes from its own chrome, never from the list content: the wider of
/// the filter-chip row and the footer key hints, measured from the real views, so neither
/// ever wraps or clips. Adding a chip or a hint widens the panel automatically.
@MainActor
enum PanelLayout {
    static let height: CGFloat = 500

    static let width: CGFloat = {
        let chips = fittingWidth(ChipRow(states: ChipStates(), toggle: { _ in }))
        let footer = fittingWidth(FooterBar(countText: "999+"))
        return ceil(max(chips, footer))
    }()

    /// Width of the chip row and of the footer, for tests and diagnostics.
    static var chromeWidths: (chips: CGFloat, footer: CGFloat) {
        (
            ceil(fittingWidth(ChipRow(states: ChipStates(), toggle: { _ in }))),
            ceil(fittingWidth(FooterBar(countText: "999+")))
        )
    }

    private static func fittingWidth<V: View>(_ view: V) -> CGFloat {
        NSHostingView(rootView: view.fixedSize()).fittingSize.width
    }
}

/// Which chips are lit and which are clickable, as plain values.
struct ChipStates: Equatable {
    var active: Set<String> = []
    var enabled: Set<String> = Set(SearchFilters.chips.map(\.token))
}

/// The row of filter chips under the search field. One row, never wrapped.
///
/// Its inputs are plain `Equatable` values on purpose. Passing closures that read the model
/// (`{ model.isChipActive($0) }`) looked equal to SwiftUI from one render to the next, so it
/// skipped re-evaluating the row and the chips kept showing the state from when the panel
/// opened: the `app` chip stayed dimmed and dead while the app filter was on.
struct ChipRow: View {
    let states: ChipStates
    let toggle: (String) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(SearchFilters.chips) { chip in
                FilterChipButton(
                    label: chip.label,
                    key: PanelModel.chipKeys[chip.token].map { "⌥" + $0.uppercased() },
                    isActive: states.active.contains(chip.token),
                    isEnabled: states.enabled.contains(chip.token),
                    action: { toggle(chip.token) })
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

/// The key-hint bar at the bottom of the panel.
struct FooterBar: View {
    let countText: String

    var body: some View {
        HStack(spacing: 8) {
            KeyHint(key: "⏎", label: "paste")
            KeyHint(key: "⇧⏎", label: "plain")
            KeyHint(key: "␣", label: "preview")
            KeyHint(key: "⌥P", label: "pin")
            KeyHint(key: "⌫", label: "delete")
            KeyHint(key: "esc", label: "close")
            Spacer()
            Text(countText)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}

/// A toggle chip in the footer-hint style: the shortcut doubles as a label on the button.
struct FilterChipButton: View {
    let label: String
    let key: String?
    let isActive: Bool
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let key {
                    Text(key)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(.quaternary))
                }
                Text(label)
                    .font(.caption)
                    .foregroundStyle(isActive ? .primary : .secondary)
            }
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? Color.accentColor.opacity(0.25) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isActive ? Color.accentColor : Color.secondary.opacity(0.3))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityLabel("\(label) filter")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

struct KeyHint: View {
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
