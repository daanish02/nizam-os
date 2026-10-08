---
type: template
title: Architecture Decision Record (ADR) Template
description: Template for docs/adrs/ADR-{NNN}-{slug}.md — captures the context, decision, alternatives, and consequences for every significant architectural choice made during /hld.
applies_to: [architect, hld, adrs]
tags: [template, adr, decisions, architecture]
---

# ADR-{{NNN}}: {{Short Decision Title}}

> **Date:** {{YYYY-MM-DD}}
> **Status:** PROPOSED | ACCEPTED | SUPERSEDED | DEPRECATED
> **Superseded by:** ADR-{{NNN}} _(only if status is SUPERSEDED)_

---

## Context

Why this decision was needed. What forces, constraints, and requirements drove it. Reference the relevant CP/CN IDs from `docs/SRS.md` and the PRD section if applicable.

_Example: "CP.01 requires the system to handle 10k concurrent users. The data model is relational (users → tasks → teams with foreign keys). We need a primary database that supports ACID transactions and managed hosting."_

---

## Decision

What was decided. One clear, unambiguous statement.

_Example: "Use PostgreSQL 16 with SQLAlchemy (async) as the primary database."_

---

## Alternatives Considered

### {{Option A}}

- **Pros:** ...
- **Cons:** ...
- **Rejected because:** ...

### {{Option B}}

- **Pros:** ...
- **Cons:** ...
- **Rejected because:** ...

_(Add or remove options as needed. At least two alternatives must be documented — a decision with no alternatives considered was not really decided, it was defaulted.)_

---

## Consequences

What changes as a result of this decision — both positive and negative.

- **Positive:** ...
- **Negative / trade-offs:** ...
- **Follow-up required:** _(e.g. "team needs to learn X", "will require Y migration in 6 months")_

---

## References

- `docs/SRS.md` §{{SECTION}} — requirement that drove this decision
- `docs/PRD.md` §{{SECTION}} — business context
- `docs/specs/{{NNN}}-{{concern}}.md` — downstream spec affected by this decision
