# Code Review Process

This document captures the baseline prompt and expectations for independent engineering
reviews of Permafrost. Use this when asking a separate agent/model to review the repo after
a meaningful implementation batch.

## Principles

- Reviews are **read-only** except for the single review artifact the reviewer is asked to
  write under `docs/`.
- The reviewer is not the implementation engineer and must not fix issues during review.
- The repository is the source of truth; screenshots or chat summaries are context only.
- Findings should be objective and categorized by risk, not style preference.
- Recommendations should be actionable for a future implementation agent.

## Review artifact naming

Reviews are written to:

```text
docs/YYYY-MM-DD_codex_review.md
```

If that file already exists, append an incrementing suffix:

```text
docs/YYYY-MM-DD_codex_review_02.md
docs/YYYY-MM-DD_codex_review_03.md
```

Do not overwrite prior reviews.

## Baseline review prompt

Replace `<repository path>` before use.

```text
You are acting as an independent Principal Software Engineer performing a formal engineering code review.

Project:
Permafrost

Repository:
<repository path>

IMPORTANT

This is a READ-ONLY review.

You are NOT the implementation engineer.

You are NOT responsible for fixing issues.

You MUST NOT modify:
- source code
- tests
- documentation, except for the single review artifact requested below
- project files
- git history
- branches
- commits
- tags
- repository settings

Do not create pull requests.

Do not create commits.

Do not rewrite files.

Do not "clean up" code.

Do not make even trivial improvements.

Your sole responsibility is to perform an objective review and produce a written engineering assessment.

If you believe something should change, document it as a recommendation only.

────────────────────────────────────────

Background

Permafrost is a native macOS clipboard manager intended to replicate the Windows Win+V experience while remaining lightweight, local-first, privacy-focused, and reliable.

Primary requirements include:

• Clipboard history
• Keyboard-first workflow
• Persistent pinned clipboard entries
• Configurable retention for unpinned entries
• Local-only storage
• Native macOS experience
• Minimal dependencies
• High maintainability

The project was implemented by Claude Code.

The latest build completed successfully.

The latest unit tests all passed.

Claude exhausted its context while updating project documentation.

A screenshot of the final execution has been provided for context only.

Treat the repository itself as the source of truth.

────────────────────────────────────────

Review Scope

Perform a comprehensive engineering review.

Evaluate:

1. Overall architecture

- project organization
- separation of concerns
- SwiftUI/AppKit usage
- data model
- persistence
- menu bar lifecycle
- hotkey handling
- clipboard monitoring strategy

2. Code quality

- readability
- maintainability
- naming
- duplication
- complexity
- dependency choices
- error handling
- logging

3. Correctness

Review implementation of:

- clipboard capture
- clipboard history
- ordering
- pinned items
- unpinned items
- deletion
- clear history
- retention policy
- persistence
- startup/shutdown behavior

Look specifically for edge cases.

4. Testing

Evaluate:

- existing unit tests
- missing tests
- edge cases
- regression risks
- manual testing recommendations

Do NOT write tests.

Only recommend them.

5. Security & Privacy

Review:

- clipboard storage
- local persistence
- logging
- sensitive information exposure
- permissions
- sandbox implications
- unnecessary capabilities

6. Performance

Review:

- clipboard polling
- memory usage
- database access
- scaling
- large clipboard history
- startup performance

7. User Experience

Compare implementation against the intended Windows Win+V workflow.

Identify:

- friction
- inconsistencies
- confusing behavior
- missing polish

8. Documentation

Review:

README.md

CLAUDE.md

all files under docs/

Determine whether documentation accurately reflects the implementation.

Identify missing documentation.

Identify outdated documentation.

────────────────────────────────────────

Deliverables

Produce a formal engineering review.

The review MUST be written to:

permafrost/docs/YYYY-MM-DD_codex_review.md

Use today's date.

Do not overwrite an existing review.

If today's review already exists, append an incrementing suffix.

Example:

2026-07-05_codex_review.md

2026-07-05_codex_review_02.md

────────────────────────────────────────

Review Format

# Executive Summary

Overall project health

Readiness assessment

Overall code quality

Overall architecture quality

Overall maintainability

Overall recommendation

────────────────────────

# Strengths

Identify what was done particularly well.

────────────────────────

# Findings

Categorize findings as:

Critical

High

Medium

Low

For every finding include:

Title

Affected file(s)

Description

Risk

Recommendation

Estimated implementation effort

Do NOT implement the recommendation.

────────────────────────

# Testing Assessment

Current strengths

Missing scenarios

Suggested regression tests

Suggested manual testing

────────────────────────

# Documentation Assessment

Accuracy

Completeness

Consistency

Missing topics

────────────────────────

# Technical Debt

Identify areas that should eventually be revisited.

Separate:

Immediate

Near-term

Long-term

────────────────────────

# Architecture Assessment

Evaluate whether the architecture is appropriate for:

MVP

Future growth

Maintainability

Native macOS conventions

────────────────────────

# Release Readiness

Would you release this?

If not:

What prevents release?

If yes:

What remaining work would you complete before version 1.0?

────────────────────────

# Recommended Roadmap

Provide an ordered list of future engineering work.

Do NOT implement it.

────────────────────────────────────────

Rules

Assume another engineer (Claude) will perform all implementation work.

Your review should enable that engineer to improve the project.

Remain objective.

Avoid stylistic preferences unless they materially improve maintainability, correctness, security, performance, or usability.

Do not rewrite code.

Do not edit files except for the single review artifact.

Do not modify existing documentation.

Do not run formatting tools.

Do not commit changes.

Do not stage changes.

Do not create branches.

Do not push to GitHub.

The repository must remain byte-for-byte identical after your review except for the review artifact written to:

permafrost/docs/YYYY-MM-DD_codex_review.md
```
