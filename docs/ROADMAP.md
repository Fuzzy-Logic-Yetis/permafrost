# Roadmap

## v0.1.0 — MVP

The Win+V experience, complete: history (text + images/snips), `⌥⌘V` panel, search,
paste-on-select, pinning, time-based retention, settings, import/export, launch at login.
Built from source, ad-hoc signed. See [PROJECT_PLAN.md](PROJECT_PLAN.md) milestones.

## v0.2.0 — Pin lifecycle & hover actions

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

## v0.3.1 — Hardening (done 2026-07-07)

Driven by the 2026-07-07 review (`docs/2026-07-07_codex_review.md`): custom hotkey
registration failure now rolls back to a working preset and surfaces the failure in
Settings instead of claiming success silently; import validates recomputed content hashes,
kind/field consistency, and rejects symlinked blobs instead of trusting the manifest;
Settings' History Management actions surface errors the same way the status-menu versions
already did; docs/SECURITY.md now discloses Input Monitoring; PermissionReset no longer
blocks the main actor. See docs/DECISIONS.md for the ADR.

## v0.4.0 — Rich capture, drag-and-drop, concealed encryption, portable backups (done 2026-07-22, now)

- ~~Paste as plain text~~ (`⇧⏎`, ADR-018) and ~~HTML-to-RTF rich-text capture~~ (ADR-019) —
  browser copies without a native `.rtf` now get real formatting instead of none, with
  page decoration (background/link color) stripped.
- ~~Drag-and-drop out of the panel~~ (ADR-020) — text/image cards drag into any app or onto
  the Desktop as a real file.
- ~~At-rest encryption for concealed (password) items~~ (ADR-021) — opt-in, AES-GCM,
  Keychain-backed key, redact-by-default/reveal-on-demand. Includes two hardening rounds
  after real-world use surfaced problems: a retroactive "Mark as Concealed" action for
  content that arrived without the source app's concealed marker, and — after an actual,
  unrecoverable data-loss incident during this work — removing a fallback-key design
  entirely so concealed content can never again be sealed with a key that isn't the one
  real, persistent one. See ADR-021 in DECISIONS.md for the full history, including that
  incident.
- ~~Portable encrypted backups~~ — export/import history to another Mac via a
  passphrase-protected archive (PBKDF2 + AES-GCM), independent of this Mac's Keychain.
- **Follow-up, 2026-07-22**: a high-effort code review of everything above surfaced ten
  issues (unbounded plaintext retention in a retry queue, a migration failure able to
  permanently disable encryption for a session, a decrypt failure showing the wrong error
  dialog, non-atomic archive import, main-thread-blocking key derivation, and others) —
  all fixed the same day, with regression tests for each. See BACKLOG.md item 4's
  follow-ups and ADR-021's 2026-07-22 entry for the full list.

## v1.0 — Distribution

Gate: project owner joins the Apple Developer Program ($99/yr) — deliberately deferred
(personal use first).

- Developer ID signing + notarization
- GitHub Releases with signed `.dmg`
- Homebrew cask
- Sparkle auto-updates
- CHANGELOG discipline (see [RELEASE_PROCESS.md](RELEASE_PROCESS.md))

## Beyond (unscheduled, see FUTURE_IDEAS.md)

Optional at-rest encryption, snippet templates, collections, automation hooks. Each idea
must survive the CLAUDE.md decision framework — Permafrost stays a clipboard manager, not
a suite.

(OCR on snips shipped 2026-07-08 — see docs/BACKLOG.md item 13 — and is no longer on this
list.)
