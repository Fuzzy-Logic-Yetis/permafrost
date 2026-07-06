# Contributing

## Setup

Requirements: macOS 14+, Xcode Command Line Tools (`xcode-select --install`). Full Xcode is
optional (nice for Instruments/debugging; `open Package.swift` works).

```sh
git clone https://github.com/Fuzzy-Logic-Yetis/permafrost.git
cd permafrost
swift build            # fetches GRDB, compiles
swift test             # core unit tests
./scripts/make-app.sh  # assembles dist/Permafrost.app (ad-hoc signed)
```

Note: every ad-hoc re-sign is a new identity to macOS — re-grant Accessibility after
rebuilds (see docs/TESTING.md).

## Ground rules

Read [CLAUDE.md](../CLAUDE.md) first — it is the operating manual (definition of done,
commit format, ADR rules). The short version:

- Conventional Commits (`feat:`, `fix:`, `docs:`, …), each commit builds and tests green.
- `PermafrostCore` never imports AppKit; all persistence stays behind `ClipboardStore`.
- New logic in core ⇒ new tests. UI changes ⇒ run the relevant docs/TESTING.md checklist items.
- Docs update in the same commit as the behavior they describe.
- New dependency ⇒ ADR, and expect pushback: the budget is one (GRDB) by design.
- No TODO comments without a docs/BACKLOG.md entry.

## Style

- `swift format` (bundled with the toolchain): `swift format --in-place --recursive Sources Tests`
- Match surrounding code. Prefer clarity over brevity. Comments explain *why*, never *what*.

## PRs

One logical change, description says what/why, links the issue, screenshots for UI, green CI.
