# Engineering Backlog

Ordered. Items are promoted to GitHub issues when about to be worked. Product-scale ideas
live in [FUTURE_IDEAS.md](FUTURE_IDEAS.md); this file is engineering work.

## Next up (v0.3)

1. ~~Custom hotkey recorder~~ — **DONE 2026-07-07.** Built natively with an AppKit-backed
   recorder in Settings; no dependency added. Existing presets/defaults remain, while a
   recorded custom shortcut is stored in UserDefaults (`customHotkeyKeyCode` +
   `customHotkeyModifiers`) and takes precedence until the user returns to a preset or
   resets to `⌥⌘V`.
2. ~~App icon~~ — **DONE 2026-07-07.** Icy-blue gradient squircle with a bold white
   snowflake glyph, generated via `scripts/generate-icon.swift` (CoreGraphics/AppKit,
   exports all 10 `.iconset` sizes, converted with `iconutil`). Wired into
   `scripts/make-app.sh` (`CFBundleIconFile` in `Info.plist`); `.icns` committed as a
   binary resource, not regenerated per build.
3. ~~Pause capture~~ — **DONE 2026-07-07.** Status-item menu toggle (mirrored in
   Settings → General) persists `capturePaused`; while paused, pasteboard changes advance
   the watcher checkpoint but are not saved, so skipped items are not backfilled on resume.
4. ~~Per-app exclusion list~~ — **DONE 2026-07-07.** Settings → Excluded Apps lets you add
   any installed app via an Open panel; Permafrost matches on bundle identifier (stable
   across renames, unlike the display name) and skips capture entirely — before the
   concealed-type check, before touching the pasteboard payload — whenever that app is
   frontmost. Excluded apps are stored as JSON in UserDefaults (`AppSettings.excludedApps`),
   consistent with the existing settings pattern.
5. **Background inserts for large images** — move image writes off the main actor if
   Instruments shows panel jank (see ARCHITECTURE.md → Concurrency).
6. ~~Preview pane~~ — **DONE 2026-07-07.** `␣` (search field empty) toggles a Quick
   Look-style overlay of the selected item's full text (unwrapped, scrollable, selectable)
   or full-resolution image, reusing the panel's existing 440×500 footprint. Follows
   selection while open; `Esc` closes it before falling back to its existing
   clear-search/close-panel behavior. Deferred: a hover/mouse trigger for the preview — the
   hover row (pin/share/delete) is already at a natural width for three icons, and a fourth
   felt like it'd crowd it more than it'd help, so this stayed keyboard-only for now.
7. ~~Monospace-aware text rendering~~ — **DONE 2026-07-07.** Code-like text
   clips are detected in the panel and rendered with a monospaced font plus subtle
   leading/trailing whitespace markers.
8. ~~UI-layer automated tests~~ — **DONE 2026-07-07.** Added a lightweight
   `PermafrostTests` target that imports the app module and tests `PanelModel` with an
   in-memory store plus fake paste service. Covered show/search resets, selection clamping,
   quick-paste recent-only bounds, commit callback ordering/accessibility fallback,
   pinning, and delete selection bounds. Screenshot/UI automation remains deliberately
   out of scope; hover action wiring stays in the manual checklist.
9. ~~Confirm status item icon visibility~~ — **RESOLVED 2026-07-07, see ADR-015.** Root
   cause: the menu bar had too many items competing for space; macOS silently drops status
   items that don't fit, with no overflow indicator. Not a Permafrost bug — freeing space
   (project owner disabled Siri and Spotlight in System Settings → Menu Bar) fixed it
   immediately and reliably. No code change needed. This also explains the ADR-013/014
   flakiness (which other transient icons were present varied per launch) and retroactively
   invalidates the ADR-014 "ghost item" accessibility-position diagnostic — a live
   screenshot proved the icon was genuinely visible while that query still reported bogus
   data, so that signal was never meaningful in the first place.

10. ~~Hotkey registration failure/rollback test coverage~~ — **DONE 2026-07-07.** Extracted
    the registration/rollback branch behind a small fakeable seam so tests don't need to
    force Carbon's `RegisterEventHotKey` to fail globally. Coverage now asserts successful
    custom registration, failed first custom registration falling back to the selected
    preset, and failed replacement custom registration restoring the previous working
    custom hotkey while reporting the rejected chord.
11. **Preview-mode keyboard-routing tests** — `PanelController.handle` lets paste/delete/
    pin/quick-paste act on the previewed item while the overlay is open (documented in
    docs/UX.md, review L-1). `PanelModel` already has app-target test coverage
    (docs/BACKLOG.md item 8); extend it to assert those actions still resolve to the
    correct item while `isPreviewShown` is true.
12. ~~Testable policy object for pasteboard watcher pause/excluded-app behavior~~ — **DONE
    2026-07-07.** `PasteboardWatcher.poll()`'s pause/transient/excluded-app/concealed
    skip logic is now a pure `PasteboardCapturePolicy.decide(_:)` (in
    Sources/Permafrost/PasteboardWatcher.swift) that takes a plain `Input` (types, isPaused,
    isExcludedApp, recordConcealed) and returns `.capture`/`.skip(reason:)` — no
    `NSPasteboard`/`NSWorkspace` involved, following the `PanelPasteServing` precedent.
    `poll()` still gathers the AppKit/AppSettings-backed inputs and just calls the policy.
    Covered by Tests/PermafrostTests/PasteboardCapturePolicyTests.swift (paused, excluded
    app, concealed default-skip, concealed opt-in, transient/auto-generated, normal capture,
    and pause-takes-priority-over-other-reasons).

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
