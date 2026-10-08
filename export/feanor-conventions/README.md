# Feanor

A phased, autonomous software-development state engine for agentic coding tools. It separates execution phases (`/prd` → `/hld` → `/scaffold` → `/specs` → `/plan` → `/exec` → `/audit`, plus brownfield's `/document`/`/standardize`) and injects micro-standards Just-In-Time, instead of dumping an entire conventions library into every context window.

Full catalog: [index.md](./index.md). Entry-point commands vs. internal machinery is explained there.

---

## This lives per-project, not globally — and never ships to production

Feanor is **not** a global tool an agent reaches for from `~/.config/feanor` in every repo. It is installed _into_ a specific project, at `skills/feanor/`, by the `lattice` CLI.

`skills/` is **gitignored**, so Feanor is never committed to the project at all — it cannot reach `main`, `qa`, or any branch, because it is not tracked content. That is the whole mechanism: nothing to strip before a release, and nothing to enforce.

`main` is production. Feanor is a development-time tool — the interrogation methods, phase agents, and micro-standards that got the code built and standardized. None of that belongs shipping with the actual product.

`.feanor/` (plan, audit reports, state) is the project's own record of what Feanor did, and is meant to be **tracked** so the plan and its audit trail survive for whoever picks the project up later. Only `.feanor/scratchpad/` is gitignored. If a project gitignores all of `.feanor/`, that record is lost — a defensible choice, but make it deliberately.

## Install

Feanor is distributed as a Lattice skill:

```bash
lattice add feanor
```

This extracts `skills/feanor/`, appends `skills/` to `.gitignore`, and installs the git hooks the skill declares in `lattice-hooks.json` — currently `pre-commit`, which blocks a direct commit to `main` or `qa` per [conventions/git/branch-strategy.md](./conventions/git/branch-strategy.md).

Hook installation is reported, never assumed. If the project is not a git repo, or already has a different `pre-commit` hook (Husky, `pre-commit`, lefthook), the CLI says so and leaves the existing hook untouched — wire `skills/feanor/scripts/pre-commit-branch-guard` into your hook manager by hand. Enforcement that is claimed but silently absent is worse than none, because someone relies on it.

Server-side branch protection (see [conventions/git/github-repo-setup.md](./conventions/git/github-repo-setup.md)) is the backstop the local hook cannot provide — `git commit --no-verify` skips any local hook.

## Updating

```bash
lattice update feanor
```

Change detection is by git tree hash, so an update is a no-op when nothing changed. Declared hooks are reinstalled on update too — a hook whose source changed must not keep silently running the old version.

**Maintainers:** after pushing a change to `feanor/` on lattice's `main`, run `../scripts/sync-skill-dist.sh feanor` from lattice's root to refresh the `feanor-dist` branch. Without it, `lattice update` finds nothing new.
