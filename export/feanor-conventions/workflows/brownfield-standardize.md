---
type: workflow
title: Brownfield Standardization & Refactoring Pipeline
description: Three independently-invocable entry points (/standardize, /document, /update) for bringing an existing codebase up to Feanor conventions without a full greenfield rewrite.
applies_to: [brownfield, standardize]
tags: [workflow, brownfield, refactoring, audit]
---

# Brownfield Standardization & Refactoring Pipeline

Three independent, directly-invocable entry points for a pre-existing codebase — none requires another to have run first, but the recommended order for a fresh brownfield project is **standardize → document → update**:

```text
/standardize ──> project is structurally compliant (marker set)
/document    ──> docs/PRD.md, docs/ARCHITECTURE.md, docs/specs/ exist and reflect reality
/specs+/plan+/exec+/audit (the greenfield low-level phases, reused) ──> update/extend a feature
```

`/standardize` and `/document` solve different problems (code structure/conventions vs. missing/wrong documentation) and can be run in either order, repeatedly, independently. "Update/extend" isn't a separate engine — once a project has a `standardized: true` marker (from `/standardize`) it's in the same shape as a greenfield project past `/hld`, so the existing `/specs` → `/plan` → `/exec` → `/audit` phases from `workflows/greenfield-pipeline.md` handle it directly.

---

## `/standardize`

- **Trigger:** User command `/standardize` run against an existing codebase.
- **Precondition:** None.
- **agents:** `agents/validation-agent.md` (compliance audit) → `agents/planner-agent.md` (fix-up tickets) → `agents/execution-agent.md` (apply fixes).
- **Process:**

1. Scan repository structure, naming, and conventions against `conventions/`.
2. Produce a compliance report (reuses `agents/validation-agent.md`'s audit procedure) — violations, missing lockfiles, naming drift, layout drift, etc.
3. Convert violations into atomic refactoring tickets (`agents/planner-agent.md`, ticket type `refactor`).
4. Execute tickets with regression tests to ensure zero breaking changes (`agents/execution-agent.md`).
5. On a clean audit (no violations, or all fix-up tickets completed and verified) — run the real script, verified working, rather than retyping the logic:

```bash
uv run scripts/write-state-marker.py standardized .feanor/state/status.json
```

- **Outputs:**
- `.feanor/audit_report.md` (compliance findings)
- `docs/plan.toml` (fix-up tickets)
- Restructured/fixed source code
- `.feanor/state/status.json` — `standardized: true` marker on clean pass

If source changes after the marker is written, treat it as stale — `/standardize` should be re-run before trusting it again.

---

## `/document`

- **Trigger:** User command `/document` run against an existing codebase.
- **Precondition:** None. Independent of `/standardize` — can run before, after, or without it.
- **agents:** `agents/requirements-agent.md` (SRS) + `agents/product-agent.md` (PRD) + `agents/architect-agent.md` (architecture/specs), following `meta/requirements-checklist.md` §0's brownfield rows. Matches `meta/command-router.md` §1's `/document` row.
- **Process:**

1. Scan repository file tree, dependency manifests (`pyproject.toml`, `package.json`), and entry points.
2. **If no `docs/PRD.md` exists:** derive the "what" from code (routes, models, integrations, entry points), record as **Derived** (not Covered), then interrogate the person only for what code can't reveal — intent, priority, by-design vs. accidental.
3. **If `docs/PRD.md` already exists:** verify its claims against current code (§0a) — a doc surviving from a prior `/document` run, or handed to you separately, is a claim, not a fact, once code exists that could confirm or contradict it.
4. Reverse-engineer system architecture, implicit API routes, schema models, and data flows into `docs/ARCHITECTURE.md` and `docs/specs/`.

- **Outputs:**
- `docs/PRD.md` (derived or verified requirements)
- `docs/ARCHITECTURE.md` (existing architectural topology)
- `docs/specs/` (extracted current interface contracts)

---

## Update / Extend a Feature

Not a distinct engine. Once `.feanor/state/status.json` has `standardized: true`, use the greenfield low-level phases directly:

- `/specs` — add/modify a contract for the change.
- `/plan` — decompose into tickets.
- `/exec` — implement.
- `/audit` — verify against the (now-current) `docs/`/`docs/specs/`, re-runnable at any milestone.

If `standardized: true` is missing or stale when one of these is invoked on a brownfield project, route to `/standardize` first — see `meta/command-router.md` §2's brownfield exception.
