# Future Ideas

Explicitly **not** MVP. Ideas parked here must survive the CLAUDE.md decision framework
before promotion to docs/BACKLOG.md. Permafrost is a clipboard manager; the moment it
becomes a suite, it has failed (see docs/RESEARCH.md).

Note: image/screen-snip history is **not** on this list — it shipped in the MVP by owner
requirement.

## Likely someday

- **OCR on snips** (Vision framework, on-device) — search inside screenshots. High value,
  fully local, native API. Strongest candidate here.
- **Optional at-rest encryption** — CryptoKit AES-GCM per-blob, key in Keychain
  (`kSecAttrAccessibleWhenUnlocked`). Design constraint from ADR-008: FTS5 can't search
  ciphertext, so encrypted items are searchable by metadata only, or the FTS index moves
  to an in-memory table built at unlock. Sketch before building.
- **Paste-as-plain-text** and simple transforms (trim, lowercase, JSON-pretty) on paste.
- **Clipboard collections** — named groups of pinned items (e.g., "onboarding links").

## Possibly

- Markdown-aware preview for text entries
- Syntax-highlighted code previews for copied source snippets. Prefer native/local
  highlighting or a tiny grammar subset; adding a dependency would need an ADR because
  GRDB already spends the dependency budget.
- Expanded multi-line text preview on hover or selection, so long clips can be inspected
  without making the default Win+V-style panel feel bulky.
- Snippet templates with placeholders (danger zone: suite-creep)
- Developer mode: pretty-print/inspect JSON, JWT decode, hex view (local-only)
- AppleScript/Shortcuts automation surface ("get latest clipboard entry matching …")
- Plugin/extension API (almost certainly suite-creep; would need overwhelming demand)

## Almost certainly never (recorded so the "no" is deliberate)

- **Cloud sync / cross-device** — contradicts local-first identity. If ever, end-to-end
  encrypted with keys the server never sees, and still probably no.
- Teams/sharing features
- Windows/Linux ports
- AI anything that requires a network call
