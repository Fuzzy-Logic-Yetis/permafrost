# UX Specification

North star: **Windows Win+V, minus the clicks.** Instant, minimal, reliable, keyboard-first.
If an interaction needs the mouse, it's a bug in the design.

## The panel

- `⌥⌘V` opens a compact floating panel near the center of the active screen.
- The app you were using **keeps focus** (the panel is non-activating); whatever you pick
  pastes into it.
- Search field is focused on open. Typing filters immediately, including OCR-recognized
  text attached to image/snipping rows once OCR has run.
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
│ ⏎ paste  ␣ preview  ⌥P pin  ⌫ delete │
│ esc close                            │
╰──────────────────────────────────────╯
```

Pinned entries live in their own section **at the bottom** (ADR-012). They're things you
reuse over time, not your most recent copy — pinning one must never bump it ahead of what
you just copied, and must never steal the `⌘1` slot from it either.

- Text cards: up to 3 lines with standard truncation. Source app + relative time in the
  caption. Code-like content (for example indented snippets, structured data, shell
  commands, SQL, or source-language keywords/punctuation) renders in a monospaced font
  with subtle markers for leading/trailing spaces and tabs.
- Image cards: thumbnail (max ~120 pt tall) + dimensions caption. When OCR finds text,
  the card shows a small text-viewfinder badge; search matches the recognized text while
  the default paste still pastes the original image.
- Concealed items (passwords, only when opt-in is enabled): shown with a 🔑 marker so the
  user always knows a secret is on screen. Otherwise identical behavior — visible,
  searchable, pinnable (owner's explicit decision; see SECURITY.md).
- Selected card: accent-tinted border/background, follows system accent color.
- **Hover actions** (mouse-first, ADR-012): hovering a card swaps its trailing badges for
  buttons — pin/unpin, share (opens the system share sheet via `NSSharingServicePicker`, the
  same one macOS's own screenshot panel uses), and delete, plus a **Paste as Plain Text**
  icon (📄, ADR-018) on `.text` cards only. Clicking any of these does not trigger the
  card's own click-to-paste gesture — proven by pin/share/delete first, extended to the
  plain-text button the same way. Lets a mouse user manage an item without touching the
  keyboard; the keyboard shortcuts remain the fast path for everyone else.
- **Paste as plain text** (`⇧⏎`, ADR-018): pastes the selected item stripped of rich
  data (no `.rtf`) instead of the normal `⏎` rich paste. Text-only — pressing `⇧⏎` on an
  `.image` card falls back to a normal paste rather than doing nothing, since images have
  no plain-text representation of their own (OCR text, when present, is the separate,
  pre-existing preview-pane action). The hover icon above is the mouse-reachable
  equivalent, since a card click already commits-and-closes with no intermediate
  "selected but not yet pasted" state to hang a second click off of.
- **Preview pane** (`␣`): a Quick Look-style overlay for the selected item — full text
  (unwrapped, scrollable, selectable/copyable, same monospace + whitespace-marker treatment
  as the card) or the full-resolution image, not the card's thumbnail. It reuses the panel's
  existing 440×500 footprint instead of growing the window, so the default panel stays
  compact and this stays opt-in. It follows the selection as you move `↑`/`↓` while open, and
  closes on a second `␣` or `Esc` (which closes the preview first, before its usual
  clear-search/close-panel behavior). Deliberately keyboard-first only — a preview toggle
  is a passive view option, not an alternate commit action, so the crowding objection that
  originally deferred a fourth hover icon (BACKLOG item 6) still applies to *this* one even
  though it no longer applies to Paste as Plain Text (ADR-018).

  Space only opens/closes the preview while the search field is empty, matching the
  existing `⌫`-delete gating — otherwise a search query containing a literal space
  (e.g. "hello world") couldn't be typed.

  While the preview is open, the underlying list's other shortcuts stay live and act on
  the previewed (selected) item: `⏎` pastes it and closes both preview and panel, `⌫`
  deletes it (preview closes with it), `⌥P` pins/unpins it, and `⌘1`–`⌘9` still quick-paste
  by position. This is deliberate — the preview is a bigger look at the same selection, not
  a separate mode — but it means those keys act on a card you can no longer see the list
  row for. Flagged by the 2026-07-07 review (L-1); documenting instead of gating, since
  gating would remove the ability to pin/delete/paste without first closing the preview.

  For image items with OCR text, the preview adds a **Recognized Text** section below the
  image. The text is selectable and has **Copy Text** / **Paste Text** buttons. Copy Text
  puts only the recognized text on the clipboard; Paste Text closes the panel and pastes
  that text into the previous app. If recognition is still running, the panel refreshes
  after the background OCR job stores text.

## Concealed text

Concealed text is redacted whenever the panel opens. Hover a concealed card and click the eye
icon to reveal it for the current panel session; closing and reopening the panel, moving
selection to a different item (including in the preview pane), or completing a Share action,
redacts it again. Share is shown only after this explicit reveal.

If a concealed item's content can't be resolved yet (the Keychain key hasn't loaded — normally
sub-second after launch), pasting it shows a distinct "Can't paste this yet" alert rather than
the Accessibility-permission prompt, since granting Accessibility wouldn't fix it.

Browsers and other apps do not always mark password-field copies as concealed. Hover any ordinary
text card and use the lock icon (**Encrypt and Conceal**) to encrypt it manually; this is one-way.

## Keyboard map

| Key | Action |
|---|---|
| `⌥⌘V` | Open/close panel (global default; configurable in Settings) |
| type | Filter (search field always live) |
| `↑` / `↓` | Move selection (moves through Recent, then Pinned); updates an open preview |
| `⏎` | Paste selected into previous app, close |
| `⇧⏎` | Paste selected **as plain text** (strips rich data); falls back to a normal paste on `.image` items (ADR-018) |
| `⌘1`–`⌘9` | Paste Nth **recent** item instantly — never addresses a pinned item, so pinning something never hijacks a quick-paste slot |
| `⌥P` | Pin/unpin selected |
| `␣` (field empty) | Toggle full preview of selected item |
| `⌫` (field empty) | Delete selected entry |
| `Esc` | Close preview if open, else clear search → close |

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

Note: macOS auto-decorates menu items whose title/selector match standard system commands
(e.g. "Settings…" + `⌘,`, "Quit …" + `terminate:`) with a system glyph even when no `.image`
was ever set — found 2026-07-21 when only those two rows got an icon and the rest of the
menu read as misaligned as a result. Every item in this menu is given an explicit blank
placeholder image (`App.swift`'s `setupStatusItem()`) so the icon gutter is either present
and empty everywhere or absent everywhere, rather than fighting that decoration item by item.

## Capture controls

The status-bar menu includes **Pause Capture**. When checked, Permafrost continues running
and the history panel remains available, but new pasteboard changes are ignored and not
backfilled later. Resuming capture starts from the next clipboard change. The same persisted
setting appears in Settings → General so the paused state is visible even if the menu is not
open.

## Hotkey settings

Settings → General keeps the preset picker from ADR-005 and adds a native custom recorder.
Click **Record Custom…**, press one key chord, then Permafrost immediately re-registers the
global hotkey and updates the status-menu title. Custom shortcuts must include at least one
primary modifier (`⌘`, `⌥`, or `⌃`) so a plain letter or Shift-only chord cannot accidentally
hijack normal typing. `Esc` or **Cancel** exits recording without changing the current
shortcut. **Use Selected Preset** removes a custom recording and returns to the currently
selected preset; **Reset to Default** returns to `⌥⌘V`.

## Import and export

Export offers **This Mac Only** for a Keychain-bound local archive and **Portable Encrypted
Backup** for moving history to another Mac. Portable Backup prompts for a 12-character-or-longer
passphrase and confirmation; Permafrost cannot recover it. Import detects a portable archive and
prompts for its passphrase automatically. A wrong passphrase or damaged archive imports nothing.

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
