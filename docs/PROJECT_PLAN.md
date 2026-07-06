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
| **M1 — Core engine** | `PermafrostCore`: store (GRDB+FTS5), retention, dedup, thumbnails, import/export; unit tests | 🔨 in progress |
| **M2 — The panel** | NSPanel + SwiftUI UI, global hotkey, search, paste-on-select, pinning, accessibility onboarding | ⏳ pending |
| **M3 — Settings & polish** | Settings window, launch-at-login, status-item menu, import/export UI | ⏳ pending |
| **M4 — Packaging** | `make-app.sh`, ad-hoc signing, install docs, tag v0.1.0 | ⏳ pending |

Post-MVP direction: see [ROADMAP.md](ROADMAP.md).

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
