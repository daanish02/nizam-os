---
type: meta
title: Architecture Decision Records (ADRs)
description: When to write ADRs, the lifecycle (PROPOSED → ACCEPTED → SUPERSEDED/DEPRECATED), index maintenance, and the gate preventing /plan from proceeding while any ADR is PROPOSED.
applies_to: [all]
tags: [cross-stack, adrs, decisions, architecture]
---

# Architecture Decision Records (ADRs)

ADRs capture the reasoning behind significant technical decisions. They answer the question future engineers and agents will ask most often: _"Why was this built this way?"_ Code shows what was built; ADRs explain why, what alternatives were rejected, and what constraints applied.

## When to Write an ADR

The architect agent writes an ADR during `/hld` for any decision from this list:

- Backend language selection (Go / Python / TypeScript)
- Database engine and ORM
- Authentication strategy (JWT / session / OAuth provider)
- API style (REST / GraphQL / tRPC)
- Hosting platform or infra provider
- Caching layer selection
- Any major external service selection (e.g. payment processor, email provider, object storage)
- **Any accepted security risk** — a threat from `docs/THREAT-MODEL.md` dispositioned `Accept` rather than mitigated. This is the decision an auditor or enterprise client asks about first, and the one most likely to be re-litigated after an incident.
- **Any PII, data-residency, or retention decision** — what personal data is held, which region it is stored in, how long it is kept. These are contractual as often as they are technical, and they constrain hosting choices downstream.
- **Multi-tenancy isolation strategy** — RLS, separate schemas, separate databases, or application-only scoping. Changing this later is a migration, not a refactor.
- Any decision the team would plausibly debate again in 6 months

If in doubt: write the ADR. A 10-minute ADR prevents a 2-hour debate later.

**When NOT to write an ADR:**

- Obvious default choices with no real alternatives (e.g. "use UTF-8 encoding")
- Implementation details that don't affect system boundaries (e.g. variable naming within a module)
- Temporary or experimental decisions explicitly scoped to a sprint

## File Location and Naming

```
docs/adrs/
├── index.md              # master table of all ADRs — maintained by architect agent
├── ADR-001-postgresql.md
├── ADR-002-rest-api.md
└── ADR-003-jwt-auth.md
```

**Filename pattern:** `ADR-{NNN}-{kebab-case-slug}.md` where `{NNN}` is zero-padded and sequential. Never reuse a number, even if an ADR is deprecated.

**Template:** `templates/adr-template.md`

## ADR Lifecycle

```
PROPOSED → ACCEPTED → SUPERSEDED (points to new ADR)
                    → DEPRECATED  (decision no longer applies)
```

- **PROPOSED** — written by architect agent during `/hld`, not yet reviewed/confirmed by the team.
- **ACCEPTED** — team has reviewed and confirmed the decision. Engineer updates the `status` field.
- **SUPERSEDED** — a later ADR replaces this one. Add `superseded_by: ADR-NNN` to the frontmatter. Never delete a superseded ADR — it preserves historical context.
- **DEPRECATED** — the decision no longer applies (feature removed, direction changed). Note why.

**Never delete an ADR.** Historical context has value even when the decision is wrong in hindsight.

## Index Maintenance (`docs/adrs/index.md`)

The architect agent creates `docs/adrs/index.md` when the first ADR is written, and updates it every time a new ADR is added:

```markdown
# Architecture Decision Records

| ID      | Title                       | Status   | Date       |
| :------ | :-------------------------- | :------- | :--------- |
| ADR-001 | Use PostgreSQL               | ACCEPTED | 2025-01-15 |
| ADR-002 | REST over GraphQL            | PROPOSED | 2025-01-16 |
| ADR-003 | JWT auth with RS256          | ACCEPTED | 2025-01-16 |
```

## The PROPOSED Gate (`/plan`)

The planner agent **MUST NOT** generate `docs/plan.toml` while any ADR is in `PROPOSED` state. PROPOSED means the decision has not been confirmed — implementing against an unconfirmed architectural decision produces work that may need to be redone.

**Gate check (deterministic):**

```bash
grep -rl "^status: PROPOSED" docs/adrs/ 2>/dev/null
```

If this returns any files: block `/plan` and list the unresolved ADRs. The engineer reviews each, updates the `status` field to ACCEPTED / SUPERSEDED / DEPRECATED, and re-runs `/plan`.

## Inline References

Reference ADR IDs in specs and code comments where a decision's consequence is visible:

```go
// ADR-002: REST chosen over GraphQL — see docs/adrs/ADR-002-rest-api.md
```

```markdown
<!-- docs/specs/001-auth-api.md -->
Auth uses RS256 JWTs per ADR-003.
```

This creates a trail from implementation back to decision rationale.
