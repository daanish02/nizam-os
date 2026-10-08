---
title: "Specifications — Index"
status: DRAFT
version: 0.1.0
date: 2026-09-10
scope: personal
---

# Specifications

Interface contracts for the personal domain. One file per domain concern,
numbered for reading order.

**What lives at this tier.** Execution order, validation rules with their
reasons, error taxonomies, field semantics, invariants, and state transitions.
**Not** what the charter tier already says — these specs add implementation
detail and never restate topology, requirements or rationale available above.

**Read `005-agent-runtime.md` first if you read only one.** It carries the rules
every other spec obeys — the approval gate, capability scoping, the audit
record. The others reference it rather than restating it.

---

## The specs

| # | Spec | Owns | Requirements | Schema |
| :--- | :--- | :--- | :--- | :--- |
| 001 | [Knowledge](001-knowledge.md) | Capture, classification, retrieval, the vault | CP.03 | `knowledge` |
| 002 | [Personal Finance](002-finance.md) | Transactions, position, budgets, zakat | CP.01 | `finance_personal` |
| 003 | [Math](003-math.md) | Exact arithmetic | NFR.05, NFR.06 | none — stateless |
| 004 | [Personal Tracking](004-personal.md) | Tasks, habits, goals, journal, briefings | CP.02, CP.05 | `personal` |
| 005 | [Agent Runtime](005-agent-runtime.md) | Approval, scoping, audit, delegation, A2A | CP.06 | `audit` |
| 006 | [Investment Review](006-investment.md) | Brokerage reads, screening, research | CP.07 | none — brokerage is the record |
| 007 | [Self-Maintenance](007-self-maintenance.md) | Detection, bounded recovery, reporting | CP.04 | none — no data access |

Three of the seven own no schema, each for a different and deliberate reason:
`math` is pure, `investment` refuses to copy the brokerage, and
`self-maintenance` is separated from data precisely because it holds host
execution.

## Dependencies

```text
005-agent-runtime          every spec obeys it
  ├── 001-knowledge        vault + retrieval
  │     ├── 004-personal   journal entries are vault notes
  │     └── 006-investment screening output is a vault note
  ├── 003-math             pure arithmetic
  │     ├── 002-finance    every monetary figure
  │     └── 006-investment every ratio
  ├── 002-finance ──────── 004-personal  (briefing reports position)
  └── 007-self-maintenance no dependencies; depends on nothing by design
```

---

## Blocking questions

Five questions block work rather than merely parameterising it. They change
interfaces, not values.

| Q | Question | Blocks | Source |
| :--- | :--- | :--- | :--- |
| SRS Q2 | Behaviour when inference is unavailable | **Every spec's tool availability** | Q-A3, Q-F5, Q-K2 |
| SRS Q6 | Boundary of safe unattended recovery | `restart_component` entirely | Q-S1, Q-S2 |
| — | The compliance constraints | `screen_candidate` entirely | Q-I1 |
| — | Balance derivation model | `report_position` | Q-F2 |
| — | `domain` versus `areas` | The knowledge schema, index and every filter | Q-K1 |

Every other open question sets a value. These five decide a shape.

## Conflicts surfaced

Writing these specs exposed disagreements that were invisible while the
information sat in separate documents.

1. **`domain` versus `areas`** *(Q-K1)*. The charter describes multi-valued
   subject areas with expected overlap; the existing schema and code implement a
   single value from a fixed set. Both cannot be right. Specified as `areas`,
   because the charter tier is authoritative — but this changes the schema.

2. **Savings has no requirement** *(002 open item 6)*. Three savings entities
   appear in `docs/SCHEMAS.md` and no functional requirement covers them. Either
   an FR is written or they leave the schema. A spec cannot be written against
   nothing.

3. **Backup is unspecified anywhere** *(`docs/RUNBOOK.md` §6)*. The system's
   stated priority is correctness of the record above availability, and nothing
   backs up the vault, the database, or the encryption key. Not a spec-tier
   question — it needs a requirement first.

4. **Goals and journal are unconfirmed** *(Q-P1, SRS Q10)*. Specified so the
   contract exists if wanted, and marked deferrable throughout.

5. **Document ingestion is unspecified** *(Q-K4)*. FR.03.1.1 names documents
   alongside links and video; extraction for PDF and image is undecided, so it
   is deferred rather than invented.

---

## Method note

These specs were written after the charter tier and before code restructuring,
which is not the order the tooling's gate expects for a project with existing
source. The override and its reasoning are recorded in the tooling's own log.

The consequence worth stating: **where a spec and the existing code disagree,
the spec is the target and the code is the thing that changes** — except where
a spec is marked with an open question, in which case neither is authoritative
until the owner resolves it.
