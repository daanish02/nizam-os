# Nizam-OS — Business Architecture (Future)

**Last updated:** 2026-07-02

Business agents and services (Phases 6a–6e). Not yet built. System architecture overview: `docs/ARCHITECTURE.md`.

---

## Agent Roster

| Agent | Persona | Phase | Status |
|---|---|---|---|
| Raha | Chief of Staff | 6a | In repo — stub profile |
| Hala | CFO | 6b | Not built |
| Omar | COO | 6c | Not built |
| Reem | CTO | 6d | Not built |
| Mira | CMO | 6e | Not built |

---

## C-suite coordination model

Raha uses a kanban board (not delegation) to coordinate Hala, Omar, Reem, and Mira. Each C-suite agent operates independently: Raha posts tasks as kanban cards, agents pick up cards from their own column, execute, and post results as comments. Raha does not invoke other agents directly — she writes, they read and act. This removes tight coupling and avoids synchronous chains that would break if one agent is down.

---

## Services

| Service | Port | Status |
|---|---|---|
| `crm-service` | 8104 | Planned |
| `analytics-service` | 8105 | Planned |
| `math-service` | 8103 | Planned |

Note: finance-service (8101) serves both personal and business — see `docs/SERVICES.md` and `docs/future/SERVICES.md`.

---

## Database

Single PostgreSQL instance, same as personal layer. Business schemas are isolated: separate roles, separate migrations, separate service connections. A compromise of one schema does not expose the others.

Schemas: `finance_business`, `crm`, `analytics`.

Full table definitions, FK constraints, DB roles and grants, migration index: `docs/future/SCHEMAS.md`.

---

## Build order

Business agents build after personal agents are stable (Phase 5 live). Phases run in sequence: 6a (Raha/CoS) → 6b (Hala/CFO) → 6c (Omar/COO) → 6d (Reem/CTO) → 6e (Mira/CMO). The personal-first principle is established in `docs/ARCHITECTURE.md`. Lessons from personal agents (Noor, Nazim, Ayah) feed directly into business implementations.

---

## Drill-down index

### Specs

| Spec | File | Phase |
|---|---|---|
| CoS v1 (Raha) | `docs/future/specs/20260701-cos-v1-design.md` | 6a |
| CFO v1 (Hala) | `docs/future/specs/20260701-cfo-v1-design.md` | 6b |
| COO v1 (Omar) | `docs/future/specs/20260701-coo-v1-design.md` | 6c |
| CTO v1 (Reem) | `docs/future/specs/20260701-cto-v1-design.md` | 6d |
| CMO v1 (Mira) | `docs/future/specs/20260701-cmo-v1-design.md` | 6e |

### Plans

Plans are written at phase start, not in advance. Each plan file will be created in `docs/future/plans/` when its phase begins.
