# ADR-007: Approval is enforced by a Hermes plugin plus signed draft tokens

> **Date:** 2026-09-26
> **Status:** ACCEPTED

## Context

Spec 004 requires the following:

- every write to be approved by the owner (FR.06.2.1)
- a model never decides whether its own call needs approval (rule 2)
- a draft touches no state (rule 4)
- an approval binds to the exact proposal (rule 7)
- only the owner's identity may approve (rule 8)

As first written, however, the specs had the *agent* send `approved=true` on
the second call. Nothing verified that the owner had actually approved.

That turned the gate into a prompt instruction. Injected instructions in
ingested content (T-23), or plain model error (T-07), could skip it. Those are
the two threats the gate exists to stop.

A second tension: rule 4 (no state at draft time) conflicts with rule 7 (bind
to the exact proposal) and with single use (no replay). All three need to hold
at once.

## Decision

Two independent layers, neither trusting the LLM.

1. **Hermes `nizam-approval` plugin.**
   - A `pre_tool_call` hook sends every write-class tool call with
     `approved=true` to Hermes's human approval gate: a Discord `/approve`
     prompt, accepted only from `DISCORD_ALLOWED_USERS`.
   - `rule_key` is a hash of the full arguments, so no approval generalises to
     a different payload.
   - The prompt times out after 30 minutes and fails closed.
2. **Signed draft token in `nizam-mcp`.**
   - The draft call returns an HMAC-signed token covering tool, agent,
     canonical payload, a random `approval_id`, and an expiry of now + 24h.
     Nothing is stored.
   - The approved call must present the token and the identical payload.
     Otherwise it gets `DRAFT_MISMATCH` or `DRAFT_EXPIRED`.
   - Replay is refused by looking up `approval_id` in `audit.log`, under an
     advisory lock, inside the write transaction. A replay gets
     `ALREADY_APPLIED`.

## Alternatives considered

### Trust the agent's `approved` flag (the original specs)
- **Pros:** Simplest. No plugin.
- **Cons:** The gate is only as strong as the prompt. That is the exact failure
  mode the gate exists to prevent.
- **Rejected because:** the owner chose to enforce approval below the LLM.

### Store pending approvals in the database
- **Pros:** An explicit record of every proposal, including declined ones.
- **Cons:** Violates rule 4 (a draft must touch no state), and needs cleanup of
  lapsed rows.
- **Rejected because:** a signed token gives binding and expiry statelessly.
  Single use falls out of the audit rows that are written anyway.

### A 24-hour Hermes prompt
- **Pros:** One approval step, no re-raise.
- **Cons:** Hermes holds an agent worker while a prompt is open. Holding
  workers for up to 24h is impractical on a 2 vCPU box.
- **Rejected because:** a 30-minute prompt plus a 24-hour draft token gives the
  owner the same 24-hour window. The agent just re-raises the prompt on
  request.

## Consequences

- **Positive:**
  - Approval can't be skipped by the model.
  - What executes is exactly what was drafted, at most once, within 24h.
  - Drafts remain side-effect-free.
- **Negative / trade-offs:**
  - `nizam-mcp` can't cryptographically prove that the Hermes gate ran.
    Hermes is trusted code on the same host (TB-3) — accepted residual risk.
  - One more component (the plugin) to deploy with every profile.
  - The plugin's write-tool list must stay in sync with the tools. Test E-30
    enforces this.
- **Follow-up:** confirm the installed Hermes version's `pre_tool_call`
  `approve` action and `gateway_timeout` key still behave as described
  (`tools/approval.py`, `request_tool_approval`) before Phase 5.

## References
- `docs/specs/004-agent-runtime.md`: "The approval gate", "Enforcement mechanism", E-25 to E-30
- `docs/SECURITY.md`: C-01, TB-3
- `docs/specs/001-knowledge.md`, `002-finance.md`: write tools inherit the mechanism
