---
type: reference
title: Capability Tiers — Baseline, Conditional, Optional
description: The three-tier model deciding which conventions apply to which project — always-on baseline, conditionally mandatory by architecture, and opt-in extras; the source of truth for .feanor/profile.toml and for what is promised to a client.
applies_to: [maintainer]
tags: [docs, maintainer, capabilities, tiers, profile, scope]
---

# Capability Tiers

Not every engineering practice belongs in every project. A metrics dashboard is real work with real operational cost; a system can be excellent without one. Access control is not like that.

Three tiers, and the difference between the second and third is the one that matters in a client conversation:

| Tier | Rule | Who decides |
| :--- | :--- | :--- |
| **Baseline** | Always applied. No toggle exists. | Nobody — it is the floor |
| **Conditional** | Mandatory **if** a structural trigger holds | The architecture, not a preference |
| **Optional** | Applied when chosen | The client, per project |

The client-facing version is three sentences: *"This is the baseline we apply to everything. These additional areas apply because your system has an API, stores personal data, and is multi-tenant. These are optional — here is what each costs and buys."*

## Tier 1 — Baseline

Always on. Cheap relative to their value, universally applicable, and their absence is a defect in any project regardless of size or domain.

| Area | Conventions |
| :--- | :--- |
| Design discipline | `coding-principles.md`, `module-boundaries.md`, `code-comments.md` |
| Testing | `tdd.md`, `testing.md` |
| Errors | `error-handling.md` |
| Security | `security.md`, `access-control.md`, `untrusted-input.md`, `secrets-management.md`, `supply-chain.md` |
| Logging | `observability-logging.md` — structured logs, redaction, correlation ids |
| Dependencies | `dependency-management.md` |
| Source control | all of `git/` |
| Language + packaging | the chosen stack's `project-layout`, `code-style`, and `ops/` Dockerfile |

**Why the whole security set is baseline.** These are not features; they are the absence of defects. A system without access control is not a cheaper system, it is a broken one. Excluding any of them is never a scope decision — it would be shipping a known vulnerability, and no client asks for that once it is put in those terms.

**Why logging is baseline but metrics is not.** Structured logs with redaction cost nothing beyond doing it correctly the first time, and without them nothing is diagnosable. Metrics require a collector, storage, dashboards, alert routing, and someone to look at them — that is an operational commitment, not a coding standard.

## Tier 2 — Conditional

Mandatory when the trigger holds. **This is not opt-in.** If a system exposes an HTTP API, API design conventions apply; the alternative is an unconventional API, not a cheaper one. Presenting these as choices invites a client to decline something they cannot meaningfully decline.

| Trigger | Becomes mandatory |
| :--- | :--- |
| Exposes an HTTP API | `api-design.md`, `middleware.md`, `health-endpoints.md` |
| Persists to a relational database | `database.md`, `db-connection.md`, the dialect file, the language's `database.md` |
| Has authenticated users | `auth.md`, and MFA rules for privileged accounts |
| Stores personal or regulated data | `data-protection.md`, plus `docs/SECURITY.md` |
| Multi-tenant | tenant isolation in `database.md`, RLS or a scoped repository |
| Publicly reachable | `rate-limiting.md`, security response headers |
| Publicly reachable + meant to be indexed (marketing site, docs, storefront) | `nextjs/project-layout.md` "Robots & Sitemap" (`app/robots.ts`, `app/sitemap.ts`), `X-Robots-Tag` in `security.md` |
| Any of the above five | `docs/THREAT-MODEL.md` per `meta/threat-model.md` |
| Uses concurrency | `go/concurrency-context.md` or `python/async-concurrency.md` |
| Deployed as a long-running service | `health-endpoints.md`, graceful shutdown, `docs/RUNBOOK.md` |

Triggers are read from the architecture, not asked as preferences. `/hld` derives them; they are recorded in `.feanor/profile.toml` so `/plan` and `/audit` read them deterministically instead of re-deriving them from prose.

## Tier 3 — Optional

Genuine product choices. A system can be complete and correct without any of these.

| Capability | Convention | What it costs | What it buys |
| :--- | :--- | :--- | :--- |
| **Metrics** | `metrics.md` | Collector, storage, dashboards, alert routing, on-call | Knowing it broke before the customer says so |
| **Distributed tracing** | `tracing.md` | Instrumentation, sampling, backend, storage | Explaining one specific slow request across services |
| **Caching** | `caching.md` | Invalidation complexity, a whole class of staleness bugs | Latency and load relief at real traffic |
| **In-app issue reporting** | `issue-reporting.md` | Public write endpoint to defend, tracker token, triage of the incoming queue | Bug reports that arrive reproducible instead of "it looked wrong yesterday" |
| **Feature flags** | *not written yet* | Flag lifecycle, dead-branch cleanup | Decoupling deploy from release |
| **Background jobs** | *not written yet* | Queue, workers, retry and idempotency | Work that outlives a request |
| **Full-text search** | *not written yet* | Index sync, its own failure modes | Search that `LIKE` cannot serve |
| **i18n** | *not written yet* | Extraction discipline, translation workflow | Non-English users |
| **SSO / SAML** | in `auth.md` | Per-provider integration and testing | Enterprise buyers who mandate it |

Four have no convention yet — that is the honest state, tracked in [OVERVIEW.md](./OVERVIEW.md)'s gaps. **A capability with no convention should not be offered as available**, because there is nothing for the execution agent to load and the result would be improvised.

## How a Project Gets Its Set

1. **`/reqs`** elicits *outcomes*, never a feature menu — "who needs to know when this breaks, and how fast?" rather than "do you want Prometheus?". Requirements stay in problem space; a client asked to pick technologies picks all of them.
2. **`/hld`** derives the conditional triggers from the architecture, then presents the optional menu with the cost/benefit above. Each acceptance is an ADR.
3. The result is written to **`.feanor/profile.toml`** in the target project.
4. **Context Resolver, Planner, and Validation Agent** all read that profile: disabled capabilities are never loaded, never ticketed, and never reported as missing.
5. The target project's **`docs/CAPABILITIES.md`** is generated from the profile, so what the client is told and what the agents enforce come from one source.

## Adding a Capability

1. Decide the tier here first. Baseline needs a strong argument — the floor should rise slowly and rarely.
2. Write the convention in `conventions/`, following `workflows/maintain-repo.md` §3.
3. Add its tags to `meta/context-resolver.md` §4 and `agents/planner-agent.md`.
4. If optional: add a key to the profile schema and a row to the Tier 3 table with an honest cost.
5. Run `reindex.py` and `validate-okf.py`.
