# Project Plan

## What we're building

A Win+V-style clipboard manager for macOS. Full requirements and the build-vs-buy analysis
live in [RESEARCH.md](RESEARCH.md); the interaction spec lives in [UX.md](UX.md).

Core requirements (MVP):

- Persistent clipboard history — text, rich text, images/screen snips
- Pinning; pinned entries never expire
- Time-based expiry for unpinned entries (configurable)
- Global hotkey (`⌥⌘V`) opening a fast, keyboard-first panel
- Search
- Paste-on-select into the frontmost app
- Menu bar app, settings window, launch at login
- Import/export
- Local-only, privacy-respecting storage

## Milestones

| Milestone | Scope | Status |
|---|---|---|
| **M0 — Scaffold** | Repo, docs, GitHub setup, CI skeleton | ✅ done |
| **M1 — Core engine** | `PermafrostCore`: store (GRDB+FTS5), retention, dedup, thumbnails, import/export; unit tests | ✅ done |
| **M2 — The panel** | NSPanel + SwiftUI UI, global hotkey, search, paste-on-select, pinning, accessibility onboarding | ✅ done |
| **M3 — Settings & polish** | Settings window, launch-at-login, status-item menu, import/export UI | ✅ done |
| **M4 — Packaging** | `make-app.sh`, ad-hoc signing, install docs, tag v0.1.0 | ✅ done |
| **M5 — Pin lifecycle & hover actions** | ADR-012: recent/pinned section split, quick-paste bounded to recent; hover pin/share/delete; Unpin All / Clear Everything; dedup metadata refresh, import path validation, error surfacing from independent code review | ✅ done |

The table above covers the MVP only and stops at M5 by design — post-MVP work is tracked by
version in [ROADMAP.md](ROADMAP.md), not by milestone here.

**Current state (2026-09-07):** v0.1.0–v0.4.0 shipped; **v0.5.0 (QR codes) is in progress** —
decoding shipped, two follow-ups still open. Start at [ROADMAP.md](ROADMAP.md) for what
shipped and [BACKLOG.md](BACKLOG.md) for what's next; version strings still read 0.4.0 until
v0.5.0 closes (see the note in ROADMAP.md).

## Workflow

- Work is tracked as GitHub issues, grouped by **milestones** (M1–M4, then version milestones).
- [BACKLOG.md](BACKLOG.md) is the ordered engineering backlog; promote items to issues when
  they're about to be worked.
- **GitHub Projects: deliberately not used.** For a solo project, a Projects board is a second
  source of truth that drifts. Issues + milestones + BACKLOG.md cover planning; revisit if the
  project gains multiple contributors.
- Labels: `bug`, `enhancement`, `docs`, `adr`, `mvp`, `post-mvp`, `ux`, `performance`,
  `security`, `good first issue`.

## Working agreements

See [CLAUDE.md](../CLAUDE.md) — definition of done, commit standards, branch strategy.
