---
name: feanor
type: skill
title: Feanor — Autonomous Software Development Engine
description: >
  Phased AI agent workflow for greenfield and brownfield software projects.
  Covers requirements, PRD, architecture, planning, execution, and audit.
applies_to: [all]
tags:
  - software-development
  - autonomous-agents
  - workflow
  - conventions
---

# Feanor

A phased state engine for building software. It splits the work into ordered phases, each with a hard precondition, and injects only the coding standards a given ticket needs rather than the whole library.

## Start here

Pick the entry point that matches the project, then let the gate confirm it:

| Situation | Command |
| :--- | :--- |
| New project, nothing built yet | `/reqs` |
| Existing code, no `docs/` | `/document` |
| Existing code, `docs/` present but not built to these conventions | `/standardize` |
| Rough idea, not ready to write requirements | `/brainstorm` |

Confirm before running it (`--list` shows every known command):

```bash
uv run skills/feanor/scripts/check-preconditions.py /reqs
```

## The pipeline

```text
/reqs → /prd → /hld → /scaffold → /specs → /plan → /exec → /audit
```

Each phase writes an artifact the next one reads. Every phase is gated: before running one, run

```bash
uv run skills/feanor/scripts/check-preconditions.py /<command>
```

It exits 0 when the phase may run, or 1 naming the missing artifact and the command that produces it. **Run the gate rather than inferring readiness** — a phase run out of order produces work that looks fine and is built on nothing.

## What it does to a project

- Writes requirements, architecture, specs and ADRs into `docs/`.
- Scaffolds `backend/` / `frontend/` / `services/*` to fixed layouts, with pinned toolchain versions.
- Turns specs into a ticket plan, then executes tickets one at a time, each with a test that must pass before it can be marked done.
- Installs a git hook blocking direct commits to `main`/`qa`.

Feanor itself lives in a gitignored `skills/` and is never committed to the project.

## Rules that matter before you start

- **Verification is a gate, not a report.** `plan.py done` refuses a ticket without a passing `plan.py verify` on record. Never hand-edit ticket status.
- **Run the scripts; do not reproduce them.** Anything mechanical is a real script under `scripts/`. Retyping its steps is how two runs diverge — see [meta/determinism-standard.md](./meta/determinism-standard.md).
- **Judgment stays with you.** Spec content, ticket scoping, and audit severity are deliberately not scripted.

## Where to look next

- [index.md](./index.md) — full catalog: commands, agents, conventions, templates.
- [meta/command-router.md](./meta/command-router.md) — every command, its preconditions, and what it produces.
- [README.md](./README.md) — install, update, and how the git hooks work.
- [docs/OVERVIEW.md](./docs/OVERVIEW.md) — what Feanor is and why it is built this way.
