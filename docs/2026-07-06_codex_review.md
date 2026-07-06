# Executive Summary

Permafrost is in good engineering health for a local-first macOS clipboard manager. The codebase is compact, the module boundary between `PermafrostCore` and the AppKit/SwiftUI shell is mostly clean, and the core persistence/search/retention behavior is covered by meaningful unit tests. The current implementation appears appropriate for continued personal daily-driver use and late pre-release hardening.

Readiness assessment: **not yet release-ready without follow-up**, primarily because the repository has a few user-visible and release-process inconsistencies, plus some edge cases around deduplication metadata and import validation. I did not identify a critical architectural flaw or an obvious broad data-loss path in the core history/retention model.

Overall code quality: **good**. Names are direct, modules are small, and the single-dependency strategy is credible. Error handling is the weakest recurring area in the app shell.

Overall architecture quality: **good**. `PermafrostCore` owns persistence, retention, search, import/export, and thumbnails; the executable owns macOS lifecycle, pasteboard polling, hotkeys, paste simulation, settings, and UI.

Overall maintainability: **good, with documentation drift now becoming the main maintenance risk**.

Overall recommendation: address the High and Medium findings before tagging another release; treat Low findings as backlog hardening.

# Strengths

- Clear product focus: the implementation stays close to the intended Win+V workflow instead of expanding into a general productivity suite.
- Strong core boundary: `PermafrostCore` remains headless and testable, with AppKit concerns kept in the executable target.
- Persistence design is pragmatic: GRDB, SQLite, FTS5, migrations, and owner-only file permissions are appropriate for this project.
- Retention semantics are robust in the store layer: purge SQL structurally excludes pinned rows, which is the right place to enforce that guarantee.
- Recent ADR-012 ordering change is well motivated and has store-level regression coverage.
- Privacy posture is unusually explicit: no network code, concealed pasteboard handling, local storage, and no content logging are all documented and mostly reflected in code.
- The test suite covers the important core invariants: deduplication, search, retention, image thumbnails, import/export, pinning, and ordering.

# Findings

## Critical

No Critical findings.

## High

### H-1: Deduplication can preserve stale privacy and rich-content metadata

`ClipboardCapture.contentHash` hashes only `kind` and plain `text` for text items (`Sources/PermafrostCore/ClipboardItem.swift:72`). When the hash already exists, `ClipboardStore.save()` only updates `lastUsedAt` and leaves `richData`, `sourceApp`, and `isConcealed` unchanged (`Sources/PermafrostCore/ClipboardStore.swift:78`).

Impact:

- Copying the same plain text later with different RTF formatting can paste the old rich representation.
- Copying text that was previously non-concealed from a password manager while concealed recording is enabled will not mark the existing row as concealed, so the key indicator can be wrong.
- Source app captions can remain stale after repeated copies from different applications.

Recommendation: decide whether dedup should update selected metadata on recopy, whether rich text should participate in the dedup hash, and whether `isConcealed` should be sticky in the safer direction (`old || new`). Add tests for same text with different `richData` and same text copied as concealed after a non-concealed copy.

### H-2: Release/version sources disagree

The app logs `PermafrostVersion.string = "0.2.0"` (`Sources/Permafrost/App.swift:4`), while the bundle script still emits `VERSION="0.1.0"` (`scripts/make-app.sh:10`) and README status still says `v0.1.0` (`README.md:75`).

Impact: built apps, logs, documentation, and tags can disagree. That weakens supportability and can produce bad release artifacts.

Recommendation: choose one version source, update all release-facing references together, and consider generating both the bundle plist and runtime string from the same value.

## Medium

### M-1: Mixed recent/pinned lists do not render a pinned section header

`PanelView.sectionHeader(at:)` correctly labels index 0, but its transition check looks for `pinned -> unpinned` (`Sources/Permafrost/Panel/PanelView.swift:82`). The store now orders `unpinned -> pinned`, so a mixed list shows `RECENT` but never introduces `PINNED`.

Impact: pinned rows at the bottom can appear as ordinary recent history, reducing clarity for the new ADR-012 behavior.

Recommendation: change the transition check to detect `!items[index - 1].isPinned && items[index].isPinned`, then manually verify mixed, all-recent, all-pinned, and search-filtered lists.

### M-2: Documentation and test checklist still describe outdated behavior

`docs/TESTING.md` still says ordering is "pinned first" (`docs/TESTING.md:20`) even though ADR-012 and the implementation now require recent first and pinned at the bottom. `docs/ARCHITECTURE.md` also names a non-existent `PermafrostDatabase` component (`docs/ARCHITECTURE.md:37`) and omits `is_concealed` from the schema (`docs/ARCHITECTURE.md:66`).

Impact: manual release testing can validate the wrong behavior, and future maintainers can misunderstand the actual schema and component map.

Recommendation: update `TESTING.md`, `ARCHITECTURE.md`, README status, and Roadmap/Release docs in the same change that resolves versioning.

### M-3: User-visible mutations often swallow persistence errors

Panel pin/delete uses `try?` (`Sources/Permafrost/Panel/PanelModel.swift:94`), status-menu destructive actions use `try?` (`Sources/Permafrost/App.swift:185`, `Sources/Permafrost/App.swift:199`), and paste recency marking uses `try?` (`Sources/Permafrost/PasteService.swift:42`).

Impact: if the database becomes unavailable or a write fails, users may see no error and believe a destructive or state-changing action succeeded.

Recommendation: log all failures at minimum; for destructive menu/settings actions, surface an alert. For panel actions, consider a lightweight non-blocking error state.

### M-4: Import paths are not constrained to the archive root

Import blob resolution appends manifest-provided paths directly to the selected directory and reads them if they exist (`Sources/PermafrostCore/ImportExport.swift:110`).

Impact: a malicious or malformed archive manifest could reference paths outside the archive directory. This is user-initiated and local-only, but import should still treat archive metadata as untrusted.

Recommendation: normalize and validate blob URLs so they remain under the import root, reject absolute paths and `..` traversal, and add tests for hostile manifest paths.

### M-5: AppKit/UI behavior is largely untested

The automated tests are core-only by design, but the highest-risk product behavior now lives in the executable target: non-activating panel focus, quick-paste routing, hover actions, Accessibility fallback, settings alerts, status-menu destructive actions, and pasteboard type handling.

Impact: regressions in the actual Win+V interaction can ship while `swift test` remains green.

Recommendation: keep the core tests, but add a small manual/automated UI verification strategy around `PanelModel` where possible and expand the manual checklist for ADR-012 quick-paste/pinned-section behavior.

## Low

### L-1: Panel count displays loaded rows, not total history

`PanelModel.reload()` loads at most 200 items (`Sources/Permafrost/Panel/PanelModel.swift:39`), and the footer displays `model.items.count`. With more than 200 matches, the UI reports the loaded subset without indicating truncation.

Recommendation: either label it as visible count, show `200+`, or expose a total count for the active query if the number is meant to be authoritative.

### L-2: UX spec promises details not implemented

`docs/UX.md` promises monospace-detected text and subtle leading/trailing whitespace visualization (`docs/UX.md:42`), but `PanelView` currently renders all text through a plain `Text(...).lineLimit(3)`.

Recommendation: either implement those details or mark them as future polish.

### L-3: First-run documentation overstates onboarding

`docs/UX.md` says first launch offers to enable launch-at-login (`docs/UX.md:87`), while the actual welcome alert only has "Got It".

Recommendation: update the spec or add the launch-at-login choice.

# Architecture Assessment

The two-target layout is appropriate. The core target owns durable business logic, while the executable owns platform integrations. This keeps the highest-value logic testable without mocking AppKit. `ClipboardStore` as the single SQL gateway is a good rule and is followed.

The main architectural tradeoff is synchronous database work on the main actor. For text history and small images this is acceptable; for large snips or 10k+ histories, thumbnail generation and writes may eventually need background scheduling. The backlog already recognizes this, so no immediate redesign is recommended.

# Correctness Assessment

Core ordering, pinning, retention, deletion, search, and import/export behavior are generally coherent. ADR-012's "recent first, pinned bottom, quick-paste only recent" rule is implemented in the store and `PanelModel`.

The most important correctness risk is deduplication metadata preservation: dedup intentionally preserves pin state, but currently also preserves rich data, concealed state, and source app. That should be made explicit and tested.

# Testing Assessment

Automated tests are strong for `PermafrostCore`. They cover meaningful invariants instead of superficial constructors. The recent ordering tests are especially useful.

Missing coverage to prioritize:

- concealed dedup edge cases;
- rich text dedup/update semantics;
- hostile import manifest paths;
- `PanelModel.commitQuickPaste` with mixed pinned/unpinned filtered results;
- section-header behavior, even if through extracted pure logic;
- manual checklist coverage for hover pin/share/delete and bulk history actions.

I did not rerun tests during this review because the request supplied the latest passing test run as context and framed this as a read-only engineering assessment.

# Security & Privacy Assessment

The project has a sound privacy baseline: local SQLite, owner-only permissions, no network code, concealed/transient pasteboard handling, and no clipboard content logging. Accessibility permission is requested for a clear product reason.

Security hardening should focus on import validation and concealed metadata correctness. Optional at-rest encryption can remain post-MVP as documented; the current FileVault plus permissions stance is honest and reasonable for personal local use.

# Performance Assessment

Polling `NSPasteboard.changeCount` every 0.3 seconds is standard and low-cost. SQLite/FTS5 is the right persistence/search foundation. Loading 200 panel rows is a sensible UI cap.

Potential future bottlenecks are image thumbnail generation and synchronous database writes on the main actor. Measure with Instruments before changing the architecture.

# User Experience Assessment

The app is close to the intended Win+V workflow: one global hotkey, search-focused panel, arrow navigation, Enter paste, quick-paste digits, pinning, deletion, and copy-only Accessibility fallback.

The pinned-header bug should be fixed before release because it undercuts the new pinned-at-bottom behavior. The version/status drift also matters to UX indirectly because users and maintainers need to know what they are running.

# Documentation Assessment

Documentation is unusually thorough for a small app, especially ADRs and security notes. However, the docs are now partially out of sync with the latest behavior. The most important stale areas are testing/order semantics, version status, architecture schema, and first-run UX.

# Final Recommendation

Proceed with the project. Before tagging or distributing the next build, fix H-1, H-2, M-1, M-2, and M-4, then rerun automated tests and the updated manual smoke checklist. The remaining items can be scheduled as normal hardening work.
