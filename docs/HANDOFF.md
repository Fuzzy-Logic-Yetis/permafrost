# Handoff

The state a fresh session needs, written by the previous session's `/handoff` (see
[CLAUDE.md](../CLAUDE.md), "Org standards"). Rewritten each time, not appended; git keeps
the history. Under 150 lines.

Last written 2026-11-17, after the filter chips and the app chip merged.

## State of `main`

- v0.6.0 is the released version; the v0.7 search work and the filter chips have landed on
  `main` but are not tagged. CI is green. Last change: the chip-row refresh fix (#29).
- Landed since the last handoff: placeholder mentions `app:` (#25); the open-time app filter
  quotes names with spaces (#26); filter chips under the search field, `⌥T today`, `⌥S pinned`,
  `⌥C concealed`, `⌥I image`, `⌥L link`, reset every time the panel opens (#27); an `app` chip
  (`⌥A`) that removes the open-time app filter and restores it from the remembered opened-from
  app, and a panel width taken from its own chrome so nothing wraps (#28); the chip row
  re-render fix (#29). Before that: v0.7 search (ADR-028 grammar, ADR-029 time filters,
  `is:` and `app:` suggestions), H2 and M3.
- Verified on the owner's MacBook Air: `swift build` succeeds, `swift test` passes (234
  tests: 100 in the app target, 134 in core), `./scripts/check-docs.sh` reports consistent.
- `main` is protected on GitHub (ADR-027): no direct pushes, and the CI `test` check must
  pass. Secret scanning (with push protection) and Dependabot security updates are on.

## The running app

- `dist/Permafrost.app` is `main` at `fc2b4f0` (everything above, through #29). Verify any
  build with `/usr/libexec/PlistBuddy -c 'Print :PermafrostGitRevision'
  dist/Permafrost.app/Contents/Info.plist`; it prints the commit the bundle was built from.
- The owner relaunched it and confirmed the filter chips look right and the `app` chip works
  (2026-11-17). Manual checks 5c to 5k in docs/TESTING.md are otherwise not all recorded as run.
- Every ad-hoc rebuild is a new code identity: after relaunching, the owner re-grants
  Accessibility and Input Monitoring (Settings > Permissions > Reset Permissions). A Developer
  ID (v1.0) would end that. Rebuilding (`./scripts/make-app.sh`) is always the owner's call.

## How to work here

- Every change goes on a branch, then a PR, then waits for CI. Agents open PRs and never
  merge or push to `main`; the owner merges.
- Work in a git worktree (`git worktree add ../permafrost-wt/<name> -b <branch>`), not by
  switching branches in the main checkout. That checkout stays on `main` because it builds
  the running app. Remove the worktree and branches after the PR merges.
- Never run `scripts/make-app.sh`, touch `dist/`, or quit, kill, relaunch or reinstall the
  running app unless the owner says to. `swift build` and `swift test` use `.build/`.
- A coordinator session on another machine ("claude lead - opus") reviewed PRs earlier. On
  2026-11-17 the owner said to leave it out (he cannot resume it), so do not message it unless
  he asks. A relayed decision is never owner approval: ADR-level decisions need the owner's
  confirmation in the session making the change (CLAUDE.md).
- Agent PR and review comments start with `🤖 <model>:`.
- `gh` lives at `/opt/homebrew/bin/gh` and is not on `PATH`. It was re-authenticated on
  2026-11-17 (the old token had expired); it stores the token in `~/.config/gh/hosts.yml`.
  If `gh` says the token is invalid, the owner runs `gh auth login -h github.com` himself.
  Git prints an SSH "device not found" warning when the Yubikey is absent; fetches still work.
  If CI shows "job was not acquired by Runner", it is GitHub macOS capacity: re-run it.

## Open work

- None in flight. No open branches or PRs. Worktrees: the main checkout and
  `../permafrost-wt/handoff` (this PR, remove after it merges).

## Decisions not yet recorded

- None.

## Next steps

1. Wait for the owner to pick the next item.
2. Backlog candidates (docs/BACKLOG.md): remaining review follow-ups M1, M4, M6 (import and
   export hardening), M5 (lightweight list rows for screenshot-heavy history), M7 (restore
   the hotkey preset after a failed registration), L2 (consistent reveal lifetime).
3. Searchable concealed content (v0.7 item 1) is paused by the owner and needs its own ADR
   plus independent review first.
4. v1.0 distribution (Developer ID, notarization, Sparkle, Homebrew) is gated on the Apple
   Developer Program; see docs/ROADMAP.md.

## Gotchas

- **SwiftUI skips re-rendering a subview whose inputs look equal.** Closures that read an
  `ObservableObject` (`{ model.isChipActive($0) }`) look equal from one render to the next, so
  the subview kept stale state (the `app` chip stayed dead, #29). Pass plain `Equatable`
  values (see `ChipStates`), not model-reading closures.
- The panel width is not a constant: `PanelLayout.width` is the wider of the chip row and the
  footer hints, measured from the real views. Adding a chip or hint widens it.
- `./scripts/check-docs.sh` treats every `docs/*.md` path it sees in any Markdown file as a
  real file, and every `ADR-NNN` as an ADR in docs/DECISIONS.md. When citing other repos
  (for example Ridgeline), use full URLs and don't use their ADR numbers.
- Saving identical text twice dedups into one row and refreshes its source app, so tests
  that need two rows must use different text.
- `swift build` prints a Combine import warning in `SettingsView.swift`; it is only a warning.
