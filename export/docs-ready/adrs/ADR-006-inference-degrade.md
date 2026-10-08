# ADR-006: LLM outage degrades deterministic writes, fails purely-reasoning requests

> **Date:** 2026-09-26
> **Status:** ACCEPTED

## Context

SRS §4.2 (Q2, the highest-value open question in the original interrogation) asked whether the system should degrade to non-reasoning recording/reporting when LiteLLM is unavailable, or fail loudly across the board. Left unresolved, it would have changed every domain's tool-availability contract.

## Decision

A tool that needs the LLM for a non-essential part of its work (embedding a note, classifying it, parsing free-form natural language into structured fields) completes the deterministic part of the write regardless, and marks the LLM-dependent part `pending`, retried by a background job on a timer. A tool that is purely reasoning-dependent (there is no deterministic fallback at all) fails explicitly and says why, rather than silently doing nothing or guessing.

## Alternatives Considered

### Fail loudly across the board when LiteLLM is down

- **Pros:** Simple, uniform behavior — one rule, no per-tool judgment calls.
- **Cons:** Loses owner input for no reason. If the owner reports a transaction with fully-structured fields, or pastes a URL to save, there's no reason a temporary LLM outage should mean that work is lost or that the owner has to remember to retry it manually later.
- **Rejected because:** it fails the wrong half of the system — the durable-record half, which is exactly the part CP.01 and CP.03 exist to make reliable.

### Silently retry without telling the owner anything degraded

- **Pros:** Owner never sees an error.
- **Cons:** Violates FR.03.3.3's explicit requirement to state when retrieval has degraded, and more generally violates the project's own stated principle that nothing should crash or fail *silently* — a queued, pending item the owner never hears about is a silent failure with extra steps.
- **Rejected because:** the owner needs to know a note is only lexically searchable for now, or that a transaction's category wasn't auto-classified yet, so he can act on it if it matters.

## Consequences

- **Positive:** the system's actual reliability (recording things) doesn't depend on an external LLM provider's uptime; owner input is never lost to a transient outage.
- **Negative / trade-offs:** every domain needs an explicit notion of "the deterministic part" vs. "the reasoning-dependent part" of each write, which is a real design task per tool (see each spec's Q2-adjacent sections), not a free abstraction.
- **Follow-up required:** a background retry job (`nizam/jobs/retry_embeddings.py` for knowledge; an equivalent for any future finance auto-classification) must exist from the start of each domain's build, not bolted on after the first real outage.

## References

- `docs/SRS.md` §4.2, §8, F-01 — the resolution
- `docs/specs/001-knowledge.md` Q-K2 — the knowledge-domain instance of this decision
- `docs/specs/002-finance.md` Q-F5 — the finance-domain instance
- `docs/specs/004-agent-runtime.md` Q-A3 — the cross-cutting statement
