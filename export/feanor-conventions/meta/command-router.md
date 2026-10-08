---
type: meta
title: Command Router & State Machine
description: Canonical mapping of every slash command to its phase engine, precondition gates, inputs, and outputs; consult this before dispatching any Feanor command.
applies_to: [all]
tags: [routing, commands, state-machine]
---

# Command Router & State Machine

## 1. Slash Command Mapping

When a user or external system invokes a command, map it directly to the designated workflow and engine:

| Command        | Workflow Type         | Target Engine Prompt                                                                                                  | Project Inputs Read                     | Outputs Written                                                                                                 |
| :------------- | :-------------------- | :-------------------------------------------------------------------------------------------------------------------- | :-------------------------------------- | :-------------------------------------------------------------------------------------------------------------- |
| `/brainstorm`  | Greenfield            | `agents/requirements-agent.md`                                                                                        | Free-form prompt                        | (none — no checklist gate, no SRS output)                                                                       |
| `/reqs`        | Greenfield            | `agents/requirements-agent.md`                                                                                        | `docs/reqs/` (if notes present), user interrogation | `docs/reqs/raw.md`, `docs/SRS.md`                                                         |
| `/prd`         | Greenfield            | `agents/product-agent.md`                                                                                             | `docs/SRS.md`                      | `docs/PRD.md`                                                                                                   |
| `/hld`         | Greenfield            | `agents/architect-agent.md`                                                                                           | `docs/SRS.md`, `docs/PRD.md`       | `docs/ARCHITECTURE.md` (always) + selected docs from `templates/high-level-docs/`, `docs/diagrams/*.excalidraw`, `docs/adrs/` |
| `/scaffold`    | Greenfield            | `agents/architect-agent.md`                                                                                           | `docs/ARCHITECTURE.md`                  | Scaffold `frontend/`, `backend/`, `docs/specs/`, `.gitignore`                                                   |
| `/specs`       | Greenfield            | `agents/architect-agent.md`                                                                                           | `docs/ARCHITECTURE.md`, Directory tree  | `docs/specs/*.md`                                                                                               |
| `/plan`        | Greenfield            | `agents/planner-agent.md`                                                                                            | `docs/`, `docs/specs/`                  | `docs/plan.toml`                                                                                             |
| `/exec`        | Greenfield            | `agents/execution-agent.md`                                                                                           | `docs/plan.toml`, `docs/specs/`      | Source code in `frontend/` or `backend/`                                                                        |
| `/audit`       | Greenfield/Brownfield | `agents/validation-agent.md`                                                                                          | Source code, `docs/specs/`, `docs/`     | `.feanor/audit_report.md` (appended, timestamped — see §4)                                                      |
| `/document`    | Brownfield            | `agents/requirements-agent.md` + `product-agent.md` + `architect-agent.md` (via `workflows/brownfield-standardize.md`) | Existing source code                   | `docs/SRS.md`, `docs/PRD.md`, `docs/ARCHITECTURE.md`, `docs/specs/`                                       |
| `/standardize` | Brownfield            | `agents/validation-agent.md` + `planner-agent.md` + `execution-agent.md` (via `workflows/brownfield-standardize.md`) | Existing source code, `conventions/`    | Restructured codebase, `.feanor/state/status.json` (`standardized: true` marker on clean pass)                  |

`/document` and `/standardize` are independent — neither requires the other to have run first. Recommended order for a fresh brownfield project is standardize → document → update (via `/specs`/`/plan`/`/exec`), but each is directly invocable on its own.

---

## 2. Hard Precondition Gates

Before executing an engine prompt, Feanor **MUST** verify that every mandatory input artifact exists. This is mechanical, so it is a script, not prose to reinterpret:

```bash
uv run feanor/scripts/check-preconditions.py /plan
```

Exit `0` means the phase may run. Exit `1` prints the missing artifact and the command that produces it — refuse execution and tell the user which phase to run first. `--list` shows every known command; `--override "<reason>"` proceeds anyway and records the reason in `.feanor/logs/overrides.log`.

**Run the script rather than re-deriving the conditions.** The rules it enforces:

| Command | Requires |
| :--- | :--- |
| `/brainstorm`, `/reqs`, `/document`, `/standardize` | nothing — entry points |
| `/prd`, `/hld` | `docs/SRS.md` |
| `/scaffold` | `docs/ARCHITECTURE.md` |
| `/specs` | `docs/ARCHITECTURE.md`, plus the brownfield marker below |
| `/plan` | `docs/ARCHITECTURE.md`, a non-empty `docs/specs/`, a scaffolded source dir, plus the marker |
| `/exec` | `docs/plan.toml` |
| `/audit` | a source directory (`backend/`, `frontend/`, or `services/*/`) |

**Brownfield exception, enforced by the same script:** for `/specs` and `/plan`, `docs/ARCHITECTURE.md` existing is not sufficient when source predates any Feanor phase. The check is `standardized: true` in `.feanor/state/status.json`, written only by `/standardize` on a clean pass. If it is missing, `false`, or older than the most recent source change, route to `/standardize` first.

**Brownfield is source without a `scaffolded: true` marker**, not merely source that exists. `/scaffold` writes that marker, so a greenfield project has source the moment it runs — and must not then be sent to `/standardize` for code Feanor just generated to its own conventions. Both markers live in `.feanor/state/status.json` and are written by `scripts/write-state-marker.py`.

`/exec` additionally requires an actionable, schema-valid ticket. `plan.py` enforces that itself — `next` refuses to hand out a ticket that fails validation:

```bash
uv run feanor/scripts/plan.py check     # whole-plan integrity
uv run feanor/scripts/plan.py next      # refuses invalid tickets
```

---

## 3. Unstructured Intent Classification (Failsafe)

If the user sends a free-form message without a leading slash command (e.g., _"I need to build a payment gateway for subscriptions"_):

1. Read `.feanor/state/status.json` or inspect the project root to determine current project maturity.
2. Route the user prompt according to state:
   - **Source code already exists, structure/naming/conventions look non-compliant:** Route to `/standardize` first.
   - **Source code already exists, no `docs/`:** Route to `/document` (brownfield: derive from code first, per `meta/requirements-checklist.md` §0), not `/prd` from scratch.
   - **Source code exists, prompt describes adding/changing a feature, but no `standardized: true` marker in `.feanor/state/status.json`:** Route to `/standardize` before `/specs` — don't trust `docs/ARCHITECTURE.md` existing as proof the project is update-ready.
   - **No source code, no `docs/` or `docs/specs/`:** Route to `/brainstorm` or `/reqs`.
   - **`docs/` exists, no `docs/specs/`:** Check scaffolding is complete first (target dirs from `/scaffold` exist) — if not, route to `/scaffold`, then `/specs`.
   - **`docs/specs/` exists, no `docs/plan.toml`:** Route to `/plan`.
   - **Plan active:** Check if prompt describes a new feature (Route to `/specs`) or a bugfix on an active ticket (Route to `/exec`).
   - **`docs/SRS.md` exists but the prompt suggests it may be stale/contradicted by current code:** Route to `/reqs` to re-run verification (§0a) before proceeding, rather than trusting the existing doc blindly.

## 4. `/audit` Is Milestone-Repeatable

`/audit` is not a one-time, pipeline-end-only command. Re-run it at any milestone — after a batch of tickets complete, before a release, whenever you want current code checked against current `docs/`/`docs/specs/`. Each run appends a new timestamped entry to `.feanor/audit_report.md` rather than overwriting the previous one, so repeated milestone audits build a history instead of erasing prior findings.
