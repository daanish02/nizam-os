---
type: template
title: Product Requirements Document (PRD) Template
description: Structural blueprint for docs/PRD.md — defines sections, field constraints, and completion criteria that the intake engine fills during /prd.
applies_to: [prd]
tags: [template, prd, requirements]
---

# Product Requirements Document (PRD)

> **Project Name:** {{PROJECT_NAME}}  
> **Version:** 1.0.0  
> **Status:** Locked / Approved  
> **Author:** {{ASK_FOR_NAME}}

> No vague, unmeasurable language ("fast," "easy," "modern," "scalable") anywhere in this document without a concrete number or criterion attached. Any credential/key/secret referenced uses a placeholder (`{{EXAMPLE_SECRET}}`), never a real value.

---

## 1. Executive Summary

- **Core Problem:** {{CONCISE_PROBLEM_STATEMENT}}
- **Proposed Solution:** {{CONCISE_SOLUTION_OVERVIEW}}
- **Target Value:** {{PRIMARY_BENEFIT_OR_METRIC}}

---

## 2. Personas & Core Workflows

### 2.1 User Personas

Defined by the job/problem being solved, not demographics.

- **{{PERSONA_NAME}}:** {{PERSONA_DESCRIPTION}} — **Job/Problem:** {{PERSONA_JOB_OR_PROBLEM}}

### 2.2 Critical Workflows

```text
[Step 1: Action] ──> [Step 2: Processing] ──> [Step 3: Outcome]
```

---

## 3. Requirements Reference

Full functional and non-functional requirements live in `docs/SRS.md`. This document does **not** restate them — it references the IDs that carry business weight and says why each matters commercially.

| SRS ID    | What it delivers for the business |
| :-------- | :-------------------------------- |
| `FR-0xx`  | {{BUSINESS_CONSEQUENCE}}          |
| `NFR-0xx` | {{BUSINESS_CONSEQUENCE}}          |

Everything in the SRS is binding whether or not it appears above. This table is the business-facing subset, not a filter — the SRS remains authoritative for scope, priority, and acceptance criteria.

---

## 4. Constraints (Budget / Timeline)

Hard limits the solution must fit inside. Dates and figures, not adjectives — "by Q3" and "under £20k/year running cost" are constraints; "soon" and "cheap" are not.

| Constraint    | Value                | Consequence if exceeded    |
| :------------ | :------------------- | :------------------------- |
| **Launch by** | {{DATE}}             | {{WHAT_HAPPENS}}           |
| **Budget**    | {{BUILD_OR_RUN_COST}} | {{WHAT_HAPPENS}}           |
| **Other**     | {{CONSTRAINT}}       | {{WHAT_HAPPENS}}           |

Omit a row only when the constraint genuinely does not exist — not when it is merely unknown. An unknown deadline is itself worth recording as unknown.

---

## 5. Success Metrics

Every metric needs a concrete, quantifiable target — no vague adjectives.

| Type          | Metric                                  | Target                  |
| :------------ | :-------------------------------------- | :---------------------- |
| **Primary**   | {{THE_ONE_METRIC_THAT_DEFINES_SUCCESS}} | {{QUANTIFIABLE_TARGET}} |
| **Secondary** | {{SUPPORTING_SIGNAL}}                   | {{QUANTIFIABLE_TARGET}} |
| **Guardrail** | {{WHAT_MUST_NOT_REGRESS}}               | {{QUANTIFIABLE_LIMIT}}  |

---

## 6. Explicit Out of Scope

The following features are intentionally deferred to prevent scope creep:

- {{OUT_OF_SCOPE_ITEM_1}}
- {{OUT_OF_SCOPE_ITEM_2}}

---

## 7. Competitive / Market Context (optional — omit for internal/non-market-facing projects)

> Include only if the project is market-facing (real competitors, being positioned/sold externally). Delete this section entirely otherwise.

- **Competitors:** {{COMPETITOR_NAME}} — {{HOW_THEY_SOLVE_THIS}}
- **Differentiation:** {{WHY_THIS_IS_DIFFERENT_OR_BETTER}}
