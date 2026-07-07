# Testing

## Unit tests (automated)

`./scripts/test.sh` — Swift Testing framework, targets `PermafrostCore` only (the
executable is a thin shell; its logic lives in core precisely so it can be tested
headlessly). The script wraps `swift test` with the framework paths that Command Line
Tools-only machines need; with full Xcode installed, plain `swift test` works too.

Required coverage (these are the product's guarantees):

- **Retention**: pinned item survives a purge that removes everything else; unpinned item
  older than TTL is removed; item younger than TTL survives; count cap removes oldest
  unpinned first and never touches pinned; `maxAge = nil` never deletes.
- **Dedup**: saving identical content twice yields one row with bumped `last_used_at`;
  re-copying a pinned item does not unpin it.
- **Search**: FTS prefix matching (`hel` finds "Hello world"), multi-token queries,
  queries with FTS-hostile characters (`"`, `*`, `(`) fall back safely, image items
  excluded from text search but present in unfiltered list.
- **Ordering** (ADR-012): unpinned first by `last_used_at` desc, then pinned in their own
  section (most-recently-pinned first, stable `pin_order`) — unpinned entries must always
  precede pinned ones regardless of age, since the panel's `⌘1`–`⌘9` quick-paste bound
  depends on that invariant.
- **Dedup metadata**: re-copying identical text refreshes `sourceApp` and `richData` to the
  new capture; `isConcealed` is OR'd (sticky in the safer direction), never cleared by a
  later non-concealed copy of the same content.
- **Import/export**: round-trip preserves content, kind, pinned state, timestamps; import
  into a store with overlapping content skips duplicates; unknown manifest version fails
  loudly; a manifest blob path outside the archive root (absolute path or `..` traversal)
  is rejected before the filesystem is touched.
- **Thumbnails**: image capture produces a thumbnail ≤ the max pixel size; corrupt image
  data doesn't crash.

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
    verify Settings' "N items, M pinned" footer updates immediately.
16. **Welcome alert**: delete `didShowWelcome` from defaults (or fresh install), launch →
    alert offers **Got It** and **Enable Launch at Login**; the latter actually toggles the
    login item (check System Settings → General → Login Items).
17. **Reset Permissions (ADR-016)**: with Accessibility granted, rebuild (new signature) →
    Settings shows Not granted despite the System Settings checkbox still appearing
    checked → Settings → Permissions → Reset Permissions… → re-grant via the row's "Open
    System Settings" button → status flips to Granted within ~2s with no relaunch needed.
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
21. **Preview pane**: `⌥⌘V`, select a long multi-line text item, press `␣` → full text
    appears in an overlay (unwrapped, scrollable if long), replacing the list within the same
    panel size; select some of the text with the mouse to confirm it's copyable. Press `↑`/
    `↓` → preview updates to the newly selected item without closing. Press `␣` again → closes,
    list reappears. Reopen preview, press `Esc` → preview closes but the panel stays open;
    press `Esc` again → panel closes (search was empty) or search clears first (non-empty).
    Select an image item, press `␣` → full-resolution image shown (not the card's thumbnail),
    scaled to fit. Type a character while the field is empty and preview is closed → confirm
    it goes into the search field rather than toggling preview (only an *empty* field treats
    `␣` as the preview key).

## Performance spot checks

- Panel open feels instant (< 100 ms) with 1k+ items
- Typing in search never drops keystrokes
- `top`: idle CPU ~0.0 for the Permafrost process
