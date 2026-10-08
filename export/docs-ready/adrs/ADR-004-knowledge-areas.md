# ADR-004: Knowledge classification uses multi-valued `areas`, not single `domain`

> **Date:** 2026-09-26
> **Status:** ACCEPTED

## Context

The prior implementation's database schema and code used a single-valued `domain` column drawn from a fixed set of ten values. The prior iteration's charter documents (ARCHITECTURE, SCHEMAS) described multi-valued `areas` with expected overlap between subjects instead — these two models were never reconciled, and the code was never updated to match the newer design (`export/BUGS-AND-GOTCHAS.md` #6). A note on, say, the economics of a specific technology genuinely belongs to more than one subject area.

## Decision

`nizam/knowledge/` uses `areas: TEXT[]`, multi-valued, drawn from a controlled, closed vocabulary (the ten-value list in `docs/specs/001-knowledge.md`), with 1–3 entries per note. There is no `domain` column anywhere in the rebuild's schema.

## Alternatives Considered

### Keep single-valued `domain`

- **Pros:** Simpler filtering (`WHERE domain = X` vs. an array-contains query), matches what the old code actually did.
- **Cons:** Forces a false single choice on notes that genuinely span subjects; was already contradicted by the project's own charter-tier docs before this rebuild even started.
- **Rejected because:** this is a from-scratch rebuild — there's no migration cost to worry about, so there's no reason to keep the model everyone had already agreed was wrong.

### Open, uncontrolled tagging only (no `areas` concept)

- **Pros:** Maximum flexibility, no vocabulary to maintain.
- **Cons:** An open vocabulary drifts and stops partitioning the vault into anything navigable — this was explicitly rejected in the original spec-writing pass for a good reason: `tags` already exists for free-form labels, and `areas` needs to stay a small, closed set to remain useful as a primary filter.
- **Rejected because:** the two-tier design (controlled `areas` + free `tags`) gives both structure and flexibility; dropping the controlled tier for tags-only loses the coarse navigation `areas` is for.

## Consequences

- **Positive:** notes classify correctly without forcing an artificial single choice; matches the design already agreed to be correct before the rebuild started.
- **Negative / trade-offs:** slightly more complex queries (array containment, GIN index) than a simple equality filter.
- **Follow-up required:** none — this is the schema from day one, not a migration.

## References

- `docs/specs/001-knowledge.md` — Q-K1, resolved; the `AreaVocabulary` shared type
- `docs/SCHEMAS.md` — `knowledge` schema section
- `export/BUGS-AND-GOTCHAS.md` #6
