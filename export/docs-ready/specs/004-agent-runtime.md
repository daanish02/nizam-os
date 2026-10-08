---
title: "Spec 004 — Agent Runtime and Approval"
status: LOCKED
version: 1.0.0
date: 2026-09-26
scope: personal, cycle 1
---

# Spec: Agent Runtime and Approval

> **File:** `docs/specs/004-agent-runtime.md`
> **Scope:** CP.06 — the contract every agent and every service obeys: the
> approval gate, capability scoping, the audit record, delegation bounds, and
> the external-agent boundary. Owns the `audit` schema.
> **Builds on:**
>
> - `docs/SRS.md` §5 CP.06 — FR.06.1.1..FR.06.4.4
> - `docs/SECURITY.md` — the control set
> - `docs/ARCHITECTURE.md` — the `nizam-mcp` daemon's bearer-token-to-domain-scope design
> - Every other spec in `docs/specs/` depends on this one

**This spec is different from the others.** It specifies no user-facing
capability. It specifies the rules the other specs obey, in one place, so that
each of them can reference rather than restate. A rule stated in every spec
drifts in every direction.

---

## Open Questions

- [x] **Q-A1 — approval expiry. RESOLVED 2026-09-26, two layers:**
      - **Draft validity is `APPROVAL_TTL = 24 hours`.** A draft's signed
        `draft_token` expires 24h after the draft is produced. After that the
        draft is lapsed, which counts as a rejection (E-06), and a fresh draft
        built against current state is required.
      - **The live Discord `/approve` prompt waits 30 minutes**
        (`approvals.gateway_timeout: 1800` in each Hermes profile), then closes
        fail-closed. Hermes holds an agent worker while a prompt is open, so a
        24h prompt is impractical on a 2 vCPU box. If the owner comes back later
        (inside 24h) and says "go ahead with that", the agent re-issues the
        approved call with the same `draft_token`, and a fresh prompt appears.
      - Net effect: the owner can approve any time within 24 hours, and what
        executes is always exactly what was drafted. See "Enforcement
        mechanism" below.
- [x] **Q-A2 — delegation bounds. RESOLVED 2026-09-26: `MAX_DELEGATION_DEPTH =
      2`, `MAX_CONCURRENT_CHILDREN = 3`.** An agent may delegate to a helper
      (depth 1→2); that helper may not itself delegate further (no depth 3). Up
      to 3 concurrent children per delegating agent — enough for e.g. gathering
      from a few sources in parallel without runaway fan-out on a 2 vCPU box.
      Not exercised in cycle 1 (no delegation exists yet — Nazim/Noor/Ayah each
      act independently) but the limit is fixed now so it doesn't need
      revisiting when delegation is actually built.
- [x] **Q-A3 — inference-down behaviour. RESOLVED 2026-09-26: degrade, don't
      fail.** See `SRS.md` §4.2 and F-01: deterministic writes complete and
      queue the reasoning-dependent part; purely-reasoning requests fail
      explicitly. This was the highest-value open question in the project and
      it's now settled — every domain spec's tool-availability sections should
      follow this rule.
- [x] **Q-A4 — external agent identity mechanism. RESOLVED 2026-09-26: mTLS /
      signed requests**, not the bearer-token model used for internal agents.
      An external agent is, by definition, less trusted than Nazim/Noor/Ayah —
      it wasn't built as part of this system and its behavior isn't governed by
      this codebase's own conventions — so it gets a stronger cryptographic
      identity check than a shared-secret token. Implementation detail (which
      CA, cert rotation, request-signing scheme) is deferred to when a real
      external agent actually needs onboarding — cycle 1 has exactly three
      agents, all internal, so there is nothing to verify yet — but the
      mechanism class is now decided and shouldn't be re-litigated later.

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
  expires_at:    timestamp     — requested_at + APPROVAL_TTL (24h, Q-A1 resolved)

AgentIdentity
  name:          string        the agent
  origin:        enum(internal, external)
  capabilities:  string[]      the declared set. Anything absent is INVISIBLE,
                               not merely refused  (FR.06.1.2)
  delegation:    object?       {max_depth, max_children} when permitted
                              — bounds: max_depth<=2, max_children<=3 (Q-A2 resolved)

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
4. **Present** — Actor: agent — show the draft's summary to the owner, then
   call the tool again with `approved=true`, the `draft_token`, and the exact
   drafted payload.
   - The Hermes `nizam-approval` plugin intercepts this call and raises the
     Discord `/approve` prompt, showing the draft summary. The call is held
     until the owner answers, or until the 30-minute prompt timeout.
   - Prompt timeout: the call is denied. The draft stays valid until its 24h
     `draft_token` expiry, and the agent may re-raise it when the owner asks.
   - `draft_token` expired: the draft is lapsed, which counts as a rejection.
5. **Decide** — Actor: owner — `/approve` or `/deny` in Discord.
   - Denied → the flow ends. **Nothing is persisted.** No audit row is written
     for a declined or lapsed draft — a draft touches no state (rule 4), and a
     denial is visible in Hermes's own session log.
   - Approved → Hermes releases the call to `nizam-mcp` (step 6).
6. **Execute** — Actor: service — verify the `draft_token`, then perform the
   write and the audit rows (carrying `approval_id`) in one transaction. The
   checks are listed under "Enforcement mechanism" below.
7. **Confirm** — Actor: agent — report what actually happened, not what was
   proposed.

**Failure handling:**

| Step | Failure | Action | Recovery |
| :--- | :--- | :--- | :--- |
| 2 | Validation failed | Return the error | Agent re-proposes |
| 4 | Prompt timed out (30 min) | Call denied | Agent re-raises the same draft on request, within 24h |
| 4 | Draft token expired (24h) | `DRAFT_EXPIRED` | Fresh draft required |
| 6 | Token invalid or payload differs from draft | `DRAFT_MISMATCH` | Fresh draft required |
| 6 | `approval_id` already executed | `ALREADY_APPLIED` | None — the write already happened |
| 6 | Write failed | Report failure | Nothing partial reported as success |
| 6 | Write succeeded, audit failed | **Roll back, report failure** | See A-4 below |

**Idempotency:** an approval is single-use. Replaying an approved payload is
refused with `ALREADY_APPLIED` — see the replay check below.

### Enforcement mechanism

Rules 1–8 above are enforced by two layers. **Neither trusts the LLM.**

**Layer 1 — Hermes `nizam-approval` plugin (owner identity).**

- **Where it lives.** It ships from `agents/plugins/nizam-approval/` and is
  installed into every profile by `deploy.sh`.
- **What it does.** It registers a Hermes `pre_tool_call` hook. For every
  `write`-class tool invoked with `approved=true`, the hook returns
  `{"action": "approve", "message": <plain-language summary>, "rule_key":
  sha256(tool + canonical args)}`.
- **Why the LLM can't skip it.** Hermes intercepts the call *before* it reaches
  `nizam-mcp` and routes it to its human approval gate. Hermes accepts
  `/approve` only from `DISCORD_ALLOWED_USERS` (rule 8, C-20).
- **Which tools it gates.** The list of write-class tools is a static list in
  the plugin, generated from each domain's tool declarations — never decided at
  call time (rule 2).
- **Why `rule_key` is per payload.** Even a mistaken "always" answer can then
  only ever match a byte-identical payload (rule 6). The owner should answer
  "once".

**Layer 2 — signed `draft_token` in `nizam-mcp` (exact payload, expiry,
single use).**

- **Draft call (`approved=false`).** After full validation, return:
  - the draft
  - `draft_token = base64(approval_id ‖ expires_at ‖ HMAC-SHA256(NIZAM_APPROVAL_KEY, tool ‖ agent ‖ canonical_payload ‖ approval_id ‖ expires_at))`
  - `approval_id` is a random 128-bit id; `expires_at` is now + 24h.
  - **Nothing is stored** (rule 4).
- **Approved call (`approved=true`).** It must carry `draft_token` and the
  exact payload. Before any write, `nizam-mcp` checks, in order:
  1. The signature is valid for this tool, this calling agent and this exact
     canonical payload. Otherwise → `DRAFT_MISMATCH`.
  2. `expires_at` is in the future. Otherwise → `DRAFT_EXPIRED`.
  3. **Replay check**, inside the write transaction: take
     `pg_advisory_xact_lock(hashtext(approval_id))`, then refuse with
     `ALREADY_APPLIED` if any `audit.log` row already carries this
     `approval_id`.
  4. Perform the write, and write the audit row(s) with `approval_id`, in the
     same transaction.
- **The approved call writes exactly what was drafted.** The drafted payload
  carries the full content (for example, `add_note` carries the note body that
  Noor built from an `ingest_url` result), so nothing is re-fetched or
  re-derived at approval time — a re-fetch could differ from what the owner
  approved (rule 7). Where a write depends on existing state, as `update_note`
  does, the token also binds a hash of that state, and a change since the draft
  → `DRAFT_MISMATCH`.
- **Where the logic lives.** `nizam/core/approval.py` holds this logic once.
  Every domain's write tools call it. None re-implements it.

**Accepted residual risk.** `nizam-mcp` cannot cryptographically prove that
Layer 1 ran. An approved call whose token is valid is trusted to have passed
the Hermes gate. Hermes is trusted code; the LLM inside it is not (TB-3). The
token still guarantees that whatever executes is exactly a payload the service
itself drafted, within 24h, at most once.

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
2. Depth and concurrent children are bounded: max_depth=2, max_children=3 (Q-A2, resolved) *(FR.06.4.4)*.
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
- **A-6 — Retention.** Indefinite — `audit.log` is never pruned or auto-deleted (`SRS.md` NFR.20, resolved). Raw operational logs (journald/systemd) rotate per `logrotate` policy, but the audit trail itself does not.

---

## The external-agent boundary

**Not built.** Specified now because a containment model retrofitted onto an
open interface is far harder than one declared before *(TB-11)*.

**The contract, non-negotiable:**

1. **Identity is verified before a task is accepted** *(C-24)*. Mechanism
   via mTLS / signed requests (Q-A4, resolved).
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
are the ones that matter most *(TESTING.md)*.

**Cycle 1 vs cycle 2.**

- **E-18 to E-23** cover delegation and external agents, which don't exist in
  cycle 1. They are **deferred to cycle 2** and become tickets when those
  capabilities are built.
- **Every other criterion is mapped to a named test or live check in
  `docs/plan.toml`**:
  - E-08, E-09, E-16 and E-17 exercise Hermes itself, so they are live checks
    in TICK-504, backed by config tests in TICK-501.
  - The rest are automated tests.

| # | Criterion | Traces to |
| :--- | :--- | :--- |
| E-01 | A read tool executes with no approval | FR.06.1.1 |
| E-02 | **A write tool called with `approved=true` on its first call is refused** | rule 3 |
| E-03 | **A rejected draft leaves the system byte-identical: no rows, no files, no cache** | rule 4 |
| E-04 | **A write attempted without a recorded approval does not execute** | FR.06.2.1, C-01 |
| E-05 | An approval whose payload differs from what executes is refused | rule 7 |
| E-06 | A lapsed approval (past its 24h TTL) is refused; a fresh draft is required | Q-A1, resolved |
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
| E-25 | **An approved call whose payload differs by one byte from the drafted payload is refused with `DRAFT_MISMATCH`** | Rule 7, Layer 2 |
| E-26 | **An approved call presenting a draft token issued to a different agent or tool is refused** | Rule 7, C-02 |
| E-27 | An approved call presented after `expires_at` is refused with `DRAFT_EXPIRED` | Q-A1 |
| E-28 | **Two concurrent approved calls with the same `draft_token` produce exactly one write; the other gets `ALREADY_APPLIED`** | Idempotency, Layer 2 |
| E-29 | A draft call leaves Postgres, the vault and every cache byte-identical | Rule 4, K-4 |
| E-30 | The Hermes plugin's write-tool list matches every tool declared `write`-class in `nizam-mcp` (a test fails if a new write tool is added without being gated) | Rule 2, Layer 1 |

---

## Open Items

| # | Item | Status |
| :--- | :--- | :--- |
| 1 | Inference-down behaviour. `[Q-A3]` | RESOLVED 2026-09-26 — degrade, don't fail |
| 2 | Approval TTL. `[Q-A1]` | RESOLVED 2026-09-26 — 24 hours |
| 3 | Delegation bounds. `[Q-A2]` | RESOLVED 2026-09-26 — depth 2, 3 concurrent children |
| 4 | External identity mechanism. `[Q-A4]` | RESOLVED 2026-09-26 — mTLS / signed requests |
| 5 | Audit retention. | RESOLVED — indefinite, see A-6 |
