---
type: meta
title: Feanor Tooling & Automation Index
description: Index of utility scripts for maintaining the Feanor knowledge base — catalog reindexing, frontmatter validation, testing, and formatting; read this before writing or running any feanor/scripts/ tooling.
applies_to: [scripts, all]
tags: [scripts, tooling, index]
---

# Feanor Tooling & Maintenance Catalog

This directory houses automated Python and Shell utilities that maintain vault hygiene, enforce OKF v0.2 metadata rules, update directory indices, and verify test passes during ticket execution.

---

## 🛠 Maintenance & Validation Tooling

- [reindex.py](./reindex.py) - Scans `feanor/` subdirectories and auto-generates clean `index.md` catalogs.
- [validate-okf.py](./validate-okf.py) - Validates YAML frontmatter metadata schema across all Markdown files.
- [run-tests.sh](./run-tests.sh) - Standard test execution harness called by `agents/execution-agent.md`.
- [format-code.sh](./format-code.sh) - Automatic code formatting pre-check script.
- [pre-commit-branch-guard](./pre-commit-branch-guard) - Git hook installed into a target project by `lattice add feanor` (declared in `../lattice-hooks.json`); blocks direct commits to `main`/`qa` per `git/branch-strategy.md`.
- [pre-commit-feanor-guard](./pre-commit-feanor-guard) - Hook for **this** repository only, not target projects: runs `check-all.sh` and keeps `feanor/` off lattice's own `main`.
- [scaffold/](./scaffold/index.md) - Real, dry-run-verified scaffold scripts called by `/scaffold` (`architect-agent.md`) instead of re-deriving mechanical setup steps from prose each run.
- [github-repo-setup.sh](./github-repo-setup.sh) - Creates the GitHub repo, configures branch protection + merge-method restriction, writes the `feanor-guard` CI backstop. Run once, right after the project's first local commit — see `git/github-repo-setup.md`. Syntax-checked only; no live GitHub run performed (no `gh` CLI on the machine that wrote it) — verify on first real use.
- [write-precommit-config.sh](./write-precommit-config.sh) - Writes `.pre-commit-config.yaml` for the stacks in use, per `git/pre-commit-hooks.md`. Real script, not the agent retyping fixed YAML from prose each run.
- [write-dependabot-config.sh](./write-dependabot-config.sh) - Writes `.github/dependabot.yml` for the stacks in use, per `git/dependabot.md`. Must run after scaffolding — detects single- vs. multi-service by checking whether `services/` exists on disk.
- [scaffold/write-dev-scripts.sh](./scaffold/write-dev-scripts.sh) - Generates `scripts/start.sh` and `scripts/stop.sh` at the project root. Detects services on disk (backend/, services/<role>/, frontend/), assigns ports (Python 8000+, Go 8100+, frontend 3000), and writes a one-command start/stop covering all of them. Must run after scaffold scripts.
- [plan.py](./plan.py) - PEP 723 inline script (no install needed — `uv run feanor/scripts/plan.py`). Manages `docs/plan.toml`: view ticket status, get next actionable ticket, mark in-progress/blocked, **`verify`** (runs the ticket's `verification_command` without a shell and records its real exit code), and **`done`** (refused unless a passing verify is on record). `verify` is the engine's quality gate — the exit code must be the command's own, not a pipeline's.
- [check-all.sh](./check-all.sh) - **One entry point for every self-consistency gate** — frontmatter, tag map, and registration. `--project` additionally runs the mechanical convention audit. Wired into `pre-commit-feanor-guard` (this repo's own hook), because a gate nothing invokes is only a suggestion.
- [audit-mechanical.py](./audit-mechanical.py) - Mechanical convention checks against a target project: lockfiles, `.env` hygiene and env-var completeness, base-image and CI-action pinning, pre-commit config, migrations, plus forbidden tokens (`shell=True`, `yaml.load`, `pickle`, `python-jose`, `math/rand`, `dangerouslySetInnerHTML`, hardcoded secrets). Run by `/audit` before its judgment work. Each finding cites the convention it enforces.
- [resolve-context.py](./resolve-context.py) - Resolves a ticket's tags and target files into the exact convention files to load, applying `conventions/tags.toml`, the priority ladder, the always-load floor, the capability profile, and the payload cap. Called by `agents/execution-agent.md`. `--explain` shows why each file was chosen; `--validate` checks the tag map.
- [check-git.py](./check-git.py) - Branch and commit discipline gate. `branch` refuses work on `main`/`qa` or a misnamed branch; `commit` additionally refuses an empty stage and a non-Conventional-Commits subject, and warns when the staged set is large enough to suggest several tickets were batched. Called by `agents/execution-agent.md` steps 0 and 7. Checks only what is mechanical — whether a change is *one logical change* stays judgment, in `git/commit-format.md`.
- [check-push.py](./check-push.py) - Runs the project's own lint/typecheck/test commands locally before a push, derived from the stacks present on disk (override via `.feanor/state/local-ci.json`). Each runs shell-free with its real exit code recorded to `.feanor/logs/validation.log`. Called by `agents/execution-agent.md` step 8 — CI is the backstop, not where a lint failure should first be discovered.
- [check-toolchain.py](./check-toolchain.py) - Toolchain preflight. Verifies each named tool is installed and within the range declared in `../conventions/versions.toml`, printing what to install and where when it is not. Called first by every scaffold script so a missing or wrong-version tool fails before anything is written. `--pin`/`--verify-range`/`--satisfies` are lookup modes so the shell scripts never parse TOML themselves.
- [check-preconditions.py](./check-preconditions.py) - Phase gate. `check-preconditions.py /plan` exits 0 when the phase may run, 1 naming the missing artifact and the command that produces it. Replaces the bash comment block that used to live in `meta/command-router.md` §2.
- [check-registration.py](./check-registration.py) - Cross-checks Feanor's own internal references: manifest ↔ router ↔ `agents/`, catalog completeness, template reachability, and every relative markdown link. Catches the drift class where a file is referenced but does not exist, or exists but is referenced nowhere.
- [append-audit-report.sh](./append-audit-report.sh) - Appends a timestamped section to `.feanor/audit_report.md`, never overwriting prior sections, so repeated `/audit` runs accumulate a history. Called by `agents/validation-agent.md`.
- [write-state-marker.py](./write-state-marker.py) - Writes a phase marker plus a UTC timestamp to `.feanor/state/status.json`. `scaffolded` records that `/scaffold` built this source tree; `standardized` records a clean `/standardize` pass. `check-preconditions.py` reads both — together they tell a greenfield tree Feanor created from brownfield source that predates it, which the presence of `backend/` alone cannot.
- [_gate.py](./_gate.py) - Shared helper, not run directly. Gives every check script the same block-with-override behaviour: `--override "<reason>"` proceeds and records the reason in `.feanor/logs/overrides.log`.
- [write-profile.py](./write-profile.py) - Writes and reads `.feanor/profile.toml`, the project's capability profile. Called by `agents/architect-agent.md` during `/hld`; read by the Context Resolver, Planner, and Validation Agent. `--show` prints the resolved profile, `--check <capability>` exits 0 when enabled. Refuses to enable a capability that has no convention file yet. See `docs/CAPABILITIES.md`.
