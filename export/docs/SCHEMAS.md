---
title: Schemas — nizam-os (Personal Domain)
status: DRAFT
version: 0.2.0
date: 2026-09-10
scope: personal
derived_from: docs/ARCHITECTURE.md, docs/SRS.md
---

# Schemas

Core entities, their relationships, and the invariants that hold. **Not DDL,
not migrations, not indexes** — those are specification tier and live in
`docs/specs/`.

One PostgreSQL instance, one database, one schema per domain. Each service
connects as its own role with grants on exactly the schemas it owns. Role
grants and the isolation model: `docs/SECURITY.md` §3.2.

> **Placeholders.** `[PENDING — SRS Q<n>]` marks an entity or attribute whose
> shape depends on an unresolved question in `docs/SRS.md`. Nothing marked that
> way has been assumed.

---

## Ownership

| Schema | Owned by | Written by | Read by |
| :--- | :--- | :--- | :--- |
| `audit` | Shared | Every service, insert-only | The owner, via dashboards |
| `knowledge` | knowledge service | knowledge | knowledge |
| `personal` | personal service | personal | personal |
| `finance_personal` | finance service | finance | finance |

The business schemas (`finance_business`, `crm`, `analytics`) are deferred with
the business domain and are not described here.

`investment` has **no schema** by design. The brokerage is the sole record of
holdings; storing a copy would create a figure that can diverge from the truth
*(FR.07.1.3, T-29)*. Qualitative screening output is a vault note, not a row.

---

## `audit`

**Purpose.** The record of everything the system did to the owner's data. Its
reader is the owner; its writers are every service.

**Core entity**

- **log** — one row per mutation. Records which schema and table were touched,
  which operation, the acting agent, the affected row, its state before and
  after, and when. The actor is the agent, not the service — attribution is to
  the party that decided, not the party that executed *(FR.06.3.1)*.
  An action contributed by an external agent records that agent's identity
  *(FR.06.4.3, C-13)*.

**Invariants**

- **Append-only, by grant.** No service role holds UPDATE or DELETE. The system
  cannot rewrite its own history even when instructed to *(FR.06.3.2, C-12)*.
- Every write to every other schema produces exactly one row here. A mutation
  with no audit row is a defect, not an omission.
- Retention: `[PENDING — SRS Q5]`.

---

## `knowledge`

**Purpose.** The index over the owner's vault. **The vault files are
authoritative; everything here is derived and rebuildable from them alone**
*(NFR.07, NFR.08)*.

**Core entities**

- **vault_index** — one row per note. Holds the note's path, title, subject
  areas, tags, source type and origin, status, and a content hash. The hash is
  what makes rebuild detectable: a file whose hash differs from its row is
  stale.
- **vault_embeddings** — one row per indexed note, holding the vector alongside
  the model and dimension that produced it. Separate from the index because
  embedding is asynchronous and expensive: a note is indexed and searchable by
  word before its vector exists.

**Invariants**

- **Subject areas are a controlled vocabulary; tags are free-form**
  *(FR.03.2.2)*. Areas are multi-valued — a note may legitimately belong to
  several, and forcing a single taxonomy loses that.
- The model and dimension are stored **per row**, not assumed globally. Without
  this, changing the embedding model silently mixes incomparable vectors in one
  index.
- A note is retrievable by word-based search whether or not its embedding
  exists. This is what lets retrieval degrade rather than fail *(FR.03.3.3)*.
- No row exists for a note the owner did not approve *(FR.03.4.1)*.
- Deleting every row here loses no knowledge. Deleting a vault file does.

---

## `personal`

**Purpose.** Tasks, habits, goals and the journal index. The assistant is the
sole writer.

**Core entities**

- **tasks** — a discrete commitment. Carries a description, optional due date,
  priority, and a state across open, complete and abandoned *(FR.02.3.1)*.
  Optionally related to a goal; a standalone task is equally valid.
- **habits** — a recurring behaviour, with a schedule and the days that do not
  break a streak when missed.
- **habit_logs** — one row per completion, on a date, optionally annotated.
- **goals** — a desired outcome with an optional target date and a lifecycle
  state.
- **journal** — one row per entry, holding the vault path and a copy of the
  content **for search only**.

**Invariants**

- **Complete and abandoned are distinct terminal states.** Collapsing them
  loses the distinction between what was done and what was dropped, which is
  most of what a review of the record is for.
- A habit's streak is derived from its logs and its schedule, never stored as a
  counter. A stored counter drifts from the log and there is then no way to
  tell which is right.
- **The journal's vault file is authoritative; this row is a search copy.** A
  row without its file is an inconsistent state and must be reported as a
  failure, not a success *(FR.05.3.2, C-14)*.
- Journal content is reachable by no agent other than the assistant *(C-10)*.
- Retention: `[PENDING — SRS Q5]`.

---

## `finance_personal`

**Purpose.** The owner's money: what he holds, what moved, what he intended to
spend, and what he owes.

**Core entities**

- **accounts** — a place value is held. Name, currency, type.
- **transactions** — one row per movement. Amount, currency, account, category,
  counterparty, date, direction, and an exchange rate where one applied.
- **transfers** — a movement between two accounts the owner holds. Records the
  amount sent and the amount received **separately**, because a cross-currency
  transfer is not one number, and any fee separately again *(FR.01.1.4)*.
- **categories** — the owner's own classification vocabulary, enforced at write
  time. An unrecognised category is refused, never invented *(FR.01.1.2)*.
- **budgets** — an intended ceiling per category per month.
- **savings_funds** — a goal-directed savings target with an optional amount
  and deadline.
- **savings_modules** — sub-buckets within a fund, each with its own target.
  Contributions are recorded at module level and roll up.
- **savings_contributions** — one row per contribution, linking the source
  transaction to the target module.
- **amortisation** — a recurring or irregular cost and the monthly figure it
  contributes to cash flow, so that an annual charge appears as twelve monthly
  impacts rather than one spike *(FR.01.2.3)*.

**Invariants**

- **Every monetary amount is an integer in the currency's smallest sub-unit.**
  No floating-point value ever represents money. This is the single most
  load-bearing invariant in the schema: rounding error in money is silent,
  compounding, and destroys trust in every figure derived from it
  *(NFR.05, FR.01.1.3)*.
- A transfer between the owner's own accounts is **not spending** and must
  never appear as such in a spending report. This is the most common way a
  personal finance figure goes wrong.
- **At most one active budget per category at a time.** Superseding one
  deactivates the previous.
- A converted figure is never stored without the rate and the as-of time that
  produced it *(FR.01.3.2)*.
- Category totals for a period reconcile exactly to that period's total
  *(NFR.06)*. Exactly, not approximately — a consequence of integer amounts.
- **Zakat holds no tables.** It is computed at request time from current
  holdings against the prevailing threshold, and a computation whose inputs
  could not be retrieved returns a failure rather than a figure
  *(FR.01.5.1, FR.01.5.2)*. Storing a zakat figure would create a number that
  is correct only at the instant it was written.
- Retention: `[PENDING — SRS Q5]`.

---

## Cross-cutting

- **Time** is stored in UTC throughout. A date the owner stated and a timestamp
  the system recorded are different things and are kept distinct — a
  transaction's date is not its insertion time.
- **The content's own date** and the record's timestamps are separate. A note
  published in 2019 and captured today has both.
- **Migrations are forward-only and numbered.** No down migrations: a rollback
  that silently discards rows is worse than a forward fix.
- **Nothing is hard-deleted where the audit record refers to it.** The record
  must remain interpretable.

---

## Open items

| # | Item | Affects |
| :--- | :--- | :--- |
| 1 | Retention per category. `[PENDING — SRS Q5]` | `audit`, `personal.journal`, `finance_personal`, operational records |
| 2 | Whether goals and journal belong in the first cycle at all. `[PENDING — SRS Q10]` | `personal.goals`, `personal.journal` — both may be out of scope |
| 3 | Whether zakat is Obligation-class. `[PENDING — SRS Q1]` | Raises the correctness bar on every amount in `finance_personal` |
