---
type: convention
title: Commit Format
description: Conventional Commits format rules covering type/scope/subject syntax, body discipline, and commit grouping to keep history navigable.
applies_to: [git]
tags: [git, commits]
---

# Commit Format

## Format

Conventional Commits: `type(scope): imperative subject`

- **Subject line**: imperative mood, lowercase, no trailing period, states _what happened_ in one line.
  - Good: `fix(query): reject unbounded SELECT without LIMIT`
  - Bad: `fixed a bug`, `Updated query.py.`
- **Scope**: the affected package/domain (e.g. `query`, `visualize`, `db`, `api`). Omit only for cross-cutting changes.
- **Types**: `feat`, `fix`, `perf`, `docs`, `chore`, `refactor`, `test`. Pick the one that matches the actual intent — a perf-motivated change is `perf`, not `fix`.
- **Body** (optional): only when the subject line isn't enough to explain _why_. Specifics, trade-offs, or context that would help a future reader — not a restatement of the diff. If the subject line already says everything necessary, skip the body.

## Size & Grouping

- **No large commits.** A commit should represent one logical change, reviewable on its own.
- If a change naturally splits into independent logical pieces (e.g. a refactor + the feature it enables), split it into multiple commits rather than one big one.
- Conversely, don't fragment one logical change into many tiny commits — group by _logic_, not by file or by save-point. If a commit doesn't stand on its own as a coherent change, it should be squashed into the one it belongs with.
- Before pushing a branch with a messy history (WIP commits, fixups), clean it up (squash/reorder) so the final commit sequence on the branch tells a clear, logical story.
