---
description: Write the handoff note so the owner can safely /clear this session
---

# Handoff

The owner is about to clear this session. Write the handoff so that a fresh session, with no memory of this conversation, can continue the work. Notes from the owner (may be empty): $ARGUMENTS

1. **Stop and park.** Don't start new work. Commit work in progress on its branch. Never leave `main` in a non-building state (`swift build` and `swift test` pass).
2. **Rewrite docs/HANDOFF.md.** Replace it rather than appending; git keeps the history. Keep it under 150 lines, using its existing sections:
   - The state of `main`: last change, version, and whether CI is green.
   - Every open branch and PR, and what each is waiting on.
   - Decisions made this session that are not yet in docs/DECISIONS.md or docs/BACKLOG.md. Record them there if you can.
   - The next steps, in order.
   - Gotchas.
3. **Sync the planning docs.** If a milestone completed, update docs/PROJECT_PLAN.md, docs/ROADMAP.md and docs/BACKLOG.md (CLAUDE.md, Definition of Done).
4. **Run `./scripts/check-docs.sh`** and fix anything it reports.
5. **Commit** with `docs: handoff` (or include the note in the session's last commit). Push it.
6. **Reply with exactly one line:**
   - `Handoff written: <commit>. Safe to /clear.`
   - If anything could not be saved, list it instead and end with `NOT safe to /clear yet.`
