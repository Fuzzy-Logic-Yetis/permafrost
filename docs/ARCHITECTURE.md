# Architecture

Rationale for every major choice here is recorded as an ADR in [DECISIONS.md](DECISIONS.md).

## Shape

Menu-bar-only agent app (`LSUIElement`), no Dock icon. Two Swift modules:

```text
┌─────────────────────────────────────────────────────────────┐
│ Permafrost (executable — AppKit/SwiftUI, @MainActor)        │
│                                                             │
│  AppDelegate ── NSStatusItem (menu: open/settings/quit)     │
│      │                                                      │
│      ├─ PasteboardWatcher   polls NSPasteboard.changeCount  │
│      │      │               every 0.3s; skips concealed/    │
│      │      ▼               transient types                 │
│      ├─ HotkeyManager       Carbon RegisterEventHotKey      │
│      │      │  ⌥⌘V          (native, no dependency)         │
│      │      ▼                                               │
│      ├─ PanelController     non-activating borderless       │
│      │      │               NSPanel + NSHostingView;        │
│      │      │               local keyDown monitor for       │
│      │      ▼               ↑↓ ⏎ Esc ⌥P ⌘1-9                │
│      │   PanelView (SwiftUI: search field + item cards)     │
│      │                                                      │
│      ├─ PasteService        writes item to pasteboard,      │
│      │                      synthesizes ⌘V via CGEvent      │
│      │                      (Accessibility permission)      │
│      └─ SettingsWindow      retention, hotkey, login item   │
└──────────────────────┬──────────────────────────────────────┘
                       │ calls (never the reverse)
┌──────────────────────▼──────────────────────────────────────┐
│ PermafrostCore (library — Foundation/GRDB only, no AppKit)  │
│                                                             │
│  ClipboardStore   CRUD, dedup-by-hash, pin/unpin, search,   │
│                   schema migrations, FTS5 sync (owns all    │
│                   SQL — there is no separate database type) │
│  RetentionPolicy  pinned=forever; unpinned TTL + count cap  │
│  Thumbnailer      ImageIO downscale for panel display       │
│  ImportExport     versioned manifest.json + blobs directory │
└──────────────────────┬──────────────────────────────────────┘
                       ▼
        ~/Library/Application Support/Permafrost/store.sqlite
        (SQLite via GRDB, FTS5 index, 0600 permissions)
```

## Data flow

1. **Capture**: user copies anywhere → `PasteboardWatcher` notices `changeCount` change →
   builds a `ClipboardCapture` (image preferred over text if both present; concealed types
   skipped unless the user opted in — ADR-011) → `ClipboardStore.save()` hashes content
   (SHA-256 over text for text rows or image bytes for image rows; OCR metadata is not part
   of the dedup key); an existing hash bumps `last_used_at` and refreshes capture metadata,
   otherwise a new row + thumbnail (images) is inserted, then retention runs.
2. **Recall**: `⌥⌘V` → `PanelController` shows the panel *without activating the app* (the
   target app keeps focus) → typing filters via FTS5 over text rows and image OCR metadata
   → `⏎` → `PasteService` writes the item
   to the pasteboard and synthesizes `⌘V` into the still-focused target app → panel closes,
   `last_used_at` bumps. List order is unpinned-first-by-recency, then a pinned section
   (ADR-012); `⌘1`–`⌘9` in `PanelModel.commitQuickPaste` are bounded to the unpinned prefix
   so pinning something can never hijack a quick-paste slot. Hovering a card swaps its
   badges for pin/share/delete buttons (`ShareButton` bridges `NSSharingServicePicker`,
   since SwiftUI has no native share-picker API on macOS).
3. **Expiry**: `RetentionPolicy` purge runs at launch, hourly, and after every insert.
   `DELETE WHERE is_pinned = 0 AND last_used_at < cutoff` — pinned rows are untouchable by
   design (the WHERE clause, not app logic, guarantees it).

## Schema (current, v2)

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
  duration of recognition, so it must only ever be called from a background context (the
  intended caller is `CaptureSaveQueue`'s serial queue once a sibling branch adds somewhere
  to persist the result), never the main actor. `TextRecognizing` is the protocol seam
  (mirrors `PanelPasteServing`) so recognition-dependent code can be tested with a fake
  recognizer instead of real Vision calls.

## Key constraints

- **No sandbox** — sandboxing forbids `CGEvent` keystroke synthesis (paste-on-select is the
  product). Direct distribution only (ADR-007).
- **Accessibility permission** is required for paste-on-select; the app degrades gracefully
  to copy-only mode without it.
- **Build without Xcode**: plain SPM + `scripts/make-app.sh` assembles the `.app` bundle and
  ad-hoc signs it. CI uses GitHub Actions macOS runners (ADR-009).
