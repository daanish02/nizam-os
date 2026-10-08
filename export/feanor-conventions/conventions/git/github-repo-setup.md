---
type: convention
title: GitHub Repo Setup
description: One-time GitHub-side setup steps — repo creation timing, branch protection rules, merge-method restriction, and required CI status checks.
applies_to: [git]
tags: [git, github, branch-protection, ci]
---

# GitHub Repo Setup

Everything else in `conventions/git/` describes _local_ files (`.pre-commit-config.yaml`, `dependabot.yml`). This file is different: it's the _GitHub-side_ settings none of those files can express — branch protection, merge-method restriction, required status checks. Not automatic; run once, deliberately.

## When

Right after the project's **first local commit**, not before and not much later:

1. `/scaffold` produces real files.
2. The first commit is made (per `commit-format.md`).
3. **This step runs** — `scripts/github-repo-setup.sh <repo-name>`.
4. Normal development proceeds (`feature/*` branches, PRs into `qa`).

Not before step 2: `gh repo create --source=.` needs a commit to push. Not much later: every commit made before branch protection is configured is a commit that could have gone straight to `main` unprotected — the gap between "repo exists" and "protection configured" should be minutes, not days.

## What Gets Configured

Run via `scripts/github-repo-setup.sh <repo-name> [--public]` (private by default) — see that script for the exact commands; this section is _why_ each setting is what it is.

### Repo-level merge method

Only merge commits allowed — squash and rebase-merge both disabled at the GitHub repo settings level, not just documented as a convention. This matches `branch-strategy.md`'s rule directly: commits are already curated into logical units per `commit-format.md`, and squash-merging would discard that structure. Disabling it at the platform level means the button to do the wrong thing doesn't exist, rather than relying on everyone remembering not to click it.

### Branch protection — `main`

- Pull request required — no direct pushes, including from admins (`enforce_admins: true`).
- The `feanor-guard` CI check (see below) required to pass before merge.
- 1 approving review required.
- Force pushes and branch deletion disabled.
- Conversation resolution required before merge.

This is the server-side enforcement layer for everything `branch-strategy.md` already says about `main` — the difference is a human clicking around GitHub settings can't accidentally skip it once it's set once, the way a local git hook can be bypassed with `--no-verify`.

### Branch protection — `qa`

Lighter: PR required, no force-push/delete, but no required review count or status check enforced — matches `branch-test-tiers.md`'s lighter bar for `qa` versus `main`.

### Why branch protection is the layer that counts

`lattice add feanor` installs a local `pre-commit` hook that blocks direct commits to `main` and `qa`. It is useful — it catches the mistake at the moment it is made, with the fix in the message — but it is local, and `git commit --no-verify` skips it entirely.

Branch protection is the same rule enforced server-side, where `--no-verify` has no effect and no local configuration can weaken it. Configure it as described above and treat the hook as an early-warning convenience, never as the enforcement.

Feanor itself needs no CI guard: it installs to a gitignored `skills/`, so it is never tracked and cannot reach `main` in the first place.

## Secrets

Any CI/deploy secret the project needs (deploy keys, API tokens for CI-run tests) goes in the repo's Actions secrets (`Settings → Secrets and variables → Actions`), never committed — same placeholder discipline as everywhere else in Feanor (`{{EXAMPLE_SECRET}}` in any doc/example). `github-repo-setup.sh` prints the direct link at the end of its run as a reminder, doesn't set any secrets itself — what a project needs there is project-specific, not something to guess.
