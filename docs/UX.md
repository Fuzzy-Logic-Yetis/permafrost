# UX Specification

North star: **Windows Win+V, minus the clicks.** Instant, minimal, reliable, keyboard-first.
If an interaction needs the mouse, it's a bug in the design.

## The panel

- `⌥⌘V` opens a compact floating panel near the center of the active screen.
- The app you were using **keeps focus** (the panel is non-activating); whatever you pick
  pastes into it.
- Search field is focused on open. Typing filters immediately.
- Panel closes on: `Esc` (clears search first if non-empty), selection (`⏎`), clicking
  outside, or losing key status.

### Layout

```text
╭──────────────────────────────────────╮
│ 🔍 Search…                           │
├──────────────────────────────────────┤
│ RECENT                               │
│ ┌──────────────────────────────────┐ │
│ │ https://github.com/Fuzzy-Logic…  │ │
│ ├──────────────────────────────────┤ │
│ │ ▦ [screenshot thumbnail]         │ │
│ ├──────────────────────────────────┤ │
│ │ SELECT * FROM clipboard_item…    │ │
│ └──────────────────────────────────┘ │
│ 📌 PINNED                            │
│ ┌──────────────────────────────────┐ │
│ │ 555-0123 – office door code      │ │
│ └──────────────────────────────────┘ │
├──────────────────────────────────────┤
│ ⏎ paste  ⌥P pin  ⌫ delete  esc close │
╰──────────────────────────────────────╯
```

Pinned entries live in their own section **at the bottom** (ADR-012). They're things you
reuse over time, not your most recent copy — pinning one must never bump it ahead of what
you just copied, and must never steal the `⌘1` slot from it either.

- Text cards: up to 3 lines with standard truncation. Source app + relative time in the
  caption. Code-like content (for example indented snippets, structured data, shell
  commands, SQL, or source-language keywords/punctuation) renders in a monospaced font
  with subtle markers for leading/trailing spaces and tabs.
- Image cards: thumbnail (max ~120 pt tall) + dimensions caption.
- Concealed items (passwords, only when opt-in is enabled): shown with a 🔑 marker so the
  user always knows a secret is on screen. Otherwise identical behavior — visible,
  searchable, pinnable (owner's explicit decision; see SECURITY.md).
- Selected card: accent-tinted border/background, follows system accent color.
- **Hover actions** (mouse-first, ADR-012): hovering a card swaps its trailing badges for
  three buttons — pin/unpin, share (opens the system share sheet via
  `NSSharingServicePicker`, the same one macOS's own screenshot panel uses), and delete.
  Lets a mouse user manage an item without touching the keyboard; the keyboard shortcuts
  remain the fast path for everyone else.

## Keyboard map

| Key | Action |
|---|---|
| `⌥⌘V` | Open/close panel (global) |
| type | Filter (search field always live) |
| `↑` / `↓` | Move selection (moves through Recent, then Pinned) |
| `⏎` | Paste selected into previous app, close |
| `⌘1`–`⌘9` | Paste Nth **recent** item instantly — never addresses a pinned item, so pinning something never hijacks a quick-paste slot |
| `⌥P` | Pin/unpin selected |
| `⌫` (field empty) | Delete selected entry |
| `Esc` | Clear search → close |

## Bulk history actions

Available from the status-bar menu and from Settings → History Management (both call the
same store operations). Deliberately **not** available as bare keystrokes inside the fast,
low-friction panel — an accidental keypress there shouldn't be able to wipe history.

| Action | Effect |
|---|---|
| Clear Unpinned History… | Deletes unpinned entries. Pinned entries are untouched. |
| Unpin All Items… | Converts every pinned entry back to normal history (not deleted — it now expires per your retention setting like everything else). |
| Clear Everything… | Deletes all entries, pinned included. Strongest confirmation; irreversible. |
| Restart Permafrost | Quits and relaunches the app, useful after testing ad-hoc builds or permission resets. |

Note: a status-item menu's key equivalents (e.g. the `,` shown next to Settings) only fire
while that menu is open — they are not global shortcuts, so they don't compete with the app
hotkey or risk firing by accident.

## Capture controls

The status-bar menu includes **Pause Capture**. When checked, Permafrost continues running
and the history panel remains available, but new pasteboard changes are ignored and not
backfilled later. Resuming capture starts from the next clipboard change. The same persisted
setting appears in Settings → General so the paused state is visible even if the menu is not
open.

## First-run / onboarding

1. First launch: menu bar snowflake appears; a one-time notification-style alert explains
   `⌥⌘V` and offers to enable launch-at-login.
2. First paste attempt without Accessibility permission: alert explains *why* the
   permission is needed (simulating ⌘V), buttons **Open System Settings** / **Not now**.
   Declining leaves copy-only mode (selection loads the clipboard; user presses ⌘V).
3. Enabling "Record concealed content (passwords)" in Settings: explicit risk-acknowledgment
   dialog (see SECURITY.md). Cancel reverts the toggle.

## Windows → macOS mapping (for the transitioning user)

| Windows habit | Permafrost equivalent |
|---|---|
| `Win + V` | `⌥⌘V` |
| `Win + Shift + S` snip → history | `⌃⇧⌘4` (macOS built-in snip-to-clipboard) → appears in Permafrost |
| Pin in Win+V panel | `⌥P` |
| "Clear all" in Win+V | Settings → Clear history (pinned items survive unless explicitly deleted) |

## Anti-goals

- No sounds. No animation longer than 150 ms. No badge counts. No onboarding carousel.
- Never steal focus from the app the user is working in.
- Never require the mouse for any core flow.
