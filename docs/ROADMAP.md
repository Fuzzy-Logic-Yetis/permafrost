# Roadmap

## v0.1.0 — MVP (now)

The Win+V experience, complete: history (text + images/snips), `⌥⌘V` panel, search,
paste-on-select, pinning, time-based retention, settings, import/export, launch at login.
Built from source, ad-hoc signed. See [PROJECT_PLAN.md](PROJECT_PLAN.md) milestones.

## v0.2 — Daily-driver polish

- Custom hotkey recorder
- App icon
- Pause capture; per-app exclusions
- Preview pane (space bar), paste-as-plain-text, drag-out
- Performance pass with Instruments at 10k+ items

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
