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
- Modern macOS collapses many third-party menu-bar icons into Control Center's own
  aggregated list, where they show up as unlabeled `"status menu"` entries via
  accessibility queries and don't expose their `NSMenu` the classic
  `menu 1 of menu bar item N` way. Don't rely on identifying a specific app's status icon
  this way — trigger the app's actual global hotkey and confirm its own panel/window
  directly instead; that's both more reliable and closer to what a real user experiences.

## Manual smoke checklist (before every tag)

Environment note: ad-hoc signed builds get a **new identity every re-sign** — macOS will
drop the Accessibility grant after rebuilds. Re-grant in System Settings → Privacy &
Security → Accessibility (remove stale entry, re-add). To reset for testing:
`tccutil reset Accessibility com.fuzzylogicyetis.Permafrost`.

1. **Launch**: `./scripts/make-app.sh && open dist/Permafrost.app` → snowflake appears in
   menu bar; no Dock icon; no window. If your menu bar is auto-hidden (fullscreen apps,
   or the global auto-hide preference), you have to reveal it first — don't mistake a
   hidden menu bar for a missing icon. See ADR-013 if the icon still isn't there once the
   bar is actually visible.
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

## Performance spot checks

- Panel open feels instant (< 100 ms) with 1k+ items
- Typing in search never drops keystrokes
- `top`: idle CPU ~0.0 for the Permafrost process
