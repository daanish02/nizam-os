---
type: convention
title: Data Protection & Classification
description: Data classification tiers, PII handling, encryption at rest and in transit, retention and deletion rules — load for any ticket that stores, moves, logs, or exports personal or regulated data.
applies_to: [go, python, typescript, ops]
tags: [data-protection, pii, classification, encryption, retention, gdpr, privacy, compliance]
---

# Data Protection & Classification

A control is only correct relative to what it protects. Classify first; the classification then decides storage, logging, transport, retention, and who may read it.

## Classification Tiers

Every field in every persisted model belongs to exactly one tier. Record the mapping in `docs/SECURITY.md`.

| Tier | Contains | Rules |
| :--- | :--- | :--- |
| **Public** | Marketing copy, published content, public ids | No restriction. |
| **Internal** | Aggregates, non-personal operational data, internal ids | Access requires authentication. Not exposed unauthenticated. |
| **Confidential** | Personal data (name, email, address, phone, IP), business-sensitive records | Encrypted in transit and at rest. Access controlled per `access-control.md`. Never in logs. Retention limit required. |
| **Restricted** | Credentials, tokens, payment data, government ids, health data, biometrics, precise location | All Confidential rules, plus: field-level encryption or tokenisation, access audit-logged, never in non-production environments, never in analytics. |

- **A field's tier is decided when the model is written, not later.** Adding a column without classifying it is how personal data ends up in a log pipeline.
- Deriving or aggregating data does not automatically lower its tier — a "count" that can be narrowed to a single person is still personal data.
- **Never copy Confidential or Restricted data into a non-production environment.** Seed development and staging with synthetic or anonymised data. A production dump in staging inherits none of production's controls.

## PII

- **Collect the minimum.** A field not collected cannot leak, cannot be subpoenaed, and needs no retention rule. Challenge every personal field at spec time — see `meta/requirements-checklist.md`.
- **Maintain a PII inventory** in `docs/SECURITY.md`: what personal data is held, where it is stored, why (the lawful basis or business reason), who can read it, and how long it is kept. This is what a regulator or enterprise client asks for first.
- **Never log personal data.** Log stable internal identifiers instead, and resolve them at read time by someone with the right to. See `observability-logging.md`'s redaction list.
- Personal data does not go into URLs, analytics events, error-tracker payloads, or third-party telemetry without an explicit decision recorded as an ADR.
- **Support deletion from the start.** A user-deletion path that has to be invented later, across a schema that assumed permanence, is a rewrite. Decide per table: hard delete, or anonymise in place (null the personal columns, keep the aggregate row).
- **Support export.** Where personal data is held on behalf of a person, they may be entitled to a copy of it. One code path assembling it beats a manual query each time.
- Deletion propagates to backups, caches, search indexes, queues, and downstream processors. Document what the delay is per store rather than pretending it is instant.

## Encryption

- **In transit: TLS 1.2 minimum, 1.3 preferred, everywhere** — including service-to-service traffic inside a private network and connections to the database. Enable HSTS at the edge, per `security.md`.
- **At rest: encryption enabled on every datastore, backup, and object store.** Managed platform encryption satisfies this; it must be explicitly on, not assumed.
- **Restricted-tier fields get application-level encryption or tokenisation** on top of disk encryption — disk encryption protects a stolen drive, not a leaked query result or a compromised read replica.
- **Never invent a scheme.** Use the platform's KMS or a vetted library, with keys held in the secret store per `secrets-management.md`. Key rotation is planned before launch, not after.
- **Passwords are hashed, never encrypted** — bcrypt or argon2 per `auth.md`. Encryption is reversible; that is the wrong property for a password.
- Payment card data: do not store it. Use a payment provider's tokenisation so the card number never reaches your systems. Storing it pulls the whole system into PCI-DSS scope.

## Retention

- **Every Confidential and Restricted table has a documented retention period** and an automated job that enforces it. Data kept "just in case" is pure liability — it can be breached, and it must be produced on request.
- Logs containing any personal data (including IP addresses) get an explicit retention window, typically 30–90 days.
- Backups have their own retention, and their own deletion path. A backup kept forever silently overrides every retention rule above it.
- Deletion is verified: a scheduled job that has been failing quietly for six months is worse than no job, because the policy is documented as met.

## Cross-Border and Third Parties

- Record where data is physically stored and processed. Data residency is frequently a contractual requirement in enterprise work, and it constrains hosting-region choices made in `/hld` — write it as an ADR.
- Every third party that receives personal data (analytics, error tracking, email, support tooling, LLM APIs) is listed in `docs/SECURITY.md` with what it receives and why.
- **Never send Confidential or Restricted data to a third-party API without an explicit recorded decision.** This includes pasting production data into an LLM prompt.

Related: `access-control.md` (who may read a record), `secrets-management.md` (protecting keys), `observability-logging.md` (redaction), `database.md` (schema, soft delete), `meta/threat-model.md` (what the data is protected against).
