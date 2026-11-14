# Handoff

The state a fresh session needs, written by the previous session's `/handoff` (see
[CLAUDE.md](../CLAUDE.md), "Org standards"). Rewritten each time, not appended; git keeps
the history. Under 150 lines.

Last written 2026-11-14, after the v0.7 search work (backlog items 6 to 9) merged.

## State of `main`

- v0.6.0 is the released version; v0.7 search work has landed on `main` but is not tagged.
  CI is green. Last change: ADR-029 (time filters, #23).
- Landed since the last handoff, newest first: time filters `is:today` and `age:<N>m|h|d` on
  last-used time (ADR-029, #23); one search grammar, filters combine in any order, `app:`
  takes one word or a quoted name (ADR-028, #22); `is:` and `app:` suggestion rows with Tab
  and arrow acceptance (#21); `is:image`, `is:text`, `is:link` (#20); pinned items no longer
  share the 200-row cap, backlog H2 (#17); clearing history no longer races pending captures,
  backlog M3 (#18); Open Filtered Apps setting (#16); `is:pinned` (#15); `is:concealed` and
  `app:` suggestions (#14).
- Verified on the owner's MacBook Air: `swift build` succeeds, `swift test` passes (217
  tests: 90 in the app target, 127 in core), `./scripts/check-docs.sh` reports consistent.
- `main` is protected on GitHub (ADR-027): no direct pushes, and the CI `test` check must
  pass. Secret scanning (with push protection) and Dependabot security updates are on.

## The running app is behind `main`

- The owner's running Permafrost was built from `347dee1` (#15 and #16). It lacks #17 and
  #18, the kind filters, the suggestion rows, the new grammar, and the time filters.
- Rebuilding (`./scripts/make-app.sh`) is the owner's call. It re-signs ad hoc, so the owner
  must relaunch and re-grant Accessibility and Input Monitoring afterwards.
- Manual checks 5c to 5j in docs/TESTING.md have not been run against a build.

## How to work here

- Every change goes on a branch, then a PR, then waits for CI. Agents open PRs and never
  merge or push to `main`. The owner decides; a coordinator session on another machine
  ("claude lead - opus") reviews PRs and merges at the owner's direction.
- Work in a git worktree (`git worktree add ../permafrost-wt/<name> -b <branch>`), not by
  switching branches in the main checkout. That checkout stays on `main` because it builds
  the running app. Remove the worktree and branch after the PR merges.
- Never run `scripts/make-app.sh`, touch `dist/`, or quit, kill, relaunch or reinstall the
  running app unless the owner says to. `swift build` and `swift test` use `.build/`.
- The owner confirmed (2026-11-14) that this session reports to the coordinator with
  `SendMessage` (`to: "claude lead - opus"`) when it finishes something, opens a PR, gets
  blocked or needs a decision. A relayed decision is not owner approval: ADR-level
  decisions need the owner's confirmation in the session making the change (CLAUDE.md).
- Agent PR and review comments start with `🤖 <model>:`.
- `gh` lives at `/opt/homebrew/bin/gh`, is not on `PATH`, and is logged in as the owner.
  Git prints an SSH "device not found" warning when the Yubikey is absent; fetches still
  work. If CI shows "job was not acquired by Runner", it is a GitHub macOS capacity
  problem, not the code: re-run it.

## Open work

- None in flight. No open branches or PRs. Worktrees: only the main checkout.

## Decisions not yet recorded

- None.

## Next steps

1. Wait for the owner or the coordinator to pick the next item.
2. Backlog candidates (docs/BACKLOG.md): remaining review follow-ups M1, M4, M6 (import and
   export hardening), M5 (lightweight list rows for screenshot-heavy history), M7 (restore
   the hotkey preset after a failed registration), L2 (consistent reveal lifetime).
3. Searchable concealed content (v0.7 item 1) is paused by the owner and needs its own ADR
   plus independent review first.
4. v1.0 distribution (Developer ID, notarization, Sparkle, Homebrew) is gated on the Apple
   Developer Program; see docs/ROADMAP.md.

## Gotchas

- `./scripts/check-docs.sh` treats every `docs/*.md` path it sees in any Markdown file as a
  real file, and every `ADR-NNN` as an ADR in docs/DECISIONS.md. When citing other repos
  (for example Ridgeline), use full URLs and don't use their ADR numbers.
- Saving identical text twice dedups into one row and refreshes its source app, so tests
  that need two rows must use different text.
- `swift build` prints a Combine import warning in `SettingsView.swift`; it is only a
  warning.
