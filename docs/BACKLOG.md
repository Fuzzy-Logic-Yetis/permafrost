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
2. ~~HTML rich-text capture~~ (ADR-019) — **DONE 2026-07-21.** Merged to `main`. Converts
   HTML → RTF at capture time (native `NSAttributedString`, no new dependency, no schema
   change) when no native `.rtf` is present, so browser-sourced copies get real rich data
   instead of none. Amended after live testing against two real product pages (a
   firearms-parts site, then Amazon): the naive conversion carried over background color
   and link color as page decoration (a colored badge became a gray/tan box in Word), so
   `HTMLRichTextConverter` now strips color specifically while keeping character-level
   emphasis (bold/italic/strikethrough/underline) intact. Native `.rtf` from Word/Pages/
   Notes is completely unaffected.
3. ~~Drag-and-drop out of the panel~~ (ADR-020) — **DONE 2026-07-21.** Text items drag as
   plain `String`, image items as PNG `Data` (`DraggableImageData`), mirroring the existing
   `shareableItems`/share-sheet precedent rather than carrying RTF. `.draggable()` needed
   zero custom gesture code to coexist with click-to-paste (spike-verified). All 5 manual
   checklist items passed, including a nice emergent bonus: dragging onto the Desktop with
   nothing to receive the drop makes Finder materialize it as a real `.txt`/`.png` file.
4. ~~At-rest encryption for concealed (password) items~~ (ADR-021) — **DONE 2026-07-21.**
   Scoped to just the opt-in concealed category (ADR-011), not the whole store — losing
   full-text search over the rare, already-flagged concealed subset was the trade that made
   this tractable where ADR-008's original "encrypt everything" framing stalled. Paired
   with redact-by-default/reveal-on-demand display; also fixed a pre-existing plaintext
   leak in Export History along the way.
   **Follow-up same day**: found that `isConcealed` is entirely capture-time/source-app-
   driven — passwords typed-and-⌘C'd or copied from apps that don't set the concealed
   pasteboard marker showed no protection at all, confirmed against a real pinned password
   with no 🔑 badge. Added `ClipboardStore.markConcealed(id:)` + a right-click "Mark as
   Concealed" context-menu action to retroactively encrypt existing plaintext items
   (one-way, text-only).
   **Critical follow-up, also same day**: the bounded-timeout/fallback-key mitigation the
   pre-implementation spike designed was exercised for real, not just in the lab — marking
   that exact real pinned password concealed happened to run during a session where the
   key fetch hit its 2-second bound, sealing it with a key that was never persisted. A
   later rebuild put a different key in play, and that item's plaintext is now
   unrecoverable. The design was wrong, not just risky as documented: removed the fallback
   key entirely (see ADR-021's critical follow-up) — the key is now set whenever it
   becomes available, no timeout, no placeholder, ever. Concealed-content actions are
   simply unavailable (fails safe, not silently insecure) until then.
   **Follow-up 2026-07-22**: a high-effort code review of everything built on ADR-021 since
   (concealed-storage hardening, retroactive concealment, portable encrypted exports)
   surfaced ten issues, all fixed on `fix/code-review-findings-2026-07-21` — see ADR-021's
   2026-07-22 follow-up in DECISIONS.md for the full list. Highlights: the key-pending
   retry queue added to `CaptureSaveQueue` traded the old data-loss bug for an unbounded
   plaintext-retention one (now capped, with bounded automatic retries instead of a bare
   drop); a transient migration failure in `setConcealedContentKey` could permanently
   disable concealed-content encryption for a session (now non-fatal and self-healing);
   archive import wasn't atomic (a failing entry left earlier entries already committed
   behind one misleading "Import failed" alert); portable-archive PBKDF2 key derivation ran
   on the main actor (froze the app during export/import).

## Next up (v0.5)

1. ~~QR code decoding on captured images~~ — **DONE 2026-09-07, ADR-022.** `VNDetectBarcodesRequest`
   behind a `BarcodeDetecting` seam mirroring `TextRecognizing`, run on the same background
   `CaptureSaveQueue` pass as OCR, sharing the `ocr_text` column so search/preview/paste/export
   needed no new plumbing. `QRPayloadClassifier` drops known secret-bearing payloads
   (`otpauth:`, `otpauth-migration:`, `WIFI:`) before any database write — screen snips never
   carry the concealed pasteboard marker, so ADR-011's protection can't cover them. Separate
   `decodeQRCodes` setting, default on.

2. ~~Explain omitted sensitive QR payloads~~ — **DONE 2026-09-08, ADR-023.** Persisted
   status distinguishes omission, encrypted storage, and unavailable-key failure. Card and
   preview notices are separate from searchable/copyable OCR content.
3. ~~Optionally save sensitive QR payloads encrypted~~ — **DONE 2026-09-08, ADR-023.**
   Separate default-off consent, persistent-key encryption, explicit preview reveal/copy,
   ciphertext same-Mac export and portable re-encryption. Original screenshots remain ordinary
   history. Both archive formats still import legacy versions; old apps reject new exports.

## Review follow-ups (2026-09-07 assessment, curated 2026-09-08)

The raw review was curated here and in ADR-023; no finding was silently discarded.

- **H1 — Fixed:** same-Mac export preflights concealed rows before any writes; ADR-021 follow-up.
- **H2 — Deferred, next hardening priority:** separate pinned access from the panel's 200-recent
  limit, including concealed pins that cannot be found by content search. Preserve recent-only
  quick-paste and avoid loading unlimited image blobs.
- **M1 — Deferred:** reject symlinked archive ancestors and enforce safe reads of manifests and
  blobs in both formats, including mutable-folder races. Existing direct symlink checks remain.
- **M2 — Fixed:** capture/OCR refresh preserves the selected ID; regression test in PanelModelTests.
- **M3 — Deferred:** coordinate Clear Everything/Clear Unpinned with captures, pending concealed
  text and delayed retries so pre-clear content cannot reappear.
- **M4 — Deferred:** build a replacement ZIP at a temporary sibling and atomically replace the
  destination only on success; failed export must preserve the previous backup.
- **M5 — Deferred:** lightweight list rows with on-demand image payloads; measure screenshot-heavy
  list/search/export memory and latency with Instruments (now installed).
- **M6 — Deferred:** bound portable KDF iteration parameters and archive expansion/allocation;
  add cancellation and malformed-input tests.
- **M7 — Deferred:** restore preset configuration as well as actual hotkey registration after
  conflicts; explicitly report double failure.
- **M8 — Capture path fixed:** all successful capture jobs notify the panel, including text and
  omitted QR. General import/purge observation remains deferred as a separate store-event task.
- **L1 — Fixed:** consent, QR privacy limits, portable-backup wording, operating manual and
  profiling-tool availability synchronized for v0.5.0.
- **L2 — Deferred:** choose consistent list-card/preview reveal lifetime. Current list cards
  remain revealed until hidden, shared, or a new panel session; UX now states this accurately.
- **Release tracking:** clarify issue #5 (whole-store versus shipped scoped encryption), reconcile
  merged v0.2–v0.5 functionality with the last published v0.1.0 tag before the next public release.
- **Further validation:** SQLite/FTS remanence after retroactive concealment, existing-directory
  permission failures, external-resource HTML conversion, and native partial-copy handling of
  revealed concealed text remain unverified concerns, not confirmed findings.

## Next up (v0.7)

1. **Searchable concealed content, without weakening at-rest encryption (ADR-024 follow-up).**
   The actual trigger for ADR-024: a search for a fragment of a password found nothing —
   trigram indexing fixed that for *unconcealed* text, but concealed items still store
   `text = nil` (ADR-011/021), so there's structurally nothing to index regardless of
   tokenizer. Proposed approach, not yet designed in detail: decrypt `encrypted_data`
   transiently in memory at query time (never persisted, never indexed), check for a
   substring match, and surface the item in results still fully redacted — exactly as today
   — unless the user separately hits Reveal. Matching ≠ displaying, so this doesn't weaken
   the redact-by-default/reveal-on-demand guarantee, but it's a real change to a guarantee
   CLAUDE.md calls out by name and needs its own ADR before implementation, including a cost
   bound on how many concealed items get decrypted per keystroke.
2. **"Show concealed only" quick filter.** Emerged from the same conversation: the user's
   "tag items as Password" idea collapses into something that already exists —
   `is_concealed` is already a boolean on every item. A filter (`is:concealed`, or a UI
   toggle) to narrow to just those costs close to nothing: no schema change, no ADR. Cheap
   enough to ship independent of item 1 above.
3. **`app:` syntax discoverability.** ADR-024 shipped the filter but deliberately left
   discovery as a follow-up: nothing today suggests `app:` exists or which app names are
   valid. A lightweight autocomplete/hint in the search field (e.g. suggest `app:Edge` once
   a few characters narrow to one known source app) — UI-only, no schema impact.

## Later

- **Sparkle auto-updates** — only meaningful once Developer ID signing exists (v1.0).
- **Homebrew cask** — requires notarized artifact (v1.0).
- **Localization scaffolding** — English-only for MVP.
- **`swift format` lint gate in CI** — currently advisory, make it enforced.

## Deliberately rejected (see ADRs / non-goals)

- Mac App Store distribution (ADR-007)
- Cloud sync (CLAUDE.md non-goals)
- Sandboxing (ADR-007)
- **Tabbed or visual Pinned/Recent split** (ADR-024 discussion) — the original ask that
  prompted ADR-024 ("scrolling through hundreds of pinned items looking for one"). Not
  pursued: the actual incident was a search bug (fixed by ADR-024) and a missing filter
  (BACKLOG "Next up" item 2), not a list-layout problem — scrolling was the symptom of
  search not working, not evidence that visual navigation was the fix. Revisit only if a
  findability problem is reported *after* items 1–3 above ship and search genuinely works.
- **General tag system** (ADR-024 discussion) — explored at length; no concrete use case
  survived that wasn't already covered by `app:` filtering, content search, or the
  concealed-only filter above. Revisit only with a real example that doesn't fit any of
  those.
