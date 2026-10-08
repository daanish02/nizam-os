---
title: Roadmap — nizam-os (Personal Domain)
status: DRAFT
version: 0.2.0
date: 2026-09-10
scope: personal
derived_from: docs/PRD.md §4
---

# Roadmap

Build order by dependency, not by calendar. No dates — no external party is
waiting, and a date nobody is held to is noise.

**Convention.** Each phase ships one idempotent orchestrator script that
reaches or verifies that phase's exit criteria. Running it twice reaches the
same state as running it once *(NFR.17)*. It is the canonical way to set up,
verify or recover a phase — and because it is also the recovery path, it gets
exercised continuously rather than only in a crisis.

> **Placeholders.** `[PENDING — SRS Q<n>]` marks ordering or content that
> depends on an unresolved question in `docs/SRS.md`.

---

## Phase 0 — Resolve the blocking questions

**Not a build phase.** Listed first because it gates everything after it.

Five open questions in `docs/SRS.md` change the shape of what gets built rather
than merely its parameters:

| Q | Question | What it changes |
| :--- | :--- | :--- |
| Q2 | Behaviour when inference is unavailable | **Every service contract.** Degrade or fail is an interface decision, not a config value |
| Q1 | Is zakat Obligation-class? | The correctness bar on all financial arithmetic |
| Q10 | Are goals and journal in the first cycle? | Whether the `personal` service is two entities or four |
| Q6 | Boundary of safe unattended recovery | The permitted-action list Nazim operates under |
| Q3 | Inference spend ceiling | The one control currently designed but unenforceable |

**Exit criteria:** each answered in `docs/SRS.md`, and every `[PENDING]` marker
they govern resolved across the high-level docs. Find them with
`grep -rn "PENDING" docs/`.

---

## Phase 1 — Verification before construction

**What.** The single check command, the commit gate, and the first adversarial
tests.

**Why first.** `docs/TESTING.md` records that no test exists anywhere and no
gate runs lint or type checking. Every phase after this one adds code whose
correctness is currently unverifiable. Building the net after the code means
retrofitting tests onto decisions already made, which reliably produces tests
that assert what the code does rather than what it should do.

**Includes**

- One command running lint, format check and tests across every component.
- A commit gate running exactly that command — the same check locally and in
  any pipeline, so a skipped local check cannot pass silently.
- Test layout per `docs/TESTING.md` §2.
- The first adversarial tests: path containment and fetch filtering — the two
  **high × high** threats *(T-16, T-24)*.

**Exit criteria:** the check command passes from a clean checkout; the two
adversarial tests exist and fail when their control is removed.

---

## Phase 2 — Foundation

**What.** The infrastructure everything runs on. Largely in place already; this
phase is about making it reproducible rather than merely working.

**Includes** database with the extensions retrieval needs; cache; the model
proxy with spend tracking and the ceiling from Q3; observability — metrics,
logs, dashboards; secrets encrypted at rest; the `audit` schema and its
insert-only grants; host hardening.

**Exit criteria:** a rebuild from the phase script reaches a working
foundation. The audit record rejects update and delete **by grant**, proven by
test *(C-12)*.

---

## Phase 3 — Agent baseline

**What.** The agent runtime configured correctly before any agent goes live.

**Why before any agent.** The controls in `docs/SECURITY.md` §6 are per-profile
settings. Establishing them once as the baseline is the difference between a
checklist that is applied and one that is remembered.

**Includes** the surface and its channels; per-agent identities; the approval
gate on; runtime capability acquisition disabled; instruction restricted to the
owner's identity; secret redaction on; models pinned; spend attribution live.

**Exit criteria:** an agent connects, refuses instruction from any other
identity, and requires approval for a state change — each proven by test, not
by inspection *(C-01, C-02, C-20)*.

---

## Phase 4 — Nazim: self-maintenance

**What.** CP.04. The system watches itself.

**Why here.** Nazim maintains everything built after it. A failure in Nazim
takes down the ability to recover from other failures; a failure in Noor or
Ayah is recoverable by hand. Build the thing that keeps the others alive first.

**Depends on** Q6 — the permitted-action list in `docs/RUNBOOK.md` §3 cannot be
finalised without it. Until then, Nazim escalates rather than acts.

**Includes** detection of a failed component; the permitted-action allowlist
matching whole invocations *(C-06)*; bounded retry then escalation; incident
reporting legible without logging in; read access to its own documentation so
it can answer questions about the system *(FR.04.4.1)*.

**Exit criteria:** a deliberately stopped component is detected, restarted and
reported without the owner involved. An invocation composing an allowlisted
command is refused, proven by test *(T-33)*.

---

## Phase 5 — Noor: knowledge

**What.** CP.03. Capture, classification, retrieval.

**Why before finance.** It is the capability the owner reaches for most often,
it is the smallest correctness surface — a misfiled note is annoying, a wrong
balance is corrosive — and it is where the system's largest attack surface
lives *(TB-8)*. Building it early means the injection controls are exercised
early rather than assumed.

**Includes** the `knowledge` schema; the vault; ingestion from link, video and
document; classification proposed by the service, never asked of the owner; the
two-pass approval flow; combined meaning- and word-based retrieval, degrading
to word-based alone when embedding is unavailable.

**Exit criteria:** a source is captured, drafted, approved and written; it is
retrievable by meaning. A rejected draft leaves nothing behind. Retrieval
degrades and says so when embedding is unavailable *(FR.03.3.3)*.

---

## Phase 6 — Ayah: tasks and habits

**What.** CP.02 and the confirmed part of CP.05.

**Scope note.** `[PENDING — SRS Q10]` — the owner named **tasks and habits**.
Goals and journal were carried from earlier material and are unconfirmed. This
phase builds what was named; the rest waits on Q10.

**Includes** the `personal` schema; task capture and state; habit logging with
streaks derived rather than stored; the morning briefing and evening recap;
recorded failure when a scheduled delivery does not happen.

**Exit criteria:** a task and a habit completion are both recorded
conversationally. The briefing arrives unprompted. A suppressed delivery leaves
a retrievable record of the failure *(FR.02.2.3)*.

---

## Phase 7 — Ayah: finance

**What.** CP.01 — the largest surface and the one where being wrong costs most.

**Why after tasks.** Same agent, so the agent already exists; and the
correctness bar here is higher than anywhere else in the system, which is worth
approaching with the test infrastructure already exercised by two prior phases.

**Depends on** Q1 — if zakat is Obligation-class, the bar rises further.

**Includes** the `finance_personal` schema; exact arithmetic as a separate
callable capability; transaction and transfer recording; category vocabulary
enforced at write time; spending reports with amortisation; balances with rate
and as-of time; budgets; zakat computed at request time and stored nowhere.

**Exit criteria:** a transaction is recorded conversationally; a period report
reconciles exactly; a transfer between the owner's own accounts does not appear
as spending; zakat computes with its threshold and source stated, and **fails
rather than defaulting when the threshold cannot be retrieved**
*(FR.01.5.2)*.

---

## Phase 8 — Hakim: research

**What.** Multi-source research, drawn on by CP.03 and CP.07.

**Why here.** Rashid depends on it — the investor delegates the reading and
keeps the judgment. Building it standalone first means the delegation bounds
are exercised before investment analysis depends on them.

**Includes** research through intermediate files rather than held in context,
so a deep task does not exhaust it *(FR.07.2.2)*; delegation bounded in depth
and concurrency; curated output written to the vault; sub-agents never
addressing the owner directly.

**Exit criteria:** a multi-source task completes without truncating its own
inputs, and its output reaches the vault through the approval gate. Delegation
respects its bounds, proven by test *(T-41)*.

---

## Phase 9 — Rashid: investment review

**What.** CP.07. Due diligence and compliance screening, read-and-advise only.

**Includes** brokerage reads with **no order capability present anywhere**;
delegation of reading to Hakim; compliance screening reported per constraint
with the figure each was judged on; purification computation; screening
reasoning preserved as a vault note.

**Exit criteria:** a candidate is screened, each constraint reported
individually with its figure and as-of date, the reasoning is retrievable
later, and **a missing input yields an explicit inconclusive result rather than
an assumed one** *(FR.07.3.3)*. No order-placing capability exists, proven by
its absence from the service.

---

## Phase 10 — The external-agent boundary

**What.** The A2A interface: an agent built outside the system can be delegated
a task and return a result, without any existing agent being modified
*(FR.06.4.1)*.

**Why last.** It opens a new trust boundary *(TB-11)*, and it is worth opening
only once the internal containment model has been exercised by five agents. A
containment model retrofitted onto an already-open interface is far harder than
one declared before.

**Includes** external identity verification; the same approval gate and
capability scoping as internal agents; external identity recorded on every
contributed action; returned results treated as untrusted content; delegation
bounded across the boundary.

**Exit criteria:** an external agent participates in a delegated task **with no
change to any existing agent's definition** *(NFR.20)*. Its unapproved action
does not execute, proven by test *(T-38)*. Its returned result cannot become
action except through the approval gate *(T-40)*. The threat model is re-run.

---

## Deliberately not on this roadmap

- **The business domain in its entirety.** Deferred until the personal system
  is proven, on the owner's direction. It gets its own requirements pass, not a
  slot here.
- **A second interface.** Out of scope by design *(C-02)*.
- **Order placement.** The system advises; the owner executes *(FR.07.1.2)*.

---

## Ordering notes

The owner named **finance first** when describing the problem, and it sits at
Phase 7 here. The reasoning for the difference: knowledge is a smaller
correctness surface and exercises the injection controls early, while finance
carries the highest cost of being wrong and benefits from arriving after the
test infrastructure has been used in anger. `[PENDING]` — this is a proposal;
the owner's own priority ordering overrides it.

**Phase 1 before everything is not a proposal.** Every subsequent phase asserts
controls and invariants that are currently unverifiable.

---

## Open items

| # | Item | Affects |
| :--- | :--- | :--- |
| 1 | The five blocking questions. `[PENDING — SRS Q1, Q2, Q3, Q6, Q10]` | Phase 0 gates everything |
| 2 | Build-order preference: knowledge-first or finance-first. `[PENDING]` | Phases 5 and 7 |
| 3 | Available build hours per week. `[PENDING — SRS Q9]` | Any sense of duration at all |
| 4 | Backup and restore is unspecified by any requirement. `[PENDING]` | Should become a requirement, then a phase item |
