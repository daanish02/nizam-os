---
title: "Specifications — Index"
status: LOCKED
version: 1.0.0
date: 2026-09-26
scope: personal, cycle 1
---

# Specifications

Interface contracts for cycle 1 of the personal domain. One file per domain concern.

**Read `004-agent-runtime.md` first if you read only one.** It carries the rules every other spec obeys — the approval gate, capability scoping, the audit record. The others reference it rather than restating it.

## The specs

| # | Spec | Owns | Requirements | Schema |
| :--- | :--- | :--- | :--- | :--- |
| 001 | [Knowledge](001-knowledge.md) | Capture, classification, retrieval, the vault | CP.03 | `knowledge` |
| 002 | [Personal Finance](002-finance.md) | Transactions, position, budgets, zakat | CP.01 | `finance_personal` |
| 003 | [Calc](003-calc.md) | Exact arithmetic | NFR.05, NFR.06 | none — stateless |
| 004 | [Agent Runtime](004-agent-runtime.md) | Approval, scoping, audit, delegation | CP.06 | `audit` |

Calc owns no schema (pure) and Agent Runtime owns only `audit` (every other spec's writes flow through it, but it holds no domain data of its own).

## Dependencies

```text
004-agent-runtime          every spec obeys it
  ├── 001-knowledge        vault + retrieval
  └── 003-calc             pure arithmetic
        └── 002-finance    every monetary figure
```

## Deferred (cycle 2 — not specified, do not build)

Personal tracking (tasks/habits/goals/journal), self-maintenance, and investment review were specified in the prior iteration's `specs-new/004`, `007`, and `006` respectively — those documents are preserved in `export/docs/specs-new/` purely as a starting point for cycle 2's own spec pass. They are not current and must not be built against without re-validating them the same way `002-finance.md`'s Q-F1/F2/F3/F5 were re-validated here.

## Open questions

**All resolved as of 2026-09-26.** Every question raised across all four specs — Q-K1 (areas vs domain), Q-K2 (embedding-optional ingestion), Q-K3 (fetch limits), Q-K4 (document ingestion approach — decided, build deferred to cycle 2), Q-F1 (zakat class), Q-F2 (balance derivation), Q-F3 (FX source), Q-F4 (zakat nisab/hawl/scope), Q-F5 (inference-down), Q-A1 (approval TTL), Q-A2 (delegation bounds), Q-A3 (inference-down), Q-A4 (external agent identity) — has a recorded resolution. See each spec's own Open Questions section for the date and reasoning.

Three of these (Q-A2, Q-A4, Q-K4) resolve a *design* question for a capability not built in cycle 1 (delegation, external agents, document ingestion) — the mechanism is fixed so it won't need re-litigating later, but nothing in cycle 1's build depends on them.

## Method note

These specs were rewritten 2026-09-26 as part of a full rebuild (`export/00-START-HERE.md`), reusing the prior iteration's spec content wherever it was still correct and only touching what needed to change: resolving answered open questions, cutting anything outside cycle-1 scope, renaming `003-math` to `003-calc` (avoids shadowing Python's stdlib `math`) and `005-agent-runtime` to `004-agent-runtime` (renumbered after cutting the deferred `004-personal` and `006-investment` specs from this pass).

**Where a spec and any old code disagree, the spec is the target.** This is a from-scratch rebuild — there is no old code to reconcile against at all; write to the spec directly.
