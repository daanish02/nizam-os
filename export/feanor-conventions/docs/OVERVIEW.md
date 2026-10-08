---
type: reference
title: Feanor Overview — What It Is and Why
description: Maintainer orientation to Feanor — the problem it solves, the three architectural ideas behind it, how the directories relate, the invariants that must not be broken, and current known gaps.
applies_to: [maintainer]
tags: [docs, maintainer, overview, architecture, philosophy]
---

# Feanor Overview

Read this first after time away. Everything else in `docs/` assumes it.

## The Problem It Solves

An LLM writing production software fails in three specific ways, and each phase of Feanor exists to counter one of them:

1. **It starts coding before it understands the problem.** Counter: requirements, PRD, and architecture are separate gated phases producing artifacts on disk. Code cannot begin until they exist.
2. **Its context degrades as the task grows.** Load an entire standards library and the model attends to none of it; load nothing and it invents conventions per file. Counter: Just-In-Time retrieval — each ticket pulls only the standards it needs.
3. **It reports success it did not achieve.** Counter: evidence-based gates. A ticket is done when a command exits zero, recorded by a script, not when the model says so.

Everything else is detail. If a change makes one of those three worse, it is the wrong change regardless of what else it improves.

## Three Ideas

**Phases as a state machine.** `/reqs → /prd → /hld → /scaffold → /specs → /plan → /exec → /audit`, each with a hard precondition checked against the filesystem (`meta/command-router.md` §2). The state lives in files, not in the conversation, so a fresh context window can resume mid-project. Brownfield enters through `/standardize` and `/document`, which converge on the same low-level phases.

**JIT micro-standards.** `conventions/` holds many small files, each one topic. A ticket carries tags; `meta/context-resolver.md` maps tags and file extensions to convention files and loads at most ten. This is why convention files are small, single-topic, and carry a descriptive `description` field — the description is what the resolver reads to decide relevance. A 500-line convention file breaks the mechanism even if its content is correct.

**Determinism where determinism exists.** `meta/determinism-standard.md` draws the line: a step with exactly one mechanical outcome is a literal runnable code block or, better, a real script under `scripts/`; a step requiring judgment stays prose. Faking determinism produces brittle prompts; faking judgment produces silent drift. The strongest form is a real script, because a code block in Markdown still has to be re-derived by the agent each run, and that re-derivation is where a flag gets dropped.

## Layout

| Directory | Contains | Loaded when |
| :--- | :--- | :--- |
| `agents/` | The system prompt each phase runs | Its command is invoked |
| `meta/` | Routing, JIT resolution, determinism, requirements method, ADR policy, threat modeling | By the agent that needs the method |
| `conventions/` | Atomic engineering micro-standards | JIT, per ticket, capped |
| `templates/` | Output blueprints for generated artifacts | By whichever agent writes that artifact |
| `workflows/` | Lifecycle pipelines and the self-maintenance protocol | Orientation, not execution |
| `scripts/` | Feanor's own tested tooling | Called directly, never retyped |
| `docs/` | Maintainer documentation (this) | Never by an agent |

The distinction that matters most: **`conventions/` is about the code being built; `agents/` and `meta/` are about how Feanor operates.** Mixing them is the failure mode `workflows/maintain-repo.md` §5 forbids.

## Invariants

Break these and the system stops working as designed:

- **Feanor never reaches `main`.** It is development-time tooling, scoped to feature branches and `qa`, enforced by a pre-commit hook. `main` holds only the product.
- **Only `plan.py` moves a ticket to done.** It runs the verification command without a shell, records the real exit code, and refuses `done` without a passing verify. Any path that lets a model mark its own work complete defeats the entire engine.
- **The resolver's cap is real.** Loading everything is the failure the whole design exists to prevent, and security conventions are ranked first so they are never the ones dropped.
- **Convention files stay small and single-topic.** Line budgets in `meta/determinism-standard.md`.
- **Every artifact is on disk.** No phase output lives only in conversation.
- **Mechanical steps are gates, not prose.** Preconditions, ticket validity, tag resolution, registration consistency, and mechanical convention compliance all refuse rather than report. Every gate takes `--override "<reason>"`, recorded in `.feanor/logs/overrides.log`. See `meta/determinism-standard.md`'s enforcement ladder.
- **Judgment is never scripted.** Spec content, ticket scoping, audit severity, and design quality stay with the model. Forcing them into checks would trade quality for the appearance of rigour — see `docs/DECISIONS.md` D-012.

## Known Gaps

Honest list. Updated as audits land — see [AUDIT-LOG.md](./AUDIT-LOG.md).

- **Optional-tier conventions are thin.** Metrics and tracing exist; caching is covered; feature flags, background jobs, search, and i18n have no conventions yet. See [CAPABILITIES.md](./CAPABILITIES.md).
- **Only three stacks.** Go, Python, TypeScript/Next.js. Anything else falls back to generic cross-stack rules, which is thinner than it looks.
- **No performance-budget convention.** `nextjs/performance.md` covers technique, not budgets or regression gates.
- **`/audit` findings are judgment, not machine-checked**, apart from the scanner step. Two runs can disagree on convention compliance.
- **No migration/rollback safety convention** beyond forward-only numbering in `database.md`.

## Where To Change What

**Full registration checklist per artifact type: [EXTENDING.md](./EXTENDING.md).** Adding a file is never enough — Feanor finds things through catalogs and `conventions/tags.toml`, so an unregistered file is invisible to every agent and nothing errors.

- A new engineering rule → a new file in `conventions/`, **plus an entry in `conventions/tags.toml`**, following `workflows/maintain-repo.md` §3.
- A change to how a phase behaves → the relevant `agents/*.md`, and check `meta/command-router.md` still agrees.
- A new capability that not every project needs → [CAPABILITIES.md](./CAPABILITIES.md) first, then the convention, then the profile schema.
- A structural decision → record it in [DECISIONS.md](./DECISIONS.md) before implementing, not after.
