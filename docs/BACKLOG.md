# Engineering Backlog

Ordered. Items are promoted to GitHub issues when about to be worked. Product-scale ideas
live in [FUTURE_IDEAS.md](FUTURE_IDEAS.md); this file is engineering work.

## Next up (v0.2)

1. **Custom hotkey recorder** — Settings currently offers presets (ADR-005). Evaluate
   building a recorder natively vs. adopting `KeyboardShortcuts` (would need an ADR to
   spend the dependency budget).
2. **App icon** — proper `.icns` (snowflake/yeti mark). MVP uses the SF Symbol status icon
   only, and the bundle ships without a custom icon.
3. **Pause capture** — status-item menu toggle to temporarily stop recording.
4. **Per-app exclusion list** — never record from user-chosen apps (e.g., a password
   manager that doesn't set concealed types, a VNC client).
5. **Background inserts for large images** — move image writes off the main actor if
   Instruments shows panel jank (see ARCHITECTURE.md → Concurrency).
6. **Preview pane** — space bar quick-look of full text/image for the selected item.

## Later

- **Optional at-rest encryption** — CryptoKit AES-GCM blobs, key in Keychain (ADR-008 has
  the constraint analysis; FUTURE_IDEAS.md has the design sketch).
- **Sparkle auto-updates** — only meaningful once Developer ID signing exists (v1.0).
- **Homebrew cask** — requires notarized artifact (v1.0).
- **Drag-and-drop out of the panel** — drag an item card into a document.
- **Paste as plain text** modifier (⇧⏎) — strip rich data on paste.
- **Localization scaffolding** — English-only for MVP.
- **`swift format` lint gate in CI** — currently advisory, make it enforced.

## Deliberately rejected (see ADRs / non-goals)

- Mac App Store distribution (ADR-007)
- Cloud sync (CLAUDE.md non-goals)
- Sandboxing (ADR-007)
