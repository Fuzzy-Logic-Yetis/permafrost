# Background Image Insert Performance Plan

GitHub issue: #7 Background inserts for large images

Role of this document: research/review only. It describes the current capture path, the main-actor work, and a safe implementation plan for a later worker. No production refactor is implemented in this branch.

## Goal

Move expensive image persistence work off the main actor only if measurement shows jank, without changing capture semantics, deduplication, retention, ordering, or privacy behavior.

## Current path and main-actor work

The current image path is synchronous from pasteboard polling through SQLite write:

1. `PasteboardWatcher` is `@MainActor` and polls `NSPasteboard.general.changeCount` every 0.3 seconds on the main run loop.
2. On a pasteboard change, `poll()` updates `lastChangeCount` immediately, gathers pasteboard types, frontmost app, pause/exclusion/concealed settings, and runs the pure `PasteboardCapturePolicy.decide` decision.
3. If capture is allowed, `makeCapture(from:types:concealed:sourceApp:)` runs on the main actor.
4. Image-specific work in `makeCapture`:
   - If `public.file-url`, paths are captured as text before image handling.
   - For `.png`, `pasteboard.data(forType: .png)` copies the image bytes on the main actor.
   - For `.tiff`, `pasteboard.data(forType: .tiff)` copies bytes, then `Thumbnailer.pngData(normalizing:)` decodes and re-encodes to PNG on the main actor.
   - `AppSettings.shared.maxImageBytes` is checked after PNG normalization.
   - A `ClipboardCapture(imageData:)` is emitted.
5. `AppDelegate` installs `watcher.onCapture` on the main actor. The closure synchronously calls:
   - `store.save(capture)`
   - `store.purge(with: settings.retentionPolicy)`
6. `ClipboardStore.save` is not actor-isolated, but the call currently originates from the main actor. Inside `save`:
   - `capture.contentHash` hashes the full image data before the database write.
   - For images, `Thumbnailer.pngThumbnail(from:)` decodes/downscales/re-encodes the PNG before the database write.
   - `dbQueue.write` then dedups by `content_hash`, updates an existing row, or inserts a new row with original `image_data` and generated `thumbnail`.
7. `ClipboardStore.purge` runs a serialized GRDB write immediately after every capture.

Main-actor hotspots are therefore:

- Reading image data from `NSPasteboard`.
- TIFF-to-PNG normalization.
- SHA-256 over full image data.
- Thumbnail generation.
- SQLite write of potentially large `image_data` blob and `thumbnail` blob.
- Retention purge after the insert/update.

The unavoidable main-actor part is pasteboard access and policy gathering. The expensive parts that can move are hashing, thumbnail generation, SQLite insert/update, and purge. TIFF normalization may be movable only if the watcher first snapshots raw pasteboard data and type on the main actor, then converts off-main.

## Recommended architecture

Add a single-writer background capture saver between `PasteboardWatcher` and `ClipboardStore`.

Recommended shape:

- Keep `PasteboardWatcher` on `@MainActor`.
- Keep `PasteboardCapturePolicy` unchanged.
- Keep pasteboard reads on `@MainActor`; snapshot enough value data to be `Sendable` (`Data`, `String?`, `Bool`, source app, pasteboard type).
- Introduce an app-layer capture save service, e.g. `CaptureSaveQueue` or `ClipboardCaptureSaver`, owned by `AppDelegate`.
- The saver should be an `actor` or otherwise serial executor that processes captures in capture order.
- `AppDelegate.watcher.onCapture` should enqueue captures and return quickly; it should not call `store.save` synchronously.
- The saver should call `store.save` and then `store.purge` on its own serial task.
- UI refresh behavior is currently pull-based when the panel opens/searches through `PanelModel.prepareForShow()` and `store.items(...)`; this means no immediate UI notification is needed for correctness. If a later live-refresh feature exists, post a non-content notification after save completes.

Recommended interface sketch:

```swift
actor CaptureSaveQueue {
    private let store: ClipboardStore
    private let retentionPolicy: @Sendable () -> RetentionPolicy

    init(store: ClipboardStore, retentionPolicy: @escaping @Sendable () -> RetentionPolicy) {
        self.store = store
        self.retentionPolicy = retentionPolicy
    }

    func enqueue(_ capture: ClipboardCapture) {
        do {
            try store.save(capture)
            try store.purge(with: retentionPolicy())
        } catch {
            Log.store.error("save failed: \(error.localizedDescription)")
        }
    }
}
```

Important: `AppSettings.shared.retentionPolicy` is `@MainActor`, so the implementation should not call it directly from a background actor. Either snapshot `settings.retentionPolicy` on the main actor at enqueue time and pass it with the capture, or create a small value-type settings snapshot before crossing actors.

Preferred safer enqueue shape:

```swift
struct PendingCapture: Sendable {
    var capture: ClipboardCapture
    var retentionPolicy: RetentionPolicy
}
```

Then `AppDelegate` enqueues `PendingCapture(capture: capture, retentionPolicy: settings.retentionPolicy)` from the main actor.

## Why a serial actor instead of detached per-capture tasks

Use one serial actor/queue rather than `Task.detached` per capture.

Reasons:

- Preserve pasteboard capture order for equal or near-equal timestamps.
- Avoid concurrent thumbnail generation spikes if a user copies several images quickly.
- Keep GRDB `DatabaseQueue` access serialized at the app level, matching the existing synchronous semantics.
- Make error logging and future completion notification simple.
- Avoid races where an older large image finishes after a newer text capture and appears newer because `Date()` was taken at save time.

To preserve ordering exactly, snapshot `Date()` at capture/enqueue time and pass it into `store.save(capture, now:)`. Today `now` is effectively the synchronous save time; after moving work off-main, using background execution time could reorder items when a large older image saves after a smaller newer item.

Recommended pending value:

```swift
struct PendingCapture: Sendable {
    var capture: ClipboardCapture
    var capturedAt: Date
    var retentionPolicy: RetentionPolicy
}
```

Then the saver calls `try store.save(pending.capture, now: pending.capturedAt)` and `try store.purge(with: pending.retentionPolicy, now: pending.capturedAt)` or `Date()` depending on desired purge semantics. For ordering, `save(..., now: capturedAt)` is the key part.

## Behavior that must not change

1. Pause capture semantics: while paused, `PasteboardWatcher` advances `lastChangeCount` and skips without backfill. Do not defer policy decisions to background after settings may have changed.
2. Excluded-app semantics: exclusion is based on the frontmost app at pasteboard-change time. Snapshot it on the main actor; do not re-check in the background.
3. Concealed semantics: concealed content captures only if `recordConcealed` was enabled at pasteboard-change time. Snapshot this policy decision.
4. File URL handling: copied files remain path text, not Finder icon images.
5. Image preference: PNG/TIFF still win over text if both are present.
6. Oversize image behavior: images over `maxImageBytes` are skipped and not inserted. Snapshot the max size before crossing actors.
7. Dedup semantics: content hash remains based on kind + normalized content; existing rows keep pin state, refresh `sourceApp`/`richData`, OR `isConcealed`, and bump `last_used_at`.
8. Retention semantics: pinned rows are never purged; unpinned TTL/count cap still applies after capture.
9. Error behavior: failures are logged and should not crash the app.
10. Database remains accessed only through `ClipboardStore`.

## Race/order/dedup/retention pitfalls

### Race: settings checked too late

If background work reads `AppSettings.shared` after enqueue, a later pause/exclusion/privacy change could affect an already-observed pasteboard item. Avoid this by making all capture/skip decisions and relevant settings snapshots on the main actor at poll time.

### Race: frontmost app changes before save

`NSWorkspace.shared.frontmostApplication` can change immediately after copy. The current code captures `localizedName` before saving. Preserve that by storing `sourceApp` in `ClipboardCapture` before enqueue.

### Order: large image saves after later text

If save timestamps are generated in the background, slow image thumbnailing can make an older image look newer or older incorrectly depending on completion order. Pass a captured/enqueued `Date` into `store.save(..., now:)`.

### Dedup: duplicate image copied while first save is in flight

A serial saver preserves order. `ClipboardStore.save` still dedups by content hash, so the second duplicate should update the first row's `last_used_at` once the first insert completes. Avoid concurrent per-capture saves because they make this harder to reason about even though `DatabaseQueue` serializes at the database level.

### Retention: purge after each capture can remove intermediate unpinned rows

Current behavior purges immediately after every save. Keep purge in the same serial save operation after each save. Snapshot the retention policy at enqueue time or intentionally read it on main and document the choice. Safer behavior-preserving default: snapshot it when the capture is enqueued.

### Memory: moving work off-main does not reduce blob memory

The app still copies image `Data` from pasteboard and then stores it. A serial queue avoids multiple simultaneous decodes, but it does not eliminate memory pressure. Do not add an unbounded backlog of many large `Data` values. If needed, cap queue length or coalesce by pasteboard change count later, but that would be behavior-changing and should be a separate decision.

### Thread-safety: `RetentionPolicy` and `ClipboardCapture` must remain Sendable

`ClipboardCapture` is already `Sendable`; verify `RetentionPolicy` is `Sendable` before passing it across actors. If not, make it `Sendable` if it only contains value types.

### ImageIO thread safety

`Thumbnailer` uses local ImageIO/CoreGraphics objects and no AppKit; it is the right code to run off-main. Do not move AppKit APIs into `PermafrostCore`.

## Suggested implementation sequence for a future worker

1. Add tests/probes first.
   - Add an app-target test around a fake serial saver if the saver is app-layer and fakeable.
   - Add a core test that saving image captures with explicit `now` preserves ordering after a delayed save simulation. This may already be covered indirectly; keep it small.
2. Create `PendingCapture` in the app target, probably near the saver or in `App.swift` if kept private.
3. Create `CaptureSaveQueue` as an `actor` in `Sources/Permafrost/`.
4. Inject `ClipboardStore` into the saver after store creation in `AppDelegate.applicationDidFinishLaunching`.
5. Change `watcher.onCapture` to snapshot `Date()` and `settings.retentionPolicy`, then `Task { await captureSaveQueue.enqueue(pending) }`.
6. Ensure the enqueue path does not capture `self` strongly longer than needed; snapshot `store`, `settings` values on main actor.
7. Keep `PasteboardWatcher.makeCapture` synchronous at first. This moves hash/thumbnail/db/purge off-main while keeping pasteboard access simple.
8. Only if Instruments still shows jank, consider a second phase: snapshot raw image data and pasteboard type on main, then perform TIFF normalization off-main before `ClipboardCapture(imageData:)` creation.
9. Run `swift build` and `./scripts/test.sh`.
10. Manually test copying a large image/screenshot and immediately invoking the panel; compare perceived responsiveness.

## Low-risk tests/probes worth adding later

Recommended test, if a future worker implements the saver:

- A pure `CaptureSaveQueue` ordering test with a fake store/recorder, not a real database delay. Enqueue a large-image placeholder then a text capture with later `capturedAt`; assert the saver calls save in enqueue order and passes the original timestamps.

Recommended integration-style core test:

- In `Tests/PermafrostCoreTests/StoreTests.swift`, save two captures with explicit `now` values out of wall-clock order and assert `items()` sorts by the supplied `last_used_at`, not completion time. This is trivial if not already covered by existing ordering tests, but it does not prove background behavior by itself.

Recommended manual/profiling probe:

- Add temporary `os_signpost` or timestamp log points around `PasteboardWatcher.makeCapture`, `ClipboardStore.save`, `Thumbnailer.pngThumbnail`, and `store.purge`, then copy a 10-25 MB image and inspect where time is spent. Do not keep noisy logs unless useful and reviewed.

## Recommendation

Implement issue #7 in two phases:

1. Phase 1: serial background save queue for `store.save` + `store.purge`, with captured timestamps and retention-policy snapshot. This is the safest high-value change because it removes hashing, thumbnail generation, SQLite blob write, and purge from the main actor while preserving current pasteboard semantics.
2. Phase 2 only if measured jank remains: move TIFF normalization off-main by introducing a `PendingPasteboardImage` value that carries raw data and type. This is more delicate because it changes where `ClipboardCapture` is constructed and needs extra tests around PNG/TIFF normalization and oversize checks.

Do not use concurrent detached saves, do not change schema, do not change dedup/hash logic, and do not move `NSPasteboard`/`NSWorkspace` access off the main actor.
