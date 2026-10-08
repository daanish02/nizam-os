# ADR-005: Account balances are always derived from the transaction ledger

> **Date:** 2026-09-26
> **Status:** ACCEPTED

## Context

SRS FR.01.3.1 requires reporting the current balance of every account. Nothing in the original requirements said whether a balance should be a separately-stored, separately-asserted figure (updated whenever the owner reports a new balance) or derived by summing recorded transactions. This was an explicitly blocking open question (Q-F2) for `report_position`.

## Decision

Balances are always derived — computed as the sum of an account's transactions — never stored as an independently-mutable column. Periodic reconciliation entries correct for anything the owner failed to record, without ever introducing a second figure that could silently disagree with the transaction history.

## Alternatives Considered

### Store an asserted balance, updated periodically by the owner

- **Pros:** Simple to implement; tolerant of the owner not recording every single transaction.
- **Cons:** Creates exactly the kind of "figure that can diverge from the truth" this project's finance domain is designed to avoid (mirrors the reasoning that keeps investment holdings out of the database entirely — SRS FR.07.1.3). A stored balance and a summed ledger can silently disagree, and nothing would ever detect it without an explicit reconciliation step, which is just the derived-balance model with extra indirection.
- **Rejected because:** cycle 1 commits to manual transaction entry (no CSV import — FR.01.1.5), meaning the owner is already expected to record transactions as they happen; a derived balance with reconciliation entries handles the "occasionally I forget one" case just as well, without the drift risk.

### Hybrid — store a balance, reconcile against the ledger, alert on mismatch

- **Pros:** Gets a fast balance read without summing the whole ledger every time.
- **Cons:** Reintroduces the exact two-sources-of-truth problem the derived model exists to avoid, just with an alerting layer bolted on. And at personal-finance transaction volumes (dozens to low hundreds per month), summing the ledger is not a performance problem worth solving this way.
- **Rejected because:** the performance concern that would justify this doesn't exist at this scale (NFR.02's 1-second target is easily met by summing a personal transaction history).

## Consequences

- **Positive:** balances can never silently drift from the record that explains them; a wrong balance is always traceable to a specific wrong or missing transaction.
- **Negative / trade-offs:** `report_position` does real aggregation work on every call rather than a single-row read — acceptable at this scale (see above), but worth reconsidering only if the ledger ever grows to a size where that stops being true (not expected).
- **Follow-up required:** a reconciliation-entry mechanism must exist from the start, not added later, since "the owner didn't record something" is the normal case, not an edge case, for manual entry.

## References

- `docs/specs/002-finance.md` — Q-F2, resolved; `AccountBalance`, Invariant F-9
- `docs/SRS.md` FR.01.3.1
- `docs/SCHEMAS.md` — `finance_personal` schema section
