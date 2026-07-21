# Future Ideas

Explicitly **not** MVP. Ideas parked here must survive the CLAUDE.md decision framework
before promotion to docs/BACKLOG.md. Permafrost is a clipboard manager; the moment it
becomes a suite, it has failed (see docs/RESEARCH.md).

Note: image/screen-snip history is **not** on this list — it shipped in the MVP by owner
requirement. OCR on snips (Vision framework, on-device) is also no longer on this list —
it shipped 2026-07-08, see docs/BACKLOG.md item 13.

## Likely someday

- **At-rest encryption, scoped to concealed (password) items only** — refined 2026-07-21
  from the original "encrypt everything" framing in ADR-008, which stalled on FTS5 not
  being able to search ciphertext for *any* encrypted item. Scoping to concealed items
  specifically (already opt-in, already visually flagged, ADR-011) shrinks that to
  "you can't full-text-search the literal characters of a password" — a trade worth making,
  since you don't want to search for that anyway and arguably shouldn't want it appearing
  in search results in cleartext at all. CryptoKit AES-GCM, key in Keychain
  (`kSecAttrAccessibleWhenUnlocked`); a new column carries ciphertext for concealed rows
  (their existing `text`/`rich_data` columns stay empty) — still a real schema change,
  still needs an ADR, but small and surgical rather than store-wide. Metadata
  (`source_app`, `created_at`, `last_used_at`, `is_pinned`) lives in separate columns
  untouched by any of this, so encrypted items still list, sort, and filter normally —
  only their content is opaque without the key.

  Pairs naturally with **redact-by-default, reveal-on-demand** display for concealed items:
  today they show plaintext in the panel with only a 🔑 icon as a flag (a real
  shoulder-surf exposure); since encrypting the content requires a decrypt-to-display step
  anyway, showing `••••••••` until the user explicitly reveals it is close to free once
  that path exists. Confirmed this needs to be a real *visual* reveal, not just an
  enable-to-paste action — motivating case: a password that's recognizable on sight but not
  memorizable (kept around specifically to re-unlock a password-manager browser extension,
  which itself then requires a hardware key to open the vault) — the user needs to *read*
  it, not just paste it blind.
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
