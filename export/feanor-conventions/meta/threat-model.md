---
type: meta
title: Threat Modeling Method
description: STRIDE-per-trust-boundary method run during /hld — turns the abuse cases from /reqs into a concrete control list, and decides which conventions the resulting tickets must load.
applies_to: [architect, hld, security]
tags: [threat-model, stride, security, architecture, controls]
---

# Threat Modeling Method

Run during `/hld`, after the topology is drafted and before `/specs`. Output is `docs/THREAT-MODEL.md` plus the control list that `docs/SECURITY.md` records and `/plan` turns into tickets.

The point is not a document. It is that every control in the system can be traced to a specific thing someone might do, and every thing someone might do has either a control or a written decision to accept it.

## When It Is Mandatory

Required when **any** of these is true — the same trigger that makes `docs/SECURITY.md` mandatory:

- The system authenticates users.
- It stores Confidential or Restricted data (see `cross-stack/data-protection.md`).
- It is multi-tenant.
- It accepts input from, or sends data to, a third party.
- It is reachable from the public internet.

Otherwise optional. A local single-user CLI with no network and no personal data does not need one — say so explicitly rather than skipping silently.

## Step 1 — Draw the Trust Boundaries

Start from the topology diagram in `docs/ARCHITECTURE.md`. A trust boundary is any place data crosses from one level of trust to another: browser → API, API → database, service → third-party API, CI → production, admin → system.

Mark on the diagram, for each boundary: what crosses it, who controls the data at the source, and what is authenticated there. **Every arrow that crosses a boundary is where threats live.** Arrows inside one boundary are much lower priority.

## Step 2 — STRIDE Each Boundary

For each boundary, ask the six questions. Most yield nothing; write down the ones that do.

| Threat | Question | Usual control |
| :--- | :--- | :--- |
| **S**poofing | Can someone claim to be a party they are not? | `auth.md` — token validation, claim pinning, MFA |
| **T**ampering | Can data be modified in transit or at rest? | TLS, signatures, integrity constraints, `data-protection.md` |
| **R**epudiation | Can someone deny having done it? | Audit log, `observability-logging.md` |
| **I**nformation disclosure | Can someone read what they should not? | `access-control.md`, encryption, `data-protection.md` |
| **D**enial of service | Can someone exhaust a resource? | `rate-limiting.md`, timeouts, body/size caps, pagination |
| **E**levation of privilege | Can someone gain rights they were not granted? | `access-control.md`, deny-by-default, mass-assignment allowlists |

- **Pull in the abuse cases from `/reqs`.** Every `AC.xx` from `meta/requirements-checklist.md` §2.6 must appear here against the boundary where it applies. The threat model is where they get their controls.
- Do not invent threats the architecture cannot express. A system with no file upload has no upload threats — say N/A and move on. Padding the model hides the real findings.

## Step 3 — Rate and Decide

For each threat: **likelihood × impact**, coarse (high/medium/low). Precision is false comfort; the ranking is what matters.

Every threat gets exactly one disposition:

- **Mitigate** — a named control, and the convention file that specifies it. This becomes a ticket in `/plan`.
- **Accept** — recorded in `docs/SECURITY.md` with the reason and a named owner. An accepted risk is a decision someone made, not a gap nobody noticed.
- **Transfer** — handled by a provider (payment processor, identity provider). Name the provider and what it covers.
- **Eliminate** — remove the feature or the data. Usually the cheapest option, and the one most often skipped.

An unmitigated high×high threat blocks `/plan`. Write an ADR for the decision if it is architectural — see `meta/adrs.md`.

## Step 4 — Feed It Forward

- Controls become tickets. Each carries the convention tags for its control (`access-control`, `untrusted-input`, `auth`, `secrets`, `data-protection`), so `/exec` loads the right rules — see `meta/context-resolver.md`.
- Each control gets a test that proves it, written the way `access-control.md` and `untrusted-input.md` specify: authenticate as the wrong user, send the hostile input, assert refusal. A control with no adversarial test is unverified.
- `/audit` checks the implementation against this list — see `agents/validation-agent.md`.

## Keeping It Current

Re-run when a trust boundary changes: a new integration, a new data category, a new role, a new public endpoint, or a move to multi-tenancy. A threat model written once at kickoff and never revisited describes a system that no longer exists.

Template: `templates/high-level-docs/threat-model-template.md`.
