---
title: Runbook — nizam-os (Personal Domain)
status: DRAFT
version: 0.1.0
date: 2026-09-10
scope: personal
derived_from: docs/ARCHITECTURE.md, docs/SRS.md CP.04
---

# Runbook

What to do when something breaks.

**This document has an unusual primary reader.** Most of it is executed by
Nazim, the system-admin agent, not by the owner — CP.04 is the requirement that
the system look after itself, and this is the procedure it follows. The owner
reads it only when Nazim escalates, or when Nazim itself is what failed
*(FR.04.4.1)*.

**The rule that makes that safe:** Nazim may only execute what appears on the
permitted-action list in §3. Anything else stops and escalates. An agent that
can improvise a remedy on a production machine is not self-maintenance, it is
an unbounded actor with root-adjacent access *(C-06, T-32)*.

> **Placeholders.** `[PENDING — SRS Q<n>]` marks a value or boundary that
> depends on an unresolved question in `docs/SRS.md`. **Where the safe-autonomy
> boundary is undrawn, the procedure defaults to escalate rather than act.**

---

## 1. Detection

The system observes its own components and detects a failed one without the
owner looking *(FR.04.1.1)*. The owner should never be the detector — if he
notices first, detection has failed and that is itself a defect.

| Signal | Meaning |
| :--- | :--- |
| A supervised process is not running | The component is down |
| A component is running but not answering | The component is wedged — worse than down, because supervision thinks it is fine |
| A scheduled briefing did not deliver | Either the schedule or a dependency failed *(FR.02.2.3)* |
| Error rate rising in the logs | Degradation, not yet failure |
| Spend rising abnormally | A runaway loop or delegation *(T-11)* |
| Storage approaching capacity | Writes will begin failing *(F-06)* |

`[PENDING — SRS Q4]` Detection interval is unset. NFR.04 proposes an attempt
within five minutes of failure; unconfirmed.

---

## 2. The recovery loop

For any detected failure, in order:

1. **Identify** the component and the signal.
2. **Check the permitted-action list** in §3. If the remedy is not on it,
   **stop and escalate** — do not improvise.
3. **Attempt the permitted remedy**, once.
4. **Verify** the component is genuinely serving, not merely running.
5. **On success:** record the incident and report it. Do not stay silent
   because it worked — a component that needed restarting is information the
   owner wants *(FR.04.3.1)*.
6. **On failure:** retry up to the bound, then **escalate and stop**
   *(FR.04.2.2)*.

`[PENDING — SRS Q6]` The retry bound is unset. Until it is, the bound is **one
attempt, then escalate.** An unbounded retry loop against a component that
cannot recover is itself a failure mode *(T-35)*.

**Every attempt is recorded and reported**, including the ones that worked
*(FR.04.3.1, C-11)*.

---

## 3. Permitted actions

**This list is the whole of Nazim's authority.** It is an allowlist of complete
invocations, not of command prefixes — a prefix allowlist is defeated by
composition and is the usual way command allowlists fail *(T-33, C-06)*.

`[PENDING — SRS Q6]` **The list is not yet finalised, because the boundary of
safe unattended recovery has not been drawn.** SRS open question 6 asks what
the system must never attempt on its own. Until it is answered, the list below
is the proposed minimum and every entry is provisional.

### Proposed — provisional

| Action | Applies to | Why it is safe |
| :--- | :--- | :--- |
| Restart a stopped capability service | Any service | Services are stateless between requests; a restart loses nothing |
| Restart the model proxy | The proxy | Holds no durable state |
| Read process and service status | Anything | Read-only |
| Read logs and metrics | Anything | Read-only |
| Read disk and memory usage | The host | Read-only |

### Proposed exclusions — escalate, never attempt

| Action | Why not |
| :--- | :--- |
| Restart the database | State-bearing. An ill-timed restart during a write risks the record the system exists to keep. |
| Any migration, schema change, or data repair | Correctness ranks above availability *(SECURITY §1)*. A wrong repair is unrecoverable. |
| Deleting anything to reclaim space | Deleting to restore service is how a self-healing system destroys the thing it protects. |
| Installing, upgrading or downgrading anything | No runtime capability acquisition *(C-03, NFR.12)*. |
| Changing configuration or credentials | Configuration is a decision, not a remedy. |
| Anything touching the vault or its git repository | The vault is authoritative and irreplaceable *(NFR.07)*. |
| Restarting Nazim itself | It cannot restore itself. Escalate to the owner. |

**When in doubt, escalate.** The cost of an unnecessary escalation is the
owner's attention for a minute. The cost of a wrong autonomous remedy on a
state-bearing component is the record of his finances.

---

## 4. Escalation

An escalation is a report, not an alert. It states, in terms the owner can act
on without logging in *(FR.04.3.1, PRD §5 guardrail)*:

- what failed, and when;
- what was attempted, and how many times;
- the outcome;
- **what remains wrong**;
- what the owner needs to decide or do.

A report the owner has to log in to understand has failed at its job.

---

## 5. Common failures

Derived from `docs/SRS.md` §9. **Failure modes were never elicited, only
inferred** — this table is a starting point, not a validated list.

| Failure | Symptom | First response | Escalate when |
| :--- | :--- | :--- | :--- |
| A capability service is down | Its tools fail for the agent calling them | Restart once, verify it serves | Restart fails, or it recurs |
| Model proxy down | No agent can reason | Restart once | Restart fails — `[PENDING — SRS Q2]` governs whether anything degrades or everything stops |
| Database unavailable | All recording and reporting fails | **Do not restart.** Escalate immediately | Immediately |
| Chat platform unavailable | No interaction at all | Nothing to do locally. Record and report on recovery | On recovery |
| Rate or threshold source unavailable | Financial figures cannot be computed | **Nothing.** The correct behaviour is to refuse the figure *(FR.01.5.2)* | Only if persistent |
| Semantic retrieval unavailable | Search quality drops | **Nothing.** Correct behaviour is to degrade and say so *(FR.03.3.3)* | Only if persistent |
| Scheduled briefing missed | No morning or evening message | Record the miss and report it *(FR.02.2.3)* | On a second consecutive miss |
| Storage approaching capacity | Usage above threshold | **Report. Do not delete anything** | Immediately, before writes start failing |
| Spend rising abnormally | Consumption above expectation | Report with per-agent attribution *(C-29)* | Immediately — `[PENDING — SRS Q3]` sets the threshold |
| Half-completed write | An entry reported as failed, or missing from search | **Escalate.** Repair is a decision, not a remedy | Immediately |

---

## 6. Recovery of the whole system

If the machine itself is rebuilt: provisioning is idempotent, so the phase
scripts are the procedure. Running one twice reaches the same state as running
it once *(NFR.17)*. There is no separate disaster-recovery process — the setup
path is the recovery path, deliberately, so that the recovery path is exercised
every time anything is set up.

**What must be restored from outside the machine**, because nothing on it can
regenerate them:

| Item | Why it cannot be regenerated |
| :--- | :--- |
| The secrets decryption key | Without it, every secret is unrecoverable |
| The vault repository | Authoritative knowledge. The index rebuilds from it; it rebuilds from nothing *(NFR.07)* |
| The database | Financial history, tasks, habits, and the audit record. Not derivable from anything else |

`[PENDING]` Backup mechanism, frequency, destination and restore verification
for these three are **not defined anywhere in the requirements**. This is a
genuine gap rather than an open question, and it is worth raising: the system's
own stated priority is correctness of the record above availability
*(SECURITY §1)*, and an unbacked record contradicts that directly.

---

## 7. Open items

| # | Item | Blocks |
| :--- | :--- | :--- |
| 1 | Safe-autonomy boundary. `[PENDING — SRS Q6]` | §3 cannot be finalised. Defaulting to escalate meanwhile. |
| 2 | Retry bound. `[PENDING — SRS Q6]` | §2. Defaulting to one attempt. |
| 3 | Detection interval and restart deadline. `[PENDING — SRS Q4]` | §1. |
| 4 | Behaviour when inference is unavailable. `[PENDING — SRS Q2]` | §5. |
| 5 | Spend alert threshold. `[PENDING — SRS Q3]` | §5. |
| 6 | **Backup and restore.** `[PENDING]` — not covered by any requirement. | §6. Recommend raising it as a new requirement rather than leaving it to this document. |
