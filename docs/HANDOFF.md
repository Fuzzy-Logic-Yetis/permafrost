# Handoff

The state a fresh session needs, written by the previous session's `/handoff` (see
[CLAUDE.md](../CLAUDE.md), "Org standards"). Rewritten each time, not appended; git keeps
the history. Under 150 lines.

Seeded 2026-11-12 when the handoff process was adopted (ADR-026). No session has written
one with `/handoff` yet.

## State of `main`

- v0.6.0 (findability: trigram search and app filtering) shipped 2026-10-13. CI is green.
- Last change: independent-review fixes (ADR-025).

## Open work

- None in flight as of this note. Next engineering work: docs/BACKLOG.md. Release plan:
  docs/ROADMAP.md (v1.0 is distribution).

## Decisions not yet recorded

- None.

## Gotchas

- `./scripts/check-docs.sh` treats every `docs/*.md` path it sees in any Markdown file as a
  real file, and every `ADR-NNN` it sees as an ADR in docs/DECISIONS.md. When citing other
  repos (for example Ridgeline), use full URLs and don't use their ADR numbers.
