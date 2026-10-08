---
type: meta
title: Requirements Interrogation Method
description: Step-by-step interrogation protocol for /reqs — source classification, problem classification (CP/CN/FR), audience gate, funnel sequencing, probing technique, coverage checklist, and zigzag validation.
applies_to: [requirements, reqs, srs]
tags: [requirements, interrogation, srs, cp-cn-fr]
---

# Requirements Interrogation Method

This is the methodology behind `/reqs` (and reusable by `workflows/brownfield-standardize.md`'s `/document`). It governs _how_ to ask and classify, not what the output document looks like — `templates/srs-template.md` is the output shape.

## 0. Source Classification & Verification (before asking anything)

Software projects start from more states than "blank folder." Detect which applies before doing anything else:

| Code exists? | `docs/reqs/` has notes? | `docs/PRD.md` exists? | Situation                          | What to do                                                                                                                                                                                                                                                                                                                                                                                                                        |
| :----------- | :---------------------- | :-------------------- | :--------------------------------- | :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| No           | No                      | No                    | Pure greenfield                    | Every category starts Missing. Proceed to interrogation normally.                                                                                                                                                                                                                                                                                                                                                                 |
| No           | Yes                     | No/Yes                | Greenfield with pre-existing notes | Read `docs/reqs/` fully, cross-reference against the checklist, mark each category Covered/Partial/Missing. Only ask about what's Partial or Missing.                                                                                                                                                                                                                                                                             |
| Yes          | any                     | No                    | Brownfield, undocumented           | **Derive first, ask second.** Reverse-engineer the "what" from the actual codebase (routes, data models, integrations, entry points) and record it in `docs/reqs/raw.md` marked **Derived**, not Covered — code can tell you what exists, not why, or what's intentional vs. accidental. Then interrogate the person only for what code can't reveal: intent, priority, what's by-design vs. a bug, what's planned vs. abandoned. |
| Yes          | any                     | Yes                   | Docs exist alongside code          | **Verify, don't trust.** See Verification below — this is the only way to catch stale/outdated/incomplete requirements.                                                                                                                                                                                                                                                                                                           |

Regardless of path: never re-ask something already clearly established (from `docs/reqs/`, from code, or from a verified doc). Only ask about what's Partial, Missing, or Conflicting.

## 0a. Verification (when both a doc and code exist)

A category marked Covered by `docs/reqs/` notes or an existing `docs/PRD.md` is a _claim_, not a fact, once code exists that could confirm or contradict it. Before trusting it:

- Spot-check the claim against actual code/behavior for that category (e.g. a claimed persona/role against actual auth/role checks in code; a claimed integration against actual API clients/env vars used; a claimed workflow against actual routes/handlers).
- **Match** → stays Covered, note it was verified.
- **Mismatch** → downgrade to **Partial**, state the conflict explicitly (what the doc says vs. what the code does), and ask the person which is authoritative. Never silently pick one side.
- A doc's age or a `stale_after` date is a _hint_ to look harder, not proof of staleness by itself — the code check is what actually decides it.

## 0.5 Problem Classification (before audience gate, before funnel)

Before asking any requirement questions, identify and classify every business problem this system must solve. This ensures all downstream requirements are problem-anchored — not solution-first.

**Notation:** `[Subject] [must/expects/hopes] [Object] [or Penalty]`

| Label           | Keyword | Meaning                                                         |
| :-------------- | :------ | :-------------------------------------------------------------- |
| O — Obligation  | must    | Contractual, regulatory, or existential — hard penalty if unmet |
| E — Expectation | expects | Strong business expectation — trust or revenue loss if unmet    |
| H — Hope        | hopes   | Nice-to-have — no hard consequence if deferred                  |

**Output:** Assign IDs `CP.01`, `CP.02`... for each problem. Record in `docs/reqs/raw.md` under a `## Customer Problems` section. Every downstream FR must trace to a CP — problems with no FRs are a gap, FRs with no CP are an orphan.

**Technique:** Ask "what goes wrong if this system doesn't exist?" to surface Obligations first. Then ask "what would stakeholders be disappointed to lose?" for Expectations. Finally "what would be a bonus?" for Hopes. Do not embed solutions — "the system needs a dashboard" is not a CP, "managers cannot see real-time team utilisation" is.

## 1. Audience Gate (always first, before any content question)

Ask who's answering:

- **You, as technical owner** — full vocabulary, technical constraint questions asked directly.
- **A non-technical client** — plain language, skip deep technical-constraint questions in this conversation; those get asked to the technical owner (you) separately, not skipped entirely.
- **You, relaying for a client** — treat as the non-technical-client style unless you say otherwise, since you're translating.

This sets vocabulary and which categories get asked directly vs. deferred for the rest of the session.

**Async relay refinement:** if you're relaying questions to a third party who won't be answering live (an email, a shared doc, a client who replies whenever) — front-load the highest-value questions first within each stage. A partial reply is likely; make sure what comes back first is what matters most. ("Grill the sender, not the subject" — the person answering can only tell you what they know; ask what they're actually positioned to answer, in priority order.)

## 2. Funnel Sequencing

Ask in this order — don't jump to detail before shape is settled:

1. Problem / Why
2. Users / Personas — define by the job/problem being solved, not demographics. "A user who needs to reconcile invoices weekly" beats "a 35-45 year old finance manager."
3. Core Workflows (the shape of the thing)
4. Scope Boundaries (explicit out-of-scope)
5. Non-Functional Constraints (performance, scale, availability). **If the project has a UI: always ask mobile-first or desktop-first explicitly — never assume.** This decides breakpoint strategy and layout priority in `nextjs/project-layout.md`/`styling-ui.md`; guessing wrong here means redoing layout work later.
5a. Security & Data Constraints — its own stage, see §2.6. Never folded into the NFC answer above.
5b. Operational Constraints — who runs this once it is live, and what happens when it breaks. See §2.7.
5c. Delivery Team & Existing Stack — who builds and maintains it, and what they have already shipped. See §2.8.
6. Integrations / External Dependencies — includes what access/credentials/test accounts/environment setup are actually needed to build against each one, not just which APIs are used.
7. Budget / Timeline
8. Success Metrics — split into **Primary** (the one thing that defines success), **Secondary** (supporting signals), and **Guardrail** (what must not regress while chasing the primary metric).
9. Failure Modes / Edge Cases
10. Competitive / Market Context — **conditional, ask only if the project is market-facing** (real competitors, being positioned/sold externally). Mark N/A immediately for internal tools/technical products — don't ask at all if the answer is obviously "not applicable."

Each stage needs a _coherent_ answer (not exhaustive) before moving to the next. Don't ask "which database" before "who is this for" is settled.

## 2.5 Customer Needs Derivation (after core workflows, before NFCs)

For each CP, derive the outcomes the software must provide. Customer Needs are the bridge between problems and requirements — they describe _what the software must do for the user_, not _how_ it does it.

**Notation:** `[Subject] needs [system] to [Verb] [Object] [Condition]`

**ID format:** `CN.{cp}.{n}` — e.g. `CN.01.1` is the first need addressing `CP.01`.

**Outcome classes:**

| Class        | Meaning                                            |
| :----------- | :------------------------------------------------- |
| Information  | System provides data or status                     |
| Control      | System performs an action on behalf of the user    |
| Construction | System creates or transforms a persistent artifact |

**Rules:**

- Every CP must have ≥ 1 CN. A CP with no CNs means either the problem is out of scope (mark N/A with reason) or needs are missing (keep as Partial).
- CNs must not contain implementation decisions — "needs the system to send an email" is fine; "needs the system to use SendGrid" is not.
- Record under `## Customer Needs` in `docs/reqs/raw.md`.

## 2.6 Security & Data Constraints (after NFCs, before integrations)

Security requirements are elicited, not remembered. A control nobody asked for has nothing to trace to, so it gets dropped under time pressure and nobody can tell whether that was a decision or an oversight. Ask these directly — they decide the auth model, the data schema, the hosting region, and whether `docs/SECURITY.md` and a threat model are mandatory.

**Data classification** (drives `cross-stack/data-protection.md`):

- What personal data does the system hold? Name the fields, not "user data."
- Any regulated categories — payment, health, biometric, government id, children's data?
- Which jurisdictions' residents' data, and must it stay in a particular region?
- How long must each category be kept, and what happens at the end of that period?

**Actors and abuse** (drives the threat model):

- Who are the untrusted actors? At minimum: anonymous internet, authenticated user acting outside their rights, compromised third-party integration, malicious insider.
- **What must a user never be able to do?** Phrase as abuse cases: "a customer must not read another customer's invoice," "a support agent must not export the full user table." These become `AC.xx` items and are the direct input to `access-control.md`.
- What is the worst realistic outcome of a breach here — regulatory, financial, or reputational? This sets how much control is proportionate.

**Access model:**

- Is the system multi-tenant? If so, what is the tenant boundary, and may any data cross it?
- What roles exist, and what may each do? Distinguish role checks from record ownership — see `access-control.md`.
- Is MFA required, for whom? Is SSO required? Enterprise buyers frequently mandate SAML/OIDC, and retrofitting it is expensive.
- Is an audit trail required — who did what, when — and who reads it?

**Compliance:**

- Any framework the project is contractually held to (SOC 2, ISO 27001, HIPAA, PCI-DSS, GDPR)? Ask explicitly. Clients rarely volunteer it, and it is not retrofittable cheaply.
- Any client security questionnaire, penetration test, or review the system must pass before launch?

**Recording:** Data classification, abuse cases, and the access model go in `docs/reqs/raw.md` under `## Security & Data Constraints`, with abuse cases numbered `AC.01`, `AC.02`, … Mark N/A with a reason only when genuinely inapplicable — "no personal data at all" is rare and worth stating explicitly when true.

## 2.7 Operational Constraints (after security, before integrations)

Who operates this once it is live, and what happens when it breaks. These answers decide which **optional capabilities** the project takes on — see `docs/CAPABILITIES.md` for the tier model.

**Ask for outcomes, never for technology.** This is a hard rule, not a style preference:

- A client shown a menu of tools says yes to all of them, which produces exactly the speculative complexity `conventions/coding-principles.md`'s YAGNI section exists to prevent. The cost lands on you, months later.
- `/reqs` stays in problem space by design — the requirements agent MUST NOT recommend frameworks. Naming Prometheus here breaks that.
- The person answering usually cannot evaluate the tool, but can always answer what they need to happen.

Ask these. Each maps to a capability decided later, at `/hld`:

| Ask | Implies |
| :--- | :--- |
| "Who finds out first when this breaks — you, or a customer telling you?" | metrics + alerting |
| "How long can it be down before it genuinely hurts?" | availability target, health checks, alerting urgency |
| "Is someone on call, or is this fixed next working day?" | alerting routing, runbook depth |
| "When something is slow, do you need to know *which* step was slow, across services?" | distributed tracing |
| "How many users at peak, and what is 'too slow' for them?" | caching, performance budgets, load testing |
| "Do you need to turn a feature on for some users before everyone?" | feature flags |
| "Does any work need to keep running after a user closes the page?" | background jobs |
| "Will people search this data, and how forgiving must that search be?" | full-text search |
| "Which languages and regions do users work in?" | i18n, data residency |
| "Who else needs to see reports on this, and how often?" | reporting/export |

**Record answers as outcomes, not solutions**, exactly as §2.5 requires of Customer Needs: *"the team must know within 5 minutes when checkout starts failing"* — not *"set up Grafana."* The first survives a change of tooling and is testable; the second is an implementation decision made by the wrong person at the wrong phase.

**Push for numbers.** "Fast recovery" and "high availability" are the vague language §"No Vague Success Language" already rejects. "Down for more than 15 minutes during business hours costs us orders" is a requirement.

The architect converts these into concrete capability selections at `/hld`, with cost and benefit for each, and records each acceptance as an ADR.

## 2.8 Delivery Team & Existing Stack (after operational constraints, before integrations)

Who builds and maintains this is the strongest single input to backend language selection — in most projects stronger than workload shape. A technically ideal language nobody on the team can maintain is the wrong choice. This is never volunteered, so ask for it directly.

**Ask about people and existing systems, never for a language preference.** Same hard rule as §2.7, for the same reason: "which language do you prefer?" invites a technology decision from whoever happens to be in the room, at the phase that is meant to stay in problem space. What the team has actually shipped is a fact; what they prefer is an opinion that belongs to the architect at `/hld`.

| Ask | Implies |
| :--- | :--- |
| "Who writes and maintains this after launch — you, an in-house team, a contractor, or nobody decided yet?" | maintenance burden; how conventional the stack must be |
| "What have they shipped to production, and in what?" | the realistic language candidates — *shipped* is the bar, not *has read about* |
| "What else does this team already run — services, CI, deploy targets?" | reuse of existing ops and deploy model; container base |
| "How many people, and is anyone on this full-time?" | one service vs. several; how much operational surface is affordable |
| "Is there an existing internal system this has to sit alongside or share code with?" | hard language/runtime constraint; shared library reuse |

**Record as facts, not conclusions:** *"two engineers, both shipped Django and FastAPI to production, no Go experience"* — not *"use Python."* The language decision is the architect's at `/hld`, made against the criteria table in `templates/high-level-docs/architecture-template.md`.

Mark N/A only when the team genuinely is not yet known (a spec written before anyone is hired) — and say so explicitly, because the architect must then choose for maximum conventionality rather than for team fit, which is a different decision with different trade-offs.

## No Vague Success Language

Never accept "fast," "intuitive," "user-friendly," "modern," "scalable" etc. as a finished answer for a requirement or metric — these aren't measurable. Push for a concrete number or criterion ("p95 latency under 200ms," "a new user completes signup without help") before marking that requirement Covered.

## 3. Probing Technique

When an answer is generic or surface-level, ask exactly **one** grounding follow-up before moving on:

- "Why does that matter?" — surfaces the real constraint behind a stated preference.
- "Walk me through one concrete example." — surfaces what a vague workflow actually involves.

Don't chain follow-ups indefinitely — one grounding question, then move on with whatever you have.

## 4. Pacing

- One question at a time.
- Prefer concrete multiple-choice framing over open-ended, especially for a non-technical respondent.
- Open-ended is fine for problem-statement / vision questions where you genuinely don't know the shape of the answer yet.

## 4a. State File Shape (deterministic — same structure every run)

`docs/reqs/raw.md` tracks per-category status. Judgment decides the status/content per category; the file's shape is fixed:

```markdown
# Raw Requirements

## {{CATEGORY_NAME}}

- **Status:** Covered | Partial | Missing | N/A | Conflicting
- **Source:** docs/reqs/{{FILE}} | interrogation | derived-from-code | {{DOC_PATH}} (verified)
- **Content:** {{ANSWER_OR_DERIVED_CONTENT}}
- **N/A reason:** {{REQUIRED IF STATUS IS N/A}}
- **Conflict:** {{WHAT DOC SAYS}} vs. {{WHAT CODE DOES}} — {{REQUIRED IF STATUS IS CONFLICTING}}
```

One `##` section per checklist category, in funnel order, always present (even if status is Missing) so the file always shows the full checklist state at a glance.

**Omit inapplicable fields entirely — don't leave them blank.** `N/A reason` appears only when Status is N/A; `Conflict` appears only when Status is Conflicting; `Content` is omitted for a bare N/A entry with nothing else to say. A section with an empty `- **Content:**` line is worse than no line at all — it looks unfinished rather than deliberately not applicable.

## 5. Coverage Checklist Gate

`docs/SRS.md` **MUST NOT** be drafted until every category below is **Covered** or explicitly marked **N/A** with a one-line reason in `docs/reqs/raw.md`. A category marked N/A without a reason is treated as Missing, not Covered. A category whose only content is vague, unmeasurable language (see above) is treated as Partial, not Covered. A category flagged **Conflicting** by the Verification step (§0a) is treated as Missing until the person resolves which side is authoritative — never averaged or silently resolved by the agent.

- [ ] Customer Problems (CP.xx — classified as O/E/H)
- [ ] Customer Needs (CN.xx.xx — derived from CPs)
- [ ] Users / Personas
- [ ] Core Workflows
- [ ] Scope Boundaries (explicit out-of-scope)
- [ ] Non-Functional Constraints
- [ ] Security & Data Constraints (classification, abuse cases AC.xx, access model, compliance — §2.6)
- [ ] Operational Constraints (who operates it, detection, recovery, scale expectations — §2.7)
- [ ] Delivery Team & Existing Stack (who builds/maintains it, what they have shipped, existing systems — §2.8)
- [ ] External Interfaces (hardware, external software systems, protocols — omit with N/A if none)
- [ ] Integrations / External Dependencies (incl. access/credentials/test-account prerequisites)
- [ ] Budget / Timeline
- [ ] Success Metrics (Primary / Secondary / Guardrail)
- [ ] Failure Modes / Edge Cases
- [ ] Competitive / Market Context (N/A by default for non-market-facing projects)

## 6. Zigzag Validation (mandatory before drafting SRS)

After the coverage gate passes and before generating `docs/SRS.md`, run this traceability check. A failed check is a coverage failure — treat the affected item as Missing, not Covered.

- [ ] **Every CP has ≥ 1 CN.** A CP with no CNs means the problem is unaddressed — either mark it N/A with a reason or derive the missing CNs.
- [ ] **Every CN has ≥ 1 FR.** A CN with no FRs means a user need will not be implemented — fill the gap or explicitly defer with a reason.
- [ ] **Every FR has a CN parent.** An FR with no CN is an orphan — it implements something nobody asked for. Remove it or find its correct CN.
- [ ] **Every CP has a traceable path to ≥ 1 FR.** Walk the full chain; a CP only connected to CNs with no FRs is effectively unimplemented.
- [ ] **Every abuse case (`AC.xx`) has ≥ 1 mitigating FR or NFR.** An abuse case with nothing mitigating it is an accepted risk — and an accepted risk must be recorded as one in `docs/SECURITY.md` with a named owner, never left silently unaddressed. This is the security half of the same traceability: a control with no abuse case is unjustified, an abuse case with no control is an open hole.
- [ ] **Every classified data category has a stated retention period and storage location.** Confidential or Restricted data with neither is not ready to design against — see `cross-stack/data-protection.md`.

Record the validation result in `docs/reqs/raw.md` under `## Zigzag Validation`.

## 7. Secrets Rule

Never write a real credential, API key, password, or other secret into `docs/reqs/raw.md`, `docs/SRS.md`, or any other file under `docs/reqs/`. If one is needed to explain an integration, use an obvious placeholder (`{{STRIPE_SECRET_KEY}}`) and note where the real value should live (environment variable, secrets manager) instead.
