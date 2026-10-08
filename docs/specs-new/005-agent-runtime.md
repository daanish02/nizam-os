---
title: "Spec 005 — Agent Runtime and Approval"
status: DRAFT
version: 0.1.0
date: 2026-09-10
scope: personal
---

# Spec: Agent Runtime and Approval

> **File:** `docs/specs-new/005-agent-runtime.md`
> **Scope:** CP.06 — the contract every agent and every service obeys: the
> approval gate, capability scoping, the audit record, delegation bounds, and
> the external-agent boundary. Owns the `audit` schema.
> **Builds on:**
>
> - `docs/SRS.md` §5 CP.06 — FR.06.1.1..FR.06.4.4
> - `docs/SECURITY.md` §3 — controls C-01..C-29
> - `docs/THREAT-MODEL.md` — TB-2, TB-3, TB-11
> - Every other spec in this directory depends on this one

**This spec is different from the others.** It specifies no user-facing
capability. It specifies the rules the other six obey, in one place, so that
each of them can reference rather than restate. A rule stated in six specs
drifts in six directions.

---

## Open Questions

- [ ] **Q-A1 — approval expiry.** How long a pending approval stays valid before
      it lapses is unspecified. An approval the owner grants a day later applies
      to a proposal built from state that has since changed. Named
      `APPROVAL_TTL` below. — Owner decides.
- [ ] **Q-A2 — delegation bounds.** `[PENDING]`. Maximum depth and concurrent
      children per agent are unset *(FR.06.4.4)*. — Owner decides.
- [ ] **Q-A3 — inference-down behaviour.** `[PENDING — SRS Q2]`. Whether
      services stay callable when reasoning is unavailable. **The highest-value
      open question in the project**: it changes every service's interface.
- [ ] **Q-A4 — external agent identity mechanism.** FR.06.4.2 requires an
      external agent's identity be verified before a task is accepted. The
      mechanism is undecided and deliberately not invented here. Not blocking
      until Phase 10. — Owner decides.

---

## Shared Types

```
ActionClass   enum(read, write, execute)
              — read:    returns data, changes nothing. NO approval  (FR.06.1.1)
              — write:   changes stored state. Approval REQUIRED
              — execute: runs a command on the host. Approval REQUIRED,
                         and only for an agent holding host capability
              — the classification is a property of the TOOL, declared once,
                never decided per call by a model

ApprovalRequest
  action:        string        the tool being invoked
  actor:         string        the agent proposing it
  summary:       string        what changes, in the owner's terms  (FR.06.2.2)
  detail:        object        the full proposed payload
  requested_at:  timestamp
  expires_at:    timestamp     [Q-A1]

AgentIdentity
  name:          string        the agent
  origin:        enum(internal, external)
  capabilities:  string[]      the declared set. Anything absent is INVISIBLE,
                               not merely refused  (FR.06.1.2)
  delegation:    object?       {max_depth, max_children} when permitted  [Q-A2]

AuditEntry
  actor:         string        the AGENT, not the service
                               — attribution is to the party that decided,
                                 not the party that executed
  origin:        enum(internal, external)   (FR.06.4.3)
  schema_name:   string
  table_name:    string
  operation:     enum(INSERT, UPDATE, DELETE)
  row_id:        string
  before_state:  object?       null on INSERT
  after_state:   object?       null on DELETE
  approval_id:   string?       the approval that authorised this write
  occurred_at:   timestamp     UTC
```

---

## The approval gate

**The single most important contract in the system.** It is the only control
standing between a model acting on a hallucinated or injected instruction and a
change to the owner's data *(T-07, T-23)*.

### Rules

1. **Every `write` and `execute` action requires approval. Every `read` action
   requires none** *(FR.06.1.1, FR.06.2.1)*. The asymmetry is deliberate:
   reads are recoverable and frequent, writes are expensive to undo and rare.
   Gating reads would make the system tiresome enough to abandon, which is the
   real failure mode for a tool whose value is friction removal.

2. **Classification is a property of the tool, fixed at declaration.** A model
   never decides whether its own call needs approval. A model that could
   classify its own action could classify a write as a read.

3. **The two-pass shape.** A write tool called without approval returns a
   *draft* — the complete proposed outcome — and persists nothing, anywhere.
   Called again with approval, it performs the write. There is no third path,
   and no tool may write on its first call.

4. **A draft touches no state.** Not the database, not the vault, not a
   temporary file, not a cache. A rejected proposal must leave the system
   byte-identical to before it *(K-4)*.

5. **The request states the effect, not the mechanism** *(FR.06.2.2, NFR.19)*.
   "Record 50 AED at the grocer, from Current, category Food" — not a serialised
   tool payload. The owner must be able to judge it without reconstructing what
   the call does.

6. **Approval is per action, never blanket.** No "approve all", no session-wide
   consent, no remembered preference. Blanket approval is the same as no gate,
   arrived at gradually.

7. **Approval binds to the exact proposal.** The approved payload is what
   executes. If anything changed since the draft, the approval is void and a
   fresh draft is required.

8. **Only the owner's identity may approve** *(FR.06.2.3, C-20)*.

### Flow

**Trigger:** an agent invokes a `write` or `execute` tool.

**Steps:**

1. **Propose** — Actor: agent — call the tool with `approved=false`.
2. **Validate** — Actor: service — validate fully, exactly as it would for a
   real write. **Validation happens before the owner is asked**, so he is never
   shown a proposal that would then fail.
   - On failure: return the error. Flow ends. The owner is not troubled.
3. **Render** — Actor: service — produce the draft.
4. **Present** — Actor: agent — show the summary and await a decision.
   - Timeout at `APPROVAL_TTL` `[Q-A1]` → lapsed, treated as rejection.
5. **Decide** — Actor: owner.
   - Rejected → flow ends. **Nothing persisted, nothing recorded except that a
     proposal was made and declined.**
   - Approved → step 6.
6. **Execute** — Actor: service — perform the write, then the audit row
   carrying the approval reference.
7. **Confirm** — Actor: agent — report what actually happened, not what was
   proposed.

**Failure handling:**

| Step | Failure | Action | Recovery |
| :--- | :--- | :--- | :--- |
| 2 | Validation failed | Return the error | Agent re-proposes |
| 4 | No decision before TTL | Lapse | Fresh draft required |
| 6 | Write failed | Report failure | Nothing partial reported as success |
| 6 | Write succeeded, audit failed | **Report failure** | See A-4 below |

**Idempotency:** an approval is single-use. Replaying an approved payload
without a fresh approval is refused.

---

## Capability scoping

1. **Each agent holds a declared capability set. Anything outside it is not
   visible to the agent** *(FR.06.1.2, C-02)*. Invisibility rather than refusal
   matters: a tool that exists and refuses invites the model to keep trying and
   to explain to the owner why it should be allowed. A tool that does not exist
   ends the line of reasoning.

2. **Each service reaches only its own schema, enforced by database grants**
   *(FR.06.1.3, C-07)*. Not by application logic — a bug in application logic is
   a vulnerability, a missing grant is an error.

3. **Agents hold no database credentials at all** *(C-08)*.

4. **No capability may be acquired at runtime** *(NFR.12, C-03)*. No package
   installation, no dynamic tool registration, no self-modification. An agent
   that can extend itself has no boundary.

5. **Host execution is held by exactly one agent**, bounded by an allowlist of
   **whole invocations, not command prefixes** *(C-06, T-33)*. Prefix matching
   is defeated by composition and is how command allowlists usually fail.

---

## Delegation

1. Delegation is off by default; enabled per agent where the mandate needs it.
2. Depth and concurrent children are bounded `[Q-A2]` *(FR.06.4.4)*.
3. **A sub-agent's actions remain subject to the approval gate.** Delegation
   never launders an action past the owner.
4. **A sub-agent never addresses the owner.** Its parent synthesises and speaks
   — otherwise the owner receives approval requests from parties he did not know
   existed.
5. Bounds apply across the external boundary exactly as within it *(T-41)*.

---

## The audit record

### `AuditEntry` → `audit.log`

```
id:            bigserial     PK
actor:         text          not-null   — the AGENT
origin:        text          not-null, default 'internal'   (FR.06.4.3)
schema_name:   text          not-null
table_name:    text          not-null
operation:     text          not-null   — INSERT | UPDATE | DELETE
row_id:        text          not-null
before_state:  jsonb         nullable   — null on INSERT
after_state:   jsonb         nullable   — null on DELETE
approval_id:   text          nullable   — the authorising approval
occurred_at:   timestamptz   not-null, default now()
```

**Grants — the invariant that matters most here.** Every service role holds
`INSERT` only. **No role in the system holds `UPDATE` or `DELETE` on this
table** *(FR.06.3.2, C-12, T-12)*. The system cannot rewrite its own history
even when instructed to. This is enforced by grant, not by convention, because a
convention is a promise and a grant is a fact.

**Indexes:**

| Name | Fields | Type | Access pattern |
| :--- | :--- | :--- | :--- |
| `audit_occurred_idx` | `occurred_at DESC` | btree | "What happened recently" |
| `audit_actor_idx` | `(actor, occurred_at DESC)` | btree | Per-agent review |
| `audit_row_idx` | `(schema_name, table_name, row_id)` | btree | History of one record |

**Invariants:**

- **A-1 — Append-only by grant.** Not by application discipline.
- **A-2 — One row per mutation.** A write with no audit row is a defect. A
  mutation and its audit row are written in the same transaction, so neither
  can exist without the other.
- **A-3 — Actor is the agent.** Not the service, not the process.
- **A-4 — Audit failure fails the write.** Since they share a transaction, an
  audit failure rolls back the mutation. An unrecorded change is worse than a
  refused one.
- **A-5 — External origin recorded.** An action contributed by an external agent
  is distinguishable in the record *(FR.06.4.3, C-13)*.
- **A-6 — Retention.** `[PENDING — SRS Q5]`.

---

## The external-agent boundary   `[Q-A4]`

**Not built.** Specified now because a containment model retrofitted onto an
open interface is far harder than one declared before *(TB-11)*.

**The contract, non-negotiable:**

1. **Identity is verified before a task is accepted** *(C-24)*. Mechanism
   `[Q-A4]`.
2. **The same approval gate applies.** Interoperation widens *who may
   participate*; it never widens *what may happen unapproved* *(FR.06.4.2,
   NFR.21)*.
3. **The capability set is declared and scoped** exactly as for an internal
   agent.
4. **Every contributed action records the external identity** *(FR.06.4.3)*.
5. **A returned result is untrusted content**, on the same footing as fetched
   web content. It may not become an action except through the approval gate,
   and may not be interpolated into a command or a query *(C-19, T-40)*.
6. **Delegation bounds apply across the boundary** *(FR.06.4.4)*.
7. **No existing agent is modified to admit a new one** *(FR.06.4.1, NFR.20)* —
   that is the entire point. Admission is by declaration.

---

## Domain Invariants

- No `write` or `execute` executes without a fresh, action-specific approval
  from the owner's identity.
- No draft touches any state.
- No agent sees a capability outside its declared set.
- No service reaches a schema it does not own.
- No component acquires capability at runtime.
- Every mutation is audited in the same transaction that performs it.
- Nothing in the system can alter the audit record.
- Untrusted content — fetched, transcribed, model-generated, or externally
  returned — never becomes an action except through the approval gate.

---

## Acceptance Criteria

Most are adversarial. This spec is the system's control surface, so its tests
are the ones that matter most *(TESTING §1)*.

| # | Criterion | Traces to |
| :--- | :--- | :--- |
| E-01 | A read tool executes with no approval | FR.06.1.1 |
| E-02 | **A write tool called with `approved=true` on its first call is refused** | rule 3 |
| E-03 | **A rejected draft leaves the system byte-identical: no rows, no files, no cache** | rule 4 |
| E-04 | **A write attempted without a recorded approval does not execute** | FR.06.2.1, C-01 |
| E-05 | An approval whose payload differs from what executes is refused | rule 7 |
| E-06 | A lapsed approval is refused; a fresh draft is required | Q-A1 |
| E-07 | **A replayed approval is refused** | idempotency |
| E-08 | **An approval from any identity other than the owner is refused** | FR.06.2.3, C-20 |
| E-09 | **A message from any identity other than the owner produces no action at all** | T-01, C-20 |
| E-10 | **A capability outside an agent's set is not merely refused but absent from its tool list** | FR.06.1.2, C-02 |
| E-11 | **A service connecting to another domain's schema is refused by the database, not by application code** | FR.06.1.3, C-07 |
| E-12 | **`UPDATE` on the audit record is refused by grant for every role** | FR.06.3.2, C-12 |
| E-13 | **`DELETE` on the audit record is refused by grant for every role** | FR.06.3.2, C-12 |
| E-14 | Every successful mutation has exactly one audit row naming the acting agent | FR.06.3.1, A-2 |
| E-15 | **A failed audit write rolls back its mutation** | A-4 |
| E-16 | **An invocation composing or extending an allowlisted command is refused** | C-06, T-33 |
| E-17 | A runtime capability-acquisition attempt fails | NFR.12, C-03 |
| E-18 | Delegation beyond the declared depth is refused | FR.06.4.4 |
| E-19 | Concurrent children beyond the bound are refused | FR.06.4.4 |
| E-20 | A sub-agent's write still surfaces an approval request to the owner | delegation rule 3 |
| E-21 | **An external agent's unapproved action does not execute** | FR.06.4.2, T-38 |
| E-22 | An external agent's contributed action is distinguishable in the audit record | FR.06.4.3, A-5 |
| E-23 | **A returned external result containing an instruction does not become an action** | T-40, C-19 |
| E-24 | An approval summary names the effect without exposing a raw payload | FR.06.2.2, NFR.19 |

---

## Open Items

| # | Item | Blocks |
| :--- | :--- | :--- |
| 1 | Inference-down behaviour. `[Q-A3 / SRS Q2]` | **Every service interface in every spec** |
| 2 | Approval TTL. `[Q-A1]` | E-06 |
| 3 | Delegation bounds. `[Q-A2]` | E-18, E-19 |
| 4 | External identity mechanism. `[Q-A4]` | Phase 10 only |
| 5 | Audit retention. `[PENDING — SRS Q5]` | A-6 |
