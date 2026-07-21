# Executive Summary

Permafrost remains a well-structured native macOS clipboard manager with strong test coverage and a sensible encrypted-field design for new concealed text captures. The recent AES-GCM + Keychain work materially improves the intended threat model, but it is **not safe to call complete yet**.

The review found one Critical implementation flaw: a Keychain read or write failure can still result in a fresh, non-persisted key being installed and used. This recreates the precise unrecoverable-data-loss failure ADR-021 says was removed. It also found High issues where existing concealed plaintext is not migrated and legacy plaintext concealed exports can be re-imported into an encrypted-capable store as plaintext. Finally, a failed decrypt currently clears the user’s pasteboard and replaces it with an empty string.

Recommendation: do not make broader security claims or treat encrypted concealed storage as release-ready until the Critical and High findings are corrected and migration/import paths are covered by regression tests.

# Strengths

- Clear module split: `PermafrostCore` owns database/cipher logic; the executable owns AppKit, Keychain, UI, and permissions.
- The cipher selection is sound: CryptoKit AES-GCM with a fresh nonce per seal, and the sealed-box combined representation is used correctly.
- New concealed captures correctly avoid filling `text` and `rich_data`; FTS naturally excludes ciphertext-backed rows.
- The plaintext-to-concealed transition in `ClipboardStore.save` and manual **Mark as Concealed** path explicitly wipe `text` and `rich_data` in the same database update.
- Same-machine encrypted export/import validates the decrypted plaintext against the stored content hash before inserting it.
- The test suite is substantial and currently passes: `./scripts/test.sh` completed with 109 tests in 12 suites during this review.
- A non-content database inspection of the current local store found one concealed row with ciphertext and no plaintext/rich-data column populated. This is a useful current-state check, but it does not replace migration coverage.

# Findings

## Critical

### Keychain failures can still install and use a non-persistent encryption key

**Affected files**
- `Sources/Permafrost/ConcealedContentKeychain.swift:31-70`
- `Sources/Permafrost/App.swift:54-56`

**Description**

`loadOrCreateKey` treats every unsuccessful `SecItemCopyMatching` status as equivalent to “item not found” by evaluating `loadKey() ?? generateAndStoreKey()`. `loadKey()` returns `nil` not only for `errSecItemNotFound`, but also for interaction/authentication failures, locked-Keychain states, and other Keychain errors.

`generateAndStoreKey()` returns its newly generated key even when `SecItemAdd` fails. Typical failure cases include an existing Keychain item (`errSecDuplicateItem`), Keychain interaction errors, or a write failure. The completion then installs that in-memory key in `ClipboardStore`; concealed content may be sealed with it even though it was never persisted. On restart, the app will read the real stored key (or another generated key), and data sealed with the failed-write key becomes unrecoverable.

This is the same fundamental failure mode described by ADR-021’s critical follow-up, reached through error handling rather than the removed timeout fallback.

**Risk**

Irrecoverable loss of concealed content, potentially after a Keychain authorization dialog, Keychain lock, access-control mismatch, duplicate-write race, or Keychain write failure.

**Recommendation**

Make Keychain loading/creation return `Result<SymmetricKey, KeychainError>` and distinguish:

- `errSecSuccess`: use the loaded key.
- `errSecItemNotFound`: generate, add, and use the key **only after** `SecItemAdd` succeeds. Handle `errSecDuplicateItem` by re-reading the existing item.
- all other statuses: report key unavailable; do not generate/use any key.

Do not invoke `setConcealedContentKey` on failure. Surface a user-visible unavailable/error state for concealed capture/reveal/mark actions, and add failure-injection tests around duplicate/add/read failure paths.

**Estimated implementation effort**

Medium.

## High

### Existing concealed plaintext rows are not migrated into encrypted storage

**Affected files**
- `Sources/PermafrostCore/ClipboardStore.swift:121-125`
- `Sources/PermafrostCore/ClipboardStore.swift:140-214`

**Description**

Migration `v3_concealed_encryption` only adds `encrypted_data`; it does not backfill existing rows where `is_concealed = 1` and `text` or `rich_data` already contains plaintext. The new save and mark paths protect future transitions, but users who had opted into concealed history before v3 keep existing password content in plaintext indefinitely unless they manually re-mark/re-copy each item.

**Risk**

The primary at-rest protection claim does not apply to the historical data most likely to matter. A user may reasonably assume enabling/upgrading to encrypted concealed storage protects their prior concealed history when it does not.

**Recommendation**

After the Keychain key is successfully available, perform a one-time transactional backfill: enumerate concealed text rows with plaintext, seal the text, clear `text`/`rich_data`, and persist the ciphertext. Do not run it until the real key is confirmed available. Provide a clear recovery/error state if a row cannot be migrated. Add an on-disk pre-v3 migration regression test.

**Estimated implementation effort**

Medium.

### Legacy plaintext concealed exports can be imported as plaintext concealed rows

**Affected files**
- `Sources/PermafrostCore/ImportExport.swift:160-242`
- `Sources/PermafrostCore/ClipboardStore.swift:414-435`

**Description**

The encrypted-import branch activates only when `entry.isConcealed` and `encryptedDataFile` is present. A pre-encryption archive containing `isConcealed: true` plus plaintext `text` follows the normal text branch, then `insertPreservingMetadata` inserts it directly with `isConcealed = true` and plaintext `text`. It bypasses the encryption logic in `save`.

**Risk**

Import can reintroduce a password into plaintext storage after the encryption feature is deployed, silently violating the expected invariant for concealed rows.

**Recommendation**

Explicitly define legacy concealed archive handling. Preferred behavior: after a real key is available, validate the legacy plaintext hash, seal it, clear plaintext/rich data, and insert only ciphertext. If encryption is unavailable, refuse or clearly skip the item rather than importing it insecurely. Add tests for legacy plaintext concealed manifests, missing ciphertext, and wrong-key encrypted archives.

**Estimated implementation effort**

Medium.

### Failed decrypt can erase the user’s current clipboard with an empty string

**Affected files**
- `Sources/Permafrost/PasteService.swift:26-39`
- `Sources/Permafrost/PasteService.swift:56-74`

**Description**

`copyToPasteboard` and `copyPlainTextToPasteboard` call `pasteboard.clearContents()` and then write `revealedText(for: item) ?? ""`. For a concealed item whose key is unavailable or whose ciphertext cannot be opened, `revealedText` returns `nil`; the code replaces the pasteboard with an empty string and continues to mark the item used. `paste(_:)` may then synthesize Command-V, pasting nothing into the destination app.

**Risk**

A failed secret reveal destroys the user’s existing clipboard data and causes a silent empty paste. This is particularly harmful because it occurs in the error path for sensitive content.

**Recommendation**

Resolve/decrypt text before clearing the pasteboard. Change copy/paste methods to report failure without touching the pasteboard when plaintext is unavailable. Surface an actionable “concealed content unavailable; unlock/authorize Keychain and try again” message, and test that the prior pasteboard remains unchanged on reveal failure.

**Estimated implementation effort**

Small to Medium.

## Medium

### Plaintext content hashes remain an offline guessing oracle for concealed values

**Affected files**
- `Sources/PermafrostCore/ClipboardItem.swift:127-138`
- `Sources/PermafrostCore/ClipboardStore.swift:92-93`

**Description**

Concealed rows retain the deterministic unsalted SHA-256 `content_hash` of plaintext. AES-GCM encrypts the value itself, but anyone with database access can hash guesses and compare them to the stored hash. This is practical for weak/common passwords, short OTP-like values, known token formats, and a candidate set known to an attacker.

**Risk**

The feature protects against direct plaintext reads but not offline confirmation of guessed secret values. Metadata such as source app, timestamps, pin state, and a concealed flag further help target guesses.

**Recommendation**

Document this residual risk immediately. For a stronger design, use a Keychain-held keyed hash/HMAC for concealed-row deduplication instead of an unsalted plaintext SHA-256, with a deliberate migration story. Do not silently change the hash scheme without considering existing uniqueness and import behavior.

**Estimated implementation effort**

Medium to Large.

### Security documentation contradicts the current encryption implementation

**Affected files**
- `docs/SECURITY.md:14-15, 19-37, 62`
- `docs/DECISIONS.md:756-951`
- `docs/BACKLOG.md:111-133`

**Description**

`SECURITY.md` still says “At-rest encryption is FileVault’s job in MVP,” tells users recorded passwords are stored in plaintext, and says app-level encryption is backlogged. ADR-021 and BACKLOG say concealed text encryption is implemented. The documentation also does not explain the plaintext-hash metadata limitation, legacy-data behavior, Keychain availability behavior, or that encrypted archives are only decryptable with the same key.

**Risk**

Users cannot make informed decisions about sensitive-data storage, export portability, recovery, or current limitations. Future contributors may regress behavior by following stale security guidance.

**Recommendation**

Update `SECURITY.md` in the same release as the code fixes. State the exact scope (concealed text only), Keychain-backed AES-GCM behavior, metadata/hash limitations, export/import limitation, legacy-data migration outcome, and the fallback behavior when the key is unavailable.

**Estimated implementation effort**

Small.

### Concealed capture/key-unavailable failures are silently dropped

**Affected files**
- `Sources/Permafrost/CaptureSaveQueue.swift:31-56`
- `Sources/PermafrostCore/ClipboardStore.swift:187-193`

**Description**

Before the key is available, saving a concealed capture throws `keyNotYetAvailable`; `CaptureSaveQueue` logs the error and drops the capture. The app offers no status/menu/UI feedback and no retry after the Keychain fetch resolves. A user who copied a password immediately after launch can believe it was saved when it was not.

**Risk**

Silent history loss during the precise startup/Keychain-authorization scenario ADR-021 acknowledges.

**Recommendation**

Expose a visible “concealed history temporarily unavailable” state while key retrieval is pending, and either retain/retry a bounded in-memory pending capture after key availability or explicitly notify the user that this capture was not saved. Avoid retaining secret plaintext longer than necessary and define queue/termination behavior.

**Estimated implementation effort**

Medium.

## Low

### Concealed text cannot be shared through the existing Share action

**Affected files**
- `Sources/Permafrost/Panel/ClipboardItem+Sharing.swift:7-15`

**Description**

`shareableItems` returns `text ?? ""`. Concealed text rows intentionally have `text == nil`, so the visible Share action shares an empty string rather than decrypting intentionally or disabling the action.

**Risk**

Confusing, inconsistent UI; a user may believe secret content was shared when an empty value was sent.

**Recommendation**

Either hide/disable Share for concealed text or make an explicit user-confirmed decrypt-and-share path through `PasteService`/`ClipboardStore`, with a clear security warning.

**Estimated implementation effort**

Small.

# Testing Assessment

## Current strengths

- AES-GCM round-trip, wrong-key failure, and nonce freshness are covered.
- New concealed rows, dedup, transition-to-concealed, manual marking, FTS exclusion, delayed key availability, and same-key export/import are covered.
- The complete suite passed during review: 109 tests in 12 suites.

## Missing scenarios

- Keychain read failure, write failure, duplicate-item race, invalid returned key material, and no-key completion behavior.
- Pre-v3 on-disk migration/backfill of existing plaintext concealed rows.
- Legacy plaintext concealed archive import.
- Pasteboard preservation when decryption fails.
- Cross-machine/wrong-key archive behavior should be explicit and surfaced rather than only skipped.
- Secret hash-guessing threat model regression/documentation check.
- App-level Keychain authorization dialog/manual flow and key-unavailable user feedback.

## Suggested manual testing

- Launch after an ad-hoc rebuild that causes Keychain authorization; verify no concealed operation seals with an unpersisted key and the UI tells the user what is unavailable.
- Create plaintext concealed history in a pre-v3 fixture, upgrade, and verify every legacy row is encrypted or visibly reported as unmigrated.
- Attempt paste/reveal with unavailable/wrong key and verify the existing system pasteboard remains intact.
- Export/import on the same machine and a different machine; verify the result is explicit and no concealed plaintext appears in manifests or SQLite.

# Documentation Assessment

Architecture and ADR documentation is detailed, especially ADR-021’s account of the removed timeout fallback. `SECURITY.md` is materially stale and currently makes claims that contradict the implementation. It requires immediate correction after the migration/key-handling fixes define the final supported behavior.

# Technical Debt

## Immediate

- Correct Keychain error handling so no unpersisted key can be used.
- Encrypt or explicitly handle existing concealed plaintext and legacy exports.
- Preserve pasteboard contents on decryption failure.

## Near-term

- User-visible key availability/failure state and retry policy.
- Accurate security/privacy/export documentation.
- Explicit same-machine versus cross-machine encrypted export support.

## Long-term

- Keyed/HMAC-based concealed dedup identifier to eliminate plaintext hash guessing.
- Developer ID signing/notarization to reduce repeated ad-hoc-signature Keychain friction.
- Broader at-rest protection remains a separate product decision; OCR/image data and non-concealed text remain plaintext by design.

# Architecture Assessment

The field-encryption approach is appropriate for an MVP when scoped honestly to concealed text, because it preserves FTS for ordinary text and avoids a SQLCipher dependency. The design needs one stronger abstraction at the Keychain boundary: key acquisition must be a fallible state machine, not an optional key with a best-effort creation fallback. Import/migration must also flow through the same encryption invariant rather than raw metadata insertion.

# Release Readiness

Not ready to claim encrypted concealed storage as release-ready. The current Critical key-handling path can reintroduce unrecoverable data loss, and High migration/import paths can leave supposedly concealed data plaintext. The rest of the app is suitable for continuing internal testing once those issues are fixed.

# Recommended Roadmap

1. Fix Keychain acquisition/create semantics and add failure-injection tests.
2. Fix paste/reveal failure so the existing pasteboard is never overwritten with an empty string.
3. Implement encrypted backfill for existing concealed rows and safe legacy archive import.
4. Update `SECURITY.md`, release notes, and manual test checklist to match the final behavior and limitations.
5. Add visible key-pending/key-error UX and a defined retry policy for concealed captures.
6. Decide whether keyed concealed deduplication is required for the intended local-threat model.
