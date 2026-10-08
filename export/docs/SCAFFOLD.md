---
title: Scaffold — nizam-os (Personal Domain)
status: DRAFT
version: 0.1.0
date: 2026-09-10
scope: personal
derived_from: docs/ARCHITECTURE.md, docs/SERVICES.md
---

# Scaffold

The declared directory structure and the reasoning behind it. **Decisions
only** — no lockfiles, caches, virtual environments or build output, none of
which is a decision anybody made.

**Two categories, kept distinct.** Directories marked **exists** are on disk
now. Directories marked **planned** are declared here but not yet created, and
are created by the phase that builds them *(`docs/ROADMAP.md`)*. Conflating the
two produces a document that describes an imaginary repository.

---

## Root

| Path | Status | Holds |
| :--- | :--- | :--- |
| `docs/` | exists | Charter and high-level documents. The tier above specifications |
| `services/` | exists | Capability services and the code shared between them |
| `scripts/` | exists | Provisioning, scheduled work, and operational tooling |
| `db/` | exists | Database schema and forward-only migrations |
| `config/` | exists | Deployed configuration for services and agents |
| `secrets/` | exists | Encrypted secrets. No plaintext, ever |
| `systemd/` | exists | Process supervision units |
| `hermes/` | exists | Agent profiles: mandate, memory, skills |
| `grafana/` | exists | Dashboard definitions |
| `inventory/` | exists | Machine-state snapshots written by scheduled watchers |
| `assets/` | exists | Images referenced by agent profiles and dashboards |
| `references/` | exists | Vendored third-party reference material |
| `tasks/` | exists | Working notes |
| `logs/` | exists | Runtime logs. Contents ignored by version control |
| `archive/` | exists | Superseded material. Ignored by version control |

**Deviation from the conventional layout, recorded deliberately.** A
service-oriented convention expects a repository root holding little more than
`services/`, `docs/` and `scripts/`. This project additionally carries agent
profiles, machine provisioning, supervision units, dashboards and encrypted
secrets, because it is an operating system for a machine rather than an
application deployed onto one. The extra directories at root are the deviation
and it is intended.

---

## Tree — as it stands today

Everything below exists on disk. Version-controlled unless noted.

```text
nizam-os/
├── docs/                              Charter and high-level documents
│   ├── VISION.md                      Why the system exists
│   ├── SRS.md                         Requirements: CP -> CN -> FR
│   ├── PRD.md                         Product view of the same scope
│   ├── ARCHITECTURE.md                Topology and load-bearing decisions
│   ├── SCAFFOLD.md                    This document
│   ├── SERVICES.md                    Capability surface and contracts
│   ├── SCHEMAS.md                     Entities and invariants
│   ├── SECURITY.md                    Controls and accepted risks
│   ├── THREAT-MODEL.md                Trust boundaries, STRIDE findings
│   ├── INTEGRATIONS.md                Third parties and failure posture
│   ├── TESTING.md                     Where the safety net holds
│   ├── RUNBOOK.md                     What to do when it breaks
│   ├── ROADMAP.md                     Build order by dependency
│   ├── reqs/
│   │   └── raw.md                     Interrogation record
│   ├── specs/                         Interface contracts (tier below)
│   ├── plans/                         Implementation plans
│   ├── guides/                        Operator walkthroughs
│   └── grafana/                       Dashboard design notes
│
├── services/                          Capability services
│   ├── shared/                        Common code
│   │   ├── nizam_shared/
│   │   │   ├── base.py                Service base: logger, db, audit
│   │   │   ├── audit.py               Change-record writer
│   │   │   └── logger.py              Structured logging
│   │   └── pyproject.toml
│   └── knowledge-service/             CP.03 -- vault capture and retrieval
│       ├── server.py                  Entry point, tool definitions
│       ├── ingestion.py               Fetch, add, update
│       ├── transcript.py              Video transcript extraction
│       ├── search.py                  Hybrid retrieval
│       ├── embedder.py                Vector generation
│       ├── indexer.py                 Index upsert
│       ├── vault_io.py                Vault file read and write
│       └── pyproject.toml
│
├── scripts/                           Provisioning and scheduled work
│   ├── setup/                         Idempotent phase orchestrators
│   ├── watchers/                      Scheduled state observation
│   ├── metrics/                       Metric emission
│   ├── save/                          Profile governance
│   ├── env/                           Secret encrypt and decrypt
│   ├── grafana/                       Dashboard provisioning
│   └── shared/                        Script logging helpers
│
├── db/
│   ├── migrations/                    Forward-only, numbered
│   └── schema.sql                     Snapshot -- authority unstated
│
├── hermes/
│   └── profiles/                      One directory per agent
│       ├── admin/                     Nazim -- self-maintenance
│       │   ├── AGENTS.md              Mandate and constraints
│       │   ├── SOUL.md                Persona
│       │   ├── memories/              Persistent memory
│       │   ├── skills/                Domain skills
│       │   └── pending/               Skills awaiting approval
│       └── curator/                   Noor -- knowledge
│           └── (same shape)
│
├── config/                            Deployed configuration
├── secrets/                           Encrypted only. Key held off-machine
├── systemd/                           Supervision units
│   └── user/
├── grafana/                           Dashboard definitions
├── inventory/                         Machine-state snapshots
├── assets/                            Profile and dashboard images
├── references/                        Vendored reference material
├── tasks/                             Working notes
├── logs/                              Runtime logs -- contents ignored
├── archive/                           Superseded material -- ignored
├── pyproject.toml                     Workspace root
└── uv.lock
```

## Tree — target

What the structure becomes once the roadmap is built. **Changes are marked**;
everything unmarked is unchanged from above.

```text
nizam-os/
├── docs/                              (unchanged)
│
├── scripts/
│   ├── check.sh                       NEW  Phase 1 -- lint, format, tests
│   ├── setup/                         one orchestrator per roadmap phase
│   └── ...                            (unchanged)
│
├── services/
│   ├── shared/                        CHANGED  absorbs script logging
│   │   └── nizam_shared/
│   │
│   ├── knowledge-service/             CHANGED  Phase 5 -- restructured
│   │   ├── main.py                    NEW  sole entry point, wiring only
│   │   ├── app/
│   │   │   ├── config.py              cross-cutting tunables only
│   │   │   ├── core/
│   │   │   │   ├── logging.py
│   │   │   │   └── errors.py          typed error hierarchy
│   │   │   ├── vault/                 the markdown store on disk
│   │   │   │   └── io.py              containment-checked paths  T-16
│   │   │   ├── notes/                 index, embeddings, retrieval
│   │   │   │   └── queries/           SQL in files, never inlined
│   │   │   └── sources/               untrusted ingress
│   │   │       ├── web.py             address-filtered fetch  T-24
│   │   │       └── youtube.py
│   │   └── tests/                     NEW  mirrors app/ exactly
│   │
│   ├── personal-service/              NEW  Phase 6 -- CP.02, CP.05
│   │   ├── main.py
│   │   ├── app/
│   │   │   ├── core/
│   │   │   ├── tasks/
│   │   │   ├── habits/
│   │   │   └── journal/               PENDING -- SRS Q10
│   │   └── tests/
│   │
│   ├── finance-service/               NEW  Phase 7 -- CP.01
│   │   ├── main.py
│   │   ├── app/
│   │   │   ├── core/
│   │   │   ├── accounts/
│   │   │   ├── transactions/
│   │   │   │   └── queries/
│   │   │   ├── budgets/
│   │   │   └── zakat/                 computed at request, stored nowhere
│   │   └── tests/
│   │
│   ├── math-service/                  NEW  Phase 7 -- stateless
│   │   ├── main.py
│   │   ├── app/
│   │   └── tests/
│   │
│   └── investment-service/            NEW  Phase 9 -- stateless, read-only
│       ├── main.py
│       ├── app/                       no order capability exists  T-28
│       └── tests/
│
├── hermes/
│   └── profiles/
│       ├── admin/                     Nazim
│       ├── curator/                   Noor
│       ├── assistant/                 NEW  Phase 6 -- Ayah
│       ├── researcher/                NEW  Phase 8 -- Hakim
│       └── investor/                  NEW  Phase 9 -- Rashid
│
├── db/
│   ├── migrations/                    001 audit, 002 knowledge,
│   │                                  003 personal, 004 finance_personal
│   └── snapshots/                     CHANGED  dump relocated and labelled
│
└── ...                                (unchanged)
```

**Read the two trees together.** The first is what exists; the second is what
the roadmap builds toward. Nothing in the second appears without a phase that
creates it, and nothing marked NEW should be created ahead of its phase — a
directory that exists before the work that justifies it is a guess about a
decision not yet made.


---

## `services/`

| Path | Status | Owns |
| :--- | :--- | :--- |
| `services/shared/` | exists | Code common to every service: logging, the change record, connection handling |
| `services/knowledge-service/` | exists | CP.03 — vault ingestion, classification, indexing, retrieval |
| **services/personal-service/** | planned — Phase 6 | CP.02, CP.05 — tasks, habits, and the confirmed part of personal tracking |
| **services/finance-service/** | planned — Phase 7 | CP.01 — transactions, balances, budgets, zakat |
| **services/math-service/** | planned — Phase 7 | Exact arithmetic. Stateless |
| **services/investment-service/** | planned — Phase 9 | CP.07 — brokerage reads. Stateless |

**Named for role, never for language.** `knowledge-service`, not
`python-service`. The name should survive a reimplementation.

### Internal layout of a service

Each service is organised by **domain**, not by technical layer. No
**models**, **services** or **routers** directory collecting unrelated features —
a feature's data, logic and interface live together, so changing a feature
touches one place.

```text
services/<name>/
├── main.py              # sole entry point: wiring only, no logic
├── app/
│   ├── config.py        # cross-cutting tunables only
│   ├── core/            # logging, error types — used by every domain
│   └── <domain>/        # one package per domain concern
│       └── queries/     # SQL in files, never inlined in code
└── tests/               # mirrors app/ exactly
```

**Why SQL lives in files.** Inlined query strings are invisible to review, hard
to diff meaningfully, and are where string composition creeps back in — the
thing `C-09` exists to prevent. A file is reviewable on its own terms.

**Why the test tree mirrors the app tree.** The test for a thing is findable from the
thing, without searching.

`[PENDING]` `services/knowledge-service/` does not yet follow this layout. Its
modules are flat and it has no test tree. Restructuring it is Phase 5 work.

---

## `scripts/`

| Path | Status | Holds |
| :--- | :--- | :--- |
| `scripts/setup/` | exists | Idempotent phase orchestrators, one per roadmap phase |
| `scripts/watchers/` | exists | Scheduled observation of machine state |
| `scripts/metrics/` | exists | Metric emission for the observability stack |
| `scripts/save/` | exists | Profile governance and validation |
| `scripts/env/` | exists | Secret encryption and decryption |
| `scripts/shared/` | exists | Shared logging helpers for scripts |
| `scripts/grafana/` | exists | Dashboard provisioning |

**Deviation, recorded.** A service-oriented convention reserves `scripts/` for
a handful of development entry points — start, stop, check. Here it also holds
provisioning and scheduled operational work, because provisioning the machine
*is* part of this project rather than a separate concern. Supervision units
reference these paths directly, so they are load-bearing rather than
conveniences.

`[PENDING]` The single check command does not exist and belongs at this
directory's top level. It is Phase 1's first deliverable *(`docs/TESTING.md`
§5)*.

`scripts/shared/` currently holds more than one logging implementation, in more
than one language, separate again from the one in `services/shared/`.
Consolidating the Python side into `services/shared/` is deferred work, noted
here so it is not mistaken for a decision.

---

## `db/`

| Path | Status | Holds |
| :--- | :--- | :--- |
| `db/migrations/` | exists | Forward-only, numbered migrations |

**Migrations live at the root, not inside a service — a deliberate deviation.**
The convention places migrations inside the service that owns them. Here the
schemas span services: the change record is written by every service and owned
by none. Splitting one migration sequence across service directories would make
the ordering between them implicit, which is worse than the deviation.

**Forward-only.** No down migrations. A rollback that silently discards rows
contradicts the priority of correctness over availability *(SECURITY §1)*.

`[PENDING]` A full schema dump sits alongside the numbered migrations with no
statement of which is authoritative. It should be the migrations, with the dump
relocated and labelled a generated snapshot.

---

## `hermes/`

| Path | Status | Holds |
| :--- | :--- | :--- |
| `hermes/profiles/` | exists | One directory per agent |
| `hermes/profiles/admin/` | exists | Nazim — self-maintenance |
| `hermes/profiles/curator/` | exists | Noor — knowledge |

Planned, by phase: assistant (Ayah, Phase 6), researcher (Hakim, Phase 8),
investor (Rashid, Phase 9).

Each profile holds its mandate, its memory, and its skills. **Behaviour lives
in skills; the profile states only mandate and constraint** — so adding a
capability is writing a skill rather than editing an agent, and each addition
is separately auditable *(ARCHITECTURE §5)*.

**Note on the split.** An agent's identity is currently spread across three
root directories: its profile here, its configuration in `config/`, its secrets
in `secrets/`. That is a consequence of how the runtime and the encryption
expect to find things, not a design preference. Recorded so it is not mistaken
for one.

---

## `docs/`

| Path | Status | Holds |
| :--- | :--- | :--- |
| `docs/reqs/` | exists | Requirements interrogation record |
| `docs/specs/` | exists | Interface contracts — the tier below this document |
| `docs/plans/` | exists | Implementation plans |
| `docs/guides/` | exists | Operator walkthroughs |
| `docs/grafana/` | exists | Dashboard design notes |

Charter documents sit at `docs/` root: vision, requirements, product
definition, architecture, services, schemas, security, threat model,
integrations, testing, runbook, roadmap, and this file.

**The tiering rule.** A fact lives at exactly one tier. This document declares
that a service exists and why it is shaped as it is; `docs/specs/` declares its
interface; the code implements it. A fact repeated across tiers drifts, and
nothing detects the drift.

---

## Not in version control

`logs/` contents, `archive/`, the tooling directory, virtual environments,
caches, and every plaintext secret. Encrypted secrets **are** committed; the
key that opens them is not, and must be held outside the machine
*(`docs/RUNBOOK.md` §6)*.

---

## Open items

| # | Item | Affects |
| :--- | :--- | :--- |
| 1 | `knowledge-service` does not follow the declared internal layout. `[PENDING]` | Phase 5 |
| 2 | The check command does not exist. `[PENDING]` | Phase 1 — blocks everything |
| 3 | Logging is implemented in several places. `[PENDING]` | `services/shared/`, `scripts/shared/` |
| 4 | Authority between the schema dump and the migrations is unstated. `[PENDING]` | `db/` |
| 5 | Four of six services are unbuilt. | Phases 6, 7, 9 |
