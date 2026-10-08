---
type: catalog
title: Feanor Skill Module Index
description: Entry point catalog for Feanor — start here to find slash commands, agents, conventions, templates, and workflows.
applies_to: [all]
tags: [feanor, index]
---

# Feanor Knowledge & Skill Registry

Feanor is a phased state engine and context-engineering system designed for autonomous software development. It prevents context degradation by separating execution phases (`/prd` → `/hld` → `/specs` → `/plan` → `/exec` → `/audit`) and injecting micro-standards JIT (Just-In-Time).

**New here?** Start with [SKILL.md](./SKILL.md) — what to run first and in what order. Install and git-hook details: [README.md](./README.md).

---

## Two Layers: Entry Points vs. Internal Machinery

**Entry Points** — the commands typed directly, nothing else is invoked by hand:

`/brainstorm` · `/prd` · `/hld` · `/scaffold` · `/specs` · `/plan` · `/exec` · `/audit` · `/document` · `/standardize`

Full routing/precondition detail: [meta/command-router.md](./meta/command-router.md).

**Internal Machinery** — reached automatically by the entry points above, never invoked directly:

- `agents/` — the actual system prompts each command runs.
- `conventions/` — atomic micro-standards, pulled in JIT by `meta/context-resolver.md` during `/exec`/`/standardize`, not read wholesale.
- `templates/` — output blueprints, read by the engine producing that artifact.
- `meta/context-resolver.md`, `meta/requirements-checklist.md` — methods other agents follow, not things you run yourself.

---

## For the Maintainer (not loaded by agents)

- [docs/](./docs/index.md) — What Feanor is and why ([OVERVIEW](./docs/OVERVIEW.md)), the capability tiers ([CAPABILITIES](./docs/CAPABILITIES.md)), security posture, audit history, and design rationale. Descriptive documentation about Feanor itself; the Context Resolver never retrieves it.

---

## Core System Architecture

- [meta/](./meta/index.md) - Command routing (`command-router.md`), state machine preconditions, and JIT lookup logic (`context-resolver.md`).
- [workflows/](./workflows/index.md) - High-level lifecycle pipelines (`greenfield-pipeline.md`, `brownfield-standardize.md`, `maintain-repo.md`).
- [agents/](./agents/index.md) - Phase engine system prompts: `requirements-agent`, `product-agent`, `architect-agent`, `planner-agent`, `execution-agent`, `validation-agent`.

---

## Atomic Micro-Standards (`conventions/`)

- [Python Engineering](./conventions/python/index.md) - `uv`, dependency management, layout, async/concurrency, auth, rate limiting, testing. Backend only.
- [Go Engineering](./conventions/go/index.md) - Modules, layout, concurrency/context, error handling, database, auth, rate limiting, testing. Backend only.
- [Next.js Engineering](./conventions/nextjs/index.md) - Bun, App Router, components/data, styling, auth, testing. Frontend only.
- [Git & Source Control](./conventions/git/index.md) - Branch strategy, commit format, pre-commit hooks, test tiers, Dependabot.
- [Ops](./conventions/ops/index.md) - Dockerfile + `.dockerignore` per stack (Python/Go backend, Next.js frontend).

New domains (e.g. data-layer-specific patterns beyond what `python/database.md`/`go/database.md` cover, ops/infra) get added here only when actually written — see `workflows/maintain-repo.md` §3 for the process. Don't link a subdirectory here before it exists.

---

## Blueprints & Tooling

- [templates/](./templates/index.md) - Structural blueprints for `PRD.md`, `docs/` high-level docs (`ARCHITECTURE.md` + as-needed), and API contracts in `docs/specs/`.
- [scripts/](./scripts/index.md) - Local utilities (`reindex.py`, `validate-okf.py`, test runners).
