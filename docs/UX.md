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
│ 📌 PINNED                            │
│ ┌──────────────────────────────────┐ │
│ │ 555-0123 – office door code      │ │
│ └──────────────────────────────────┘ │
│ RECENT                               │
│ ┌──────────────────────────────────┐ │
│ │ https://github.com/Fuzzy-Logic…  │ │
│ ├──────────────────────────────────┤ │
│ │ ▦ [screenshot thumbnail]         │ │
│ ├──────────────────────────────────┤ │
│ │ SELECT * FROM clipboard_item…    │ │
│ └──────────────────────────────────┘ │
├──────────────────────────────────────┤
│ ⏎ paste  ⌥P pin  ⌫ delete  esc close │
╰──────────────────────────────────────╯
```

- Text cards: up to 3 lines, monospace-detected content keeps its shape, leading/trailing
  whitespace visualized subtly. Source app + relative time in the caption.
- Image cards: thumbnail (max ~120 pt tall) + dimensions caption.
- Concealed items (passwords, only when opt-in is enabled): shown with a 🔑 marker so the
  user always knows a secret is on screen. Otherwise identical behavior — visible,
  searchable, pinnable (owner's explicit decision; see SECURITY.md).
- Selected card: accent-tinted border/background, follows system accent color.

## Keyboard map

| Key | Action |
|---|---|
| `⌥⌘V` | Open/close panel (global) |
| type | Filter (search field always live) |
| `↑` / `↓` | Move selection |
| `⏎` | Paste selected into previous app, close |
| `⌘1`–`⌘9` | Paste Nth visible item instantly |
| `⌥P` | Pin/unpin selected |
| `⌫` (field empty) | Delete selected entry |
| `Esc` | Clear search → close |

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
