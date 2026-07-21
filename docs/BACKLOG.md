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
5. ~~Background inserts for large images~~ — **DONE 2026-07-07.** Captures are now
   enqueued through a serial `CaptureSaveQueue`; pasteboard/AppKit state is still
   snapshotted on the main actor, while hashing, thumbnail generation, SQLite blob writes,
   and retention purge happen off the UI thread with the original capture timestamp and
   retention-policy snapshot.
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
11. ~~Preview-mode keyboard-routing tests~~ — **DONE 2026-07-07.** Extended
    `PermafrostTests` model coverage for the documented preview behavior without brittle
    AppKit event driving: preview opens/closes, closes on `prepareForShow`, follows
    selection, commit/delete/pin/quick-paste resolve to the intended item while
    `isPreviewShown` is true. Also tightened model behavior so deleting the previewed item
    closes preview and pinning keeps selection anchored to the item after section reordering.
    Real `PanelController` `NSEvent` routing remains covered by the manual preview checklist.
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
13. ~~OCR on screen snips (Vision, on-device)~~ — **DONE 2026-07-08.** Image
    captures can run Apple's on-device Vision OCR on the background capture queue when
    Settings → Images → "Recognize text in images" is enabled. Recognized text is stored
    as image metadata (`ocr_text`), included in search/import/export, shown in the image
    preview, selectable, and available through Copy Text / Paste Text actions. OCR
    completion posts a panel refresh notification so searches/previews update after the
    background job finishes.

## Next up (v0.4)

1. ~~Paste as plain text~~ (⇧⏎ + hover icon) — **DONE 2026-07-21, ADR-018.** Merged to
   `main`. Along the way, manual testing surfaced and fixed a real data-loss bug: any paste
   (rich or plain) was being re-captured by `PasteboardWatcher` as if it were a new incoming
   copy, which silently self-deduped for rich paste but destroyed the source item's rich
   data for plain-text paste. Fixed with `PasteboardWatcher.ignoreOwnWrite()`.
2. **HTML rich-text capture** (ADR-019) — in progress, on branch `feat/html-rich-capture`.
   Browsers copy rich content as `public.html`, never `.rtf`; `PasteboardWatcher` only ever
   captured `.rtf`, so web-sourced copies had no rich data at all (found testing item 1).
   Design: convert HTML → RTF at capture time (native `NSAttributedString`, no new
   dependency, no schema change — smaller in scope than first assumed, see ADR-019) rather
   than storing a second rich-data type. Plan, spike results, and red tests are recorded in
   ADR-019; implementation not yet started.
3. **Drag-and-drop out of the panel** — drag an item card into a document. **Not planned in
   detail yet.** ADR-018 explicitly scoped this out: it shares the "what does interacting
   with the card body mean" question with items 1–2 above, but needs its own throwaway
   technical spike first (does SwiftUI's `.draggable`/`onDrag` coexist with the existing
   `LazyVStack` + `ScrollView` + `onTapGesture` without regressing click-to-paste?) before a
   real design/test plan can be written with confidence. Comes after item 2 ships, not in
   parallel with it — one interaction-model change in flight at a time.

## Later

- **Optional at-rest encryption** — CryptoKit AES-GCM blobs, key in Keychain (ADR-008 has
  the constraint analysis; FUTURE_IDEAS.md has the design sketch).
- **Sparkle auto-updates** — only meaningful once Developer ID signing exists (v1.0).
- **Homebrew cask** — requires notarized artifact (v1.0).
- **Localization scaffolding** — English-only for MVP.
- **`swift format` lint gate in CI** — currently advisory, make it enforced.

## Deliberately rejected (see ADRs / non-goals)

- Mac App Store distribution (ADR-007)
- Cloud sync (CLAUDE.md non-goals)
- Sandboxing (ADR-007)
