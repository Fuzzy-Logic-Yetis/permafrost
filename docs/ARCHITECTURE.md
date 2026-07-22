# Architecture

Rationale for every major choice here is recorded as an ADR in [DECISIONS.md](DECISIONS.md).

## Shape

Menu-bar-only agent app (`LSUIElement`), no Dock icon. Two Swift modules:

```text
┌───────────────────────────────────────────────────────────────┐
│ Permafrost (executable — AppKit/SwiftUI, @MainActor)          │
│                                                                │
│  AppDelegate ── NSStatusItem (menu: open/settings/quit)       │
│      │                                                        │
│      ├─ PasteboardWatcher    polls NSPasteboard.changeCount   │
│      │      │                every 0.3s; skips concealed/     │
│      │      ▼                transient types                  │
│      ├─ CaptureSaveQueue     serial background save: hashing, │
│      │      │                thumbnails, HTML→RTF conversion, │
│      │      │                OCR (Vision), retention purge —  │
│      │      │                keeps the UI thread free         │
│      │      ▼                                                 │
│      ├─ ConcealedContent     Keychain read/write for the      │
│      │  Keychain             concealed-content key; no        │
│      │                       timeout, no fallback key ever     │
│      ├─ HotkeyManager        Carbon RegisterEventHotKey       │
│      │      │  ⌥⌘V           (native, no dependency)          │
│      │      ▼                                                 │
│      ├─ PanelController      non-activating borderless        │
│      │      │                NSPanel + NSHostingView;         │
│      │      │                local keyDown monitor for        │
│      │      ▼                ↑↓ ⏎ ⇧⏎ ␣ Esc ⌥P ⌘1-9            │
│      │   PanelView (SwiftUI: search, cards, preview pane,     │
│      │                drag-and-drop, share sheet)             │
│      │                                                        │
│      ├─ PasteService         writes item to pasteboard,       │
│      │                       synthesizes ⌘V via CGEvent       │
│      │                       (Accessibility permission)        │
│      ├─ ImportExportUI       save/open panels, zip via ditto, │
│      │                       This Mac Only vs. Portable         │
│      │                       Encrypted Backup choice            │
│      └─ SettingsWindow       retention, hotkey, login item    │
└──────────────────────┬─────────────────────────────────────────┘
                       │ calls (never the reverse)
┌──────────────────────▼─────────────────────────────────────────┐
│ PermafrostCore (library — Foundation/GRDB only, no AppKit)    │
│                                                                │
│  ClipboardStore    CRUD, dedup-by-hash, pin/unpin, search,    │
│                     schema migrations, FTS5 sync (owns all    │
│                     SQL — there is no separate database type) │
│  RetentionPolicy   pinned=forever; unpinned TTL + count cap   │
│  Thumbnailer        ImageIO downscale for panel display        │
│  ImportExport       versioned manifest.json + blobs directory  │
│                     (This Mac Only archive, ADR-021)           │
│  PortableArchive    passphrase-encrypted (PBKDF2+AES-GCM)      │
│                     single-file archive for moving history to │
│                     another Mac, independent of its Keychain   │
│  ConcealedContent   AES-GCM seal/open given a key — knows      │
│  Cipher             nothing about where that key comes from    │
└──────────────────────┬─────────────────────────────────────────┘
                       ▼
        ~/Library/Application Support/Permafrost/store.sqlite
        (SQLite via GRDB, FTS5 index, 0600 permissions)
```

## Data flow

1. **Capture**: user copies anywhere → `PasteboardWatcher` notices `changeCount` change →
   builds a `ClipboardCapture` (image preferred over text if both present; concealed types
   skipped unless the user opted in — ADR-011) → handed to `CaptureSaveQueue`, a serial
   background queue: HTML-only rich text is converted to RTF (ADR-019) when no native
   `.rtf` is present, image OCR runs (Vision) if enabled, then `ClipboardStore.save()`
   hashes content (SHA-256 over text for text rows or image bytes for image rows; OCR
   metadata is not part of the dedup key). Concealed captures are sealed (AES-GCM) using
   the Keychain-backed key if it's ready; if it isn't yet (e.g. right after launch), the
   capture is queued in memory, bounded, and retried once the key arrives — never written
   to disk as plaintext, never silently dropped for a merely-late key (ADR-021). An
   existing hash bumps `last_used_at` and refreshes capture metadata, otherwise a new row +
   thumbnail (images) is inserted, then retention runs.
2. **Recall**: `⌥⌘V` → `PanelController` shows the panel *without activating the app* (the
   target app keeps focus) → typing filters via FTS5 over text rows and image OCR metadata
   → `⏎` (or `⇧⏎` for plain text, ADR-018) → `PasteService` decrypts concealed content on
   demand, writes the item to the pasteboard, and synthesizes `⌘V` into the still-focused
   target app → panel closes, `last_used_at` bumps. List order is unpinned-first-by-recency,
   then a pinned section (ADR-012); `⌘1`–`⌘9` in `PanelModel.commitQuickPaste` are bounded
   to the unpinned prefix so pinning something can never hijack a quick-paste slot. `␣`
   opens a full-size preview pane that follows selection. Hovering a card swaps its badges
   for reveal (concealed items only)/plain-text/pin/share/delete buttons (`ShareButton`
   bridges `NSSharingServicePicker`, since SwiftUI has no native share-picker API on
   macOS); cards are also `.draggable()` (ADR-020) for dragging straight into another app
   or onto the Desktop.
3. **Expiry**: `RetentionPolicy` purge runs at launch, hourly, and after every insert.
   `DELETE WHERE is_pinned = 0 AND last_used_at < cutoff` — pinned rows are untouchable by
   design (the WHERE clause, not app logic, guarantees it).
4. **Concealed content** (opt-in, ADR-011/ADR-021): a Keychain-backed 256-bit key is
   fetched on a background queue at launch, with no timeout and no fallback — an earlier
   design that fell back to a session-only key on a timeout caused a real, unrecoverable
   data-loss incident (see ADR-021's history) and was removed entirely. Until the key
   arrives, concealed-content operations fail explicitly (throw / return `nil`) rather than
   using a placeholder. Once installed, existing legacy plaintext-concealed rows (from
   before a key was ever available) are backfilled into encrypted storage automatically.
5. **Import/export**: `ImportExport` (This Mac Only) ties concealed content to this Mac's
   Keychain key; `PortableArchive` instead derives its own key from a user passphrase
   (PBKDF2-HMAC-SHA256, 600k iterations, off the main thread) so a backup is restorable on
   a different Mac. Both validate and decrypt every entry before writing anything, so a
   damaged archive or one bad entry imports nothing rather than a misleading partial result.

## Schema (current, v3)

```sql
CREATE TABLE clipboard_item (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  content_hash  TEXT NOT NULL UNIQUE,   -- SHA-256 of content; dedup key
  kind          TEXT NOT NULL,          -- 'text' | 'image'
  text          TEXT,                   -- plain text (also FTS5-indexed)
  ocr_text      TEXT,                   -- recognized text for image rows; not a dedup key
  rich_data     BLOB,                   -- RTF alternate representation, if any
  image_data    BLOB,                   -- original PNG for images/snips
  thumbnail     BLOB,                   -- downscaled PNG for panel display
  encrypted_data BLOB,                  -- AES-GCM sealed box, concealed .text rows only
                                         -- (ADR-021); text/rich_data are NULL when this is set
  source_app    TEXT,                   -- localized name of frontmost app at capture
  created_at    DATETIME NOT NULL,
  last_used_at  DATETIME NOT NULL,      -- copy-again or paste bumps this
  is_pinned     BOOLEAN NOT NULL DEFAULT 0,
  pin_order     INTEGER,                -- stable ordering among pinned items
  is_concealed  BOOLEAN NOT NULL DEFAULT 0  -- password-manager content, opt-in (ADR-011)
);
-- + clipboard_item_fts: FTS5 external-content table on (text, ocr_text), trigger-synchronized
```

Expiry is measured from `last_used_at`, not `created_at`: an entry you keep pasting stays
alive (ADR-010).

## Concurrency

- All AppKit/UI and the pasteboard poll run on the main actor.
- `PasteboardWatcher` snapshots pasteboard/AppKit state on the main actor, then hands
  accepted captures to `CaptureSaveQueue`, a serial background queue. This keeps hashing,
  thumbnail generation, SQLite blob writes, and post-insert retention purge off the UI
  thread while preserving capture order and the policy/settings state observed at copy
  time.
- `ClipboardStore` wraps a GRDB `DatabaseQueue` (serialized writes, Sendable). Reads may
  still happen from UI code when the panel opens/searches; writes are serialized by both
  `CaptureSaveQueue` and GRDB.
- `VisionTextRecognizer` (`Sources/Permafrost/OCR`, issue #6) follows the same rule: Vision's
  `VNImageRequestHandler.perform` is synchronous and blocks the calling thread for the
  duration of recognition, so it runs from `CaptureSaveQueue` only when the image-OCR
  setting was enabled at capture time. The recognized text is saved back to the image row's
  `ocr_text` metadata and an app notification asks the panel model to refresh any visible
  search/preview. `TextRecognizing` is the protocol seam (mirrors `PanelPasteServing`) so
  recognition-dependent code can be tested with a fake recognizer instead of real Vision
  calls.
- `ClipboardStore`'s concealed-content cipher is set late, from a background queue, once
  `ConcealedContentKeychain`'s Keychain fetch resolves (no timeout — see ADR-021). It's
  `NSLock`-protected so reads from the main actor (panel reveal, paste) and the write from
  that background queue can't race.
- `ImportExportUI`'s export/import (including `PortableArchive`'s PBKDF2 key derivation)
  runs on a background queue, hopping back to the main actor (`MainActor.assumeIsolated`)
  only to present passphrase prompts and the final result alert — this work is expensive
  enough that running it on the main actor would freeze the whole app for its duration.

## Key constraints

- **No sandbox** — sandboxing forbids `CGEvent` keystroke synthesis (paste-on-select is the
  product). Direct distribution only (ADR-007).
- **Accessibility permission** is required for paste-on-select; the app degrades gracefully
  to copy-only mode without it.
- **Build without Xcode**: plain SPM + `scripts/make-app.sh` assembles the `.app` bundle and
  ad-hoc signs it. CI uses GitHub Actions macOS runners (ADR-009).
