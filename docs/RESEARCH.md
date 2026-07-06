# Research: Should Permafrost Exist?

Conducted 2026-07-05, before any code was written. Question: given the requirements
(history, hotkey, search, pin-forever, time-based expiry for unpinned, fast, native,
local-first, private — explicitly *not* a productivity suite), should we
(A) use an existing app, (B) configure one, (C) extend an open-source project,
(D) fork one, or (E) build new?

## Landscape

| Option | Pinning | Time-based expiry | Search | Local/private | License | Cost | Maintained | Notes |
|---|---|---|---|---|---|---|---|---|
| macOS Tahoe Spotlight (26.1+) | ❌ none | 30 min / 8 h / 7 d only | basic | ✅ | — | free | Apple | Text-only, formatting stripped; no pin; 7-day hard cap |
| **Maccy** | ✅ (⌥P) | ❌ count-based (999 cap) | ✅ fuzzy | ✅ honors concealed types | MIT, open source | free | ✅ very active (20.6k★, v2.7.x Nov 2025) | Closest match, ~90% of spec |
| Raycast | ✅ | 3 mo free tier / unlimited Pro | ✅ | ✅ encrypted local | closed | freemium subscription | ✅ | Full launcher suite — explicitly out of scope |
| Alfred (Powerpack) | ✅ | 24 h–3 mo presets | ✅ | ✅ | closed | paid | ✅ | Suite; clipboard is a feature, not the product |
| ClipBook | ✅ | ? | ✅ | ✅ | source-available, paid | paid | ✅ small | Solo dev, small community |
| CopyClip 2 | ✅ | ❌ | ✅ | ✅ | closed | $7.99 | 〰️ | Basic; count-based |
| PastePal | ✅ | ? | ✅ | iCloud-oriented | closed | $9.99 | ✅ | Sync-first design |
| Unclutter | — | — | — | ✅ | closed | $19.99 | 〰️ | Desktop 3-in-1; wrong shape entirely |
| Clipy / Flycut | folders/— | ❌ | limited | ✅ | MIT/GPL | free | ⚠️ low activity | Aging codebases |

Key sources: [Tahoe clipboard settings (MacRumors)](https://www.macrumors.com/2025/11/04/more-spotlight-clipboard-settings-macos-26-1/),
[9to5Mac on Tahoe 26.1](https://9to5mac.com/2025/11/04/macos-tahoe-26-1-adds-new-tools-for-spotlights-clipboard-feature/),
[Maccy repo](https://github.com/p0deje/Maccy), [Maccy time-based-clear request #805](https://github.com/p0deje/Maccy/issues/805),
[Raycast clipboard history](https://www.raycast.com/core-features/clipboard-history),
[ClipBook open-sourcing (Mac Observer)](https://www.macobserver.com/tips/developer-opens-macos-clipboard-manager/).

## Analysis

- **(A) Use existing — Maccy** is the rational pure-utility answer and remains the
  recommended stopgap daily driver. It fails the spec on exactly two points: retention is
  count-based only (time-based expiry is upstream issue #805, open and unimplemented), and
  the UX is a searchable list rather than a Win+V card panel.
- **(B) Configure existing** — no configuration of any candidate produces time-based expiry
  or pin-forever-plus-expiry semantics. Dead end.
- **(C) Extend Maccy upstream** — community-optimal, and worth doing *anyway* someday, but
  the panel UX and roadmap would remain upstream's; the retention semantic is a product
  identity here, a feature request there.
- **(D) Fork Maccy** — inherits a mature codebase *and* its architecture, UI framework
  choices, localization burden, and issue backlog; the delta we want touches its core. A
  fork that rewrites the core is a new app with extra history.
- **(E) Build** — the MVP is genuinely small (two modules, one dependency, ~3k lines), the
  differentiating semantics are the *foundation* rather than a retrofit, and project
  ownership inside Fuzzy Logic Yetis + native macOS/Swift skill-building are explicit goals
  of the project owner's Windows→macOS transition.

## Decision

**Build (E).** Confirmed by project owner 2026-07-05 at the decision gate. Recorded as
[ADR-001](DECISIONS.md#adr-001-build-a-new-app-instead-of-adopting-or-extending-maccy).

Honest caveat, on the record: if the goal were only "have a clipboard manager today,"
installing Maccy would be the right call. The goal is broader; that is why this repo exists.
