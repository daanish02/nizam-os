# ADR-003: Cycle 1 scope is knowledge + finance only; business is out indefinitely

> **Date:** 2026-09-26
> **Status:** ACCEPTED

## Context

The prior iteration's documentation accumulated a 10-agent business roster (CFO/COO/CTO/CMO-style agents, CRM, analytics) alongside the personal domain, despite the owner's explicit 2026-09-10 direction to limit scope to personal only for the time being. That contradiction was never fully cleaned up across every doc, and was one of the concrete reasons a from-scratch rebuild was chosen over continuing to refactor in place.

## Decision

Cycle 1 builds exactly two capability domains: knowledge (CP.03) and personal finance (CP.01), plus the cross-cutting agent runtime rules (CP.06) they both depend on. Tasks/habits/goals/journal (CP.02/05), self-maintenance beyond Nazim's basic restart allowlist (CP.04), and investment review (CP.07) are cycle 2, not built now. The business domain is out indefinitely, not merely deferred — it requires its own fresh requirements pass if ever revisited, never a scope creep back into the personal system.

## Alternatives Considered

### Build all personal-domain capabilities from the prior SRS at once

- **Pros:** The prior SRS already specified all seven CPs; building them together avoids a second requirements pass later.
- **Cons:** Larger surface before anything is proven in daily use; more to get right simultaneously; the exact failure mode that led to a confusing, half-finished system last time.
- **Rejected because:** the owner's own stated preference (in this session) is two proven domains in daily use before expanding, and a smaller cycle-1 surface is easier to verify end-to-end at every phase of `export/00-START-HERE.md`.

### Keep business in scope, just build it last

- **Pros:** Matches the original, broader vision of the project (a personal *and* business operating system).
- **Cons:** This is precisely the ambiguity that let business-domain content leak into "personal" docs before — "build it last" tends to mean "document it now, contradict it later."
- **Rejected because:** the owner's repeated, explicit direction across two separate sessions (2026-09-10 and 2026-09-26) is to drop business scope, not defer it within the same document set.

## Consequences

- **Positive:** every doc in this rebuild can say "personal, cycle 1" without qualification — no document needs to simultaneously describe two scopes.
- **Negative / trade-offs:** cycle 2's specs (tasks/habits, self-maintenance, investment) will need their own short requirements pass before they're built — the archived prior specs for those domains (`export/docs/specs-new/004`, `006`, `007`) are a starting point, not something to build against unmodified, since some of their open questions were never resolved and some of their assumptions (e.g. investment being in cycle 1) are now wrong.
- **Follow-up required:** when cycle 2 starts, re-run a short interrogation for whatever domain comes first, following the same pattern used to resolve cycle 1's open questions in `SRS.md` §12.

## References

- `docs/VISION.md` — cycle 1 vs cycle 2 domain list
- `docs/SRS.md` §1.2 — in-scope / deferred / out-of-scope breakdown
- `export/BUGS-AND-GOTCHAS.md` #7 — the business-domain remnants this decision cuts off for good
