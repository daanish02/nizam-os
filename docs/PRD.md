---
title: Product Requirements Document — nizam-os (Personal Domain)
status: DRAFT
version: 0.1.0
date: 2026-09-10
scope: personal
derived_from: docs/SRS.md
---

# Product Requirements Document

**Project:** nizam-os
**Scope:** Personal domain. Business domain deferred to a later cycle.
**Status:** DRAFT — distilled from `docs/SRS.md`. Open questions there apply
here unchanged.

---

## 1. Executive Summary

One person runs his life the way most people do: some of it manually, and the
rest not at all. Money moves without being recorded, so he cannot tell whether
he is overspending or underspending. Commitments live in his memory, so
deadlines slip. He reads heavily, but nothing he reads is captured in a form he
can find again. Each of these has a mobile application that would solve it in
isolation, which is how he ends up with several applications and the overhead
of switching between them.

nizam-os replaces that with a small team of autonomous agents on a machine he
already owns, reachable through one conversational surface. He says what
happened; the system records it. It tells him each morning where he stands. It
captures what he reads, classifies it without being told how, and finds it
again by meaning. It watches its own components and restarts what breaks. It
never changes anything without asking first.

The point is not automation for its own sake. It is that the operational layer
of his life stops consuming the attention he wants spent on decisions. In his
words: *"this entire project is going to be automation of multiple things of my
life, that way I focus on the larger decisions, bigger things."*

Nothing here carries a hard penalty — no contract, no regulator, no second
person harmed if it fails for a day. That shapes the product: correctness and
containment matter more than availability, and the system's own autonomy is the
risk being managed, not an outside attacker.

---

## 2. Personas & Core Workflows

### 2.1 User Personas

- **The owner — sole user.** Runs his own personal life and, later, a business.
  **Job:** keep money recorded, commitments held, reading retained and the
  system healthy, without opening an application, remembering to do it, or
  logging into a server.

- **The owner — as operator.** The same person in a different mode.
  **Job:** understand what the system did, correct it when wrong, and extend
  it, without re-reading its source to recall how it works.

No second persona exists. Single-user by design.

### 2.2 Critical Workflows

**W-01 — Record a transaction.** The owner states a payment in conversation.
The system parses amount, account, category and counterparty, presents what it
will record, and writes it on approval. *(FR.01.1.1–FR.01.1.4)*

**W-02 — Understand spending.** The owner asks where his money went. The system
reports the period broken down by category, against the comparable prior
period, with irregular costs spread across the months they cover.
*(FR.01.2.1–FR.01.2.3)*

**W-03 — Morning briefing.** Unprompted at a set time: current position across
accounts, what is due, what is coming. *(FR.02.2.1)*

**W-04 — Evening recap.** Unprompted at a set time: the day's spending,
outstanding commitments, and an open thread for a reflective entry.
*(FR.02.2.2, FR.05.3.1)*

**W-05 — Capture a source.** The owner drops a link, video or document. The
system extracts the content, proposes a title and classification, shows the
complete draft, and writes it to the vault only on approval.
*(FR.03.1.1–FR.03.4.2)*

**W-06 — Retrieve knowledge.** The owner describes what he is looking for. The
system returns matching notes by meaning as well as by wording.
*(FR.03.3.1–FR.03.3.3)*

**W-07 — Capture a commitment.** The owner states a task. It is recorded with
its due date and priority and held until closed. *(FR.02.1.1, FR.02.3.1)*

**W-08 — Track a habit.** The owner reports a completion. The system records it
and maintains the streak according to the habit's schedule.
*(FR.05.1.1, FR.05.1.2)*

**W-09 — Self-heal.** A component fails. The system detects it, attempts a
restart within an explicit permitted-action list, stops after a bounded number
of attempts, and reports what failed, what it tried, and what remains wrong.
*(FR.04.1.1–FR.04.3.1)*

**W-10 — Ask the system about itself.** The owner asks how something is
configured or why it is built that way. The system answers from its own
documentation. *(FR.04.4.1)*

**W-11 — Compute zakat.** On demand, from zakatable holdings against the
prevailing threshold, stating the threshold, its source and its as-of time —
and refusing to produce a figure it cannot source. *(FR.01.5.1, FR.01.5.2)*

**The rule across all of them.** Reads happen freely. Every write waits for the
owner. *(FR.06.1.1, FR.06.2.1)*

---

## 3. Requirements Reference

Full requirements, traceability and acceptance criteria: `docs/SRS.md`.

| Problem | Requirement group | Priority |
| :--- | :--- | :--- |
| CP.01 — Cannot see where money goes | FR.01.* — recording, reporting, position, budget, zakat | MUST |
| CP.02 — Memory is the record | FR.02.* — task capture, daily summaries, commitment state | MUST |
| CP.03 — Reading does not compound | FR.03.* — capture, classification, retrieval, approval | MUST |
| CP.04 — Upkeep is a burden | FR.04.* — detection, bounded recovery, incident reporting | MUST |
| CP.05 — Fragmented across applications | FR.05.* — habits, goals, journal, one surface | MUST / SHOULD |
| CP.06 — Manual or not at all | FR.06.* — scoped autonomy, approval gate, change record | MUST |

All six problems classify as **Expectations**. None is an Obligation. The
consequence is deliberate: this product is judged on whether it removes work,
not on whether it survives an outage.

---

## 4. Constraints (Budget / Timeline)

**Infrastructure.** One self-hosted machine, already provisioned and in
service, at a fixed annual cost. Not elastic. Memory is the binding constraint —
agents, services, datastore and observability are co-resident, so no two heavy
scheduled processes may start together.

**Inference.** All model usage passes through one local proxy where spend is
tracked and capped. **[CONFIRM] — no monthly ceiling has been set.** This is
the only variable cost in the system and it is currently unbounded.

**Timeline.** Sequenced by dependency, not by calendar. No deadline exists,
because no external party is waiting. Build order:

1. Knowledge capture and retrieval — the capability the owner reaches for most.
2. Personal tracking — tasks first, habits after.
3. Personal finance — the largest surface and the one where correctness costs
   the most to get wrong.
4. Self-maintenance — valuable throughout, but by the owner's own account the
   infrastructure is currently behaving, so it is not urgent.

**[CONFIRM]** — this ordering is proposed, not stated. The owner named finance
first when describing the problem.

**Delivery capacity.** The owner builds and maintains this alone with an AI
coding assistant. **[CONFIRM] — available hours per week unknown.** It is the
single largest scheduling unknown.

---

## 5. Success Metrics

**[CONFIRM] — every figure below is a proposal. None was stated by the owner.**

**Primary.** The owner stops using separate applications for finance, tasks and
notes. One surface, or the product has not solved the problem it was built for.

**Secondary.**

| Metric | Proposed target |
| :--- | :--- |
| Daily briefing delivered on schedule | ≥ 95% of days |
| Sources captured per week | **[CONFIRM]** |
| Component failures recovered unattended | ≥ 80% |
| Transactions recorded conversationally rather than in another app | ≥ 90% |

**Guardrail — what must not regress while chasing the above.**

| Guardrail | Target |
| :--- | :--- |
| Approved actions the owner later regrets | Zero. Any occurrence is a defect in how the approval was presented. |
| Monthly inference spend | Within the ceiling once set. |
| Owner sessions logged directly into the machine | Trending to zero. Needing to log in means the reporting failed. |
| Financial reporting accuracy | Exact. Category totals reconcile to period totals, always. |

The guardrails matter more than the secondary metrics here. A system that
captures more sources but occasionally does something unwanted is worse than
one that captures fewer and never does.

---

## 6. Explicit Out of Scope

**Deferred to a later cycle, with its own requirements pass:**

- The entire business domain — the coordination layer and the CFO, COO, CTO and
  CMO roles, with their services and data.
_(Investment review was previously listed here; it is now in scope — see §2.2
W-12 and W-13.)_

**Out of scope permanently, by design:**

- Multi-tenancy, multi-user access, or distribution to anyone else. This is
  personal infrastructure, not a product.
- General-purpose assistant behaviour. Each agent holds a domain; anything
  outside it is refused or routed, never improvised.
- Any agent operating outside its declared capability set.
- Any component reaching an external model provider directly rather than
  through the single proxy.
- Placing orders, moving money, or taking any irreversible external action.
  The system advises and records; the owner executes.
- A web interface, a mobile application, or any second surface.
- Public reachability of any component.

---

## 7. Competitive / Market Context

Not applicable. Personal infrastructure for one person, not positioned or sold.
The alternative it displaces is a handful of consumer applications plus manual
effort — that is the comparison that matters, and it is covered by the primary
metric in §5.

---

## 8. Open Questions

Carried from `docs/SRS.md` §12, unresolved and blocking lock:

1. Is zakat an Obligation rather than an Expectation?
2. What should happen when the inference path is unavailable?
3. What monthly inference spend is acceptable?
4. Are the proposed latency and uptime targets right?
5. How long must financial records, journal entries and operational logs be kept?
6. What must the system never attempt to fix unattended?
7. ~~Does investment review belong in this cycle?~~ **RESOLVED: yes.**
8. What single measurable outcome means this worked?
9. How many hours per week are available to build it?
10. Are habits, goals and journaling all wanted in the first cycle, or is it
    finance, tasks and knowledge only?
11. Is the build order in §4 right, given finance was named first?
