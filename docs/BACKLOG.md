# Engineering Backlog

Ordered. Items are promoted to GitHub issues when about to be worked. Product-scale ideas
live in [FUTURE_IDEAS.md](FUTURE_IDEAS.md); this file is engineering work.

## Next up (v0.3)

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
7. **Monospace-aware text rendering** — detect code-like clipboard content and render with
   a monospaced font + subtle leading/trailing whitespace markers (UX.md originally
   promised this for MVP; deferred, see 2026-07-06 review L-2).
8. **UI-layer automated tests** — `PanelModel`/`PanelController` behavior (quick-paste
   bounds, section transitions, hover action wiring) is currently verified only by the
   manual checklist (docs/TESTING.md) and store-level invariant tests. Investigate a
   lightweight harness once the interaction surface stabilizes (2026-07-06 review M-5).
9. **[NEXT ACTION, needs project owner] Confirm status item icon visibility** (ADR-013,
   ADR-014) — genuinely unresolved as of 2026-07-07. What's confirmed: the core `⌥⌘V`
   panel works correctly (real screenshot showed actual captured history), so this is a
   discoverability/cosmetic bug, not a functional one. What's ruled out: crash, nil
   button/image, `isVisible: false`, global menu-bar auto-hide, a system "Menu Bar Only"
   per-app toggle (no such control exists in System Settings → Menu Bar — checked), and
   Input Monitoring denial (hotkey works without it, so probably unrelated despite being a
   real, now-fixed gap — see ADR-014). Applied so far: `isTemplate = true`, explicit
   `isVisible = true`, a text-title fallback (" ❄︎") alongside the image, and an explicit
   `IOHIDRequestAccess` call for Input Monitoring. None of these were visually confirmed to
   fix it in a live screenshot taken afterward.
   **Concrete next steps, in order of effort:**
   a. Project owner: just look at the actual menu bar after pulling this commit and
      rebuilding — screenshots analyzed mid-session may have caught the wrong moment/Space.
   b. If still not visible: manually add Permafrost to System Settings → Privacy &
      Security → Input Monitoring via the "+" button (requires your password/Touch ID —
      Claude cannot do this step) and relaunch, in case ADR-014's "probably unrelated"
      conclusion is wrong.
   c. If still not visible: try signing with a persistent self-signed identity (`security`
      + `codesign --sign "<name>"`) instead of ad-hoc `-`, to test whether a stable code
      identity changes how `NSStatusBar`/tccd treat the item — doesn't require Developer ID
      membership, untried so far.
   d. Last resort: replace the SF Symbol with a bundled custom `.icns`/PNG image (also
      double-serves BACKLOG item 2, the app icon) to rule out an SF-Symbol-specific
      rendering quirk on this OS version entirely.

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
