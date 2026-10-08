---
title: "Spec 002 — Personal Finance"
status: DRAFT
version: 0.1.0
date: 2026-09-10
scope: personal
---

# Spec: Personal Finance

> **File:** `docs/specs-new/002-finance.md`
> **Scope:** CP.01 — recording what moved, reporting where it went, current
> position, intended versus actual, and the zakat obligation. Owns the
> `finance_personal` schema.
> **Builds on:**
>
> - `docs/SRS.md` §5 CP.01 — FR.01.1.1 through FR.01.5.2
> - `docs/SCHEMAS.md` — `finance_personal` entities and invariants
> - `docs/SERVICES.md` — the `finance` contract
> - `docs/specs-new/003-math.md` — every arithmetic operation used here
> - `docs/THREAT-MODEL.md` — T-31 (figures from unretrieved inputs)

**The governing rule of this domain.** Every monetary value is an integer in the
currency's smallest sub-unit. No floating-point value represents money anywhere
— not in storage, not in transit, not in a calculation, not in a test fixture.
Rounding error in money is silent, compounds, and destroys trust in every
derived figure, which would defeat CP.01 entirely *(NFR.05, FR.01.1.3)*.

---

## Open Questions

- [ ] **Q-F1 — is zakat an Obligation?** `[PENDING — SRS Q1]`. Currently
      classed as an Expectation. If it is an Obligation, the correctness bar
      rises across this whole domain: every arithmetic path needs an
      independently-derived test, and `calculate_zakat` needs a second
      verification path. — Owner decides.
- [ ] **Q-F2 — how do balances become known?** FR.01.3.1 requires reporting the
      current balance of every account. Nothing in the requirements says whether
      a balance is **derived** from an opening figure plus recorded transactions,
      or **asserted** by the owner periodically. This spec assumes **derived,
      with a reconciliation mechanism** — see `AccountBalance` and Invariant
      F-9. If the owner will not record every transaction, derived balances
      drift and the assumption is wrong. — Owner decides. **Blocking for
      `report_position`.**
- [ ] **Q-F3 — exchange rate source and staleness.** FR.01.3.2 requires a rate
      and its as-of time on every converted figure. The source is unnamed and
      the maximum tolerable staleness is unset. Named `RATE_MAX_AGE` below. —
      Owner decides.
- [ ] **Q-F4 — zakat scope.** Which account types and asset classes are
      zakatable, the nisab basis (gold or silver), and the hawl (lunar-year
      holding period) treatment are all unspecified. `NISAB_GOLD_GRAMS` has a
      conventional default of 85; the rest do not. **This is a religious
      determination, not a technical one.** — Owner decides.
- [ ] **Q-F5 — inference-down behaviour.** `[PENDING — SRS Q2]`. Recording and
      reporting need no model reasoning once parsed. Whether these tools stay
      available when inference is down is unresolved. — Owner decides.

---

## Shared Types

```
Money                             the only representation of a monetary value
  amount:     integer             in the currency's smallest sub-unit.
                                  NEVER a float, NEVER a decimal string
  currency:   string              ISO 4217, uppercase, 3 letters
                                  — the pair is atomic; an amount without its
                                    currency is meaningless and must never be
                                    passed, stored or returned alone

SubUnitScale                      how many sub-units make one major unit
                                  — AED->fils 100, USD->cents 100,
                                    KWD->fils 1000, JPY->none 1
                                  — a per-currency table, not a global constant.
                                    Assuming 100 is wrong for roughly a dozen
                                    currencies and wrong silently

Direction     enum(debit, credit)
              — debit:  value leaving an account
              — credit: value entering an account
              — a transfer is NOT a direction; it is its own entity  (F-2)

AccountType   enum(current, savings, cash, credit, investment)
              — credit accounts carry a negative balance when used;
                the sign is not an error

TxnCategory                       controlled, owner-defined vocabulary
                                  — enforced at write time. An unrecognised
                                    category is refused, never invented  (FR.01.1.2)

DateRange
  from:       date                inclusive
  to:         date                inclusive
                                  — inclusive at both ends, stated because
                                    half-open ranges silently drop a day's
                                    spending at period boundaries

FxRate
  pair:       string              e.g. "AED/USD"
  rate:       integer             scaled integer, with `scale`
  scale:      integer             decimal places the rate is scaled by
  as_of:      timestamp           when the rate was published
  source:     string              who published it
                                  — a rate without as_of and source may not be
                                    presented to the owner  (FR.01.3.2)

Provenance                        attached to every derived financial figure
  as_of:      timestamp
  source:     string
  inputs:     string[]            which inputs the figure was computed from
```

---

## MCP Tools

Reads execute freely. Every write is approval-gated *(FR.06.2.1)*.

### `record_transaction`

**Description:** Record a single movement of money into or out of one account.
Use when the owner states a payment, a purchase, or income received.

**When NOT to call:** Do not call for a movement between two of the owner's own
accounts — use `record_transfer`. Recording a transfer as two transactions
double-counts it as both spending and income *(F-2)*.

**Inputs:**

```
amount_minor:  integer   required  — in the currency's sub-unit. Positive
currency:      string    required  — ISO 4217
account:       string    required  — account name or id
direction:     string    required  — debit | credit
category:      string    required  — must exist in the owner's vocabulary
occurred_on:   date      optional  default=today  — when it HAPPENED
counterparty:  string    optional  — merchant or payer
note:          string    optional
fx_rate:       object    optional  — FxRate, required when currency differs
                                     from the account's currency
approved:      boolean   optional  default=false
```

**`amount_minor` is always positive.** Direction carries the sign. A signed
amount plus a direction gives two sources of truth for one fact, and they
eventually disagree.

**Logic (execution order):**

1. Validate `amount_minor` is a positive integer → `INVALID_AMOUNT`. **Reject a
   non-integer outright**; do not round. A caller sending `10.5` has a
   floating-point value somewhere upstream and that is a defect to surface, not
   to absorb *(NFR.05)*.
2. Validate `currency` is ISO 4217 and known to the sub-unit table →
   `UNKNOWN_CURRENCY`.
3. Resolve `account` → `ACCOUNT_NOT_FOUND`. Reject a closed account →
   `ACCOUNT_CLOSED`.
4. Validate `direction` → `INVALID_DIRECTION`.
5. Validate `category` against the owner's vocabulary → `UNKNOWN_CATEGORY`,
   listing valid values. **Never invent or fuzzy-match a category**
   *(FR.01.1.2)*: a silently reclassified transaction makes every category total
   wrong in a way nothing surfaces.
6. If `currency` differs from the account's currency, require `fx_rate` →
   `FX_RATE_REQUIRED`. Reject a rate older than `RATE_MAX_AGE` `[Q-F3]` →
   `FX_RATE_STALE`.
7. Reject `occurred_on` in the future → `FUTURE_DATE`.
8. **If `approved` is false:** return the parsed interpretation for the owner to
   confirm — amount in major units for readability, account, category,
   direction, date. Persist nothing. Stop.
9. Insert the transaction. Write the audit row.
10. Return.

**Output — draft:**

```
status:       "draft"
parsed:       amount_display, currency, account, direction,
              category, occurred_on, counterparty?
message:      string
```

**Output — recorded:**

```
status:        "recorded"
id:            integer
account_balance_after:  Money   — the account's balance after this  [Q-F2]
```

**Error cases:**

| Condition | Error returned | Notes |
| :--- | :--- | :--- |
| Amount not a positive integer | `INVALID_AMOUNT`: "Amount must be a positive integer in sub-units." | **Do not round.** Model restates in sub-units |
| Currency unknown | `UNKNOWN_CURRENCY` | — |
| Account not found | `ACCOUNT_NOT_FOUND`: "...Known: <list>." | Model re-picks |
| Account closed | `ACCOUNT_CLOSED` | Model asks the owner |
| Category unknown | `UNKNOWN_CATEGORY`: "...Valid: <list>." | Model re-picks or asks the owner to define one |
| FX rate needed, absent | `FX_RATE_REQUIRED` | Model fetches a rate first |
| FX rate stale | `FX_RATE_STALE`: "Rate is <n> old; max <RATE_MAX_AGE>." | Model fetches a current rate |
| Date in the future | `FUTURE_DATE` | Model confirms the date |
| Datastore unavailable | `STORE_UNAVAILABLE` | **Do not retry.** Never report a recording that did not happen |

**Idempotent:** no. Two approved calls create two transactions — correct, since
identical purchases genuinely recur. Duplicate detection is the owner's, via the
draft.

---

### `record_transfer`

**Description:** Record a movement between two accounts the owner holds.

**When NOT to call:** Never for money leaving the owner's control entirely —
that is a transaction.

**Inputs:**

```
from_account:      string    required
to_account:        string    required  — must differ from from_account
sent_minor:        integer   required  — leaving, in the source currency's sub-unit
received_minor:    integer   required  — arriving, in the destination currency's sub-unit
fee_minor:         integer   optional  default=0
fee_currency:      string    optional  default=source account's currency
fx_rate:           object    optional  — FxRate, required when currencies differ
occurred_on:       date      optional  default=today
approved:          boolean   optional  default=false
```

**Sent and received are recorded separately, always** — not one amount plus a
rate. In a cross-currency transfer they are genuinely two facts, and deriving
one from the other loses the actual settled amount to rounding
*(FR.01.1.4)*. Fee is separate again, because a fee is an expense while the
transfer itself is not.

**Logic:**

1. Validate both amounts positive integers → `INVALID_AMOUNT`.
2. Resolve both accounts → `ACCOUNT_NOT_FOUND`. Reject identical →
   `SAME_ACCOUNT`.
3. If currencies differ, require `fx_rate` → `FX_RATE_REQUIRED`; reject stale
   → `FX_RATE_STALE`.
4. If currencies match, require `sent_minor == received_minor + fee_minor` when
   the fee is in the same currency → `TRANSFER_UNBALANCED`. **A same-currency
   transfer that does not balance is an error, not a rounding artefact.**
5. Reject future dates → `FUTURE_DATE`.
6. **If not approved:** return the interpretation. Persist nothing. Stop.
7. Insert one transfer row — **not two transactions** *(F-2)*. Insert the fee as
   a transaction categorised as a fee, if non-zero. Write audit rows.
8. Return.

**Output:** `status`, `id`, both balances after.

**Error cases:** `INVALID_AMOUNT`, `ACCOUNT_NOT_FOUND`, `SAME_ACCOUNT`,
`FX_RATE_REQUIRED`, `FX_RATE_STALE`, `TRANSFER_UNBALANCED`, `FUTURE_DATE`,
`STORE_UNAVAILABLE`.

**Idempotent:** no.

---

### `report_spending`

**Description:** Report what was spent over a period, broken down by category,
optionally against the comparable prior period.

**When NOT to call:** Do not call for balances — use `report_position`.

**Inputs:**

```
from:            date      required
to:              date      required  — inclusive
compare:         boolean   optional  default=true   — against the prior period
amortise:        boolean   optional  default=true   — spread irregular costs
currency:        string    optional  default=owner's reporting currency
categories:      string[]  optional  — restrict to these
```

**Logic:**

1. Validate `from <= to` → `INVALID_RANGE`.
2. Select debit transactions in range. **Exclude transfers entirely** — a
   movement between the owner's own accounts is not spending, and including it
   is the single most common way a personal finance figure goes wrong *(F-2)*.
3. Exclude the transfer-fee category from spending totals? **No — fees are
   spending.** The transfer is not; its fee is.
4. If any transaction's currency differs from the reporting currency, convert
   using the rate recorded **on that transaction**, not a current rate. A past
   expense is worth what it cost then.
5. If `amortise`, add each active amortisation entry's monthly impact to its
   category for each month in range *(FR.01.2.3)*.
6. If `compare`, repeat for the immediately prior period of equal length.
7. Compute per-category totals and the period total via `003-math`.
8. **Assert the reconciliation invariant** before returning: the sum of category
   totals equals the period total exactly *(F-5, NFR.06)*. A mismatch is an
   internal error, not a rounding tolerance → `RECONCILIATION_FAILED`.
9. Return with provenance.

**Output:**

```
period:            DateRange
currency:          string
total:             Money
by_category:       [ {category, total: Money, share_bp: integer} ]
                   — share in basis points (integer), not a float percentage
comparison:        optional
                     prior_period, prior_total,
                     delta: Money, delta_bp: integer
amortised_included: boolean
provenance:        Provenance
```

**Error cases:**

| Condition | Error returned | Notes |
| :--- | :--- | :--- |
| `from` after `to` | `INVALID_RANGE` | — |
| Category unknown | `UNKNOWN_CATEGORY` | — |
| A transaction needs conversion but has no recorded rate | `MISSING_HISTORICAL_RATE` | **Do not substitute a current rate.** Report which transactions |
| Category totals do not sum to the total | `RECONCILIATION_FAILED` | **Internal defect.** Never return a figure that does not reconcile |

**Idempotent:** yes.

---

### `report_position`

**Description:** Report the balance of every account and a single total.

**Inputs:**

```
currency:      string   optional  default=owner's reporting currency
as_of:         date     optional  default=today
include_closed: boolean optional  default=false
```

**Logic:**

1. For each account, compute the balance `[Q-F2]`.
2. For accounts not in the reporting currency, obtain a current rate. Reject a
   rate older than `RATE_MAX_AGE` `[Q-F3]` → `FX_RATE_STALE`.
3. **If any required rate is unavailable, do not return a total.** Return
   per-account balances with the total explicitly withheld and the reason named
   *(FR.01.3.2, AC.10, T-31)*. A total computed from a guessed rate is worse
   than no total.
4. Sum via `003-math`.
5. Return with the rate and as-of time for every conversion *(FR.01.3.2)*.

**Output:**

```
as_of:        date
currency:     string
accounts:     [ {account, type, balance: Money,
                 converted: Money?, rate: FxRate?} ]
total:        Money?      — ABSENT when any rate was unavailable
total_withheld_reason: string?
provenance:   Provenance
```

**Error cases:** `FX_RATE_STALE`, `RATE_UNAVAILABLE` (total withheld, not an
error), `STORE_UNAVAILABLE`.

**Idempotent:** yes.

---

### `manage_budget`

**Description:** Set an intended monthly ceiling for a category, or report
actual spending against intent.

**Inputs:**

```
action:        string   required  — set | report
category:      string   required for set
limit_minor:   integer  required for set
currency:      string   required for set
month:         string   optional  — YYYY-MM, default current
approved:      boolean  optional  default=false  — for set only
```

**Logic — `set`:**

1. Validate category and amount as elsewhere.
2. **If an active budget exists for that category, deactivate it before
   inserting** — at most one active budget per category at a time *(F-6)*. Two
   active ceilings for one category means no ceiling.
3. Approval-gated; draft shows what is being superseded.

**Logic — `report`:**

1. Sum actual spending per budgeted category for the month, per
   `report_spending` rules.
2. Return actual against limit, with remaining and the proportion consumed in
   basis points.
3. **Surface an exceeded category during the month, not after it closes**
   *(FR.01.4.2)* — the report is usable mid-period by design.

**Output — report:**

```
month:       string
budgets:     [ {category, limit: Money, actual: Money,
                remaining: Money, consumed_bp: integer, exceeded: boolean} ]
```

**Error cases:** `UNKNOWN_CATEGORY`, `INVALID_AMOUNT`, `INVALID_MONTH`.

**Idempotent:** `report` yes. `set` converges — the same set twice leaves one
active budget.

---

### `calculate_zakat`

**Description:** Compute the zakat obligation from current zakatable holdings
against the prevailing nisab threshold.

**When NOT to call:** Do not call when any holding figure is unavailable — the
tool will refuse, and refusing is correct.

**Inputs:**

```
as_of:            date     optional  default=today
nisab_basis:      string   optional  — gold | silver   [Q-F4]
```

**Logic (execution order):**

1. Determine zakatable holdings `[Q-F4]`. Which account types and asset classes
   qualify is a religious determination and is not decided here.
2. **Obtain the current metal price for the nisab basis. If it cannot be
   retrieved, stop and return `NISAB_UNAVAILABLE`. Do not use a cached price, a
   default, or a previous value** *(FR.01.5.2, AC.10, T-31)*. This is the single
   most important rule in this tool: a zakat figure computed from a stale
   threshold is confidently wrong about a religious obligation, which is worse
   than no figure.
3. Compute the nisab threshold via `003-math` from the price and
   `NISAB_GOLD_GRAMS` `[Q-F4]`.
4. If holdings are below nisab, return `obligation = 0` **with the threshold and
   holdings stated** — the owner needs to see the comparison, not just the zero.
5. If at or above, compute the obligation at the applicable rate via `003-math`.
6. **Round in the owner's favour** — the payable obligation rounds up to the
   nearest sub-unit, never down. Under-paying an obligation through a rounding
   convention is not an acceptable default.
7. Return with full provenance: threshold, its price, its source, its as-of
   time, and every holding included *(FR.01.5.1)*.
8. **Store nothing.** Zakat has no tables. A stored figure is correct only at
   the instant it was written *(F-8)*.

**Output:**

```
as_of:            date
basis:            string
nisab:            Money
nisab_source:     Provenance     — price, source, as_of. MANDATORY
holdings:         [ {account, balance: Money, included: boolean, reason?} ]
zakatable_total:  Money
above_nisab:      boolean
obligation:       Money          — 0 when below nisab
rate_applied:     string
provenance:       Provenance
```

**Error cases:**

| Condition | Error returned | Notes |
| :--- | :--- | :--- |
| Metal price unavailable | `NISAB_UNAVAILABLE`: "Cannot determine nisab; no figure produced." | **Never substitute.** Tell the owner why |
| A holding balance is unavailable | `HOLDINGS_INCOMPLETE`: "Cannot value <account>." | Refuse rather than under-report |
| Zakatable scope undefined | `SCOPE_UNDEFINED` | `[Q-F4]` unresolved |
| Price older than tolerance | `NISAB_STALE` | Refuse |

**Idempotent:** yes. Purely computational, stores nothing.

---

## Schema

### `Account` → `finance_personal.accounts`

```
id:           bigserial     PK
name:         text          not-null, unique
currency:     char(3)       not-null, immutable
                            — immutable: changing an account's currency
                              retroactively reinterprets every transaction on it
type:         text          not-null  — AccountType
opening_minor: bigint       not-null, default 0
                            — the balance before the first recorded transaction  [Q-F2]
opening_on:   date          not-null
zakatable:    boolean       not-null, default true   [Q-F4]
closed_at:    timestamptz   nullable
created_at:   timestamptz   not-null, default now()
```

### `Transaction` → `finance_personal.transactions`

```
id:              bigserial     PK
account_id:      bigint        not-null, FK->accounts.id, restrict
amount_minor:    bigint        not-null, CHECK > 0
                               — always positive; direction carries the sign
currency:        char(3)       not-null
direction:       text          not-null  — debit | credit
category_id:     bigint        not-null, FK->categories.id, restrict
counterparty:    text          nullable
occurred_on:     date          not-null
                               — when it HAPPENED. Distinct from created_at,
                                 which is when it was recorded. The owner
                                 records yesterday's lunch today
fx_rate_minor:   bigint        nullable   — the rate AT THE TIME, scaled
fx_rate_scale:   integer       nullable
fx_as_of:        timestamptz   nullable
fx_source:       text          nullable
                               — the four fx_* columns are all-or-nothing;
                                 a rate without provenance may not be displayed
transfer_id:     bigint        nullable, FK->transfers.id
                               — set only on a transfer's fee row, so the fee
                                 traces to its transfer
note:            text          nullable
created_at:      timestamptz   not-null, default now()
```

### `Transfer` → `finance_personal.transfers`

```
id:                bigserial   PK
from_account_id:   bigint      not-null, FK->accounts.id, restrict
to_account_id:     bigint      not-null, FK->accounts.id, restrict
                               CHECK from_account_id <> to_account_id
sent_minor:        bigint      not-null, CHECK > 0
sent_currency:     char(3)     not-null
received_minor:    bigint      not-null, CHECK > 0
received_currency: char(3)     not-null
                               — sent and received stored separately; neither
                                 derived from the other  (FR.01.1.4)
fee_minor:         bigint      not-null, default 0
fee_currency:      char(3)     not-null
fx_rate_minor:     bigint      nullable
fx_rate_scale:     integer     nullable
occurred_on:       date        not-null
created_at:        timestamptz not-null, default now()
```

### `Category` → `finance_personal.categories`

```
id:        bigserial   PK
name:      text        not-null, unique
kind:      text        not-null  — spending | income | fee | transfer_internal
active:    boolean     not-null, default true
                       — deactivated, never deleted: historical transactions
                         must keep resolving their category
```

### `Budget` → `finance_personal.budgets`

```
id:            bigserial   PK
category_id:   bigint      not-null, FK->categories.id
month:         date        not-null  — first day of the month
limit_minor:   bigint      not-null, CHECK > 0
currency:      char(3)     not-null
active:        boolean     not-null, default true
created_at:    timestamptz not-null, default now()
```

Partial unique index on `(category_id, month) WHERE active` — **at most one
active budget per category per month, enforced by the database** *(F-6)*. The
charter puts this logic in the service; a partial unique index makes it
unbreakable, which is strictly better for an invariant this cheap to enforce.

### `Amortisation` → `finance_personal.amortisation`

```
id:              bigserial   PK
description:     text        not-null
category_id:     bigint      not-null, FK->categories.id
full_minor:      bigint      not-null, CHECK > 0
currency:        char(3)     not-null
period:          text        not-null  — annual | quarterly | monthly
monthly_minor:   bigint      not-null
                             — the precomputed monthly impact. Stored rather
                               than derived so a report is reproducible even if
                               the rounding convention later changes
starts_on:       date        not-null
ends_on:         date        nullable
active:          boolean     not-null, default true
```

### Savings

`savings_funds`, `savings_modules`, `savings_contributions` — a fund holds
modules, a module accumulates contributions, a contribution links to the
transaction that funded it. Full field detail deferred: savings appear in
`docs/SCHEMAS.md` but no FR in `docs/SRS.md` covers them, so **there is no
requirement to specify against.** Raised as an open item below rather than
invented here.

**Indexes:**

| Name | Fields | Type | Access pattern |
| :--- | :--- | :--- | :--- |
| `txn_account_date_idx` | `(account_id, occurred_on)` | btree | Balance derivation per account |
| `txn_date_idx` | `occurred_on` | btree | Period selection in `report_spending` |
| `txn_category_date_idx` | `(category_id, occurred_on)` | btree | Category totals |
| `budget_active_uniq` | `(category_id, month) WHERE active` | partial unique | Enforces F-6 |
| `transfer_accounts_idx` | `(from_account_id, to_account_id)` | btree | Transfer history |

**Invariants:**

- **F-1 — Integer money.** Every monetary column is an integer in sub-units.
  No numeric, no float, no decimal-as-text. *(NFR.05)*
- **F-2 — Transfers are not spending.** A transfer never appears in a spending
  total. Its fee does. *(FR.01.1.4)*
- **F-3 — Amount and currency are atomic.** Neither is stored, passed or
  returned without the other.
- **F-4 — Provenance for conversions.** A converted figure is never presented
  without its rate and as-of time. *(FR.01.3.2)*
- **F-5 — Exact reconciliation.** Category totals sum exactly to the period
  total. Not within tolerance — exactly. A consequence of F-1. *(NFR.06)*
- **F-6 — One active budget per category per month.** DB-enforced.
- **F-7 — Categories deactivate, never delete.** Historical transactions must
  keep resolving.
- **F-8 — Zakat is computed, never stored.** No table, no cache, no memoisation.
  *(FR.01.5.1)*
- **F-9 — Balance derivation is total.** A balance is opening plus every
  recorded movement. If any movement is missing, the balance is wrong and
  nothing detects it — which is why `[Q-F2]` matters. *(FR.01.3.1)*
- **F-10 — Historical rates for historical figures.** A past transaction
  converts at the rate recorded on it, never at a current rate.
- **F-11 — Refuse rather than guess.** Any figure whose input cannot be
  retrieved is withheld with a reason, never estimated. *(FR.01.5.2, T-31)*

---

## Flows

### Recording from natural language

**Trigger:** the owner states a payment in conversation.

**Steps:**

1. **Parse** — Actor: the assistant — extract amount, currency, account,
   category, counterparty, date from what he said.
   - Ambiguity is resolved by asking, not by guessing. A wrong category is worse
     than a question.
2. **Convert to sub-units** — Actor: the assistant — "50 dirhams" becomes
   `5000` with currency `AED`. **The conversion to sub-units happens once, at
   the boundary**, and nothing downstream sees major units except display.
3. **Draft** — Actor: `finance` — validate everything, return the
   interpretation in readable form.
4. **Present** — Actor: the assistant — show what will be recorded.
   - Decision: approved → step 5; corrected → back to step 1.
5. **Record** — Actor: `finance` — insert, audit, return the new balance.

**End state — success:** one transaction row, one audit row, a balance the owner
saw confirmed.

**End state — failure:** nothing recorded; the owner is told what was wrong.

**Idempotency:** not idempotent by design. The owner's confirmation is the
duplicate check.

---

### Monthly reporting

**Trigger:** the owner asks where his money went, or the evening recap runs.

**Steps:**

1. **Select** — debit transactions in range, transfers excluded *(F-2)*.
2. **Convert** — per-transaction historical rates *(F-10)*.
   - On a missing historical rate: **stop.** Report which transactions cannot be
     valued. Do not substitute *(F-11)*.
3. **Amortise** — add monthly impacts of active amortisation entries.
4. **Aggregate** — per-category totals via `003-math`.
5. **Verify** — assert exact reconciliation *(F-5)*. A mismatch is an internal
   defect and must fail loudly rather than return a plausible number.
6. **Compare** — repeat for the prior period.

**End state — success:** a report whose figures reconcile and whose every
conversion carries provenance.

**End state — failure:** no report, and a statement of which inputs were
missing. **Never a partial report presented as complete.**

---

## Domain Invariants

- Integer sub-units everywhere. A float touching money anywhere in this domain
  is a defect, including in tests *(F-1)*.
- Every write is approval-gated and audited.
- Every category value is validated against the owner's vocabulary. Never
  invented, never fuzzy-matched *(FR.01.1.2)*.
- Every figure derived from an external input carries provenance, or is withheld
  *(F-4, F-11)*.
- Arithmetic is performed by `003-math`, never inline in this service and never
  by the model *(NFR.05)*.
- Transfers are never spending *(F-2)*.

---

## Acceptance Criteria

| # | Criterion | Traces to |
| :--- | :--- | :--- |
| B-01 | A stated transaction is recorded with every field, defaulting the date to today | FR.01.1.1 |
| B-02 | A non-integer amount is **refused, not rounded** | F-1, NFR.05 |
| B-03 | An unrecognised category is refused with the valid list; never coerced | FR.01.1.2 |
| B-04 | A cross-currency transfer records sent and received separately, with the fee separate | FR.01.1.4 |
| B-05 | **A transfer between the owner's own accounts does not appear in any spending total** | F-2 |
| B-06 | Category totals equal the period total exactly, for every period, with no tolerance | NFR.06, F-5 |
| B-07 | An annual amortised cost appears as a monthly figure, not a single spike | FR.01.2.3 |
| B-08 | No converted figure is returned without its rate and as-of time | FR.01.3.2, F-4 |
| B-09 | A period report converts each transaction at its own historical rate | F-10 |
| B-10 | When a rate is unavailable, the total is **withheld with a reason**, not estimated | F-11, T-31 |
| B-11 | **Zakat with an unavailable metal price returns `NISAB_UNAVAILABLE` and no figure** | FR.01.5.2 |
| B-12 | A zakat result states threshold, price source, as-of time and every holding included | FR.01.5.1 |
| B-13 | Zakat below nisab returns zero **with the comparison shown** | FR.01.5.1 |
| B-14 | The zakat obligation rounds up, never down | fairness convention |
| B-15 | No zakat figure is persisted anywhere | F-8 |
| B-16 | Setting a budget for a category with an active one deactivates the old; the DB rejects two | F-6 |
| B-17 | An exceeded budget is surfaced mid-month | FR.01.4.2 |
| B-18 | A currency whose sub-unit scale is not 100 round-trips exactly | SubUnitScale |
| B-19 | Every successful write produces one audit row naming the actor | FR.06.3.1 |
| B-20 | A closed account rejects new transactions | ACCOUNT_CLOSED |

---

## Open Items

| # | Item | Blocks |
| :--- | :--- | :--- |
| 1 | Zakat class. `[Q-F1 / SRS Q1]` | The correctness bar for the whole domain |
| 2 | Balance derivation model. `[Q-F2]` | `report_position`, F-9 — **blocking** |
| 3 | Rate source and staleness tolerance. `[Q-F3]` | Every conversion |
| 4 | Zakatable scope, nisab basis, hawl. `[Q-F4]` | `calculate_zakat` — **blocking** |
| 5 | Inference-down behaviour. `[Q-F5 / SRS Q2]` | Tool availability |
| 6 | **Savings has no requirement.** It appears in `docs/SCHEMAS.md` with no FR behind it. Either an FR is written or it leaves the schema. | Savings entities |
