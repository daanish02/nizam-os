---
type: convention
title: Branch Strategy
description: Git branching rules covering the main/qa/feature hierarchy, naming prefixes, merge direction, hotfix flow, and release promotion for Feanor-managed projects.
applies_to: [git]
tags: [git, branching]
---

# Branch Strategy

## Hierarchy

Two promotion tiers, one direction:

```text
feature/*  ──┐
fix/*        ├──> qa ──> main
hotfix/*   ──┘        (hotfix/* may also merge directly into main, see below)
```

- `main` — production. Highest test/security bar (see [branch-test-tiers.md](./branch-test-tiers.md)).
- `qa` — integration/staging. All feature and fix branches merge here first.
- Feature/fix branches are short-lived, cut from `qa` (or `main` for hotfixes), deleted after merge.

## Naming Prefixes

| Prefix      | Purpose                    | Cut from | Merges into   |
| :---------- | :------------------------- | :------- | :------------ |
| `feature/*` | New functionality          | `qa`     | `qa`          |
| `fix/*`     | Non-urgent bug fix         | `qa`     | `qa`          |
| `hotfix/*`  | Urgent production patch    | `main`   | `main` + `qa` |
| `release/*` | Release stabilization/prep | `qa`     | `main`        |

- Branch name after prefix: short kebab-case description of the change, e.g. `feature/saved-dashboards`, `fix/chart-tooltip-overflow`.
- A `hotfix/*` branch **MUST** be merged into both `main` (to ship the fix) and `qa` (to keep qa in sync) — never one without the other.

## Merge Strategy

- **Rebase, don't squash.** While working, rebase your branch onto its target (`qa` or `main`) frequently to keep history linear and surface conflicts early.
- Merge into `qa` with `--no-ff` (or fast-forward if trivial) — never squash-merge. Commits are already curated into logical units per [commit-format.md](./commit-format.md); squashing would discard that structure.
- **Merges into `main` are always `--no-ff`, never fast-forward, no exceptions.** A fast-forward merge doesn't run git hooks — and the Feanor branch guard (see below) is a hook. A fast-forward into `main` would silently skip the check meant to keep `feanor/`/`.feanor/` out of it.

## Feanor Scoping

Feanor installs to `skills/feanor/` and `skills/` is gitignored (see `feanor/README.md`), so the tool itself is never tracked and cannot reach any branch. There is nothing to strip before a release.

`.feanor/` — the plan, audit reports, and phase state — is meant to be tracked on every branch including `main`, with only `.feanor/scratchpad/` ignored. It is the project's own record of how the code came to be, and it is worth as much to whoever inherits the project as the code is: data about the project, not the tool. Gitignoring all of `.feanor/` discards that record, so do it deliberately if at all.

## Enforcing This Hierarchy

The rules above are enforced in two layers, not left to discipline:

1. **Local hook** — `lattice add feanor` installs `pre-commit`, which blocks a direct commit to `main` or `qa` and names the branch command to run instead. Catches the mistake before anything is pushed — but `git commit --no-verify` skips it, and so does any workflow that never commits locally.
2. **Server-side branch protection** — configured by `github-repo-setup.md` / `scripts/github-repo-setup.sh`, requiring a PR into `main` and `qa`. This is the layer that cannot be bypassed, and it is the one that matters.

Both exist because they fail differently: the hook is immediate but skippable, protection is unskippable but only at push time. Neither alone is sufficient.

During `/exec`, `uv run feanor/scripts/check-git.py branch` performs the same check before a ticket runs, so the problem surfaces before any work is done on the wrong branch rather than at commit time.

## Rules

- Never commit directly to `main` or `qa`. All changes land via a branch + merge (PR or reviewed fast-forward) — enforced server-side by GitHub branch protection, not just convention, see `github-repo-setup.md`.
- `qa` is the only branch feature/fix branches target. Nothing merges into `main` except `qa` or `hotfix/*`/`release/*`.
- Delete branches after merge — keeps the branch list meaning "active work," avoids stale-branch buildup.
