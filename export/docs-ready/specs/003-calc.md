---
title: "Spec 003 — Calc"
status: LOCKED
version: 1.0.0
date: 2026-09-26
scope: personal, cycle 1
---

# Spec: Calc

> **File:** `docs/specs/003-calc.md`
> **Package:** `nizam/calc/` — named `calc`, not `math`, to avoid shadowing
> Python's stdlib `math` module in every file that needs both.
> **Scope:** Exact arithmetic as a callable capability. Stateless: no database,
> no writes, no memory, no clock.
> **Builds on:**
>
> - `docs/SRS.md` — NFR.05, NFR.06
> - `docs/ARCHITECTURE.md` — the `nizam-mcp` daemon, `/calc/mcp`
>
> **Exposure — DECIDED 2026-09-26: both.** `nizam/calc/` is a pure library that
> `nizam/finance/` imports in-process, with no network hop. The same functions
> are also mounted as read-class MCP tools at `/calc/mcp`, scoped to Ayah. The
> reason is this service's own premise: the *agent* must not do arithmetic in
> its reasoning either. For example, "what's 450 AED a month for a year?" must
> be a call, not a guess. No approval is ever needed: every calc tool is
> `read`-class and pure.
> - `docs/specs/002-finance.md` — the primary consumer
> - Investment review (cycle 2, deferred) will be the secondary consumer when built

**Why this service exists.** An agent doing arithmetic inside its own reasoning
will eventually get it wrong, and nothing will detect it, because there is no
artefact to check. A model that produces `1247.83` has produced a token
sequence, not a computation. Making arithmetic a call means every financial
figure has a derivation that can be repeated and verified *(NFR.05)*.

**The consequence for callers:** no agent and no other service performs monetary
arithmetic itself. Not addition, not percentages, not rounding. This is a hard
boundary, and the cheapest place to violate it is a "simple" sum.

---

## Open Questions

- [x] **Q-M1 — rounding convention per operation. RESOLVED 2026-09-26: half-even
      (banker's rounding) is the general default** for all money math, applied
      at every computation boundary on integer sub-units. The zakat exception
      stands as already specified below (round up, never down — a religious
      obligation should never be under-computed). Any operation proposed below
      with a different rounding mode must justify the exception explicitly;
      absent a justification, use half-even.

---

## Shared Types

```
Money                        as defined in 002-finance
  amount:    integer         sub-units. NEVER a float
  currency:  string          ISO 4217

ScaledInt                    an exact non-monetary rational
  value:     integer
  scale:     integer         decimal places
                             — 12.34 is {value: 1234, scale: 2}
                             — rates, ratios and percentages all use this.
                               A float rate silently poisons every amount it
                               touches, so no float crosses this boundary either

Rounding   enum(half_up, half_even, up, down)
           — half_up:   ties away from zero. Conventional for display
           — half_even: ties to even. Minimises drift across many operations
           — up:        always away from zero, regardless of remainder
           — down:      always toward zero (truncation)

BasisPoints  integer        — 1/10000. Proportions are returned as integer
                             basis points rather than float percentages, so a
                             share is exact and comparable
```

---

## MCP Tools

Every tool is pure: same inputs, same output, always. No tool reads a clock,
generates randomness, touches a datastore, or has any side effect. This is what
makes the whole service testable by inspection.

### `add_money`

**Description:** Sum a list of monetary amounts exactly.

**When NOT to call:** Do not call for amounts in mixed currencies — convert
first with `convert_currency`, then sum.

**Inputs:**

```
amounts:   Money[]   required  — 1..1000 entries
```

**Logic:**

1. Reject an empty list → `EMPTY_INPUT`. A sum of nothing is ambiguous between
   zero and undefined; the caller should say which it means.
2. Reject mixed currencies → `CURRENCY_MISMATCH`, naming the currencies found.
   **Never convert implicitly** — an implicit conversion needs a rate, and a
   rate carries provenance the caller must supply and display.
3. Reject any non-integer amount → `NON_INTEGER_AMOUNT`.
4. Sum as integers. Detect overflow → `OVERFLOW`.

**Output:** `total: Money`, `count: integer`

**Error cases:**

| Condition | Error | Notes |
| :--- | :--- | :--- |
| Empty list | `EMPTY_INPUT` | Caller states zero explicitly |
| Mixed currencies | `CURRENCY_MISMATCH`: "Found: AED, USD." | Convert first |
| Non-integer amount | `NON_INTEGER_AMOUNT` | **A float reached here — a defect upstream** |
| Sum exceeds range | `OVERFLOW` | — |

**Idempotent:** yes. Pure.

---

### `convert_currency`

**Description:** Convert an amount from one currency to another at a supplied
rate, handling differing sub-unit scales.

**When NOT to call:** Do not call without a rate carrying provenance — the
caller must have obtained one it can display *(FR.01.3.2)*.

**Inputs:**

```
amount:       Money       required
to_currency:  string      required  — ISO 4217
rate:         ScaledInt   required  — units of target per unit of source
rounding:     string      optional  default=half_even   [Q-M1]
```

**The rate is an input, never fetched here.** This service has no network access
and no clock. Fetching a rate would give it a hidden dependency and make it
non-deterministic, which would defeat its entire purpose.

**Logic:**

1. Reject unknown currencies → `UNKNOWN_CURRENCY`.
2. Reject identical source and target → `NO_CONVERSION_NEEDED` (not an error
   condition worth silently passing — the caller has a logic bug).
3. Convert through major units exactly: divide by the source sub-unit scale,
   multiply by the rate, multiply by the target scale — **as one exact integer
   expression, with a single rounding at the end**. Rounding at intermediate
   steps compounds error, and it is the usual way currency conversion goes
   subtly wrong.
4. Apply `rounding` once, at the final step only.
5. Return the result **with the rate and rounding used**, so the caller can show
   its derivation.

**Output:**

```
converted:     Money
rate_applied:  ScaledInt
rounding:      string
```

**Error cases:** `UNKNOWN_CURRENCY`, `NO_CONVERSION_NEEDED`,
`NON_INTEGER_AMOUNT`, `INVALID_RATE` (zero or negative).

**Idempotent:** yes. Pure.

---

### `compute_share`

**Description:** Express a part as a proportion of a whole, in basis points.

**Inputs:**

```
part:    Money   required
whole:   Money   required
```

**Logic:**

1. Reject mismatched currencies → `CURRENCY_MISMATCH`.
2. **If `whole` is zero, return `null` with `undefined: true`** — not zero, not
   an error. A share of nothing is undefined, and returning zero would show the
   owner "0% of spending" where the truthful answer is "there was no spending".
3. Compute `part * 10000 / whole` as integer division with half-even rounding.

**Output:** `share_bp: integer?`, `undefined: boolean`

**Idempotent:** yes. Pure.

---

### `amortise`

**Description:** Spread a recurring cost across the months it covers.

**Inputs:**

```
full:      Money    required
period:    string   required  — annual | quarterly | monthly
rounding:  string   optional  default=half_even
```

**Logic:**

1. Determine the month count: annual 12, quarterly 3, monthly 1.
2. Divide. **Return both the per-month figure and the remainder** — 100 divided
   by 12 does not distribute evenly, and hiding the remainder means twelve
   monthly figures that do not sum to the annual cost. The caller decides where
   the remainder lands; this service refuses to lose it.

**Output:**

```
monthly:    Money
remainder:  Money     — monthly * months + remainder == full, exactly
months:     integer
```

**Idempotent:** yes. Pure.

---

### `compute_zakat`

**Description:** Compute a zakat obligation from a zakatable total and a nisab
threshold.

**When NOT to call:** Do not call without a threshold derived from a retrieved
price. This tool computes; it does not decide whether the inputs are sound
*(that is `002-finance` step 2)*.

**Inputs:**

```
zakatable_total:  Money      required
nisab:            Money      required
rate:             ScaledInt  optional  default=2.5%  as {value: 25, scale: 3}
```

**Logic:**

1. Reject mismatched currencies → `CURRENCY_MISMATCH`.
2. If `zakatable_total < nisab`, return zero obligation with `above_nisab:
   false`. **Return the comparison, not just the zero.**
3. Otherwise compute `zakatable_total * rate`.
4. **Round up, never down.** Settled, not a proposal: under-paying a religious
   obligation through a rounding convention is not an acceptable default. The
   rounding mode is not caller-overridable for this tool.

**Output:**

```
obligation:    Money
above_nisab:   boolean
nisab:         Money         — echoed so the comparison is visible
rate_applied:  ScaledInt
rounding:      "up"
```

**Idempotent:** yes. Pure.

---

### `compute_ratio`

**Description:** Divide two amounts exactly, returning a scaled integer. Used by
investment screening (cycle 2) for debt, interest-income and receivables
ratios. Built in cycle 1 because it is pure and cheap, and Ayah can use it for
ratio questions (e.g. "what share of my spending was food?").

**Inputs:**

```
numerator:    Money      required
denominator:  Money      required
scale:        integer    optional  default=4  — decimal places in the result
```

**Logic:**

1. Reject mismatched currencies → `CURRENCY_MISMATCH`.
2. **If the denominator is zero, return `undefined: true`** — never zero, never
   an error. A screening ratio against a zero denominator is genuinely
   undefined, and reporting it as zero would pass a compliance check that should
   have been inconclusive *(FR.07.3.3)*.
3. Compute at the requested scale with half-even rounding.

**Output:** `ratio: ScaledInt?`, `undefined: boolean`

**Idempotent:** yes. Pure.

---

### `compound`

**Description:** Compound a principal over periods at a rate.

**Inputs:**

```
principal:  Money      required
rate:       ScaledInt  required  — per period
periods:    integer    required  — 0..1200
rounding:   string     optional  default=half_even
```

**Logic:**

1. Reject negative periods → `INVALID_PERIODS`. Zero periods returns the
   principal unchanged.
2. Compute iteratively in exact integer arithmetic, **rounding once at the end**
   rather than each period. Per-period rounding compounds the rounding itself,
   which is a different and larger number.

**Output:** `result: Money`, `growth: Money`

**Idempotent:** yes. Pure.

---

## Schema

**None.** This service owns no data, holds no state, and connects to no
database. It has no database role.

That is worth stating explicitly rather than omitting the section: a stateless
service is a decision, and a future contributor adding a cache to it would break
the property the service exists to provide.

---

## Domain Invariants

- **M-1 — Purity.** Every tool is a pure function. No clock, no randomness, no
  network, no storage, no logging of inputs. Same inputs, same output, forever.
- **M-2 — No floats, at any boundary.** No input, output, or intermediate value
  is a floating-point number. A float arriving here is a defect upstream and is
  rejected rather than absorbed *(NFR.05)*.
- **M-3 — Currency is never implicit.** Two amounts in different currencies are
  never combined without an explicit rate supplied by the caller.
- **M-4 — Round once, at the end.** Intermediate rounding is prohibited in every
  multi-step operation.
- **M-5 — Undefined is not zero.** Division by zero returns `undefined`, never
  zero and never an error. Conflating them produces confidently wrong reports.
- **M-6 — Remainders are returned, never discarded.** Any division that does not
  distribute evenly returns its remainder so the caller can preserve exactness.
- **M-7 — Zakat rounds up.** Not caller-overridable.

---

## Acceptance Criteria

| # | Criterion | Traces to |
| :--- | :--- | :--- |
| C-01 | Summing mixed currencies is refused, naming the currencies | M-3 |
| C-02 | A non-integer amount is refused at every entry point | M-2 |
| C-03 | Conversion between currencies of differing sub-unit scale is exact, verified against independently computed expected values | M-4 |
| C-04 | Conversion rounds once; a multi-step conversion matches a single-expression computation | M-4 |
| C-05 | `compute_share` with a zero whole returns `undefined`, not zero | M-5 |
| C-06 | `compute_ratio` with a zero denominator returns `undefined`, not zero | M-5, FR.07.3.3 |
| C-07 | `amortise` returns a remainder such that `monthly * months + remainder == full` exactly | M-6 |
| C-08 | Zakat below nisab returns zero **and** the comparison | 002-finance B-13 |
| C-09 | Zakat rounds up: a fractional sub-unit obligation rounds away from zero | M-7 |
| C-10 | Zakat rounding cannot be overridden by a caller parameter | M-7 |
| C-11 | `compound` with zero periods returns the principal unchanged | — |
| C-12 | `compound` over N periods rounds once, not N times | M-4 |
| C-13 | Every tool called twice with identical inputs returns byte-identical output | M-1 |
| C-14 | The service holds no database role and opens no connection | schema |
| C-15 | A currency with a sub-unit scale of 1000 round-trips exactly | SubUnitScale |
| C-16 | A currency with no sub-unit round-trips exactly | SubUnitScale |

**Note on testing this domain.** Expected values must come from an independent
source — hand-computed, or from a reference implementation — never from running
the code and recording its output. A pure arithmetic service is exactly where a
tautological test is easiest to write and most useless *(TESTING.md)*.

---

## Open Items

| # | Item | Status |
| :--- | :--- | :--- |
| 1 | Rounding convention per operation. `[Q-M1]` | RESOLVED 2026-09-26 — half-even default, zakat rounds up |
| 2 | The sub-unit scale table is referenced by `002-finance` but owned by neither spec. | Decide at implementation time: own it in `nizam/calc/` (this package is the natural home — both `finance` and any future `investment` consumer need it, and it has no domain-specific meaning of its own). |
