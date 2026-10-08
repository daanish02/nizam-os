---
title: "Spec 006 — Investment Review"
status: DRAFT
version: 0.1.0
date: 2026-09-10
scope: personal
---

# Spec: Investment Review

> **File:** `docs/specs-new/006-investment.md`
> **Scope:** CP.07 — brokerage reads, research delegation, compliance screening,
> and preserving the reasoning. **Read-and-advise only.** Owns no schema.
> **Builds on:**
>
> - `docs/SRS.md` §5 CP.07 — FR.07.1.1..FR.07.4.2
> - `docs/specs-new/003-math.md` — every ratio and figure
> - `docs/specs-new/001-knowledge.md` — screening output is a vault note
> - `docs/THREAT-MODEL.md` — TB-9; threats T-28, T-29, T-31

**Two structural decisions define this domain.**

**No order capability exists anywhere.** Not disabled, not approval-gated —
absent from the service *(FR.07.1.2, T-28)*. A capability that exists and is
gated can be ungated by a configuration change; one that was never written
cannot.

**No holdings are stored.** The brokerage is the sole record *(FR.07.1.3,
T-29)*. A stored copy is a figure that can silently diverge from the truth, and
an investment decision made on a stale position is exactly the failure this
capability exists to prevent.

---

## Open Questions

- [ ] **Q-I1 — the compliance constraints themselves.** Screening needs the
      owner's actual thresholds: which business activities disqualify outright,
      the debt ratio limit, the interest-income limit, the receivables limit,
      and the denominator each is measured against (market capitalisation or
      total assets — the two give materially different answers). **This is a
      religious determination the owner must supply; it is deliberately not
      invented here.** — Owner decides. **Blocking for `screen_candidate`.**
- [ ] **Q-I2 — purification basis.** FR.07.3.4 requires computing a purification
      obligation. The ratio applied, the period covered, and whether it accrues
      per holding period or per dividend are unspecified. — Owner decides.
- [ ] **Q-I3 — filing data source.** Screening needs financial statement figures.
      Whether these come from the brokerage, a separate data provider, or the
      researcher reading filings directly is undecided, and it determines
      whether figures carry usable provenance. — Owner decides.
- [ ] **Q-I4 — real return basis.** An inflation measure for real-return
      analysis is unnamed. — Owner decides.
- [ ] **Q-I5 — screening staleness.** How long a screening result stays valid
      before re-screening is required. Financial ratios change quarterly; a
      year-old screening is not evidence about today. — Owner decides.

---

## Shared Types

```
Position
  symbol:         string
  name:           string
  quantity:       ScaledInt      — fractional shares exist; not an integer
  market_value:   Money
  currency:       string
  as_of:          timestamp      MANDATORY on every position  (FR.07.1.1)

ScreeningVerdict  enum(pass, fail, inconclusive)
                  — inconclusive is NOT a soft fail. It means a required input
                    was unavailable, and it must never be presented as either
                    a pass or a fail  (FR.07.3.3)

ConstraintResult
  constraint:     string
  verdict:        ScreeningVerdict
  measured:       ScaledInt?     the figure judged, null when inconclusive
  threshold:      ScaledInt?
  basis:          string         what the ratio was measured against  [Q-I1]
  provenance:     Provenance     source and as-of of every input figure
  reason:         string         why this verdict, in the owner's terms

Provenance                       as defined in 002-finance
  as_of:      timestamp
  source:     string
  inputs:     string[]
```

---

## MCP Tools

All reads. **This domain has no write tools** — its only persistence is a vault
note written through `001-knowledge`, which carries its own approval gate.

### `list_positions`

**Description:** Report current holdings from the brokerage.

**Inputs:** none

**Logic:**

1. Query the brokerage.
2. **Return figures exactly as retrieved, with the retrieval time.** No caching,
   no storage, no reconciliation against a local copy — there is no local copy
   *(F.07.1.3)*.
3. On unavailability → `BROKERAGE_UNAVAILABLE`. **Do not return a previous
   result** *(T-29)*.

**Output:** `as_of`, `positions: Position[]`, `total_value: Money?`,
`total_withheld_reason?`

The total is withheld when positions span currencies and a rate is unavailable —
the same rule as `002-finance report_position` *(F-11)*.

**Error cases:**

| Condition | Error | Notes |
| :--- | :--- | :--- |
| Brokerage unreachable | `BROKERAGE_UNAVAILABLE` | **Never serve a cached position** |
| Credential rejected | `BROKERAGE_AUTH_FAILED` | Escalate to the owner |

**Idempotent:** yes.

---

### `get_watchlist`

**Description:** Report the owner's watchlist from the brokerage.

**Inputs:** none. **Output:** `as_of`, `entries[]`.
**Error cases:** as `list_positions`. **Idempotent:** yes.

---

### `get_market_data`

**Description:** Current price and basic market figures for a symbol.

**Inputs:** `symbol: string required`

**Logic:** validate the symbol form → `INVALID_SYMBOL`; query; **return with
`as_of`**. A price without its timestamp may not be presented *(FR.07.3.2)*.

**Output:** `symbol`, `price: Money`, `as_of`, `currency`, `market_cap: Money?`

**Idempotent:** yes.

---

### `get_financials`   `[Q-I3]`

**Description:** Financial statement figures for a symbol, used by screening.

**Inputs:** `symbol`, `period: string optional — annual | quarterly`

**Logic:**

1. Retrieve the figures.
2. **Every figure carries its source, its as-of date, and the reporting period
   it belongs to** *(FR.07.3.2)*. A ratio computed from figures of different
   periods is meaningless, so the period must travel with the number.
3. **Any figure that cannot be retrieved is returned as null with a reason —
   never as zero** *(T-31)*. Zero debt and unknown debt produce opposite
   screening verdicts.

**Output:**

```
symbol, period, reported_for: date
figures: { total_debt, market_cap, total_assets, cash_and_equivalents,
           interest_income, total_revenue, receivables }
           each: {value: Money?, available: boolean, reason?}
provenance: Provenance
```

**Error cases:** `INVALID_SYMBOL`, `FINANCIALS_UNAVAILABLE`,
`SYMBOL_NOT_COVERED`.

**Idempotent:** yes.

---

### `screen_candidate`   `[Q-I1]`

**Description:** Screen a symbol against the owner's compliance constraints and
report each constraint individually.

**When NOT to call:** Do not call when the constraints are unconfigured — it
will refuse, and refusing is correct.

**Inputs:** `symbol: string required`, `as_of: date optional default=today`

**Logic (execution order):**

1. If constraints are unconfigured → `CONSTRAINTS_UNDEFINED` `[Q-I1]`. **Do not
   apply a conventional default.** These are religious determinations and a
   guessed threshold produces a confidently wrong verdict on a question the
   owner cares about precisely because it is not arbitrary.
2. Retrieve financials *(`get_financials`)* and market data.
3. **Business-activity screen first.** A disqualifying activity is an immediate
   `fail` and the ratio screens are not run — a company excluded on activity is
   excluded regardless of its balance sheet, and running the ratios anyway
   implies they could rescue it.
4. For each ratio constraint, in order:
   - If any required input is unavailable → this constraint is **`inconclusive`**,
     naming the missing input. **Not a fail** *(FR.07.3.3)*.
   - Otherwise compute via `003-math compute_ratio`. **If the denominator is
     zero, the ratio is `undefined` and the constraint is `inconclusive`** —
     never zero, never a pass *(M-5)*.
   - Compare against the threshold; record measured value, threshold, basis and
     provenance.
5. **Aggregate.** Any `fail` → overall `fail`. Otherwise any `inconclusive` →
   overall **`inconclusive`**. All `pass` → overall `pass`. **An inconclusive
   constraint never aggregates into a pass** — that is the rule that keeps a
   missing figure from becoming an approval.
6. If overall `pass` and impermissible income is present, compute the
   purification obligation via `003-math` `[Q-I2]` *(FR.07.3.4)*.
7. **Return advice, never a decision.** The output states explicitly that
   execution rests with the owner *(FR.07.4.2)*.

**Output:**

```
symbol, as_of
verdict:          ScreeningVerdict
constraints:      ConstraintResult[]     — every constraint, individually
purification:     {obligation: Money, ratio: ScaledInt, period: string}?
inconclusive_inputs: string[]            — what was missing, if anything
advice_only:      true                   — always. Execution is the owner's
provenance:       Provenance
```

**Error cases:**

| Condition | Error | Notes |
| :--- | :--- | :--- |
| Constraints unconfigured | `CONSTRAINTS_UNDEFINED` | `[Q-I1]`. Do not default |
| Symbol not covered | `SYMBOL_NOT_COVERED` | Tell the owner |
| All financials unavailable | `FINANCIALS_UNAVAILABLE` | **Not a fail.** Inconclusive |

**Idempotent:** yes. Computes and stores nothing.

---

### `compute_real_return`   `[Q-I4]`

**Description:** Nominal return adjusted for inflation over a period.

**Inputs:** `nominal_return: ScaledInt`, `period: DateRange`,
`inflation_measure: string optional`

**Logic:** obtain the inflation figure for the period; **if unavailable, refuse
rather than assuming zero** *(T-31)* → `INFLATION_UNAVAILABLE`; compute via
`003-math`; return with provenance.

**Output:** `real_return: ScaledInt`, `inflation_applied`, `provenance`

**Idempotent:** yes.

---

## Research delegation

The investor delegates reading to the researcher and keeps judgment for itself
*(FR.07.2.1, FR.07.2.2)*.

**Trigger:** a screening or assessment needs material beyond retrievable figures
— an annual report, industry context, a filing narrative.

**Steps:**

1. **Delegate** — Actor: investor — a bounded research task naming exactly what
   is needed. Bounds per `005-agent-runtime` `[Q-A2]`.
2. **Gather** — Actor: researcher — **work through files rather than holding
   everything in context** *(FR.07.2.2)*. A multi-source task that accumulates
   in context truncates its own earliest inputs and produces a synthesis missing
   what it started from.
3. **Synthesise** — Actor: researcher — return an assessment **citing every
   source** *(FR.07.2.1)*.
4. **Judge** — Actor: investor — the researcher gathers; the investor decides.
   The separation is deliberate: the party that read the material is not the
   party that judges it.
5. **Report** — Actor: investor — synthesise for the owner. **The sub-agent
   never addresses the owner directly** *(005-agent-runtime, delegation rule 4)*.

**Untrusted content.** A researcher's output is derived from fetched material
and is untrusted on the same footing *(T-40, C-19)*. It informs an assessment;
it never becomes an action except through the approval gate.

---

## Persisting the reasoning

**Trigger:** a screening or assessment the owner wants preserved
*(FR.07.4.1)*.

**Steps:**

1. Compose a note: verdict, every constraint with its figure and threshold,
   every input's provenance, and what was inconclusive and why.
2. Write through `001-knowledge add_note` with `source=screening`.
3. **The knowledge domain's approval gate applies** — this domain has no
   separate write path.

**Why the reasoning and not just the verdict:** a verdict alone cannot be
revisited on its merits. Six months later the owner needs to know what the debt
ratio was and where the figure came from, not that the answer was "pass"
*(FR.07.4.1)*.

---

## Schema

**None.** This domain owns no tables and holds no database role.

Positions and watchlist come from the brokerage and are never copied *(T-29)*.
Screening output is a vault note owned by `001-knowledge`. Stated explicitly so
that adding a "cache table for performance" is recognised as breaking the
invariant this domain is built on.

---

## Domain Invariants

- **I-1 — No order capability exists.** Absent, not disabled *(FR.07.1.2)*.
- **I-2 — No holdings stored.** The brokerage is the sole record
  *(FR.07.1.3)*.
- **I-3 — Provenance on every figure.** Source, as-of, and reporting period
  *(FR.07.3.2)*.
- **I-4 — Inconclusive is not fail and never becomes pass.** A missing input
  suspends the verdict *(FR.07.3.3)*.
- **I-5 — Never substitute for a missing figure.** Not zero, not a default, not
  a previous value *(T-31)*.
- **I-6 — Advice, never decision.** Every output states that execution rests
  with the owner *(FR.07.4.2)*.
- **I-7 — Arithmetic via `003-math`.** No ratio computed inline or by a model.
- **I-8 — Researcher output is untrusted content.**

---

## Acceptance Criteria

| # | Criterion | Traces to |
| :--- | :--- | :--- |
| F-01 | Positions match the brokerage, with retrieval time stated | FR.07.1.1 |
| F-02 | **No order-placing capability exists in the service's tool list** | FR.07.1.2, I-1, T-28 |
| F-03 | **No table or cache holds a position figure** | FR.07.1.3, I-2, T-29 |
| F-04 | With the brokerage unavailable, no previous result is served | I-2 |
| F-05 | Every constraint is reported individually with its measured figure | FR.07.3.1 |
| F-06 | Every figure carries source, as-of and reporting period | FR.07.3.2, I-3 |
| F-07 | **A missing input yields `inconclusive`, never `fail` and never `pass`** | FR.07.3.3, I-4 |
| F-08 | **An inconclusive constraint prevents an overall `pass`** | I-4 |
| F-09 | **A zero denominator yields `inconclusive`, not a passing zero ratio** | M-5, I-4 |
| F-10 | An unavailable financial figure is null with a reason, never zero | I-5 |
| F-11 | Unconfigured constraints refuse to screen rather than defaulting | Q-I1, I-5 |
| F-12 | A disqualifying activity fails immediately without running ratios | logic step 3 |
| F-13 | Purification states the ratio applied and the period | FR.07.3.4 |
| F-14 | Screening reasoning is retrievable later with its inputs intact | FR.07.4.1 |
| F-15 | **Every assessment states that execution rests with the owner** | FR.07.4.2, I-6 |
| F-16 | A multi-source research task completes without truncating its inputs | FR.07.2.2 |
| F-17 | An assessment cites every source it drew on | FR.07.2.1 |
| F-18 | A sub-agent never addresses the owner directly | delegation rule 4 |
| F-19 | Real return with inflation unavailable refuses rather than assuming zero | I-5 |

---

## Open Items

| # | Item | Blocks |
| :--- | :--- | :--- |
| 1 | The compliance constraints. `[Q-I1]` | `screen_candidate` — **blocking** |
| 2 | Purification basis. `[Q-I2]` | FR.07.3.4 |
| 3 | Filing data source. `[Q-I3]` | `get_financials`, provenance quality |
| 4 | Inflation measure. `[Q-I4]` | `compute_real_return` |
| 5 | Screening staleness. `[Q-I5]` | Whether a stored screening may be reused |
