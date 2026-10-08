---
type: template
title: SECURITY.md Template
description: Blueprint for docs/SECURITY.md — trust boundaries, auth model, data classification, PII inventory, control list, secret registry, and accepted risks; mandatory whenever the project authenticates users or holds personal data.
applies_to: [hld, security]
tags: [template, security, controls, pii, compliance]
---

# Security

> **Project:** {{PROJECT_NAME}}
> **Last reviewed:** {{DATE}} · **Owner:** {{OWNER}}
> Threats and their dispositions live in `docs/THREAT-MODEL.md`. This document records what is *in place*.

## Trust Boundaries

```mermaid
flowchart LR
    Untrusted[{{UNTRUSTED_ACTOR}}] -->|{{VALIDATION_STEP}}| Trusted[{{TRUSTED_ZONE}}]
```

## Auth Model

- **Mechanism:** {{JWT_SESSION_OIDC}} — access token TTL {{TTL}}, refresh TTL {{TTL}}
- **Revocation:** {{TOKEN_VERSION_OR_DENYLIST}} — per `cross-stack/auth.md`
- **Roles/permissions:** {{RBAC_MODEL}}
- **Object-level ownership:** {{HOW_ENFORCED}} — per `cross-stack/access-control.md`
- **Tenant isolation:** {{RLS_OR_SCOPED_REPOSITORY_OR_NA}}
- **MFA:** {{REQUIRED_FOR_WHOM}}

## Data Classification

Every persisted field belongs to exactly one tier — see `cross-stack/data-protection.md`.

| Data | Tier | Where stored | Encryption | Retention | Lawful basis / reason |
| :--- | :--- | :--- | :--- | :--- | :--- |
| {{FIELD_OR_ENTITY}} | Confidential | {{STORE}} | {{AT_REST_METHOD}} | {{PERIOD}} | {{WHY_HELD}} |

**Deletion path:** {{HOW_A_USER_IS_DELETED_AND_WHAT_PROPAGATES}}
**Export path:** {{HOW_A_USER_GETS_A_COPY}}

## Controls In Place

One row per control, traceable back to the threat it addresses.

| Control | Addresses | Where implemented | Test that proves it |
| :--- | :--- | :--- | :--- |
| {{CONTROL}} | T-01 / AC.01 | {{FILE_OR_LAYER}} | {{TEST_PATH}} |

## Secrets Registry

Per `cross-stack/secrets-management.md`. Values never appear here — only their location and lifecycle.

| Secret | Where stored | Owner | Rotation | Last rotated |
| :--- | :--- | :--- | :--- | :--- |
| {{SECRET_NAME}} | {{SECRET_STORE}} | {{OWNER}} | {{INTERVAL}} | {{DATE}} |

## Third Parties Receiving Data

| Service | Receives | Tier | Why | Data processing agreement |
| :--- | :--- | :--- | :--- | :--- |
| {{PROVIDER}} | {{FIELDS}} | {{TIER}} | {{PURPOSE}} | {{YES_NO_LINK}} |

## Compliance

- **Frameworks in scope:** {{SOC2_ISO_HIPAA_PCI_GDPR_OR_NONE}}
- **Data residency:** {{REGIONS_AND_CONSTRAINT}}
- **Evidence / audit trail:** {{WHAT_IS_LOGGED_AND_KEPT_HOW_LONG}}

## Verification

- **Scanners in CI:** {{SAST_DEPENDENCY_SECRET_SCANNERS}} — see `cross-stack/supply-chain.md`
- **Last penetration test / review:** {{DATE_AND_OUTCOME}}

## Known Risks / Accepted Trade-offs

Mirrors the `Accept` rows in `docs/THREAT-MODEL.md`. An accepted risk needs an owner and a revisit date, or it is just an unfixed bug with better paperwork.

| ID | Risk | Why accepted | Owner | Revisit by |
| :- | :--- | :--- | :--- | :--- |
| {{ID}} | {{RISK}} | {{WHY_ACCEPTED_OR_MITIGATION}} | {{OWNER}} | {{DATE}} |

## Incident Log

| Date | What | Data affected | Resolution |
| :--- | :--- | :--- | :--- |
| {{DATE}} | {{WHAT_HAPPENED}} | {{SCOPE}} | {{WHAT_WAS_DONE}} |
