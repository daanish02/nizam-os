---
type: workflow
title: Greenfield Development Pipeline
description: Sequential state machine for new projects — each phase (/reqs → /prd → /hld → /specs → /plan → /exec → /audit) produces verified disk artifacts before the next phase may begin.
applies_to: [greenfield]
tags: [workflow, greenfield, lifecycle, state-machine]
---

# Greenfield Development Pipeline

The Greenfield Pipeline governs end-to-end development of new projects. It enforces a sequential state machine where each phase produces verified disk artifacts before downstream coding can begin.

```text
[Reqs] ──> [PRD] ──> [HLD] ──> [Scaffold] ──> [Specs] ──> [Plan] ──> [Exec Loop] ──> [Audit]

```

`/brainstorm` is available at any point for free-form exploration but sits outside this state machine — no gate.

---

## Stage-by-Stage Workflow

### Stage 1: Requirements (`/reqs`)

- **Trigger:** User command `/reqs`. No precondition — this is the entry point.
- **Agent:** `agents/requirements-agent.md`
- **Method:** `meta/requirements-checklist.md` (source classification, problem classification §0.5, audience gate, funnel sequencing, customer needs derivation §2.5, probing technique, coverage checklist, zigzag validation §6)
- **Template:** `templates/srs-template.md`
- **Process:** Read `docs/reqs/` (if notes already exist there) first; classify customer problems (CP); run full funnel; derive customer needs (CN); run zigzag validation; draft `docs/SRS.md` only once the checklist is fully Covered/N/A and zigzag passes.
- **Outputs:**
  - `docs/reqs/raw.md` (running interrogation state — overwritten as session proceeds)
  - `docs/SRS.md`

### Stage 1b: Product Definition (`/prd`)

- **Trigger:** User command `/prd`.
- **Precondition Gate:** `docs/SRS.md` MUST exist.
- **Agent:** `agents/product-agent.md`
- **Template:** `templates/prd-template.md`
- **Process:** Read SRS fully; distill into business-readable PRD (personas, executive summary, success metrics, out-of-scope). No re-interrogation.
- **Outputs:**
  - `docs/PRD.md`

### Stage 2: System Architecture (`/hld`)

- **Trigger:** User command `/hld`.
- **Precondition Gate:** `docs/SRS.md` MUST exist.
- **Agent:** `agents/architect-agent.md`
- **Template:** `templates/high-level-docs/index.md` (selection guide — `ARCHITECTURE.md` always generated, others per project need)
- **Process:** Define tech stack, service boundaries, data models, network topologies, and Mermaid architecture diagrams. Generate the 3 companion Excalidraw diagrams into `docs/diagrams/` per `templates/high-level-docs/diagrams-guide.md`.
- **Outputs:**
- `docs/ARCHITECTURE.md` (+ any selected docs: `SCHEMAS.md`, `APIS.md`, `UI.md`, `SECURITY.md`, `DEPLOYMENT.md`, `RUNBOOK.md`, `EXTERNAL-SERVICES.md`, `PLAN.md`)
- `docs/diagrams/*.excalidraw`

### Stage 3: Repository Scaffolding (`/scaffold`)

- **Trigger:** User command `/scaffold`.
- **Precondition Gate:** `docs/ARCHITECTURE.md` MUST exist.
- **Engine:** `agents/architect-agent.md`
- **Process:** Create clean project folders, initialize dependency files (e.g., `uv init --workspace`), and write root `.gitignore`.
- **Outputs:**
- `README.md` (from `templates/readme-template.md` — filled from PRD + ARCHITECTURE; no inline doc/test references)
- `docs/TESTING.md` (from `templates/high-level-docs/testing-template.md` — test layout, tiers, run commands; fill what's knowable at scaffold time, leave tier markers and coverage statement to be completed as tests are written)
- Target directory tree (e.g., `frontend/`, `backend/`, `docs/specs/`)
- **After the first commit following this stage:** run `scripts/github-repo-setup.sh <repo-name>` — see `git/github-repo-setup.md` for why this specific point in the sequence (needs a commit to push; every commit before branch protection is configured is unprotected, so don't delay it).

### Stage 4: Contract Specification (`/specs`)

- **Trigger:** User command `/specs`.
- **Precondition Gate:** `docs/ARCHITECTURE.md` MUST exist and scaffolding MUST be complete.
- **Engine:** `agents/architect-agent.md`
- **Template:** `templates/spec-template.md`
- **Process:** Write exact, language-agnostic interface contracts for APIs, database schemas, message queues, and shared types.
- **Outputs:**
- `docs/specs/NNN-<concern>.md` — one file per domain concern, numbered for reading order (e.g. `001-auth-api.md`, `002-users-schema.md`). Count and names vary by project surface area.

### Stage 5: Ticket Planning (`/plan`)

- **Trigger:** User command `/plan`.
- **Precondition Gate:** `docs/ARCHITECTURE.md` AND `docs/specs/` directory MUST exist.
- **Engine:** `agents/planner-agent.md`
- **Process:** Decompose specs into atomic, 2-to-5-minute tickets. Assign file paths, test commands, and JIT convention tags.
- **Outputs:**
- `docs/plan.toml`

### Stage 6: JIT Execution Loop (`/exec`)

- **Trigger:** User command `/exec` or loop runner.
- **Precondition Gate:** `docs/plan.toml` MUST exist with at least one `todo` ticket whose dependencies are all `done`.
- **Engine:** `agents/execution-agent.md`
- **Process:**

1. Fetch active ticket via `uv run feanor/scripts/plan.py next`.
2. Invoke JIT Context Resolver (`meta/context-resolver.md`) to load micro-standards from `conventions/`.
3. Write code, then verify via `uv run feanor/scripts/plan.py verify <id>` — the script runs the ticket's `verification_command` without a shell and records its real exit code.
4. Mark ticket done via `uv run feanor/scripts/plan.py done <id>` — refused unless step 3 passed.

- **Outputs:**
- Implementation code in `frontend/` or `backend/`
- `.feanor/logs/validation.log`

### Stage 7: Evidence Audit (`/audit`)

- **Trigger:** User command `/audit`. **Milestone-repeatable** — not pipeline-end-only. Re-run after any batch of tickets, before a release, or whenever current code should be checked against current `docs/`/`docs/specs/`. Each run appends a timestamped section to `.feanor/audit_report.md`.
- **Precondition Gate:** Source code exists. Full plan completion is not required.
- **Engine:** `agents/validation-agent.md`
- **Process:** Verify implementation against original `docs/specs/` and `docs/PRD.md`.
- **Outputs:**
- `.feanor/audit_report.md`
