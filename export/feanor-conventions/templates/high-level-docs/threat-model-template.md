---
type: template
title: THREAT-MODEL.md Template
description: Blueprint for docs/THREAT-MODEL.md — trust boundaries, STRIDE findings per boundary, and the disposition of every threat; generated during /hld per meta/threat-model.md.
applies_to: [hld, security]
tags: [template, threat-model, stride, security]
---

# Threat Model

> **Project:** {{PROJECT_NAME}}
> **Last reviewed:** {{DATE}} · **Owner:** {{OWNER}}
> Method: `meta/threat-model.md`. Re-run when a trust boundary changes.

## Scope

- **In scope:** {{COMPONENTS_COVERED}}
- **Out of scope:** {{WHAT_IS_NOT_COVERED_AND_WHY}}
- **Assumptions:** {{WHAT_IS_TAKEN_AS_TRUSTED}} — e.g. the cloud provider's hypervisor, the identity provider's correctness.

## Trust Boundaries

```mermaid
flowchart LR
    subgraph untrusted["Untrusted — {{UNTRUSTED_ZONE}}"]
        A[{{EXTERNAL_ACTOR}}]
    end
    subgraph app["Application — authenticated"]
        B[{{API_SERVICE}}]
    end
    subgraph data["Data — private network"]
        C[({{DATASTORE}})]
    end
    A -->|{{WHAT_CROSSES}} · {{AUTH_AT_THIS_EDGE}}| B
    B -->|{{WHAT_CROSSES}} · {{AUTH_AT_THIS_EDGE}}| C
```

| # | Boundary | What crosses | Authenticated by |
| :- | :--- | :--- | :--- |
| B1 | {{FROM}} → {{TO}} | {{DATA}} | {{MECHANISM}} |

## Actors

| Actor | Trusted? | Can reach | Motivation |
| :--- | :--- | :--- | :--- |
| Anonymous internet | No | {{PUBLIC_SURFACE}} | {{WHY_THEY_WOULD}} |
| Authenticated user | Partially | {{THEIR_OWN_DATA}} | Access beyond their rights |
| {{THIRD_PARTY}} | Partially | {{INTEGRATION_SURFACE}} | Compromise upstream |
| {{INSIDER_ROLE}} | Partially | {{ADMIN_SURFACE}} | Misuse of legitimate access |

## Findings

One row per threat that actually applies. Delete the STRIDE categories that yield nothing for a boundary rather than padding with "N/A" rows.

| ID | Boundary | STRIDE | Threat | Abuse case | L×I | Disposition | Control | Convention |
| :- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| T-01 | B1 | Elevation | {{WHAT_SOMEONE_COULD_DO}} | AC.01 | H×H | Mitigate | {{THE_CONTROL}} | `cross-stack/access-control.md` |
| T-02 | B1 | Info disclosure | {{...}} | AC.02 | M×H | Mitigate | {{...}} | `cross-stack/data-protection.md` |
| T-03 | B2 | DoS | {{...}} | — | M×L | Accept | — | — |

- **Abuse case** references `AC.xx` from `docs/SRS.md`. Every `AC.xx` must appear in this table — that is the zigzag check in `meta/requirements-checklist.md` §6.
- **Disposition** is one of Mitigate / Accept / Transfer / Eliminate. Never blank.
- **Convention** names the file the implementing ticket must load, so `/plan` can tag it.

## Accepted Risks

Every `Accept` above, restated with a named owner. An accepted risk with no owner is an unnoticed gap wearing a disposition.

| ID | Risk | Why accepted | Owner | Revisit by |
| :- | :--- | :--- | :--- | :--- |
| T-03 | {{RISK}} | {{REASON}} | {{OWNER}} | {{DATE}} |

## Controls to Implement

The direct input to `/plan`. Each becomes at least one ticket, with an adversarial test.

| Control | Threats addressed | Convention tags | Test that proves it |
| :--- | :--- | :--- | :--- |
| {{CONTROL}} | T-01 | `access-control`, `python-boundaries` | {{ADVERSARIAL_TEST}} |
