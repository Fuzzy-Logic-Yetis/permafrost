# Executive Summary

Permafrost is in good engineering health for an MVP-stage macOS utility. The architecture has a clear split between AppKit/SwiftUI app concerns and the GRDB-backed `PermafrostCore` storage layer, and the recent background-save and OCR work generally follows the project's local-first, dependency-light direction.

I would not treat the current build as a polished v1.0 release yet. The main remaining risks are around lifecycle durability for asynchronous captures, privacy expectations introduced by automatic OCR, and a few stale docs that now contradict the implementation. None of the findings appear to be release-blocking for internal or beta use if they are documented, but they should be addressed before broad distribution.

Overall code quality is strong: naming is direct, responsibilities are mostly well separated, and the tests are unusually comprehensive for this stage. Maintainability is also strong, with the caveat that OCR has created a new cross-cutting pipeline that needs explicit lifecycle and privacy decisions rather than remaining an implicit background side effect.

Overall recommendation: continue toward beta after resolving the High finding and either fixing or explicitly documenting the Medium findings.

# Strengths

- Clear module boundary: `PermafrostCore` owns storage, retention, thumbnails, and import/export without importing AppKit, while the executable owns UI, pasteboard, hotkeys, permissions, and Vision OCR integration.
- Storage semantics are deliberate and well tested: deduplication, pinned/unpinned ordering, retention, FTS search, OCR search, and import/export all have focused tests.
- The product invariant that pinned items never consume quick-paste slots is implemented at both storage ordering and `PanelModel.commitQuickPaste`.
- Security posture is simple and inspectable: no network dependencies, local SQLite storage, owner-only directory intent, concealed/transient pasteboard filtering, and explicit password opt-in.
- AppKit/SwiftUI integration is pragmatic: `NSPanel` handles non-activating workflow, SwiftUI renders the panel/settings, and small AppKit bridges are used only where needed.
- Import/export hardening is materially better than a naive archive reader: manifest versioning, traversal rejection, symlink rejection, kind/hash validation, and duplicate skipping are all present.
- The documentation set is unusually complete for an early project: architecture, decisions, security, UX, testing, release process, and code-review process all exist and are useful.

# Findings

## Critical

No Critical findings.

## High

### Title

Pending background captures can be lost on quit/restart because the save queue is not drained during app termination.

### Affected files

- `Sources/Permafrost/CaptureSaveQueue.swift`
- `Sources/Permafrost/App.swift`

### Description

`PasteboardWatcher` enqueues captures asynchronously (`App.swift:57-67`) and `CaptureSaveQueue.enqueue` performs save, OCR, and purge work on a serial `DispatchQueue` (`CaptureSaveQueue.swift:25-43`). The only drain method is `waitUntilIdle()` (`CaptureSaveQueue.swift:46-48`), and it is currently used by tests only; there is no `applicationWillTerminate`, restart, or quit path that stops the watcher and waits briefly for queued saves.

This is most visible after large image captures because thumbnailing and Vision OCR are synchronous inside the queue before purge completes. A user can copy or snip an item, immediately quit or use "Restart Permafrost", and lose a capture that the UI implied had been accepted.

### Risk

Clipboard history durability is a core product promise. Silent loss is especially likely for the exact path issue #7 targeted: large screenshots/images saved in the background.

### Recommendation

Add an app lifecycle shutdown path that stops polling, prevents new enqueue work, and drains the capture queue with a bounded timeout before terminating/restarting. Consider making queue state observable so the status menu can avoid immediate restart while a save is in progress. Add tests around queue draining semantics and manual smoke coverage for "copy large image, immediately quit/relaunch".

### Estimated implementation effort

Medium.

## Medium

### Title

Automatic OCR creates new plaintext/search/export exposure without a dedicated privacy control or warning.

### Affected files

- `Sources/Permafrost/CaptureSaveQueue.swift`
- `Sources/Permafrost/OCR/TextRecognizing.swift`
- `Sources/PermafrostCore/ImportExport.swift`
- `Sources/Permafrost/Settings/SettingsView.swift`
- `docs/SECURITY.md`

### Description

Every image capture now runs Vision OCR in the background when possible (`CaptureSaveQueue.swift:29-37`, `TextRecognizing.swift:39-51`). The recognized text is stored as `ocr_text`, searched via FTS, displayed in preview, and exported inline in `manifest.json` (`ImportExport.swift:57-63`). The privacy section in Settings warns only about concealed/password pasteboard content (`SettingsView.swift:174-195`), not about OCR extracting visible text from screenshots into searchable/exportable plaintext.

OCR remains local-only, which is good, but it changes the threat model: a screenshot of a document, token, password reset code, medical record, or chat may now expose searchable plaintext even though the user copied an image.

### Risk

Users may reasonably understand that images are stored, but not that text inside those images is extracted, indexed, displayed, and exported as text. This can increase accidental disclosure in panel search, shoulder-surfing, export archives, and forensic inspection.

### Recommendation

Make OCR behavior explicit in Settings and `docs/SECURITY.md`. Consider an "Recognize text in images" setting, default-on only if the owner accepts the privacy tradeoff, or at minimum a clear privacy note near the image/OCR settings. Document that OCR text is included in exports and follows the same retention/pinning behavior as the parent image.

### Estimated implementation effort

Small to Medium, depending on whether a setting is added.

### Title

Panel preview can promise live OCR completion without reloading when OCR finishes.

### Affected files

- `Sources/Permafrost/CaptureSaveQueue.swift`
- `Sources/PermafrostCore/ClipboardStore.swift`
- `Sources/Permafrost/Panel/PanelModel.swift`
- `Sources/Permafrost/Panel/PanelView.swift`

### Description

`CaptureSaveQueue` persists OCR later via `store.setOCRText` (`CaptureSaveQueue.swift:36`, `ClipboardStore.swift:222-227`). `PanelModel` reloads only on show, query changes, and local actions (`PanelModel.swift:43-73`); there is no store-change notification or OCR completion callback. Meanwhile the image preview states "OCR text will appear here after recognition finishes." (`PanelView.swift:368-371`).

If a user opens an image preview while OCR is still running, the preview can remain stale until the panel is reopened or another reload-triggering action occurs. Search results can similarly miss newly recognized text until the next reload.

### Risk

The OCR UX can look broken or nondeterministic, especially for the first screenshot after capture. Users may assume OCR failed when it has actually completed in the database.

### Recommendation

Emit an app-level notification or store update event after `setOCRText`, and have `PanelModel` reload while preserving query/selection when visible. If live refresh is intentionally deferred, change the empty OCR copy to avoid promising live appearance.

### Estimated implementation effort

Medium.

### Title

Import/export and OCR work are synchronous from menu actions and can block the main thread.

### Affected files

- `Sources/Permafrost/ImportExportUI.swift`
- `Sources/PermafrostCore/ImportExport.swift`
- `Sources/Permafrost/CaptureSaveQueue.swift`

### Description

Export iterates all items and writes blobs/manifests synchronously (`ImportExport.swift:50-97`), and `ImportExportUI` runs `ditto` synchronously with `waitUntilExit` from the menu action. Import similarly unzips and reads every manifest/blob synchronously before showing completion. Separately, OCR is synchronous by design and currently shares the same serial queue as capture persistence.

The background capture queue correctly keeps large image saves off the UI thread, but import/export can still freeze the app for large histories. OCR sharing the save queue also means one expensive recognition can delay subsequent text captures from being persisted.

### Risk

With thousands of entries or many large images, the menu bar app may appear hung during import/export. Under heavy image capture, later clipboard items may be delayed longer than users expect, increasing perceived data-loss risk if they quit before the queue drains.

### Recommendation

Move import/export orchestration to a background task with progress/completion reporting back to the main actor. Consider splitting "persist capture bytes" from "run OCR enrichment" so OCR cannot delay durable storage of later captures. At minimum, document expected behavior and add performance/manual tests for large archives and repeated screenshot captures.

### Estimated implementation effort

Medium.

## Low

### Title

Documentation still describes OCR as scaffold/deferred even though it is wired into storage and UI.

### Affected files

- `docs/BACKLOG.md`
- `docs/UX.md`
- `docs/ARCHITECTURE.md`
- `Sources/Permafrost/OCR/TextRecognizing.swift`

### Description

Several docs contradict the current implementation. `docs/BACKLOG.md:81-90` says OCR is not wired into `CaptureSaveQueue` or `ClipboardItem`; `docs/UX.md:48-50` says UI affordances for copying recognized text are deferred; `docs/UX.md:82-90` still lists future OCR insertion points that now exist; `docs/ARCHITECTURE.md:105-111` and `TextRecognizing.swift:6-12` still say a sibling branch will add persistence.

### Risk

Future implementation agents may follow stale instructions and duplicate or regress finished work. Users and reviewers may misunderstand release readiness and privacy behavior.

### Recommendation

Update OCR-related docs to describe the current pipeline: image capture, background Vision recognition, `ocr_text` persistence/search/export, preview display, Copy Text/Paste Text actions, and remaining gaps such as live refresh or OCR privacy controls.

### Estimated implementation effort

Small.

### Title

Database sidecar file permissions are asserted only opportunistically and need regression coverage.

### Affected files

- `Sources/PermafrostCore/ClipboardStore.swift`
- `docs/SECURITY.md`
- `Tests/PermafrostCoreTests`

### Description

`ClipboardStore.onDisk` creates the support directory with `0700` and then attempts to set `0600` permissions on the main database and sidecars (`ClipboardStore.swift:16-27`). This is a good intent, but the code ignores sidecar chmod failures and only touches files that exist at open time. There is no automated test verifying the resulting permissions after writes, journal creation, or future SQLite configuration changes.

### Risk

The docs promise owner-only storage. If SQLite sidecar behavior or process umask changes, clipboard content could be more readable than intended without tests catching the regression.

### Recommendation

Add an on-disk storage permission test that performs writes and verifies the support directory, database, and any created `-wal`, `-shm`, or `-journal` files are owner-only. If needed, configure SQLite/file creation more explicitly rather than relying on post-open best effort.

### Estimated implementation effort

Small.

### Title

Global hotkey re-registration is coupled to every UserDefaults change.

### Affected files

- `Sources/Permafrost/App.swift`
- `Sources/Permafrost/AppSettings.swift`

### Description

`observeSettingsChanges` listens to broad `UserDefaults.didChangeNotification` and calls `registerEffectiveHotkey()` for any defaults mutation (`App.swift:103-115`). This includes unrelated settings such as retention, capture pause, image size, excluded apps, and welcome state.

### Risk

The current cost is probably low, but broad re-registration makes hotkey behavior more coupled than necessary and can surface unrelated Carbon registration errors while the user is changing non-hotkey settings.

### Recommendation

Use more specific change notifications or compare the last effective hotkey before re-registering. Keep capture indicator refresh separate from hotkey registration.

### Estimated implementation effort

Small.

# Testing Assessment

Current strengths: Core behavior has solid unit coverage for retention, deduplication, search, ordering, import/export hardening, OCR metadata, and thumbnail/image handling. App-layer tests cover panel state, quick-paste semantics, hotkey rollback, pasteboard capture policy, capture queue OCR behavior with a fake recognizer, and OCR text normalization without invoking Vision.

Missing scenarios:

- App termination/restart with pending captures, especially large image/OCR work.
- Live panel refresh after asynchronous OCR completion.
- Real `VisionTextRecognizer` manual coverage on representative screenshots, including no-text images, rotated/scaled screenshots, and multi-column text.
- Large import/export archives on the main thread, including user cancellation and error presentation.
- On-disk permission checks after actual writes and sidecar creation.
- Manual privacy checks for OCR text in search, preview, and export archives.

Suggested regression tests:

- Queue-drain contract tests for shutdown/restart behavior.
- `PanelModel` reload-preserves-selection test driven by an OCR completion notification.
- Permission regression test for `ClipboardStore.onDisk`.
- Import/export performance or at least stress tests with many image entries.

Suggested manual testing:

- Copy a large screenshot and immediately quit/reopen; verify it persists with or without OCR complete.
- Open preview before OCR completes and confirm the UI refreshes or the copy accurately reflects deferred behavior.
- Export a history with OCR images and concealed opt-in data; inspect manifest contents and confirm docs/settings match actual exposure.
- Run a 1k/10k item history with mixed text/images; verify panel responsiveness, import/export UX, startup, and idle CPU.

# Documentation Assessment

Accuracy is mixed after the recent OCR completion. README and SECURITY mostly match the local-first product, but OCR-specific privacy exposure is underdocumented. BACKLOG, UX, ARCHITECTURE, and an OCR source comment still describe OCR persistence/UI as future work even though it is implemented.

Completeness is otherwise strong. The project has enough docs for a new engineer to understand architecture, testing, security, release process, and operating expectations.

Consistency needs a cleanup pass around issue #6/#7 status, version/status naming, and which OCR tasks are complete versus still open.

Missing topics:

- OCR privacy model and export implications.
- Background queue lifecycle guarantees.
- Expected behavior during long import/export operations.
- Store change notification model, if live UI updates are added.

# Technical Debt

Immediate:

- Add shutdown draining or an equivalent durability guarantee for `CaptureSaveQueue`.
- Update stale OCR documentation.
- Clarify OCR privacy behavior in settings/docs.

Near-term:

- Add live store/OCR update notification support for the panel.
- Move import/export orchestration off the main thread with progress/error reporting.
- Add filesystem permission regression tests.

Long-term:

- Consider separating durable capture persistence from enrichment jobs such as OCR.
- Revisit optional at-rest encryption if the product targets broader distribution.
- Introduce a small event/observation layer around storage mutations if more UI surfaces need live updates.

# Architecture Assessment

For MVP, the architecture is appropriate. The two-module split is clean, GRDB is a reasonable dependency, and native macOS APIs are used directly where they matter: pasteboard polling, Carbon hotkeys, AppKit panel behavior, and Accessibility paste simulation.

For future growth, the main architectural pressure is that persistence has become both a durable capture path and an enrichment pipeline. OCR is valuable, but it should not compromise durable capture ordering or shutdown safety. A simple job split or lifecycle-aware queue would keep the architecture understandable.

Maintainability is good. Most seams are testable (`PanelPasteServing`, `TextRecognizing`, `PasteboardCapturePolicy`, hotkey registrar abstraction). The biggest maintainability issue is documentation drift, not code complexity.

Native macOS conventions are mostly respected. The non-activating panel and menu-bar lifecycle are appropriate for a Win+V-like utility, and the settings/privacy permission UI follows macOS expectations well enough for MVP.

# Release Readiness

I would release this to technical testers or a small beta audience, with known limitations documented. I would not call it v1.0-ready until the pending-capture shutdown risk is fixed and OCR privacy behavior is explicit.

What prevents broader release:

- Potential silent loss of queued captures on quit/restart.
- OCR plaintext extraction is not clearly surfaced as a privacy-affecting behavior.
- Some docs directly contradict the implementation.

Remaining work before version 1.0:

- Durability/lifecycle fix for background captures.
- OCR privacy setting or explicit consent/documentation.
- Live UI refresh for asynchronous OCR completion.
- Background import/export UX for large histories.
- Signing/notarization and release packaging work already noted in project docs.

# Recommended Roadmap

1. Fix capture queue lifecycle: stop watcher, drain or persist pending work on quit/restart, and add tests/manual smoke coverage.
2. Update OCR documentation and settings/privacy copy to reflect current behavior and export implications.
3. Add OCR completion notifications so the panel/search refreshes without reopening.
4. Move import/export work off the main thread and add progress/error UX.
5. Add on-disk permission regression tests for database and SQLite sidecars.
6. Split capture persistence from OCR enrichment if performance testing shows OCR can delay durable saves.
7. Continue release hardening: signed/notarized builds, permission onboarding polish, and large-history performance profiling.
