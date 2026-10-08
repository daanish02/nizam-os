---
title: "Spec 007 — Self-Maintenance"
status: DRAFT
version: 0.1.0
date: 2026-09-10
scope: personal
---

# Spec: Self-Maintenance

> **File:** `docs/specs-new/007-self-maintenance.md`
> **Scope:** CP.04 — detecting that a component failed, restoring it where safe,
> reporting what happened, and answering the owner's questions about the system.
> Owns no schema.
> **Builds on:**
>
> - `docs/SRS.md` §5 CP.04 — FR.04.1.1..FR.04.4.1
> - `docs/RUNBOOK.md` — the procedure this spec makes executable
> - `docs/THREAT-MODEL.md` — TB-10; threats T-32, T-33, T-34, T-35, T-36

**This is the highest-privilege domain in the system and the only one that can
execute on the host.** Everything below exists to bound that.

**The structural decision:** the agent holding host execution holds **no service
access and reaches no data**. The highest-privilege agent has nothing to
exfiltrate, and the data-holding agents cannot execute. Neither half is
sufficient alone; the separation is what makes it safe.

---

## Open Questions

- [ ] **Q-S1 — the permitted-action list.** `[PENDING — SRS Q6]`. What the
      system may attempt unattended is undrawn. `docs/RUNBOOK.md` §3 carries a
      **provisional** list. **Until resolved, the default is escalate, never
      act** — an agent improvising a remedy on a live machine is not
      self-maintenance. — Owner decides. **Blocking for `restart_component`.**
- [ ] **Q-S2 — retry bound.** `[PENDING — SRS Q6]`. Default meanwhile: **one
      attempt, then escalate** *(T-35)*. — Owner decides.
- [ ] **Q-S3 — detection interval.** `[PENDING — SRS Q4]`. NFR.04 proposes an
      attempt within five minutes; unconfirmed. — Owner decides.
- [ ] **Q-S4 — spend alert threshold.** `[PENDING — SRS Q3]`. Without a ceiling
      there is nothing to alert against *(T-11)*. — Owner decides.
- [ ] **Q-S5 — storage headroom threshold.** At what remaining capacity to warn.
      **Must fire well before writes begin failing**, since the failure mode is
      silent *(F-06)*. — Owner decides.

---

## Shared Types

```
ComponentState  enum(serving, running_unresponsive, stopped, unknown)
                — running_unresponsive is WORSE than stopped: supervision
                  believes it is healthy while it serves nothing. It is the
                  state a naive "is the process alive" check misses entirely

Severity        enum(info, warning, critical)

ActionOutcome   enum(succeeded, failed, refused, skipped)
                — refused means the action was not on the permitted list.
                  Distinct from failed, and the distinction matters: refused
                  is the control working, failed is the component not recovering

Incident
  component:      string
  detected_at:    timestamp
  state:          ComponentState
  attempts:       AttemptRecord[]
  resolved:       boolean
  outstanding:    string        what remains wrong. MANDATORY  (FR.04.3.1)

AttemptRecord
  action:         string        the exact invocation attempted
  outcome:        ActionOutcome
  at:             timestamp
  detail:         string
```

---

## MCP Tools

`check_*` are reads. `restart_component` is `execute` and requires approval
under the standing rules *(005-agent-runtime)*.

### `check_components`

**Description:** Report the state of every supervised component.

**Inputs:** `component: string optional` — one component, or all

**Logic:**

1. For each component, determine supervision state.
2. **Where a component exposes a health check, call it.** A process that is
   running but not serving is `running_unresponsive`, and distinguishing that
   from `serving` is the whole value of this tool — a liveness check alone
   reports a wedged service as healthy.
3. Return states with the time observed.

**Output:** `checked_at`, `components: [{name, state, since?, detail?}]`,
`unhealthy_count`

**Error cases:** `COMPONENT_NOT_FOUND`, `CHECK_FAILED` (state `unknown`, which
is **not** the same as `stopped` and must not trigger a restart).

**Idempotent:** yes.

---

### `check_resources`

**Description:** Report host resource state — memory, storage, load.

**Logic:** read current usage; **compare storage against the headroom threshold
`[Q-S5]` and flag before exhaustion**, because a full disk fails writes
silently *(F-06)*.

**Output:** `checked_at`, `memory`, `storage {used, available, threshold_breached}`,
`load`, `warnings[]`

**Idempotent:** yes.

---

### `check_spend`

**Description:** Report inference consumption, attributed per agent.

**Logic:** read recorded consumption for the period; **attribute per agent**
*(C-29)* so a runaway is identifiable rather than merely visible; compare
against the ceiling `[Q-S4]`.

**Output:** `period`, `total`, `by_agent[]`, `ceiling?`, `breached: boolean?`

**Note:** with no ceiling set `[Q-S4]`, `breached` is null — **not false**.
Reporting `false` would imply a bound that does not exist.

**Idempotent:** yes.

---

### `read_logs`

**Description:** Read recent log lines for a component, for diagnosis.

**Inputs:** `component`, `since: timestamp optional`, `level: string optional`,
`limit: integer optional default=100 — 1..1000`

**Logic:** validate the component against the known set → `COMPONENT_NOT_FOUND`.
**The component name is never interpolated into a shell command or a path**;
it resolves through a fixed mapping *(C-18, T-33)*. Return lines with
**secret patterns redacted** *(C-22)* — logs are exactly where a credential
surfaces.

**Output:** `component`, `lines[]`, `truncated: boolean`

**Idempotent:** yes.

---

### `restart_component`   `[Q-S1]`

**Description:** Attempt to restore a failed component. **Approval-gated,
allowlist-bounded.**

**When NOT to call:** Do not call for a state-bearing component. Do not call
when state is `unknown` — diagnose first. Do not call to "refresh" a healthy
component.

**Inputs:**

```
component:  string   required
reason:     string   required  — why a restart is warranted
approved:   boolean  optional  default=false
```

**Logic (execution order):**

1. **Resolve the component to a permitted invocation.** If it is not on the
   allowlist → `ACTION_REFUSED`, outcome `refused` *(Q-S1)*. **Refusal is the
   control working, not a failure**, and must be reported as such.
2. **The allowlist matches whole invocations, never prefixes** *(C-06, T-33)*.
   A prefix match is defeated by composition, which is how command allowlists
   usually fail.
3. **No argument derived from input is interpolated into a shell.** The
   invocation is fixed and selected by lookup, then executed as an argument
   vector *(C-18)*.
4. Check the attempt count for this component in the current incident. At the
   bound `[Q-S2]` → `RETRY_LIMIT_REACHED`, escalate, **stop** *(T-35, FR.04.2.2)*.
5. **If not approved:** return exactly which invocation would run and why.
   Execute nothing. Stop.
6. Execute. Record the attempt *(T-36)*.
7. **Verify the component is serving, not merely running** — a restart that
   returns success while the service stays wedged is a false recovery, and
   reporting it as fixed is worse than reporting the failure.
8. Return the outcome and the post-restart state.

**Output:** `component`, `action_taken`, `outcome`, `state_after`,
`attempt_number`, `retry_limit_reached: boolean`

**Error cases:**

| Condition | Error | Notes |
| :--- | :--- | :--- |
| Not on the allowlist | `ACTION_REFUSED`: "Not a permitted action for <c>." | **The control working.** Escalate, do not retry |
| Retry bound reached | `RETRY_LIMIT_REACHED` | Escalate. **Do not continue** |
| Restart ran, still not serving | `RESTART_INEFFECTIVE` | Escalate with logs |
| Component unknown | `COMPONENT_NOT_FOUND` | — |
| State is `unknown` | `DIAGNOSE_FIRST` | Do not restart on unknown state |

**Idempotent:** no — each call is an attempt and counts against the bound.

---

### `answer_system_question`

**Description:** Answer the owner's question about the system's design,
configuration or agent roster, from the project's own documentation
*(FR.04.4.1)*.

**Inputs:** `question: string required`

**Logic:**

1. Retrieve from the project's documentation.
2. **Answer with the source named** — which document, which section. An
   unattributed answer about the system's own configuration is indistinguishable
   from a guess.
3. **If the documentation does not cover it, say so.** Do not infer from code,
   and do not reason to a plausible answer *(I-5-equivalent)*. "The docs do not
   say" is a useful answer; a confident wrong one about the owner's own system
   is not.

**Output:** `answer`, `sources[]`, `covered: boolean`

**Idempotent:** yes.

---

## Flows

### Detection and bounded recovery

The executable form of `docs/RUNBOOK.md` §2.

**Trigger:** the detection interval elapses `[Q-S3]`, or a component reports a
failure.

**Preconditions:** none.

**Steps:**

1. **Detect** — `check_components`. State `serving` → end.
2. **Classify** — is the remedy on the permitted list `[Q-S1]`?
   - Not on the list → **escalate. Do not improvise.** Flow ends at step 5.
   - State `unknown` → diagnose, do not act.
3. **Attempt** — `restart_component`, once, approval-gated.
   - Refused → escalate, outcome `refused`.
4. **Verify** — confirm serving, not merely running.
   - Not serving and under the bound → step 3.
   - At the bound `[Q-S2]` → escalate, **stop** *(FR.04.2.2)*.
5. **Report** — always. **Including on success** *(FR.04.3.1)* — a component
   that needed restarting is information the owner wants even when the restart
   worked. Silence on success trains him to assume silence means health.

**Failure handling:**

| Step | Failure | Action | Recovery |
| :--- | :--- | :--- | :--- |
| 2 | Remedy not permitted | Escalate with the state | Owner acts |
| 3 | Approval declined | Record and escalate | Owner acts |
| 4 | Still not serving | Retry to the bound, then stop | Owner acts |
| 5 | Report undeliverable | **Record locally** | Deliver on recovery |

**End state — success:** component serving, incident recorded, owner informed.

**End state — failure:** attempts bounded and stopped, owner informed with what
remains wrong. **Never an unbounded retry loop** *(T-35)*.

**Idempotency:** the loop is bounded per component per incident. A new incident
resets the count; the same incident never restarts it.

---

### Escalation report

**Trigger:** any escalation, or any completed recovery.

**Content** *(FR.04.3.1)* — what failed and when; every attempt and its outcome,
including refusals; **what remains wrong**; what the owner must decide or do.

**The test of this report:** the owner can act on it without logging into the
machine. Needing to log in is itself the gap this capability exists to close
*(PRD §5 guardrail)*.

---

## Schema

**None.** This domain owns no tables and holds no database role — the deliberate
consequence of the privilege separation stated at the top.

Incidents are reported to the owner and recorded in the system's logs. **The
agent that can execute on the host cannot write to the owner's data**, and that
is the point.

`[PENDING]` Whether incident history should be queryable later — "how often has
this failed?" — is unrequirement-ed. It would need a store, which would require
revisiting the separation above. Raised, not decided.

---

## Domain Invariants

- **S-1 — One agent holds host execution.** No other agent has any.
- **S-2 — That agent reaches no data.** No service access, no database role.
- **S-3 — Allowlist by whole invocation, never prefix** *(C-06, T-33)*.
- **S-4 — No shell interpolation.** Invocations are fixed and selected by
  lookup, executed as argument vectors *(C-18)*.
- **S-5 — Bounded attempts, then stop** *(FR.04.2.2, T-35)*.
- **S-6 — Verify serving, not running.** A restart is not a recovery until the
  component serves.
- **S-7 — Refused is not failed.** Refusal is the control working and is
  reported as such.
- **S-8 — Report always, including success** *(FR.04.3.1)*.
- **S-9 — Escalate on doubt.** Where the boundary is undrawn `[Q-S1]`, escalate.
- **S-10 — Never attempt a state-bearing remedy unattended.** No database
  restart, no migration, no data repair, no deletion to reclaim space
  *(RUNBOOK §3)*.
- **S-11 — Redact secrets from log output** *(C-22)*.

---

## Acceptance Criteria

| # | Criterion | Traces to |
| :--- | :--- | :--- |
| G-01 | A deliberately stopped component is detected without owner involvement | FR.04.1.1 |
| G-02 | **A running-but-wedged component reports `running_unresponsive`, not `serving`** | ComponentState |
| G-03 | State `unknown` does not trigger a restart | DIAGNOSE_FIRST |
| G-04 | **An action absent from the allowlist is refused, outcome `refused`** | FR.04.2.1, S-3 |
| G-05 | **An invocation composing or extending an allowlisted command is refused** | C-06, T-33 |
| G-06 | **A component name containing shell metacharacters never reaches a shell** | C-18, S-4 |
| G-07 | **Attempts stop at the bound and escalate; no unbounded loop** | FR.04.2.2, T-35 |
| G-08 | A restart that leaves the component unserving reports `RESTART_INEFFECTIVE`, not success | S-6 |
| G-09 | Every attempt is recorded, including refusals | T-36, S-7 |
| G-10 | An incident report names what failed, what was attempted, and **what remains wrong** | FR.04.3.1 |
| G-11 | A successful recovery is still reported | S-8 |
| G-12 | **The maintenance agent holds no database role and no service capability** | S-1, S-2 |
| G-13 | **A database restart is refused, not attempted** | S-10, RUNBOOK §3 |
| G-14 | Storage headroom is flagged **before** writes fail | F-06, Q-S5 |
| G-15 | Log output has secret patterns redacted | C-22, S-11 |
| G-16 | A system question is answered with its source named | FR.04.4.1 |
| G-17 | An uncovered question returns `covered: false`, not an inferred answer | S-9 |
| G-18 | Spend with no ceiling returns `breached: null`, not `false` | check_spend |
| G-19 | Recurring scheduled work cannot be created by an agent without an explicit mandate | T-34, AC.09 |

---

## Open Items

| # | Item | Blocks |
| :--- | :--- | :--- |
| 1 | Permitted-action list. `[Q-S1 / SRS Q6]` | `restart_component` — **blocking** |
| 2 | Retry bound. `[Q-S2 / SRS Q6]` | S-5. Defaulting to one |
| 3 | Detection interval. `[Q-S3 / SRS Q4]` | The detection loop |
| 4 | Spend ceiling. `[Q-S4 / SRS Q3]` | `check_spend` alerting |
| 5 | Storage threshold. `[Q-S5]` | `check_resources` |
| 6 | Whether incident history is queryable. `[PENDING]` | Would require revisiting S-2 |
