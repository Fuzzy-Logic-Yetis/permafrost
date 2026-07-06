# Release Process

## Versioning

SemVer, tags `vMAJOR.MINOR.PATCH`. Version lives in `scripts/make-app.sh`
(`CFBundleShortVersionString`) — bump it in the release commit.

## v0.x releases (current: build-from-source, ad-hoc)

1. Ensure `main` is green (CI) and the docs/TESTING.md manual checklist passes.
2. Update version in `scripts/make-app.sh`; note highlights in the GitHub release draft.
3. Update docs/PROJECT_PLAN.md milestone status if applicable.
4. `git tag -a vX.Y.Z -m "vX.Y.Z"` and `git push --tags`.
5. Create the GitHub release from the tag. **No binary artifacts are attached to v0.x
   releases** — an unsigned/ad-hoc binary from the internet trains users to bypass
   Gatekeeper. Install instructions are build-from-source (README).

## v1.0+ releases (requires Apple Developer Program — deferred, ROADMAP.md)

Additions to the process, in order:

1. Developer ID Application certificate; sign with hardened runtime
   (`codesign --options runtime`).
2. Notarize (`xcrun notarytool submit … --wait`) and staple (`xcrun stapler staple`).
3. Package as `.dmg`; attach to the GitHub release.
4. Update the Homebrew cask.
5. Sparkle appcast update (once auto-update ships).

## Checklist template

```text
- [ ] CI green on main
- [ ] Manual smoke checklist passed (docs/TESTING.md)
- [ ] Version bumped
- [ ] Docs current (README, PROJECT_PLAN status)
- [ ] Tag pushed, release notes written
```
