---
title: Schemas — nizam-os (Personal Domain, Cycle 1)
status: LOCKED
version: 1.0.0
date: 2026-09-26
scope: personal, cycle 1
derived_from: ARCHITECTURE.md, SRS.md, docs/specs/001-knowledge.md, docs/specs/002-finance.md
---

# Schemas

Core entities, their relationships, and the invariants that hold. **Not DDL** —
the exact column-level shape lives in each spec's own `## Schema` section
(`docs/specs/001-knowledge.md`, `002-finance.md`); this document is the
cross-domain summary so you don't have to read every spec to see the whole
picture.

One PostgreSQL instance, one database (`nizam`), one schema per domain. Each
service connects as its own role with grants on exactly the schema(s) it owns
— no service can read or write another domain's schema, enforced at the
database level (SRS NFR.11).

---

## Ownership

| Schema | Owned by | Written by | Read by |
| :--- | :--- | :--- | :--- |
| `audit` | Shared — the agent runtime spec (`004-agent-runtime.md`) | Every domain service, insert-only | The owner, via Grafana or a query tool |
| `knowledge` | `nizam/knowledge/` | `svc_knowledge` role | `svc_knowledge` role (the retry-embeddings job connects as this role too) |
| `finance_personal` | `nizam/finance/` | `svc_finance` role | `svc_finance` role |
| `litellm` | LiteLLM itself | LiteLLM | LiteLLM, spend dashboards |

`calc` has **no schema** — it's a pure, stateless module with no I/O
(`docs/specs/003-calc.md`). Deferred-domain schemas (`personal` for
tasks/habits/journal, an investment schema if one is ever needed) are not
described here — see `docs/specs/index.md` for the cycle-2 note.

## `audit`

One table: `audit.log`. Append-only — no service holds `UPDATE` or `DELETE`
grants on it, only `INSERT` and `SELECT` (SRS FR.06.3.2, NFR.15). Every write
any domain service makes is preceded or followed by one row here, naming the
acting agent, the action, the target, and before/after state where applicable.

This is the one schema every other schema's writes are traceable through — see
`docs/specs/004-agent-runtime.md` for the exact row shape and write discipline.

- Every domain role (`svc_knowledge`, `svc_finance`) holds `INSERT` and
  `SELECT` on `audit.log`, never `UPDATE` or `DELETE`. The audit row is written
  in the **same transaction** as the domain write it records (spec 004 A-4). If
  audit fails, the write rolls back.
- `approval_id` has a **non-unique** index. One approved action can write
  several rows — a transfer, for example. The replay check (spec 004 Layer 2)
  looks up "any row with this `approval_id`" under an advisory lock, rather
  than relying on a unique constraint.

## `knowledge`

Two tables, both derived and rebuildable from the vault's Markdown files (SRS
NFR.08 — the vault file is truth, the index is a cache):

- `vault_index` — one row per note: path, title, `areas` (multi-valued,
  `TEXT[]`, controlled vocabulary — see `docs/specs/001-knowledge.md` for the
  exact ten-value list), tags, status, confidence, dates, `embedding_status`.
- `vault_embeddings` — one row per note per embedding model, `pgvector` column.
  Separate from `vault_index` because a note can have zero (LLM was down at
  ingest time), one, or in principle more than one embedding over its
  lifetime, and the two have different write patterns (index changes on every
  edit, embeddings change only on re-embed).

**No `domain` column anywhere.** The prior iteration had a single-valued
`domain`; this is a from-scratch rebuild using `areas` from day one (Q-K1,
resolved).

## `finance_personal`

Tables per `docs/specs/002-finance.md`'s `## Schema` section: accounts,
transactions, categories, budgets. **No stored balance column anywhere** —
`report_position` always sums the transaction ledger (Q-F2, resolved). A
reconciliation-entry mechanism corrects for drift between the ledger and
reality without ever introducing a second source of truth for "the balance".

Money is always `(amount: bigint, currency: text)` — never a single float
column, never currency-implicit.

- **Savings is not an entity.** It is `accounts.type = 'savings'`, resolved
  2026-09-26.
- **`zakat_state`** is a single row holding `hawl_start`. It is the one
  deliberate piece of stored state in zakat, because the lunar-year hawl clock
  depends on when nisab was *first* crossed (spec 002 Q-F4). The obligation
  figure itself is never stored.

## Cross-cutting invariants

- **Every domain's writes go through the approval gate and land an audit row.** No domain schema has a write path that bypasses `004-agent-runtime.md`'s rules.
- **No schema references another schema's tables with a foreign key.** Cross-domain relationships (e.g. a finance report citing a knowledge note) are references by ID/path in application code, not database-enforced joins — this keeps the domain isolation real, not just conventional.
- **Every timestamp is UTC.** Display conversion to the owner's local time (UTC+4) happens in the presentation layer, never stored.
- **Every monetary amount is paired with its currency at the column level**, never a bare integer with currency assumed from context.

## Open items

- The exact DDL (indexes, constraints, check clauses) is an implementation-time decision guided by each spec's `## Schema` section, not repeated here.
