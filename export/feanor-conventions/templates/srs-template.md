---
type: template
title: Software Requirements Specification (SRS) Template
description: IEEE 830-based SRS template with CP/CN/FR traceability chain — the primary requirements artifact produced by /reqs; defines problem classification, customer needs, external interfaces, functional requirements, and traceability matrix.
applies_to: [requirements, srs]
tags: [template, srs, requirements, ieee-830]
---

# Software Requirements Specification

> **Project Name:** {{PROJECT_NAME}}
> **Version:** 1.0.0
> **Date:** {{DATE}}
> **Author:** {{AUTHOR}}
> **Status:** Draft → Locked

> No vague, unmeasurable language ("fast," "easy," "scalable") without a concrete number or criterion. No credentials — use `{{PLACEHOLDER}}`.

---

## 1. Introduction

### 1.1 Purpose

This document specifies the software requirements for **{{PROJECT_NAME}}**. It is the authoritative source for functional requirements, non-functional requirements, and interface constraints. All downstream documents (`docs/PRD.md`, `docs/ARCHITECTURE.md`, `docs/specs/`) derive from this document.

**Intended audience:** engineering team, product stakeholders, QA, and any AI agent operating on this project.

### 1.2 Scope

**{{PROJECT_NAME}}** is {{ONE_SENTENCE_DESCRIPTION}}.

In scope: {{IN_SCOPE_SUMMARY}}.
Out of scope: {{OUT_OF_SCOPE_SUMMARY}}.

### 1.3 Definitions and Acronyms

| Term | Definition |
| :--- | :--------- |
| CP | Customer Problem — a classified business problem this system must address |
| CN | Customer Need — an outcome the software must provide to address a CP |
| FR | Functional Requirement — a specific system behavior implementing a CN |
| NFR | Non-Functional Requirement — a quality attribute with measurable criteria |

Add project-specific terms below.

### 1.4 References

- `docs/PRD.md` — Business-readable product requirements derived from this document
- `docs/ARCHITECTURE.md` — System design derived from this document
- `docs/specs/` — Binding API and data contracts derived from this document
- `docs/reqs/raw.md` — Raw stakeholder notes and interrogation state (if present)

---

## 2. Problem Classification

Classify every business problem this system must solve before deriving requirements. Each CP must use the structured notation and be assigned an Obligation/Expectation/Hope label.

**Notation:** `[Subject] [must/expects/hopes] [Object] [or Penalty]`

| ID | Problem Statement | Class | Penalty if Unmet |
| :--- | :--- | :--- | :--- |
| CP.01 | {{SUBJECT}} must {{OBJECT}} or {{PENALTY}} | O — Obligation | {{PENALTY}} |
| CP.02 | {{SUBJECT}} expects {{OBJECT}} or {{PENALTY}} | E — Expectation | {{PENALTY}} |
| CP.03 | {{SUBJECT}} hopes {{OBJECT}} | H — Hope | None |

**Class definitions:**

| Label | Keyword | Meaning |
| :--- | :--- | :--- |
| O — Obligation | must | Contractual, regulatory, or existential — hard failure if unmet |
| E — Expectation | expects | Strong business expectation — trust or revenue loss if unmet |
| H — Hope | hopes | Nice-to-have — no hard consequence if deferred |

---

## 3. Overall Description

### 3.1 Product Perspective

Context diagram showing this system's boundary and external actors. **Mermaid is mandatory.**

```mermaid
graph TD
    User([{{USER_ACTOR}}]) --> System[{{PROJECT_NAME}}]
    System --> ExtService([{{EXTERNAL_SERVICE}}])
    Admin([{{ADMIN_ACTOR}}]) --> System
```

Replace placeholders with actual actors and systems. Add subgraphs for internal components if relevant.

### 3.2 Customer Needs

For each CP, derive the outcomes the software must provide. Every CN must trace to exactly one CP.

**Notation:** `[Subject] needs [system] to [Verb] [Object] [Condition]`

| ID | Need Statement | Outcome Class | Traces To |
| :--- | :--- | :--- | :--- |
| CN.01.1 | {{SUBJECT}} needs the system to {{VERB}} {{OBJECT}} {{CONDITION}} | Information | CP.01 |
| CN.01.2 | {{SUBJECT}} needs the system to {{VERB}} {{OBJECT}} {{CONDITION}} | Control | CP.01 |
| CN.02.1 | {{SUBJECT}} needs the system to {{VERB}} {{OBJECT}} {{CONDITION}} | Construction | CP.02 |

**Outcome classes:**

| Class | Meaning |
| :--- | :--- |
| Information | System provides data or status to the user |
| Control | System performs an action on behalf of the user |
| Construction | System creates or transforms a persistent artifact |
| Entertainment | System provides an experience (rare in business software) |

### 3.3 User Personas

Defined by job-to-be-done, not demographics.

- **{{PERSONA_NAME}}:** {{PERSONA_DESCRIPTION}} — **Job:** {{JOB_TO_BE_DONE}}

### 3.4 Constraints

- **Platform / OS:** {{PLATFORM_CONSTRAINT}}
- **Regulatory / Compliance:** {{COMPLIANCE_CONSTRAINT}}
- **Technology:** {{TECHNOLOGY_CONSTRAINT}}
- **Budget / Timeline:** {{BUDGET_TIMELINE_CONSTRAINT}}

### 3.5 Delivery Team & Existing Stack

Facts about who builds and maintains this, gathered at `/reqs` §2.8. The architect reads this at `/hld` as the highest-weight input to language selection — record what the team has **shipped to production**, never a language recommendation.

- **Who builds / maintains it:** {{IN_HOUSE_TEAM_CONTRACTOR_OR_UNDECIDED}}
- **Shipped to production in:** {{LANGUAGES_FRAMEWORKS_WITH_EVIDENCE}}
- **Team size / availability:** {{SIZE_AND_WHETHER_FULL_TIME}}
- **Existing systems this must sit alongside:** {{SYSTEMS_OR_NONE}}
- **Existing ops / CI / deploy targets to reuse:** {{OPS_OR_NONE}}

If the team is genuinely not yet known, write `N/A — team not yet identified` rather than leaving this blank. That is a different input than "no constraints", and the architect handles it differently (choosing for conventionality rather than for fit).

---

## 4. External Interface Requirements

### 4.1 Hardware Interfaces

> List physical devices, sensors, or hardware APIs this software must interact with.
> For each: device name, interface type (USB/serial/GPIO/MQTT/etc.), data format, expected throughput.
> **Omit this section entirely if no hardware interfaces exist.**

| Device | Interface | Data Format | Throughput / Latency |
| :--- | :--- | :--- | :--- |
| {{DEVICE_NAME}} | {{INTERFACE_TYPE}} | {{FORMAT}} | {{SPEC}} |

### 4.2 External Software Systems

For each third-party service or legacy system this software integrates with:

| System | Version / Tier | Integration Type | Auth Method | Rate Limits | SLA |
| :--- | :--- | :--- | :--- | :--- | :--- |
| {{SYSTEM_NAME}} | {{VERSION}} | REST / Webhook / SDK | {{AUTH}} | {{LIMITS}} | {{SLA}} |

### 4.3 Communication Protocols and Formats

| Protocol | Purpose | Format | Notes |
| :--- | :--- | :--- | :--- |
| HTTPS / REST | Primary API | JSON | All endpoints TLS 1.2+ |
| {{PROTOCOL}} | {{PURPOSE}} | {{FORMAT}} | {{NOTES}} |

---

## 5. Functional Requirements

Every FR must trace to a CN (and transitively to a CP). Use RFC 2119 keywords.

**FR ID format:** `FR.{cp}.{cn}.{n}` — e.g. `FR.01.1.1` is the first FR implementing `CN.01.1` which addresses `CP.01`.

| ID | Traces To | Priority | Requirement | Acceptance Criteria |
| :--- | :--- | :--- | :--- | :--- |
| FR.01.1.1 | CN.01.1 | MUST | The system shall {{VERB}} {{OBJECT}} {{CONSTRAINT}} | {{MEASURABLE_CRITERION}} |
| FR.01.1.2 | CN.01.1 | SHOULD | The system should {{VERB}} {{OBJECT}} {{CONSTRAINT}} | {{MEASURABLE_CRITERION}} |
| FR.01.2.1 | CN.01.2 | MUST | The system shall {{VERB}} {{OBJECT}} {{CONSTRAINT}} | {{MEASURABLE_CRITERION}} |
| FR.02.1.1 | CN.02.1 | MUST | The system shall {{VERB}} {{OBJECT}} {{CONSTRAINT}} | {{MEASURABLE_CRITERION}} |

**FR syntax:** `The [System] shall/should/may [Verb] [Object] [Constraint] [Condition]`

No code snippets, no implementation details. Each FR must have exactly one correct implementation derivable from it.

---

## 6. Non-Functional Requirements

| ID | Category | Priority | Requirement | Measurable Target |
| :--- | :--- | :--- | :--- | :--- |
| NFR.01 | Performance | MUST | API p95 latency | < 200ms under {{LOAD}} |
| NFR.02 | Security | MUST | Auth mechanism | JWT, RS256, 15min access token TTL |
| NFR.03 | Availability | SHOULD | Uptime | 99.5% monthly |
| NFR.04 | Scalability | SHOULD | Horizontal scaling | Stateless; supports N instances |

No vague adjectives — every NFR needs a number or criterion.

---

## 7. Traceability Matrix

Complete mapping from customer problems to functional requirements.

| CP | CP Description | CN | CN Description | FR | FR Description |
| :--- | :--- | :--- | :--- | :--- | :--- |
| CP.01 | {{CP_DESCRIPTION}} | CN.01.1 | {{CN_DESCRIPTION}} | FR.01.1.1 | {{FR_DESCRIPTION}} |
| | | CN.01.1 | {{CN_DESCRIPTION}} | FR.01.1.2 | {{FR_DESCRIPTION}} |
| | | CN.01.2 | {{CN_DESCRIPTION}} | FR.01.2.1 | {{FR_DESCRIPTION}} |
| CP.02 | {{CP_DESCRIPTION}} | CN.02.1 | {{CN_DESCRIPTION}} | FR.02.1.1 | {{FR_DESCRIPTION}} |

**Zigzag validation (mandatory before locking):**

- [ ] Every CP has ≥ 1 CN
- [ ] Every CN has ≥ 1 FR
- [ ] Every FR has a CN parent (no orphans)
- [ ] No vague/unmeasurable language in any FR or NFR
