#!/bin/bash
# Fails on the documentation drift this project has actually experienced, rather than on
# style. Run by CI on every push and before tagging (docs/RELEASE_PROCESS.md).
#
# Each check exists because the corresponding drift really happened:
#   1. Version strings desynced silently, twice (CLAUDE.md Definition of Done, item 7).
#   2. Docs referenced files that had been deleted (2026-09-07 docs prune).
#   3. A shipped feature never reached ROADMAP.md, so the documented entry path for a new
#      session (CLAUDE.md -> PROJECT_PLAN.md -> ROADMAP.md) reported stale state (ADR-022).
#   4. ADR cross-references are load-bearing here and a typo'd number is invisible.
set -uo pipefail
cd "$(dirname "$0")/.."

problems=$(mktemp)
trap 'rm -f "$problems"' EXIT

note() { echo "  - $*" >>"$problems"; }

# ── 1. Version strings agree ────────────────────────────────────────────────────
app_version=$(grep -oE 'static let string = "[0-9]+\.[0-9]+\.[0-9]+"' Sources/Permafrost/App.swift |
    grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
script_version=$(grep -oE '^VERSION="[0-9]+\.[0-9]+\.[0-9]+"' scripts/make-app.sh |
    grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
readme_version=$(grep -oE '^\*\*v[0-9]+\.[0-9]+\.[0-9]+\*\*' README.md |
    grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

if [ -z "$app_version" ] || [ -z "$script_version" ] || [ -z "$readme_version" ]; then
    note "could not read a version string (App.swift='$app_version' make-app.sh='$script_version' README='$readme_version')"
elif [ "$app_version" != "$script_version" ] || [ "$app_version" != "$readme_version" ]; then
    note "version strings disagree: App.swift=$app_version make-app.sh=$script_version README=$readme_version"
fi

# ── 2. The released version has a ROADMAP section ───────────────────────────────
# Ties "what we say we shipped" to "what the roadmap records", the ADR-022 failure.
if [ -n "$readme_version" ] && ! grep -qE "^## v${readme_version}([^0-9]|$)" docs/ROADMAP.md; then
    note "README claims v${readme_version} but docs/ROADMAP.md has no '## v${readme_version}' section"
fi

# ── 3. Every referenced doc exists ──────────────────────────────────────────────
while IFS= read -r file; do
    dir=$(dirname "$file")

    # Markdown links: [text](path.md) and [text](path.md#anchor)
    while IFS= read -r link; do
        [ -z "$link" ] && continue
        case "$link" in http*|mailto:*|\#*) continue ;; esac
        target="${link%%#*}"
        [ -z "$target" ] && continue
        [ -f "$dir/$target" ] || note "$file links to missing '$target'"
    done < <(grep -oE '\]\([^)]+\.md[^)]*\)' "$file" | sed -E 's/^\]\(//; s/\)$//')

    # Bare mentions like "see docs/BACKLOG.md", which markdown-link checks miss.
    # YYYY-MM-DD paths in CODE_REVIEW.md are naming templates, not real files.
    while IFS= read -r target; do
        [ -z "$target" ] && continue
        case "$target" in *YYYY*|*MM-DD*) continue ;; esac
        [ -f "$target" ] || note "$file mentions missing '$target'"
    done < <(grep -oE '(^|[^/[:alnum:]])docs/[A-Za-z0-9_.-]+\.md' "$file" |
        grep -oE 'docs/[A-Za-z0-9_.-]+\.md' | sort -u)
done < <(find . -name "*.md" -not -path "./.build/*")

# ── 4. Every referenced ADR exists ──────────────────────────────────────────────
while IFS= read -r adr; do
    grep -qE "^## ${adr}:" docs/DECISIONS.md || note "referenced $adr has no section in docs/DECISIONS.md"
done < <(grep -rhoE 'ADR-[0-9]{3}' --include="*.md" --include="*.swift" --include="*.sh" \
    . 2>/dev/null | grep -v '^\./\.build' | sort -u)

# ── Report ──────────────────────────────────────────────────────────────────────
if [ -s "$problems" ]; then
    echo "Documentation drift detected:"
    sort -u "$problems"
    echo
    echo "See CLAUDE.md 'Documentation standards' and the Definition of Done."
    exit 1
fi

echo "Docs consistent: v${app_version}, links and ADR references resolve."
