---
title: Integrations — nizam-os (Personal Domain)
status: DRAFT
version: 0.2.0
date: 2026-09-10
scope: personal
derived_from: docs/ARCHITECTURE.md, docs/THREAT-MODEL.md
---

# Integrations

Every third party the system depends on: what it is relied on for, what happens
when it is gone, and what crosses the boundary in each direction.

**Why this document matters more here than usual.** Every entry is a trust
boundary. Data crossing outward is data leaving the owner's machine; data
crossing inward is untrusted content that will subsequently be fed to a model.
Both directions are threats, not just dependencies — see
`docs/THREAT-MODEL.md` TB-6 through TB-9.

> **Placeholders.** `[PENDING — SRS Q<n>]` marks a dependency whose handling
> depends on an unresolved question in `docs/SRS.md`.

---

## Summary

| Integration | Relied on for | Criticality | Data outward | Data inward |
| :--- | :--- | :--- | :--- | :--- |
| Chat platform | The sole owner-facing surface | **Hard** | Everything the owner discusses | Instructions and approvals |
| Model provider | All agent reasoning | **Hard** | Prompt content, incl. Confidential data | Generated output |
| Public web | Source material for capture | Soft | The URL requested | **Fully untrusted content** |
| Video sources | Transcripts for capture | Soft | The identifier requested | **Fully untrusted content** |
| Transcript fallback | Transcripts the primary path cannot get | Soft | The identifier requested | **Fully untrusted content** |
| Brokerage | Positions, watchlist, prices, filings | Soft | Authentication only | Financial figures |
| Rate and threshold data | Currency conversion, zakat threshold | **Hard for correctness** | Nothing identifying | Numeric figures |
| Observability stack | Metrics, logs, dashboards | Soft, local | Operational data — stays on the machine | — |
| Management VPN | Operator access to the machine | Soft | — | — |

---

## Chat platform

**Relied on for** the only interaction path between the owner and every agent.
Each agent has its own channels; instruction is accepted only from the owner's
identity *(C-20)*.

**When it is gone** all interaction stops. There is no fallback surface, by
design — a second surface is explicitly out of scope *(C-02)*.

`[PENDING — SRS Q2]` Whether scheduled work continues and delivers on recovery,
or halts, is unresolved.

**Boundary notes.** This is a third party holding the complete history of the
owner's conversations, including financial figures and journal content —
accepted risk **R-03**. A compromise of the owner's account on this platform is
indistinguishable from the owner — accepted risk **R-04**. The platform account
is the root of trust for the entire system.

---

## Model provider, via the local proxy

**Relied on for** every reasoning capability. No agent reaches the provider
directly; all inference passes through one local proxy that holds the
credential, tracks consumption and enforces the ceiling *(C-28)*.

**When it is gone** no agent can reason. This is the system's single largest
availability dependency.

`[PENDING — SRS Q2]` **Whether capabilities degrade to non-reasoning recording
and reporting, or fail loudly, is unresolved and changes every service
contract.** It is the highest-value open question in the project.

**Boundary notes.** Any financial figure or journal entry an agent reasons over
leaves the machine — accepted risk **R-02**, the most significant confidentiality
exposure in the system. The provider credential is held only by the proxy and
is never in an agent's reach *(C-23)*. The ceiling figure is
`[PENDING — SRS Q3]`; until set, spend is unbounded.

---

## Public web

**Relied on for** the content behind a link the owner wants captured.

**When it is gone** a single capture fails. Nothing else is affected.

**Boundary notes — the primary injection surface.** Fetched content is wholly
untrusted and is subsequently fed to a model, which may read instructions in it
as direction *(T-23)*. The approval gate is the control; the residual is
accepted risk **R-01**.

Every fetch rejects non-public schemes and private address ranges, revalidated
after each redirect — the machine runs a loopback proxy holding provider
credentials, which makes an unfiltered fetch directly exploitable rather than
theoretical *(C-16, T-24)*. Size caps and timeouts apply *(C-17)*, values
`[PENDING — SRS Q4]`.

---

## Video sources and transcript fallback

**Relied on for** transcripts of video the owner wants captured. A primary
extraction path with a secondary fallback, since one source failing to yield a
transcript is common enough to plan for *(FR.03.1.3)*.

**When gone** video capture degrades to whatever metadata is available, or
fails. No other capability is affected.

**Boundary notes.** Transcript text is untrusted content on the same footing as
web content. Extraction invokes an external tool: arguments pass as a vector,
never through a shell, and the identifier is validated against an expected form
first *(C-18, T-26)*.

---

## Brokerage

**Relied on for** positions, watchlist, price and filing data. **Read-only, and
the read-only-ness is structural**: no capability to place, modify or cancel an
order exists anywhere in the system *(T-28)*.

**When it is gone** investment review is unavailable. Nothing else is affected,
and nothing is stale, because no copy is kept *(T-29)*.

**Boundary notes.** The brokerage is the sole record of holdings. Credentials
are held by the service and never reach an agent *(C-23)*. Every figure carries
its as-of date; a figure that cannot be retrieved yields an inconclusive result
rather than an assumption *(FR.07.3.3)*.

---

## Rate and threshold data

**Relied on for** currency conversion and the zakat threshold.

**When it is gone** — and this is the important case — **the system must refuse
to state a figure rather than substitute a stale or default value**
*(FR.01.5.2, FR.01.3.2, AC.10)*. Soft in availability terms, hard in
correctness terms: a wrong zakat figure or a wrong converted total is worse
than no figure at all.

`[PENDING — SRS Q1]` If zakat is Obligation-class, this dependency's
correctness requirement rises further.

---

## Observability stack

Metrics collection, log aggregation and dashboards, all running on the same
machine. Local, not third-party — listed here because it is a dependency of
CP.04, not because it is external.

**When it is gone** the owner loses visibility into the system's health and
spend. Nothing stops working, but self-maintenance degrades to unobserved.

**Boundary notes.** Operational data never leaves the machine. Dashboard access
is read-only against the database.

---

## Management VPN

**Relied on for** the operator's access to the machine. Not used by any agent.

**When it is gone** direct operator access is lost. In normal operation this
matters not at all — needing to log in is itself a gap in self-maintenance
*(PRD §5 guardrail)*.

---

## Credentials and access

Every integration above needs a credential. All are held encrypted at rest,
never committed in plaintext, and held by the service that uses them rather
than by any agent *(C-21, C-23)*.

`[PENDING]` Which of these have sandbox or test credentials available for
development, as opposed to only production credentials, is unrecorded. It was
raised in requirements and never answered, and it determines whether
integration behaviour can be tested at all without touching live accounts.

---

## Adding an integration

Adding one creates a new trust boundary. Before it goes in:

- [ ] What crosses outward, and is any of it Confidential?
- [ ] What crosses inward, and is it untrusted content?
- [ ] What happens when it is unavailable — degrade, fail, or refuse?
- [ ] If it supplies a figure, what happens when the figure cannot be
      retrieved? *(Never substitute a default.)*
- [ ] Which service holds the credential? *(Never an agent.)*
- [ ] Threat model re-run for the new boundary.
- [ ] Recorded here, in `docs/SECURITY.md`, and in `docs/THREAT-MODEL.md`.

---

## Open items

| # | Item | Affects |
| :--- | :--- | :--- |
| 1 | Behaviour when the model provider is unavailable. `[PENDING — SRS Q2]` | Every capability |
| 2 | Inference spend ceiling. `[PENDING — SRS Q3]` | Model provider |
| 3 | Fetch size cap and timeout. `[PENDING — SRS Q4]` | Public web, video |
| 4 | Test versus production credentials per integration. `[PENDING]` | Whether integrations are testable at all |
