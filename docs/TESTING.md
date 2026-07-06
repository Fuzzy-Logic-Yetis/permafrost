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
- **Ordering**: pinned first (stable `pin_order`), then unpinned by `last_used_at` desc.
- **Import/export**: round-trip preserves content, kind, pinned state, timestamps; import
  into a store with overlapping content skips duplicates; unknown manifest version fails
  loudly.
- **Thumbnails**: image capture produces a thumbnail ≤ the max pixel size; corrupt image
  data doesn't crash.

CI runs `swift build && swift test` on every push (`.github/workflows/ci.yml`). Green CI is
a merge precondition (CLAUDE.md → Definition of Done).

## Manual smoke checklist (before every tag)

Environment note: ad-hoc signed builds get a **new identity every re-sign** — macOS will
drop the Accessibility grant after rebuilds. Re-grant in System Settings → Privacy &
Security → Accessibility (remove stale entry, re-add). To reset for testing:
`tccutil reset Accessibility com.fuzzylogicyetis.Permafrost`.

1. **Launch**: `./scripts/make-app.sh && open dist/Permafrost.app` → snowflake appears in
   menu bar; no Dock icon; no window.
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

## Performance spot checks

- Panel open feels instant (< 100 ms) with 1k+ items
- Typing in search never drops keystrokes
- `top`: idle CPU ~0.0 for the Permafrost process
