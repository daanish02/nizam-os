# Schemas

Single PostgreSQL instance. Database: `nizam`. Each service connects as its own role with grants scoped to exactly the schemas it needs. 

This document records core entities, their relationships, and the invariants that hold. Not DDL, not migration scripts, not indexes. Those are spec tier: [SPECS](docs/specs/).

> Role grants and isolation model: [SECURITY](docs/SECURITY.md).

---

## Schema ownership

| Schema | Owned by | Service |
|--------|----------|---------|
| `audit` | Shared | All services write; no service deletes |
| `litellm` | LiteLLM internal | LiteLLM proxy (Prisma-managed) |
| `knowledge` | curator's domain | `knowledge-service` |
| `personal` | assistant's domain | `personal-service` |
| `finance_personal` | assistant's financial domain | `finance-service` |
| `finance_business` | cfo's domain | `finance-service` |
| `crm` | coo's domain | `crm-service` |
| `analytics` | cmo's domain | `analytics-service` |

---

## `audit` schema

**Invariant:** Append-only. No service role holds UPDATE or DELETE on `audit.log`. Every mutation by any service is recorded here.

**Core entity:** 

- **audit.log** — tracks which schema, which table, which operation (INSERT/UPDATE/DELETE), which actor, the affected row, before and after state, and when. `actor` is the Hermes profile name. Every write is attributed to the agent that made it. Grafana role has SELECT-only access for dashboards.

---

## `knowledge` schema

**Core entities:**

- **vault_index** — one row per note in `~/nizam-vault/commons/`. Tracks the note's file path, title, areas (multi-value controlled vocabulary), source type and URL, tags (free-form), status lifecycle, confidence level, and content hash.
- **vault_embeddings** — one row per indexed note. Stores the embedding vector alongside the model and dimension used to generate it. Separate table because embedding generation is async and expensive — a note can be indexed before its embedding is computed.

**Key invariants:**
- `areas` is a controlled vocabulary enforced at write time by knowledge-service. Values are defined in the service config, not in a DB table. Adding a new area requires a service config change.
- `tags` is free-form — no enforcement. Used for supplementary metadata.
- `date_created` is the original content's publication date. Separate from the DB record timestamps.
- A note can belong to multiple areas. Overlap is by design.
- Embedding dimensions must match the configured embedding model. Changing the model requires a migration.

---

## `personal` schema

**Core entities:**

- **habits** — a recurring behavior the owner tracks. Has a name, frequency (rrule string), optional rest days that don't break streaks, and active/inactive status.
- **habit_logs** — one row per day a habit was completed. Links to the habit; stores the date and an optional note.
- **goals** — a desired outcome with an optional target date and a status lifecycle.
- **tasks** — a discrete unit of work. Has priority, energy level, due date, status, and optional link to a goal.
- **journal** — one row per journal entry. Stores the vault file path and mirrors content in the DB for search. Vault file is the source of truth; DB copy is for BM25 search only.

**Key invariants:**
- `habit_logs` are append-only in practice — retroactive edits are not expected.
- Journal entries are written to both vault and DB atomically. A DB write without the vault file is an inconsistent state.
- Tasks may optionally link to a goal; standalone tasks are valid.

---

## `finance_personal` schema

**Core entities:**

- **accounts** — a financial account the owner holds. Has a name, currency, and type.
- **transactions** — one row per logged transaction. Has amount (in sub-units), currency, account, category, merchant, date, direction, and optional exchange rate if multicurrency.
- **transfers** — a movement of value between two accounts the owner holds. Records the original and received amounts separately (to handle FX conversions). Fee is recorded separately; fee currency defaults to the source account's currency.
- **categories** — a controlled vocabulary for transaction classification. Defined by the owner; enforced at write time.
- **budgets** — a budget allocation per category per calendar month. Only one active budget per category at a time. When a new budget is created for a category that already has an active one, finance-service deactivates the old row before inserting. Logic lives in the service, not as a DB constraint.
- **savings_funds** — a goal-based savings target. Has a name, currency, optinal target amount, and optional deadline.
- **savings_modules** — sub-buckets within a fund. Each module has its own target amount and purpose. Contributions are logged at the module level and roll up to the fund.
- **savings_contributions** — one row per contribution to a savings module. Links to the source transaction and the target module.
- **amortization** — recurring or irregular costs amortized for cash flow reporting. Covers subscriptions, annual fees, and any cost that should be spread across months for accurate monthly cash flow. Stores the full amount, period (annual/monthly/etc.), and the effective monthly impact finance-service uses in reports.

**Key invariants:**
- `finance_personal` is entirely separate from `finance_business` — separate role, separate entities, separate connection, separate migration. A compromise of one does not expose the other.
- **All monetary amounts are stored in the currency's smallest sub-unit as an integer** (e.g. 50 AED → 5000 fils; 10 USD → 1000 cents). The mapping of currency → sub-unit divisor is defined in `finance-service/config.yaml`. Reporting converts back to major units for display. This eliminates floating-point rounding in all arithmetic.
- **Zakat has no persistent tables.** `calculate_zakat` is a runtime calculation: `finance-service` fetches the current gold price, computes the nisab threshold from zakatable account balances, and returns the obligation. Nisab gold gram threshold is configurable via `NISAB_GOLD_GRAMS` tunable param (default: 85g).

---

## `finance_business` schema

**Core entities:** revenue, expenses, invoices, accounts, and reporting periods.

Invariants and entity detail: [SPECS](docs/specs).

---

## `crm` schema

**Core entities:** contacts, companies, pipeline stages, interactions, and deals.

Invariants and entity detail: [SPECS](docs/specs).

---

## `analytics` schema

**Core entities:** campaigns, content items, metrics snapshots, and audience segments.

Invariants and entity detail: [SPECS](docs/specs).
