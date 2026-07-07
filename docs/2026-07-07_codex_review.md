# Executive Summary

Permafrost is materially stronger than it was in the 2026-07-06 review. The prior high-risk issues around deduplication metadata, version mismatch, pinned-section labeling, import path traversal, panel-model coverage, and most status-menu error handling have been addressed. The project is now a credible personal daily-driver build with a much richer v0.3-style feature set.

Readiness assessment: **close, but not quite release-clean**. I would not tag a public-ish v0.3 build until the custom-hotkey failure path, import archive validation, Settings destructive-action errors, and permission documentation are corrected.

Overall code quality: **good**. The code remains compact and direct despite the feature growth. The new tests are well scoped.

Overall architecture quality: **good**. `PermafrostCore` remains headless and testable, while AppKit/SwiftUI platform integration stays in the executable target.

Overall maintainability: **good, with a caution**: the repo is accumulating detailed operational documentation quickly. That is useful, but planning/status docs now need a small consolidation pass.

Overall recommendation: fix the Medium findings before the next tagged build; keep the Low findings as normal hardening work.

# Strengths

- Prior review findings were taken seriously and mostly resolved with tests.
- `ClipboardStore.save()` now refreshes rich/source metadata and preserves `isConcealed` in the safer direction.
- Import path traversal for absolute and `..` paths now has explicit tests.
- `PanelModel` has app-target unit coverage for search reset, quick-paste bounds, commit ordering, pinning, and deletion.
- ADR-012 behavior is now consistently implemented: recent items first, pinned items below, and quick-paste digits only target recent items.
- The Settings surface now covers pause capture, excluded apps, permissions, custom hotkeys, and history management in one place.
- The manual smoke checklist is much more realistic about macOS permissions, ad-hoc signing, and menu-bar space constraints.

# Findings

## Critical

No Critical findings.

## High

No High findings.

## Medium

### M-1: Custom hotkey recording can claim success even when registration fails

The recorder accepts any shortcut with at least one primary modifier (`Sources/Permafrost/HotkeyManager.swift:13`, `Sources/Permafrost/Settings/SettingsView.swift:421`). Settings immediately stores it and shows "Recorded custom shortcut" (`Sources/Permafrost/Settings/SettingsView.swift:103`). `HotkeyManager.register(shortcut:)` logs Carbon registration failure but returns no status to the UI (`Sources/Permafrost/HotkeyManager.swift:170`).

Impact: a user can record a reserved, conflicting, or otherwise unavailable shortcut and see it as active even though the global hotkey does not work. That breaks the primary entry point to the app.

Recommendation: make registration return success/failure, surface failure in Settings, and either keep the previous hotkey active or roll back to a known-good preset. Add tests around validation policy and manual checklist coverage for a deliberately conflicting shortcut.

### M-2: Import still trusts manifest content hashes and kind/content consistency

Import now constrains simple manifest blob paths, but it still constructs `ClipboardItem` directly from manifest fields (`Sources/PermafrostCore/ImportExport.swift:130`) and trusts `entry.contentHash` (`Sources/PermafrostCore/ImportExport.swift:134`). The canonical hash logic lives in `ClipboardCapture.contentHash` (`Sources/PermafrostCore/ClipboardItem.swift:72`) but is not recomputed on import.

Impact: a malformed or hostile archive can import rows whose `content_hash` does not match their actual text/image content, or rows whose `kind` does not match the populated fields. That can break deduplication, search expectations, and future export/import behavior. A symlink inside an extracted archive may also bypass string-only root checks if `Data(contentsOf:)` follows it.

Recommendation: validate imported items before insertion: recompute hash from content, require text rows to have text and no image blob, require image rows to have image data, reject unexpected blob combinations, and consider resolving symlinks or rejecting symlinked blob files. Add tests for mismatched hashes, text-with-image blobs, image-without-image data, and symlink traversal if feasible.

### M-3: Settings destructive history actions still swallow persistence failures

The status-menu actions now show errors, but Settings → History Management still uses `try?` for clear unpinned, unpin all, and clear everything (`Sources/Permafrost/Settings/SettingsView.swift:293`, `Sources/Permafrost/Settings/SettingsView.swift:302`, `Sources/Permafrost/Settings/SettingsView.swift:314`).

Impact: the same user-visible action has different failure behavior depending on where it is launched. A failed destructive or state-changing operation in Settings can appear to succeed.

Recommendation: share the status-menu error surfacing behavior in Settings, or route both UI surfaces through one history-management helper.

### M-4: Security documentation is stale about Input Monitoring

The code explicitly requests and displays Input Monitoring (`Sources/Permafrost/HotkeyManager.swift:147`, `Sources/Permafrost/Settings/SettingsView.swift:235`), and ADR-014/016 document that choice. `docs/SECURITY.md` still says "No ... Input Monitoring" (`docs/SECURITY.md:57`).

Impact: this is a trust and transparency issue. A privacy-focused app must accurately disclose every permission it requests, especially one adjacent to keystroke monitoring.

Recommendation: update `SECURITY.md` to list both Accessibility and Input Monitoring, explain why Input Monitoring is requested, and clarify any degraded behavior if it is denied.

## Low

### L-1: Preview overlay leaves hidden list actions active

The UX spec says the preview closes on Space or Esc and follows arrow selection (`docs/UX.md:57`). `PanelController.handle` still lets Return paste, Delete delete, Option-P pin, and Command-number quick-paste while the preview overlay is open (`Sources/Permafrost/Panel/PanelController.swift:129`, `Sources/Permafrost/Panel/PanelController.swift:141`, `Sources/Permafrost/Panel/PanelController.swift:151`, `Sources/Permafrost/Panel/PanelController.swift:155`).

Impact: this may be acceptable power-user behavior, but it is not documented in the preview affordance and could surprise users because the underlying list is hidden.

Recommendation: either document those keys as intentionally active in preview mode or gate preview mode so only arrows, Space, Esc, and perhaps Return are active.

### L-2: Roadmap and backlog disagree about v0.3 status

`docs/ROADMAP.md` still lists custom hotkey recorder, app icon, pause capture, per-app exclusions, preview pane, and monospace-aware rendering as v0.3 future work (`docs/ROADMAP.md:17`), while `docs/BACKLOG.md` marks nearly all of those as done on 2026-07-07 (`docs/BACKLOG.md:8`).

Impact: project state is understandable if one reads every doc, but a new contributor can easily misread the next milestone.

Recommendation: update the Roadmap to reflect completed v0.3 items, decide whether the app version should remain `0.2.0` while v0.3 work is already present, and name the true next milestone.

### L-3: Permission reset blocks the main actor while running `tccutil`

`PermissionReset.resetAccessibilityAndInputMonitoring()` launches `tccutil` twice and waits synchronously from a main-actor Settings alert action.

Impact: this is likely brief, but any hang in `tccutil` freezes the UI.

Recommendation: run the reset work off the main actor or show a short progress state if this grows beyond a quick developer convenience.

# Architecture Assessment

The architecture remains sound. The new app-target tests did not require breaking the core/app boundary; introducing `PanelPasteServing` was a good small seam for testing `PanelModel` without scripting AppKit or Accessibility.

The project is still appropriately dependency-light. The custom hotkey recorder, app icon generation, pause capture, exclusions, and preview pane were implemented with platform APIs and local code rather than new packages.

# Correctness Assessment

Core store behavior is substantially improved. Deduplication metadata, pinned ordering, retention, clear history, and unpin-all semantics are now well covered.

The main correctness concern is import trusting archive metadata too far. Import/export is a data boundary, not just a convenience feature; it should preserve the store's invariants instead of relying on manifests to be honest.

# Testing Assessment

Automated coverage is now meaningfully broader:

- `PermafrostCoreTests` covers store, retention, search, import/export, and image utilities.
- `PermafrostTests` covers key `PanelModel` behavior with an in-memory store and fake paste service.

Remaining test gaps:

- custom hotkey registration failure and rollback;
- import hash/kind consistency validation;
- Settings history-management error paths;
- preview-mode keyboard routing expectations;
- pasteboard watcher pause/excluded-app behavior, if it can be extracted behind a small testable policy object.

I did not rerun the test suite during this review, matching the previous read-only review posture.

# Security & Privacy Assessment

The privacy posture is still strong: local-only storage, no network code, owner-only database permissions, concealed/transient pasteboard handling, and no content logging.

The permission documentation needs immediate correction. Input Monitoring is now part of the app's permission story, and `SECURITY.md` should not deny that. Import validation should also be tightened because archives are user-selected but still untrusted input.

# Performance Assessment

The current design remains acceptable for a small native clipboard manager: polling `changeCount`, SQLite/FTS5, and a 200-row panel cap are reasonable. Synchronous image capture and thumbnailing remain the likely future performance pressure point, already identified in the backlog.

# User Experience Assessment

The UX has improved: pinned separation is clearer, hover actions are practical, preview mode is useful, and Settings now exposes real daily-driver controls.

The biggest UX risk is custom hotkey false success. Users will believe they changed the primary shortcut, then the panel will not open. That should be fixed before declaring the hotkey recorder done.

# Documentation Assessment

The docs are detailed and mostly current, especially `TESTING.md` and the ADRs. The stale `SECURITY.md` permission claim and Roadmap/Backlog status mismatch should be cleaned up before the next release.

# Final Recommendation

Proceed with Permafrost. The codebase is healthy, and the previous review drove real improvements. Before tagging the next build, fix M-1 through M-4, update the Roadmap/Security docs, rerun `./scripts/test.sh`, and perform the expanded manual smoke checklist in `docs/TESTING.md`.
