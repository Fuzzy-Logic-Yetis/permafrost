# Testing

## Unit tests (automated)

`./scripts/test.sh` — Swift Testing framework. The script wraps `swift test` with the
framework paths that Command Line Tools-only machines need; with full Xcode installed,
plain `swift test` works too.

Most storage/search/retention behavior lives in `PermafrostCoreTests`. Lightweight
UI-layer coverage lives in `PermafrostTests`, which imports the app module and exercises
`PanelModel` against an in-memory store plus a fake paste service. These tests deliberately
avoid screenshots, synthetic key events, pasteboard writes, or Accessibility prompts.

Required coverage (these are the product's guarantees):

- **Retention**: pinned item survives a purge that removes everything else; unpinned item
  older than TTL is removed; item younger than TTL survives; count cap removes oldest
  unpinned first and never touches pinned; `maxAge = nil` never deletes.
- **Dedup**: saving identical content twice yields one row with bumped `last_used_at`;
  re-copying a pinned item does not unpin it.
- **Search**: FTS prefix matching (`hel` finds "Hello world"), multi-token queries,
  queries with FTS-hostile characters (`"`, `*`, `(`) fall back safely, image items with no
  OCR metadata are excluded from text search but present in unfiltered list, and image rows
  with `ocr_text` can match recognized text without changing image paste behavior.
- **Ordering** (ADR-012): unpinned first by `last_used_at` desc, then pinned in their own
  section (most-recently-pinned first, stable `pin_order`) — unpinned entries must always
  precede pinned ones regardless of age, since the panel's `⌘1`–`⌘9` quick-paste bound
  depends on that invariant.
- **Dedup metadata**: re-copying identical text refreshes `sourceApp` and `richData` to the
  new capture; re-copying identical images refreshes non-nil OCR metadata without changing
  the image content hash/dedup key and does not clear existing OCR text just because a later
  capture has none; `isConcealed` is OR'd (sticky in the safer direction), never
  cleared by a later non-concealed copy of the same content.
- **Import/export**: round-trip preserves content, kind, OCR text metadata for image rows,
  pinned state, timestamps; import
  into a store with overlapping content skips duplicates; unknown manifest version fails
  loudly; a manifest blob path outside the archive root (absolute path or `..` traversal)
  is rejected before the filesystem is touched. Added 2026-07-07 (review M-2): a
  recomputed content hash that doesn't match the manifest's claim is rejected; a `.text`
  entry with an image blob (or vice versa) is rejected; a symlinked blob file is rejected
  without being followed.
- **Thumbnails and image storage**: image capture produces a thumbnail ≤ the max pixel
  size; large images preserve original image data while generating a bounded thumbnail;
  identical large images deduplicate; large image rows obey the same recent-first/pinned
  ordering as text rows; corrupt image data doesn't crash.
- **Panel model**: show/search resets, selection clamping, `⌘1`-`⌘9` quick-paste restricted
  to the unpinned prefix, commit callback order and Accessibility fallback, pin toggling,
  delete selection bounds, and preview-mode behavior: preview opens/closes, closes on
  `prepareForShow`, follows selection, and commit/delete/pin/quick-paste still resolve to
  the intended selected/recent item while preview is shown.
- **Hotkey registration rollback**: app-target tests fake registration success/failure so
  Carbon does not need to fail globally; they cover successful custom registration, first
  custom failure falling back to the selected preset, and replacement custom failure
  restoring the previous working custom shortcut while surfacing the rejected chord.
- **Pasteboard capture policy**: `PasteboardCapturePolicy.decide` (extracted from
  `PasteboardWatcher.poll`, BACKLOG item 12) — paused capture skips; excluded frontmost
  app skips; concealed content skips by default; concealed content captures once opted in
  (`recordConcealed`); transient/auto-generated types skip; normal content captures; pause
  takes priority when multiple skip reasons apply at once. Tested with plain `Input` values
  — no `NSPasteboard`/`NSWorkspace` involved.
- **OCR text normalization** (BACKLOG item 13, issue #6): `OCRTextNormalizer` — lines sort
  top-to-bottom, ties broken left-to-right; per-line trimming; runs of blank lines collapse
  to one; leading/trailing blank lines are stripped; empty input yields an empty string.
  Tested with plain `RecognizedLine` values, no Vision/`VNRecognizedTextObservation`
  involved. `VisionTextRecognizer` itself (the actual Vision call) has no automated test —
  it's a thin, side-effect-free wrapper around `VNImageRequestHandler.perform`; exercise it
  manually by copying a screenshot with visible text once the storage/UI wiring lands.

CI runs `swift build && swift test` on every push (`.github/workflows/ci.yml`). Green CI is
a merge precondition (CLAUDE.md → Definition of Done).

## Scripted verification (osascript / screencapture / cliclick)

When driving the running app from a terminal instead of by hand (useful for a Claude
session to self-verify a fix), a few environment-specific gotchas from doing this on a dev
machine running inside VS Code, learned the hard way on 2026-07-06/07:

- **Never synthesize `Escape` system-wide** (`osascript -e 'tell application "System
  Events" to key code 53'`, or `cliclick kp:esc`) to dismiss a menu/panel during a scripted
  check. `Escape` is a real, system-wide key event — it does not stay scoped to whatever
  app you're aiming at. If the host editor (VS Code, with the Claude Code extension) has
  Escape bound to "interrupt the current agent request" — which it does — that synthetic
  keystroke lands there too and silently cancels the very session that sent it, producing a
  confusing loop of "tool use rejected" with no actual human action behind it. Dismiss
  UI some other way instead: click elsewhere, let the panel's own auto-dismiss (loses key
  status) handle it, or just leave a test artifact open — it's not destructive.
- Sending other synthetic keystrokes (`⌥⌘V` to trigger the hotkey, plain text via
  `keystroke`) and mouse moves (`cliclick m:x,y`) are fine — this was only ever about
  Escape specifically colliding with an IDE-level shortcut.
- The **terminal/editor process itself** needs its own Accessibility and Screen Recording
  grants (System Settings → Privacy & Security) before `osascript keystroke`,
  `screencapture`, or `cliclick` will work at all — separate from whatever Permafrost's own
  Accessibility grant is. Granting these requires restarting the host app (VS Code) for the
  new permission to take effect.
- Always relaunch `dist/Permafrost.app` with `open dist/Permafrost.app`, never by exec'ing
  the raw binary (`./dist/Permafrost.app/Contents/MacOS/Permafrost`) from a shell (found
  2026-07-21). TCC's "responsible process" attribution can credit a directly-exec'd child
  with its launching process's own grants instead of the child's — if the host terminal/IDE
  already has Accessibility (as VS Code/Claude typically do on this dev machine), a
  raw-exec'd Permafrost read `AXIsProcessTrusted() == true` with **zero** TCC record under
  Permafrost's own identity, and no corresponding row in System Settings at all. `open`
  launches through LaunchServices like a real user double-click, giving Permafrost its own
  independent identity and an honest read.
- `screencapture -R x,y,w,h` takes **points**, not the pixel dimensions `sips -g
  pixelWidth` reports — on a scaled-resolution Retina display these differ (e.g. a
  2940×1912-pixel capture on a display whose actual logical width is ~1470pt). Requesting
  an out-of-range region fails with "does not intersect any displays"; requesting more
  than the real width from `x=0` silently clamps rather than erroring, which can look like
  success while quietly not being the region you meant. When in doubt, capture the full
  screen unregioned and crop the saved file, or verify against a known-good coordinate
  (e.g. a window's own position/size via `System Events`) rather than assuming pixel dims.
- `cliclick m:x,y` / `c:x,y` also take **points, not pixels** — same 2x gotcha as
  `screencapture -R` above. Converting a coordinate you eyeballed from a *displayed* (chat)
  image requires two steps, not one: multiply by the image's own displayed→original ratio
  to get real pixels, **then divide by 2** for cliclick's point space. Forgetting the second
  step silently clicks the wrong place with no error — verify by screenshotting immediately
  after a click and confirming the expected UI actually changed.
- `IOHIDCheckAccess`/`IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)` is the correct way
  to explicitly request **Input Monitoring** (distinct from Accessibility) with a normal
  system prompt — see ADR-014. Once TCC has recorded a *denial* for a service, the API
  won't re-prompt; `tccutil reset ListenEvent <bundle-id>` clears it without needing a
  password (unlike manually adding an app via System Settings' "+" button, which does).
  Because `requestInputMonitoringAccessIfNeeded()` runs on every launch, and ad-hoc
  rebuilds mean TCC sees a brand-new, never-before-seen signature each time, the native
  "Keystroke Receiving" system prompt will pop up on **every fresh ad-hoc rebuild's first
  launch** during development — this is expected, correct system behavior for an
  undetermined grant, not a bug. It's tied to *launching the app*, not to opening
  Permafrost's own Settings window, even though the two often happen close together during
  a test cycle and can look related. A real end user would only see this once, on their
  genuine first launch.
- Checking Permafrost's box directly in System Settings → Input Monitoring while it's
  already running pops up **macOS's own** "Quit Now / Later" dialog (found 2026-07-21,
  confusable with a Permafrost bug) — Input Monitoring only takes effect after the process
  restarts, so the OS forces that choice itself; Permafrost's code has no part in it. "Quit
  Now" quits the app, and since this is an ad-hoc-signed dev build launched manually (not a
  registered Login Item), macOS does **not** reliably auto-relaunch it afterward — you need
  to relaunch by hand (`open dist/Permafrost.app`). A real notarized/signed release may
  behave better here, but don't assume it during ad-hoc dev testing.
- Modern macOS collapses many third-party menu-bar icons into Control Center's own
  aggregated list, where they show up as unlabeled `"status menu"` entries via
  accessibility queries and don't expose their `NSMenu` the classic
  `menu 1 of menu bar item N` way. Don't rely on identifying a specific app's status icon
  this way — trigger the app's actual global hotkey and confirm its own panel/window
  directly instead; that's both more reliable and closer to what a real user experiences.

## Manual smoke checklist (before every tag)

Environment note: ad-hoc signed builds get a **new identity every re-sign** — macOS will
drop the Accessibility/Input Monitoring grants after rebuilds. The confusing part
(confirmed 2026-07-07): the System Settings checkbox for "Permafrost" can still *appear*
checked after a rebuild — it's matched by name/bundle ID for display, but tied to the
*previous* signature underneath. Permafrost's own Settings → Permissions display will
correctly and honestly report **Not granted** for the new binary despite the checkbox
looking checked. Toggling the existing checkbox off and back on is **not sufficient** — it
doesn't rebind to the new signature. Fix: Settings → Permissions → **"Reset Permissions…"**
(ADR-016), then grant fresh via the "Open System Settings" button next to each row — no
relaunch needed, the status updates live within ~2 seconds. Don't rebuild again before
verifying (any further rebuild repeats the mismatch). The manual equivalent, if needed
outside the app (e.g. CI or a broken build that won't launch):
`tccutil reset Accessibility com.fuzzylogicyetis.Permafrost` and
`tccutil reset ListenEvent com.fuzzylogicyetis.Permafrost`.

1. **Launch**: `./scripts/make-app.sh && open dist/Permafrost.app` → snowflake appears in
   menu bar; no Dock icon; no window. If your menu bar is auto-hidden (fullscreen apps,
   or the global auto-hide preference), you have to reveal it first — don't mistake a
   hidden menu bar for a missing icon. If it's genuinely still not there: macOS silently
   drops menu-bar-extra icons that don't fit when the bar is crowded, with no overflow
   indicator at all (ADR-015, not a Permafrost bug) — free space via System Settings →
   Menu Bar (disable Siri/Spotlight) or by quitting other menu-bar-extra apps.
2. **Capture text**: copy three different strings in another app → `⌥⌘V` → all three
   present, newest first.
3. **Capture snip**: `⌃⇧⌘4`, snip a region → `⌥⌘V` → thumbnail card present → `⏎` into
   Preview (File → New from Clipboard works too) → image intact.
4. **Paste-on-select**: focus TextEdit, `⌥⌘V`, arrow to an item, `⏎` → text lands in
   TextEdit without clicking; TextEdit never lost focus.
5. **Search**: `⌥⌘V`, type a fragment → list filters live; `Esc` clears search first, then
   closes.
6. **Pin**: `⌥P` an item → it moves to the pinned section; restart the app → still pinned.
7. **Retention**: in Settings set TTL to the test value (1 day), insert a row with an old
   `last_used_at` via `sqlite3`, relaunch → old unpinned row gone, pinned rows intact.
8. **Concealed types (default)**: copy a password from a password manager → it must NOT
   appear in history.
8b. **Concealed opt-in**: enable Settings → Privacy → record passwords → acknowledgment
    dialog appears (Cancel reverts the toggle); accept, copy a password → it appears with
    the 🔑 marker, can be pinned, survives restart.
9. **Dedup**: copy the same text twice → one entry, moved to top.
10. **No accessibility**: revoke permission → `⏎` falls back to copy-only (item on
    pasteboard, panel closes, onboarding alert offers the settings deep link).
11. **Settings**: change retention/hotkey preset/launch-at-login → each takes effect
    without relaunch (hotkey re-registers immediately).
12. **Import/export**: export archive, wipe DB (quit app, delete
    `~/Library/Application Support/Permafrost/`), relaunch, import → history and pins back.
13. **Pin ordering & quick-paste (ADR-012)**: pin an older item, then copy something new →
    `⌥⌘V` → the new copy is at the top of RECENT and pastes with `⌘1`; the pinned item shows
    under a separate PINNED header at the bottom and never responds to a number key.
14. **Hover actions**: hover a card → pin/share/delete buttons replace the badges; clicking
    each works and does **not** also trigger paste-on-select (the card's tap-to-paste must
    not fire underneath a button click).
15. **Bulk history actions** (menu bar *and* Settings → History Management): Clear Unpinned
    History (pinned survives), Unpin All Items (pinned items reappear in RECENT, no data
    lost, then expire per retention like anything else), Clear Everything (wipes all,
    strongest confirmation). Trigger a failure (e.g. quit the app mid-operation isn't
    testable manually, but confirm the failure path exists in code review) — on success,
    verify Settings' "N items, M pinned" footer updates immediately. Both surfaces (menu
    bar and Settings) now share the same failure-alert path (ADR-017, review M-3).
16. **Welcome alert**: delete `didShowWelcome` from defaults (or fresh install), launch →
    alert offers **Got It** and **Enable Launch at Login**; the latter actually toggles the
    login item (check System Settings → General → Login Items).
17. **Reset Permissions (ADR-016)**: with Accessibility granted, rebuild (new signature) →
    Settings shows Not granted despite the System Settings checkbox still appearing
    checked → Settings → Permissions → Reset Permissions… → re-grant via the row's "Open
    System Settings" button (now always visible, granted or not) → status flips to Granted
    within ~2s with no relaunch needed. Also confirm both rows' "Open System Settings"
    buttons show up while already Granted, and that a reset failure (hard to force manually,
    but confirm in code review: non-zero `tccutil` exit) surfaces via the "Operation failed"
    alert instead of failing silently.
17a. **Reset Permissions on an already-granted, same-session process**: with Accessibility
    (or Input Monitoring) already Granted in the *current* running session (no rebuild),
    click Reset Permissions… → the dot flips to orange immediately and **stays orange** —
    it must not flip back to green on its own within the next few 2-second poll ticks, even
    though the live `AXIsProcessTrusted()`/`IOHIDCheckAccess` read is known to still report
    stale "granted" in this scenario (found 2026-07-21). Then re-grant via "Open System
    Settings" → confirm it correctly flips back to Granted once you check the box (proving
    the reconfirm gate disarms itself rather than getting stuck).
18. **Settings window fits on screen**: open Settings → entire window (through History
    Management) is visible and none of it is hidden behind the Dock or off-screen; window
    is draggable via its title bar and resizable via its edges (found 2026-07-07: it had
    grown taller than the screen as sections were added, with no way to reposition it since
    it also wasn't resizable at the time).
19. **Pause Capture**: status menu → Pause Capture shows a checkmark and the snowflake
    tints orange; copy a unique string while paused → it does not appear in `⌥⌘V`; uncheck
    Pause Capture, copy another unique string → the second string appears, while the skipped
    paused string is not backfilled. Settings → General mirrors the paused state.
20. **Per-app exclusion**: Settings → Excluded Apps → Add App…, pick an app (e.g. Terminal)
    → it appears in the list. Switch to that app, copy text → `⌥⌘V` → item does NOT appear.
    Remove it from the list, copy the same text again → it now appears. Quit and relaunch
    Permafrost → the exclusion list persists.
21. **Custom hotkey recorder**: Settings → General → Record Custom…, press a chord with at
    least one of `⌘`, `⌥`, or `⌃` (for example `⌃⌥H`) → Active hotkey and the status-menu
    Open title update immediately, and the new chord opens/closes the panel without
    relaunch. Try a plain key or Shift-only chord → it is rejected. Record again and press
    `Esc` or Cancel → the old shortcut remains. Use Selected Preset → the chosen preset
    works again. Reset to Default → `⌥⌘V` works again. Quit/relaunch → the last custom
    shortcut persists if one was active.
22. **Paste as plain text (ADR-018)**: copy some bold/rich text from **Word, Pages, Notes,
    TextEdit in Rich Text mode, or a browser** (ADR-019 added HTML→RTF conversion, so
    browser copies carry recovered rich data too now — see item 22a). Open the panel →
    hover the card → confirm a 📄 "Paste as Plain Text" icon appears alongside
    pin/share/delete, and hovering/clicking it does **not** trigger the card's own
    click-to-paste (no premature commit). Click it → pastes into the target app with
    formatting stripped (plain text only), panel closes. Repeat via keyboard: select the
    same item, press `⇧⏎` → identical stripped-formatting result, vs. plain `⏎` which still
    pastes the rich version. Confirm the 📄 icon does **not** appear when hovering an
    `.image` card, and that `⇧⏎` on a selected image card falls back to a normal (rich)
    paste rather than doing nothing.
22a. **HTML→RTF rich capture (ADR-019)**: copy formatted text from a browser — a product
    page with a strikethrough sale price and a colored "Sale"/"Best Seller" badge is a good
    real-world test (Amazon and most e-commerce product pages qualify) — → paste rich
    (`⏎`) into a rich-text app (TextEdit in Rich Text mode, Word, Pages) → confirm bold/
    italic/strikethrough survive, **and confirm no background color/highlight box and no
    colored text comes through** (found 2026-07-21 testing against a real product page and
    Amazon: the badge's background color was carrying over as an opaque gray/tan box, and
    link text kept its color — both intentionally stripped now; only the *style*
    (bold/italic/strikethrough/underline) survives, not color). Paste as plain text (`⇧⏎`)
    on the same item → confirm it's still fully stripped. Separately, copy from
    Word/Pages/Notes (native `.rtf` present) → confirm behavior is bit-for-bit unchanged
    from before this ADR, background color and text color included — the sanitization only
    runs on the HTML-derived path, never on native RTF (check
    `~/Library/Application Support/Permafrost/store.sqlite`'s `rich_data` length matches
    what was on the pasteboard for a native-RTF item, not a converted/re-encoded version).
    **Critical regression check** (found 2026-07-21: this silently destroyed the source
    item once already): after a plain-text paste, re-open the panel and confirm the
    **same item still shows its rich content** (or check
    `~/Library/Application Support/Permafrost/store.sqlite`'s `rich_data` column directly)
    — it must not have been nulled out or duplicated into a second, plain-only entry.
    `PasteboardWatcher.ignoreOwnWrite()` exists specifically to prevent Permafrost's own
    paste writes from being re-captured as if they were a new incoming copy; if this check
    ever fails again, that's where to look first.
23. **Preview pane**: `⌥⌘V`, select a long multi-line text item, press `␣` → full text
    appears in an overlay (unwrapped, scrollable if long), replacing the list within the same
    panel size; select some of the text with the mouse to confirm it's copyable. Press `↑`/
    `↓` → preview updates to the newly selected item without closing. Press `␣` again → closes,
    list reappears. Reopen preview, press `Esc` → preview closes but the panel stays open;
    press `Esc` again → panel closes (search was empty) or search clears first (non-empty).
    Select an image item, press `␣` → full-resolution image shown (not the card's thumbnail),
    scaled to fit. Type a character while the field is empty and preview is closed → confirm
    it goes into the search field rather than toggling preview (only an *empty* field treats
    `␣` as the preview key).
24. **Custom hotkey conflict/rollback (review M-1)**: pick a chord already claimed
    system-wide (a reliable one: `⌘Space`'s modifier alone won't register since it needs a
    letter/number/etc. — instead bind Permafrost's custom hotkey to the same chord already
    used by e.g. a running app's global shortcut, such as a screenshot tool's capture key,
    or simplest: register the same chord in a second copy of Permafrost first so the OS
    already owns it). Recording that chord in Settings should, instead of silently claiming
    success: revert the Active Hotkey display back to the previous working shortcut, show an
    inline error message naming the rejected chord, and the previous shortcut must still
    open the panel.
25. **Drag-and-drop out of the panel (ADR-020)**: quick click on a text/image card still
    pastes-and-closes exactly as before (regression check). Press-and-drag a text card onto
    TextEdit/Notes/Mail compose → plain text lands at the drop point, panel stays open
    throughout. Press-and-drag an image card onto Finder/Mail compose → lands as a real
    image (PNG), not a broken/empty file. Hover a card to reveal pin/share/delete/📄, click
    one of those buttons → still performs that action, does not instead start dragging the
    whole card. Drag onto the Desktop with nothing to receive it → Finder materializes the
    drop as a real `.txt`/`.png` file (confirmed 2026-07-21 — an emergent side effect of
    using plain `String`/PNG `Data` as the drag payload, not something specifically built,
    but a nice one). Drag and release somewhere that won't accept it → nothing pastes
    anywhere, panel unaffected, no crash/hang.
26. **Concealed-content encryption (ADR-021)**: with "Record concealed content" enabled
    (Settings), copy a password from a password manager's copy-password button → the card
    shows `••••••••••••` by default, both in the list and in preview (`␣`). Hover the card
    → an eye icon appears in the hover row alongside pin/share/delete/📄 → click it → the
    actual text appears in place, monospaced; click again (or the eye-slash icon) → re-
    redacts. In the preview pane, a "Reveal"/"Hide" button does the same. A plain click on
    the card, or `⏎`, still pastes the real content (decrypted transparently) without
    requiring reveal first — reveal is a display-only toggle, independent of paste.
    Directly inspect `~/Library/Application Support/Permafrost/store.sqlite` for that row:
    `text`/`rich_data` must be NULL, `encrypted_data` must be non-NULL and non-empty.
    Confirm it's genuinely unsearchable: type a fragment of the actual password into the
    search field → no match; the item still appears in the unfiltered list. Export History,
    then check the exported `manifest.json` directly → the password's plaintext must not
    appear anywhere in that file (it should only be reachable via the separate
    `.encrypted` blob file). Import that same archive back in → the item reappears and
    still decrypts/pastes correctly. Copy an *ordinary* (non-concealed) password-shaped
    string for contrast → confirm it behaves completely normally (visible, searchable, no
    eye icon) — nothing about this feature should affect non-concealed content.

    **Ad-hoc rebuild scenario** (found via spike, 2026-07-21, see ADR-021): after rebuilding
    Permafrost (new ad-hoc signature) with concealed items already recorded from a prior
    build, launch it and confirm the app still opens and works normally within a couple of
    seconds — even if macOS shows a Keychain authorization prompt for the concealed-content
    key in the background, launch must not hang waiting on it indefinitely (bounded ~2s
    timeout, falls back to a session-only key). If that happens, previously-recorded
    concealed items won't decrypt correctly *this session* — expected and specific to
    ad-hoc dev signing, not a bug; resolves permanently once Developer ID signing lands.
27. **Mark as Concealed (ADR-021 follow-up)**: copy a password-shaped string through a
    plain route that doesn't set the source app's concealed marker (type it and ⌘C, or
    copy from Notes/TextEdit) → confirm it shows up as ordinary, unredacted text (no 🔑, no
    eye icon) — proving the gap this closes is real. Right-click the card → "Mark as
    Concealed" appears → click it → the card immediately redacts (`••••••••••••`), gains
    the 🔑 badge and the eye reveal icon, exactly like a natively-concealed item. Confirm
    in `store.sqlite`: `text`/`rich_data` are now NULL, `encrypted_data` is populated.
    Confirm it's no longer findable via search. Right-click it again → "Mark as Concealed"
    should **not** appear anymore (no "unmark," one-way only). Right-click an `.image` card
    → the option should not appear at all (text-only). Drag a concealed card (mouse, not
    automatable — see ADR-020's own note on this) onto a native app → confirm the real
    decrypted text lands, not an empty drop (found 2026-07-21: this was silently dragging
    an empty string before the fix, since `item.text` is nil for encrypted rows).

## Performance spot checks

- Panel open feels instant (< 100 ms) with 1k+ items
- Typing in search never drops keystrokes
- Large image capture does not visibly stall panel/search interaction; measure with
  Instruments around screenshot-to-clipboard captures before closing BACKLOG item 5.
- `top`: idle CPU ~0.0 for the Permafrost process
- Large image capture: copy a 10–25 MB image or full-resolution screenshot, immediately
  open `⌥⌘V`, and confirm the panel remains responsive while the capture is saved in the
  background. The image should appear shortly after save completes; later copies should
  preserve recency order based on capture time, not thumbnail/write completion time.
