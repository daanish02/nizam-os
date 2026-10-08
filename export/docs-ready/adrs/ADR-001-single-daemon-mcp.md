# ADR-001: One Python package, one MCP daemon, HTTP transport

> **Date:** 2026-09-26
> **Status:** ACCEPTED

## Context

CP.06 requires every agent to be strictly scoped to its declared domains (FR.06.1.2, NFR.11). The prior implementation ran the knowledge service as a stdio subprocess spawned per Hermes session, with secrets injected directly into its config's `env:` block. That pattern doesn't extend cleanly to multiple domains and made a real secret leak more likely (`export/BUGS-AND-GOTCHAS.md` #3). The VPS has only 2 vCPU / 7.8 GB RAM.

## Decision

Build one Python package (`nizam`) and run one long-lived daemon (`nizam-mcp`) that serves every domain's MCP tools over HTTP on `127.0.0.1:8100`, one path per domain. Agent identity and domain scope are resolved from a bearer token at the daemon, not left to each spawned process or to prompt-level trust.

## Alternatives Considered

### One process per domain (current-scale equivalent of the old pattern, generalized)

- **Pros:** OS-level process isolation between domains.
- **Cons:** More systemd units, more RAM overhead on a 7.8 GB box, no gain in security since the real isolation boundary needed is DB-role/schema, not process boundary — there's no untrusted multi-tenant workload here to isolate against.
- **Rejected because:** the isolation this system actually needs (SRS §7.2 — the threat is the system's own autonomy) is enforced correctly by scoped DB roles and a token→domain map either way; paying the RAM cost for OS-level isolation buys nothing extra at this scale.

### Stdio subprocess per session (the prior pattern)

- **Pros:** Simple, no daemon lifecycle to manage, Hermes's default MCP pattern.
- **Cons:** No shared connection pool, cold start per session, secrets end up in the spawning config rather than a narrow daemon env, harder to add a uniform auth/audit layer across domains.
- **Rejected because:** it was the actual shape of the system when the secret leak happened, and it doesn't scale to multiple domains without duplicating the auth/audit logic per service.

## Consequences

- **Positive:** one place for auth, audit, and health-check logic; lower RAM footprint; a real bearer-token boundary between agents instead of relying on each subprocess's own env being correctly scoped.
- **Negative / trade-offs:** a single daemon is a single point of failure for every domain at once (mitigated by NFR.04's one-retry-then-escalate restart policy) and a bug in one domain's tool code can in principle affect the process serving others (mitigated by each domain being a separate Python module with its own DB role — a crash is caught per-request by the ASGI layer, not a shared-state bleed).
- **Follow-up required:** if a domain ever needs a genuinely different runtime (e.g. a non-Python worker), it would need its own process and a routing decision at the daemon — not anticipated for cycle 1 or cycle 2.

## References

- `docs/SRS.md` §5 CP.06 — FR.06.1.2, NFR.11
- `docs/ARCHITECTURE.md` — the `nizam-mcp` daemon section
- `docs/specs/004-agent-runtime.md` — the scope-map design
