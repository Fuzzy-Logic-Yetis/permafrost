# Permafrost ❄️

**Win+V-style clipboard history for macOS — pin forever, expire the rest.**

Permafrost brings the Windows clipboard manager experience (`Win + V`) to macOS, with the
retention model Windows never had: **pinned entries are permanently frozen; unpinned entries
thaw and expire** after a period you choose.

Local-first. Keyboard-first. No cloud, no analytics, no network code at all.

## Features

- **Clipboard history** — text, rich text, and images (including screen snips via ⌃⇧⌘4)
- **One hotkey** — `⌥⌘V` opens the panel over whatever you're doing; `Esc` dismisses it
- **Pinning** — pinned entries never expire, live in their own section, and never steal a
  quick-paste slot from your latest copy
- **Time-based retention** — unpinned entries expire automatically (1/7/30/90 days, or never)
- **Search** — type to filter instantly (SQLite FTS5 under the hood), including recognized
  text from images (see OCR below)
- **Paste on select** — `⏎` pastes straight into the app you were using; `⇧⏎` pastes plain
  text (strips rich formatting) when you don't want the source's styling
- **Rich text capture** — native `.rtf` is kept as-is; HTML-only copies (e.g. from browsers)
  are converted to RTF automatically, with page styling (background/link color) stripped
  so only the actual formatting (bold/italic/etc.) survives
- **Drag-and-drop** — drag a card straight out of the panel into any app, or onto the
  Desktop to materialize it as a real `.txt`/`.png` file
- **OCR on screenshots** — recognized text from screen snips (on-device, via Apple's Vision
  framework) is searchable, previewable, and copyable as text
- **Preview pane** — `␣` opens a full-size, scrollable look at the selected item without
  leaving the panel
- **Concealed (password) content — opt-in** — off by default; when enabled, content from
  password managers is recorded encrypted at rest (AES-GCM, a macOS Keychain-backed key),
  redacted in the panel until you deliberately reveal it
- **Mouse-friendly too** — hover any entry for reveal / plain-text / pin / share / delete
  buttons
- **Menu bar app** — no Dock icon, no window clutter
- **Pause capture** — temporarily stop recording from the menu bar or Settings
- **Import / export** — a **This Mac Only** archive (tied to this Mac's Keychain) or a
  **Portable Encrypted Backup** (passphrase-protected, importable on another Mac); your
  history is yours, take it with you

## Windows → macOS cheat sheet

| Windows | Permafrost / macOS |
|---|---|
| `Win + V` (clipboard history) | `⌥⌘V` |
| `Win + Shift + S` (screen snip → clipboard) | `⌃⇧⌘4` (built into macOS; Permafrost keeps the snip) |
| Pin item in Win+V | `⌥P` on the selected item |
| Paste from history | `⏎` or `⌘1`–`⌘9` |
| Paste as plain text | `⇧⏎` |

## Install

Permafrost is currently built from source (signed/notarized downloads are on the
[roadmap](docs/ROADMAP.md)).

```sh
git clone https://github.com/Fuzzy-Logic-Yetis/permafrost.git
cd permafrost
./scripts/make-app.sh          # builds release binary and assembles Permafrost.app
open dist/Permafrost.app
```

Requires macOS 14+ and the Xcode Command Line Tools (`xcode-select --install`).

On first paste, macOS will ask you to grant **Accessibility** permission
(System Settings → Privacy & Security → Accessibility). This is required to
simulate `⌘V` into the frontmost app. Without it, Permafrost still works in
copy-to-clipboard mode.

## Privacy

- Everything is stored in a local SQLite database:
  `~/Library/Application Support/Permafrost/` (owner-only file permissions)
- Content copied from password managers (1Password, Bitwarden, etc.) is **not recorded by
  default** — Permafrost honors `org.nspasteboard.ConcealedType` and transient pasteboard
  types. If you *want* password history, there's an explicit opt-in behind a
  risk-acknowledgment prompt; opted-in content is AES-GCM encrypted at rest with a
  macOS Keychain-backed key, redacted in the panel by default, and only decrypted on a
  deliberate reveal (see [docs/SECURITY.md](docs/SECURITY.md))
- **Excluded apps** — add any app to Settings → Excluded Apps and Permafrost never records
  anything copied while that app is frontmost, useful for apps that don't mark their
  clipboard content as concealed
- There is no network code in this application. None. Verify it — the source is right here.

See [docs/SECURITY.md](docs/SECURITY.md) for the full story.

## Documentation

| Doc | What's in it |
|---|---|
| [CLAUDE.md](CLAUDE.md) | Project operating manual (standards, workflow, definition of done) |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Components, data flow, schema |
| [docs/DECISIONS.md](docs/DECISIONS.md) | Architecture Decision Records |
| [docs/RESEARCH.md](docs/RESEARCH.md) | Why this exists — competitor analysis and the build-vs-buy gate |
| [docs/UX.md](docs/UX.md) | Interaction spec and keyboard map |
| [docs/BACKLOG.md](docs/BACKLOG.md) | Ordered engineering backlog — what's shipped, what's next |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Where this is going |
| [docs/FUTURE_IDEAS.md](docs/FUTURE_IDEAS.md) | Deferred ideas and explicitly unscheduled possibilities |
| [docs/TESTING.md](docs/TESTING.md) | Automated test notes and the manual smoke checklist |
| [docs/CODE_REVIEW.md](docs/CODE_REVIEW.md) | Baseline prompt and process for independent engineering reviews |

## Status

**v0.4.0** — under active development, daily-driver-ready. See
[docs/ROADMAP.md](docs/ROADMAP.md) for what shipped and what's next.

## License

[MIT](LICENSE) © Fuzzy Logic Yetis
