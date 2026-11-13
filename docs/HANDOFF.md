# Handoff

The state a fresh session needs, written by the previous session's `/handoff` (see
[CLAUDE.md](../CLAUDE.md), "Org standards"). Rewritten each time, not appended; git keeps
the history. Under 150 lines.

Last written 2026-11-13, after ADR-026 and ADR-027 landed.

## State of `main`

- v0.6.0 (findability: trigram search and app filtering) is the released version. CI is
  green on `main`.
- Last changes: ADR-026 (org standards, `/handoff`, session-start hook), then ADR-027
  (every change through a PR).
- Verified on the owner's MacBook Air on 2026-11-13: `swift build` succeeds, `swift test`
  passes (90 tests in 7 suites), `./scripts/check-docs.sh` reports consistent.
- `main` is protected on GitHub (ADR-027): no direct pushes, owner included, and the CI
  `test` check must pass. No approving review is required; the owner merges by hand.
  Secret scanning (with push protection) and Dependabot security updates are on.
  Dependabot opens PRs and never merges.

## How to work here

- Every change goes on a branch, then a PR, then wait for CI. The owner merges. Agents
  never merge and never push to `main`.
- Agent PR and review comments start with `🤖 <model>:`.
- The owner runs the app daily from `dist/Permafrost.app`. Sessions must not run
  `scripts/make-app.sh`, touch `dist/`, or quit, kill, relaunch or reinstall the running
  app. `swift build` and `swift test` use `.build/` and are safe.
- `gh` lives at `/opt/homebrew/bin/gh` and is not on `PATH` in this shell; it is logged in
  as the owner's account.

## Open work

- This handoff PR (branch `docs/handoff-2026-11-13`), docs-only, waiting on CI and the
  owner's merge. No other branches or PRs are open.

## Decisions not yet recorded

- None.

## Next steps

1. Wait for the owner's go-ahead; none of the backlog is started.
2. Then docs/BACKLOG.md, "Next up (v0.7)", in order. Item 2 (a `is:concealed` filter) and
   item 3 (`app:` discoverability) are cheap and need no ADR. Item 1 (searchable concealed
   content) needs its own ADR first because it changes a guarantee CLAUDE.md names.
3. Release plan: docs/ROADMAP.md (v1.0 is distribution).

## Gotchas

- `./scripts/check-docs.sh` treats every `docs/*.md` path it sees in any Markdown file as a
  real file, and every `ADR-NNN` it sees as an ADR in docs/DECISIONS.md. When citing other
  repos (for example Ridgeline), use full URLs and don't use their ADR numbers.
- `swift build` prints a Combine import warning in `SettingsView.swift` (line 47). It is a
  warning only and not new work.
