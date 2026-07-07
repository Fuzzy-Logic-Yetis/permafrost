# Roadmap

## v0.1.0 — MVP

The Win+V experience, complete: history (text + images/snips), `⌥⌘V` panel, search,
paste-on-select, pinning, time-based retention, settings, import/export, launch at login.
Built from source, ad-hoc signed. See [PROJECT_PLAN.md](PROJECT_PLAN.md) milestones.

## v0.2.0 — Pin lifecycle & hover actions (now)

Driven by first real-world use (see ADR-012 and the 2026-07-06 review in
docs/DECISIONS.md): recent-first/pinned-at-bottom ordering with quick-paste bounded to the
recent section, hover pin/share/delete on every card, Unpin All / Clear Everything bulk
actions (menu + Settings), dedup metadata refresh (source app, rich text, sticky concealed
flag), import path-traversal validation, and error surfacing on destructive actions.

## v0.3.0 — Daily-driver polish (done 2026-07-07)

- ~~Custom hotkey recorder~~, ~~app icon~~, ~~pause capture~~, ~~per-app exclusions~~,
  ~~preview pane~~ (space bar), ~~monospace-aware text rendering~~ — see docs/BACKLOG.md
  for details and dates.
- Deferred out of this milestone: paste-as-plain-text, drag-out (docs/BACKLOG.md "Later").
- Performance pass with Instruments at 10k+ items — deferred until Instruments is available
  (no Xcode installed yet, see docs/PROJECT_PLAN.md environment notes).

## v0.3.1 — Hardening (now)

Driven by the 2026-07-07 review (`docs/2026-07-07_codex_review.md`): custom hotkey
registration failure now rolls back to a working preset and surfaces the failure in
Settings instead of claiming success silently; import validates recomputed content hashes,
kind/field consistency, and rejects symlinked blobs instead of trusting the manifest;
Settings' History Management actions surface errors the same way the status-menu versions
already did; docs/SECURITY.md now discloses Input Monitoring; PermissionReset no longer
blocks the main actor. See docs/DECISIONS.md for the ADR.

## v1.0 — Distribution

Gate: project owner joins the Apple Developer Program ($99/yr) — deliberately deferred
(personal use first).

- Developer ID signing + notarization
- GitHub Releases with signed `.dmg`
- Homebrew cask
- Sparkle auto-updates
- CHANGELOG discipline (see [RELEASE_PROCESS.md](RELEASE_PROCESS.md))

## Beyond (unscheduled, see FUTURE_IDEAS.md)

OCR on snips, optional at-rest encryption, snippet templates, collections, automation
hooks. Each idea must survive the CLAUDE.md decision framework — Permafrost stays a
clipboard manager, not a suite.
