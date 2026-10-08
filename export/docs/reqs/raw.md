# Raw Requirements — nizam-os

Running interrogation state for `/reqs`. Overwritten as the session proceeds.
Started: 2026-09-10.

---

## 0. Source Classification

**Situation:** Treated as **pure greenfield** by owner direction.

Code and prior docs exist on disk. The owner has directed that they are **not**
used as input to this run — not as notes, not as derived requirements. Every
category starts Missing and is elicited fresh.

Two reasons on record:

1. The project **predates Feanor**. Its existing docs were written to a
   different method and carry that method's shape.
2. **Feanor's project structure does not fit this project.** Feanor's layout
   conventions assume a single backend service (± a frontend). nizam-os is a
   multi-agent operating system spanning a VPS, systemd units, a fleet of
   agents, a knowledge vault, and shared infrastructure. Not every Feanor
   standard can or should be followed here.

Consequence for the whole pipeline: Feanor's **method** (phase gates, CP/CN/FR
traceability, coverage gate, zigzag validation, ticket verification) is
adopted. Feanor's **layout conventions** are adopted only where they fit, and
every deviation is recorded with a reason rather than silently ignored.

---

## 1. Audience Gate

**Answering:** the technical owner, directly.

Full technical vocabulary. Security (§2.6), operational (§2.7) and delivery-team
(§2.8) questions asked directly, not deferred.

---

## 2. Coverage Checklist

| # | Category | Status |
| :- | :-- | :-- |
| 0.5 | Customer Problems (CP) | Missing |
| 1 | Problem / Why | Missing |
| 2 | Users / Personas | Missing |
| 2.5 | Customer Needs (CN) | Missing |
| 3 | Core Workflows | Missing |
| 4 | Scope Boundaries | Missing |
| 5 | Non-Functional Constraints | Missing |
| 5a | Security & Data Constraints | Missing |
| 5b | Operational Constraints | Missing |
| 5c | Delivery Team & Existing Stack | Missing |
| 6 | Integrations / External Dependencies | Missing |
| 7 | Budget / Timeline | Missing |
| 8 | Success Metrics | Missing |
| 9 | Failure Modes / Edge Cases | Missing |
| 10 | Competitive / Market Context | N/A — personal infrastructure, one owner, not market-facing |

**Gate status (updated 2026-09-10, after drafting):**

Coverage after the draft pass:

| # | Category | Status |
| :- | :-- | :-- |
| 0.5 | Customer Problems (CP) | Covered — CP.01–CP.06, all class E |
| 1 | Problem / Why | Covered |
| 2 | Users / Personas | Covered — single owner, two modes |
| 2.5 | Customer Needs (CN) | Covered — 23 CNs, all traced |
| 3 | Core Workflows | Covered — W-01..W-11 in PRD |
| 4 | Scope Boundaries | Covered — personal only, business deferred |
| 5 | Non-Functional Constraints | **Partial** — every target is a proposal |
| 5a | Security & Data Constraints | **Partial** — AC.01–AC.10 written; retention unset |
| 5b | Operational Constraints | **Partial** — safe-autonomy boundary undrawn |
| 5c | Delivery Team & Existing Stack | **Partial** — capacity unknown |
| 6 | Integrations / External Dependencies | Covered |
| 7 | Budget / Timeline | **Partial** — no inference ceiling |
| 8 | Success Metrics | **Partial** — all proposed, none stated |
| 9 | Failure Modes / Edge Cases | **Partial** — derived, not elicited |
| 10 | Competitive / Market Context | N/A |

**Gate: still NOT PASSED.** Seven categories remain Partial.

**Deviation D-002 — drafting before the gate.** Feanor's requirements-agent
forbids drafting `docs/SRS.md` until every category is Covered or N/A. It was
drafted anyway, deliberately. Reason: the owner stated he could not answer the
funnel questions cold — *"even I don't know how to answer all of these
questions"* — and asked for the documents to be produced from existing material
instead. The draft is therefore serving as the elicitation instrument: it is
easier to correct a claim than to generate one. Every inferred item is marked
**[CONFIRM]** in the document and listed in §12. The gate closes when those are
answered, at which point the documents move from DRAFT to locked.

---

## Customer Problems

_(CP.xx — `[Subject] [must/expects/hopes] [Object] [or Penalty]`. O=Obligation, E=Expectation, H=Hope.)_

**Round 1 — owner, 2026-09-10.** Verbatim substance, not yet classified:

- Without another means of tracking money, the owner cannot understand where
  his money is going. Domain: personal finances.
- The owner may not be able to remember a task, or a note, or anything of that
  kind.
- The project as a whole is automation of multiple parts of the owner's life,
  so that attention goes to larger decisions and bigger things.

**Current alternative (asked: what are you doing today instead?)** — "either it
is manual, or I'm not doing anything." No third option. Where a thing is not
manual, it simply does not happen.

**Round 2 — owner, 2026-09-10.** Classification and scope.

**Penalty test results:**

- Money: the owner does not know whether he is overspending *or underspending*
  — he has no way to find out. "I feel blind but nothing has broken yet." No
  hard loss has occurred. → **Expectation**, not Obligation.
- Tasks/notes: "I miss deadlines because of not having notes or tasks."
  Deadlines are already being missed. But in the personal domain the cost lands
  on the owner himself. → **Expectation**, strong.
- Manual-or-nothing: "cost is purely my own attention." → **Expectation**.

No Obligations surfaced in the personal domain. Recorded deliberately: this
system carries no contractual, regulatory or existential penalty. That is a
finding, not a gap — see §5a, where it also drives the security posture.

**Scope cut (major):** *"Let me limit myself only to the personal aspect for
now."* Business is deferred until the personal system is proven. Personal-only
is the scope of this SRS. Business agents are explicitly out of scope, revisited
in a later cycle.

**Infrastructure is not a problem:** *"the infrastructure works quite well,
there has been no issues with it."* Infrastructure reliability is therefore not
a CP. Self-maintenance is still wanted (see CP.04) but as an
attention-saver, not as a fix for an existing failure.

**Consolidation motive, stated directly:** *"it's like multiple mobile
applications — I want to put it into one thing and use an agentic approach."*
Replacing a set of separate apps with one agent-driven surface is itself a
problem being solved.

---

### Classified Customer Problems

| ID | Statement | Class |
| :-- | :-- | :-- |
| CP.01 | Owner **expects** to understand where his money goes — both overspending and underspending — or he continues operating blind on personal finances, with no way to find out. | **E** |
| CP.02 | Owner **expects** not to depend on his own memory for tasks, notes and commitments, or he continues missing deadlines. | **E** |
| CP.03 | Owner **expects** to retain and retrieve what he learns — he reads and learns a great deal and has no system for note-taking or for finding things again — or the reading does not compound. | **E** |
| CP.04 | Owner **expects** the system to look after itself, both its infrastructure and the application on it, or its upkeep becomes another manual task and defeats the purpose. | **E** |
| CP.05 | Owner **expects** personal tracking — tasks, habits — to live in one agentic surface instead of several separate mobile applications, or the fragmentation itself is the overhead. | **E** |
| CP.06 | Owner **expects** the operational work of his life to happen without his manual effort, or it is done manually or not at all, consuming attention he wants spent on larger decisions. | **E** |

All six are Expectations. CP.06 is the umbrella motive; CP.01–CP.05 are the
concrete domains it decomposes into.

### The four domains named by the owner

1. **Personal finance** — current costs and future plans.
2. **Learning** — note-taking, retrieval, making heavy reading stick.
3. **Self-maintenance** — the system takes care of itself, infrastructure and
   application alike.
4. **Personal tracking** — tasks, habits.

### Agency model (§3 question C)

*"Something that should act on its own, but with the proper guardrails in
place, and for some things it should track and remind me as I act."*

So: **mixed agency, decided per action, not globally.** Some actions are
autonomous-within-guardrails; others are track-and-remind only. Which class each
action falls into is a per-workflow decision, still to be elicited.

**Failure preference:** *"the more costly failure will be it does something I
didn't want it to do"* — with the qualifier that it is genuinely a mix, and
which failure is worse differs case by case. Recorded as: **wrong action is the
default-worse failure**, so guardrails bias toward silence over unwanted action,
but this is overridable per workflow and each workflow must state its own bias.

## Customer Needs

_(CN.{cp}.{n} — derived after CPs.)_

## Security & Data Constraints

_(Data classification, abuse cases AC.xx, access model, compliance.)_

## Recorded Deviations from Feanor Conventions

_(Each: what the convention says, what this project does instead, why.)_

- **D-001 — Layout.** Feanor `ops/root-layout.md` expects `backend/` or
  `services/<role>/` plus optional `frontend/`. nizam-os additionally carries
  agent profiles, VPS provisioning scripts, systemd units, dashboards, and a
  knowledge vault integration. Full root-layout conformance is not a goal.
  Reason: project scope is an operating system, not a web application.
