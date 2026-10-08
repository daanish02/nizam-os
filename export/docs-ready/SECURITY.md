---
title: Security — nizam-os (Personal Domain, Cycle 1)
status: LOCKED
version: 1.1.0
date: 2026-09-26
scope: personal, cycle 1
---

# Security

This document replaces what was previously split across SECURITY.md and
THREAT-MODEL.md. The prior iteration kept its control and threat tables in
three places, and they drifted apart (`export/BUGS-AND-GOTCHAS.md` #8). This is
now the single home for:

- the **control catalogue** (`C-xx`)
- the **threat register** (`T-xx`)
- the **trust boundaries** (`TB-x`)

Every spec cites these IDs, and they resolve here.

**The real threat model, stated once (SRS §7.2, §7.4):** there is no external
attacker with anything to gain. There is no public surface, no third-party
data, no regulated category and no compliance regime. The actual risk is
**the system's own autonomy**: an agent taking an action the owner didn't
intend, whether from a model mistake or from instructions injected into
content it ingested. Effort is weighted accordingly — toward containing
autonomy and preserving the record, not toward perimeter defense.

---

## Network exposure

| Component | Bind address | Reachable from |
| :--- | :--- | :--- |
| `nizam-mcp` | `127.0.0.1:8100` | Hermes gateways on the same host only |
| LiteLLM proxy | `127.0.0.1:4000` | Hermes gateways, `nizam-mcp` |
| Postgres | `127.0.0.1:5432` | `nizam-mcp`, LiteLLM |
| Redis | `127.0.0.1:6379` | LiteLLM only (its response cache). `nizam-mcp` does not use Redis in cycle 1. |
| Loki | `127.0.0.1:3100` | Promtail, Grafana |
| Grafana | `:3000` on all interfaces. UFW denies public inbound (set up by `nizam-dotfiles`). | The owner's devices, at `http://<tailscale-ip>:3000` |
| SSH | Key-only, no password, no root login | **Tailscale only.** The public `22/tcp` rule is deleted once Tailscale is confirmed working — see `nizam-dotfiles/docs/RUNBOOK.md` → Machine setup, Step 4 |

Host hardening is owned by the `nizam-dotfiles` repo, not this one: SSH
config, UFW, fail2ban, unattended-upgrades, Tailscale, and the
Prometheus/Grafana/Loki install.

After every deploy, run `ss -tlnp`. Anything listening on a non-loopback
address other than Grafana `:3000` and SSH is a regression.

---

## Secrets

- **Where real values live.** In `~/.config/nizam/*.env` (directory mode 700,
  files mode 600, outside the git working tree), with age/sops-encrypted
  copies in the repo as `secrets/*.env.enc`. `scripts/deploy.sh --sync-secrets`
  decrypts the repo copies into `~/.config/nizam/`.
- **The age private key** lives at `~/.config/sops/age/keys.txt` (mode 600).
  That is sops's default lookup path, so no `SOPS_AGE_KEY_FILE` variable is
  needed. It is never inside the repo working tree.
  - **The owner keeps an offline copy** (password manager or printed). Without
    it, every `.env.enc` in the repo is unrecoverable after a disk loss.
  - The **public** key goes in `.sops.yaml` at the repo root, so `sops`
    encrypts to it automatically.
- **Config files reference `${VAR}` only.** This covers Hermes `config.yaml`
  and systemd units (via `EnvironmentFile=`).
- **Gitignore every secret-shaped path before it is ever written to, not
  after.** Written in blood — see `export/BUGS-AND-GOTCHAS.md` #3.
- **Pre-commit check.** `scripts/secrets.sh check` runs as a pre-commit hook. It
  fails if any `secrets/*.env` is newer than its `.env.enc`, and fails loudly on
  a zero-byte `.env.enc` (`export/BUGS-AND-GOTCHAS.md` #10).
- **Each consumer gets its own LiteLLM virtual key.** That means Nazim, Noor,
  Ayah and `nizam-mcp` (for embeddings). The master key is used only by the
  LiteLLM service itself and by the owner for key administration. It never
  appears in an agent's or `nizam-mcp`'s environment.
- **Rotation.** No fixed schedule in cycle 1. Rotate immediately if a secret
  may have touched an unignored file, a log line, a commit or a chat. The
  procedure is in `RUNBOOK.md`.

---

## Autonomy containment

### The approval gate — how it is actually enforced

`docs/specs/004-agent-runtime.md` defines the rules. The enforcement has two
independent layers, and neither trusts the LLM:

1. **Hermes `nizam-approval` plugin (owner identity).**
   - A small Hermes plugin (`agents/plugins/nizam-approval/`, deployed to every
     profile) registers a `pre_tool_call` hook.
   - For any `write`-class MCP tool called with `approved=true`, the hook
     returns `{"action": "approve", "message": <the draft's plain-language
     effect>}`. Hermes then routes the call to its human approval gate.
   - The owner sees the prompt in Discord and answers `/approve` or `/deny`.
     Hermes accepts that answer only from `DISCORD_ALLOWED_USERS`.
   - **The LLM cannot skip this.** The call is intercepted inside Hermes before
     it reaches `nizam-mcp`.
   - The prompt waits `approvals.gateway_timeout = 1800` seconds (30 minutes),
     then fails closed. The draft stays valid (next layer), so a later "go ahead
     with that" simply re-opens the prompt.
   - The owner answers **once**, never "session" or "always" (spec 004 rule 6).
     The plugin keys every request on a hash of the full call arguments, so even
     a mistaken "always" can only ever match a byte-identical payload.
2. **Signed draft token in `nizam-mcp` (exact payload).**
   - A write tool's draft call (`approved=false`) returns a `draft_token`: an
     HMAC-SHA256 over the canonical payload, the tool name, the agent, and an
     expiry of `now + 24h` (`APPROVAL_TTL`, Q-A1). The key is
     `NIZAM_APPROVAL_KEY`, held only by `nizam-mcp`.
   - The approved call must present that token together with the exact drafted
     payload. `nizam-mcp` verifies the signature, the payload hash and the
     expiry, and refuses otherwise.
   - This is stateless: nothing is stored at draft time (spec 004 rule 4). It
     still binds the approval to exactly what the owner saw (rule 7).

**Accepted residual risk.** `nizam-mcp` cannot cryptographically verify that
the Hermes gate ran. Hermes is trusted code on the same host; the LLM running
inside it is not. This trust boundary is TB-3.

### Nazim's operational boundary

Nazim (admin) runs shell commands as the `vazir` user. Two different mechanisms
constrain it, because system units and user units behave differently:

| Unit | Scope | Needs sudo? | Enforced by |
| :--- | :--- | :--- | :--- |
| `litellm-proxy.service` | system | yes | `deploy/sudoers/admin-nizam`, which allows exactly `systemctl restart litellm-proxy` and `systemctl status litellm-proxy` |
| `nizam-mcp.service` | system | yes | same sudoers file, same two exact commands |
| `hermes-gateway-curator.service` | user | no | Hermes `command_allowlist` in `agents/admin/config.yaml`, matching whole invocations, not prefixes (C-06) |
| `hermes-gateway-assistant.service` | user | no | same |

- **Never:** Postgres, Redis, Loki, Grafana, Prometheus, any `nizam-dotfiles`
  unit, any other system unit, Nazim's own gateway (`hermes-gateway-admin` —
  systemd's `Restart=always` handles that), and no file edits.
- **One restart attempt, then escalate** in Discord `#alerts` (NFR.04).
- The sudoers file alone would not be enough: user units need no sudo, so for
  them the Hermes allowlist is the real enforcement. Also keep Hermes's
  dangerous-command approval on (`approvals.mode: manual`), so anything outside
  the allowlist hits the owner gate instead of running.

---

## Trust boundaries

| ID | Boundary | What crosses | Trusted side | Control |
| :--- | :--- | :--- | :--- | :--- |
| TB-1 | Owner → Discord | Instructions, approvals | The owner | Discord account security |
| TB-2 | Discord → agents | Messages claiming to be from the owner | — | Sender allowlist (`DISCORD_ALLOWED_USERS`) — C-20 |
| TB-3 | Agent (LLM) → `nizam-mcp` | Tool invocations | **Nobody — LLM output is untrusted** | Bearer-token scopes, Hermes approval plugin, signed draft token — C-01, C-02 |
| TB-4 | `nizam-mcp` → Postgres | Reads, writes | The service | One DB role per domain — C-07 |
| TB-5 | `nizam-mcp` → vault | Note file writes | The service | Path containment — C-15 |
| TB-6 | Agent / `nizam-mcp` → LiteLLM | Prompts, including ingested content | The caller | Per-consumer virtual key |
| TB-7 | LiteLLM → OpenRouter | Prompt content leaves the machine | LiteLLM | Provider key over TLS — T-19 accepted |
| TB-8 | `nizam-mcp` → public web / video | Fetched content **enters** the system | **Nobody — fully untrusted** | C-16, C-17, C-18; approval gate for any resulting action |
| TB-9 | `nizam-mcp` → FX / metal-price API | Rates, prices | The API, for freshness only | As-of stamping, staleness refusal — T-31 |
| TB-10 | Nazim → host OS | Shell commands | **Nobody — LLM output is untrusted** | Sudoers plus the Hermes command allowlist — C-06 |
| TB-11 | External agent → system | Delegated task and result | **Outside this system** | mTLS / signed requests plus a declared scope (Q-A4) — C-19, C-24. **No external agent exists in cycle 1.** |

---

## Control catalogue

The Status column uses:

- **Active** — implemented in cycle 1.
- **Cycle 2** — only relevant once a deferred capability exists.

| ID | Control | Mitigates | Status |
| :--- | :--- | :--- | :--- |
| C-01 | Every state-changing action is presented to the owner and executes only on explicit approval. Reads execute freely. Enforced by the Hermes plugin plus the signed draft token (above). | T-07, T-23, AC.01 | Active |
| C-02 | Each agent holds a declared capability set, as bearer-token scopes at `nizam-mcp`. Capabilities outside it are refused with 403 and are not exposed to that agent's MCP connection. | T-05, AC.03 | Active |
| C-03 | No component may install software or acquire capability while running. | T-10, AC.04 | Active |
| C-04 | Delegation is bounded (depth 2, 3 concurrent children — Q-A2), and a sub-agent stays subject to the approval gate. | T-11, T-41 | Cycle 2 (no delegation yet) |
| C-05 | Recurring scheduled work is denied by default, and allowed only where a mandate requires it. Cycle 1's only timers are backup, embedding retry and metrics — system jobs, not agent-scheduled. | T-34, AC.09 | Active |
| C-06 | Host command execution is restricted to one agent (Nazim), bounded by an allowlist matching whole invocations, with privilege scoped to named operations. | T-32, T-33 | Active |
| C-07 | Each domain connects as its own database role, granted only on the schemas it owns. The database enforces this, not the application. | T-06, T-14 | Active |
| C-08 | Agents hold no database credentials. All state access goes through `nizam-mcp`. | T-06 | Active |
| C-09 | Every value crossing into a query is bound as a parameter. No query is assembled by string composition. | T-13 | Active |
| C-10 | Journal content is reachable only by the agent that owns personal tracking. | T-18 | Cycle 2 (no journal yet) |
| C-11 | Every change is recorded with the acting agent, before/after state and a timestamp. | T-09 | Active |
| C-12 | No role holds UPDATE or DELETE on `audit.log`. Append-only by grant. | T-12, AC.07 | Active |
| C-13 | An action contributed by an external agent is recorded with that agent's identity. | T-39 | Cycle 2 |
| C-14 | A write that half-succeeds is reported as a failure, never as a partial success. | T-17 | Active |
| C-15 | Every resolved file path must sit inside its intended root (the vault). Anything else is refused. | T-16 | Active |
| C-16 | Outbound fetches reject non-public schemes and private/loopback/link-local ranges, re-checked after every redirect. | T-24 | Active |
| C-17 | Fetches carry a response size cap and a timeout: 10 MB, 15 s, at most 5 redirects (Q-K3). | T-25 | Active |
| C-18 | External tools are invoked with an argument vector, never through a shell, and identifiers are validated against an expected form first. | T-26 | Active |
| C-19 | A result returned by an external agent is untrusted content. It may not become an action except through the approval gate, and may not be interpolated into a command or query. | T-40 | Cycle 2 |
| C-20 | Instructions and approvals are accepted only from the owner's own Discord identity. Every other sender is ignored. | T-01, AC.08 | Active |
| C-21 | Secrets are encrypted at rest and never committed in plaintext. | AC.05 | Active |
| C-22 | Known secret patterns are redacted from tool output before an agent sees it. Best effort, not a guarantee. | T-20, AC.05 | Active (Hermes redaction) |
| C-23 | Provider credentials are held by the service that uses them and are never within an agent's reach. | T-22 | Active |
| C-24 | An external agent's identity is verified (mTLS / signed requests, Q-A4) before any task is accepted, and it is bound by the same gate and scoping as an internal agent. | T-37, T-38 | Cycle 2 |
| C-25 | Every Nizam component binds to loopback. The only exceptions are Grafana (UFW-protected, Tailscale access) and SSH (Tailscale only). | — | Active |
| C-26 | Management access is over Tailscale only, key-based, with password authentication disabled and fail2ban in place. | — | Active (`nizam-dotfiles`) |
| C-27 | OS security updates apply automatically, without automatic service restarts. | — | Active (`nizam-dotfiles`) |
| C-28 | All inference passes through the one LiteLLM proxy. Spend is visible per virtual key. No hard ceiling in cycle 1 (NFR.13). | T-11, AC.06 | Active (visibility only) |
| C-29 | Consumption is recorded per agent, so a runaway is attributable. | T-11 | Active |

---

## Threat register

Likelihood × impact. Treatment is one of Mitigate / Accept / Eliminate.

| ID | Threat | L × I | Treatment | Status |
| :--- | :--- | :--- | :--- | :--- |
| T-01 | Someone other than the owner instructs an agent. | Low × High | Mitigate — C-20 | Active |
| T-02 | The owner's Discord account is compromised. | Low × High | Accept — it is the root of trust. Mitigation is account hygiene (2FA). | Active |
| T-03 | Discord holds the full conversation history, including financial figures. | High × Medium | Accept — inherent to a hosted chat surface. | Active |
| T-04 | Discord is unavailable. | Medium × Medium | Accept — availability is not the primary quality attribute. | Active |
| T-05 | An agent invokes a capability outside its mandate. | Medium × High | Mitigate — C-02 | Active |
| T-06 | An agent writes another domain's data. | Medium × High | Mitigate — C-07, C-08 | Active |
| T-07 | An agent takes a state change the owner never intended. | High × High | Mitigate — C-01 | Active |
| T-08 | The owner approves a harmful action because it looked plausible. | Medium × High | Accept with mitigation — approval prompts state the effect plainly (FR.06.2.2) | Active |
| T-09 | An action cannot be attributed afterwards. | Medium × Medium | Mitigate — C-11 | Active |
| T-10 | An agent acquires undeclared capability at runtime. | Low × High | Mitigate — C-03 | Active |
| T-11 | Runaway inference spend (loop or delegation). | Medium × Medium | Mitigate — C-28, C-29, C-04 | Active |
| T-12 | The audit record is altered or deleted. | Low × High | Mitigate — C-12 | Active |
| T-13 | Input alters a query's meaning (injection). | Medium × High | Mitigate — C-09 | Active |
| T-14 | A compromised domain reads another domain's data. | Low × High | Mitigate — C-07 | Active |
| T-15 | One query exhausts the pool or memory on the co-resident box. | Medium × Medium | Mitigate — bounded result sets (`limit` ≤ 50), statement timeouts | Active |
| T-16 | A note path escapes the vault and writes elsewhere on the host. | High × High | Mitigate — C-15. **Must be adversarially tested.** | Active |
| T-17 | A write leaves the file and its index inconsistent. | Medium × Medium | Mitigate — C-14 | Active |
| T-18 | Journal content is exposed to the wrong agent. | Low × High | Mitigate — C-10 | Cycle 2 |
| T-19 | Owner data leaves the machine as prompt content to OpenRouter. | High × High | **Accept** — inherent to hosted inference. | Active |
| T-20 | A secret is echoed in prompt content or tool output. | Medium × High | Mitigate — C-22 (best effort) | Active |
| T-21 | LiteLLM is down and reasoning stops. | Medium × High | Mitigate — degrade and queue (ADR-006). **Resolved.** | Active |
| T-22 | The OpenRouter key is stolen. | Low × Medium | Mitigate — C-23 | Active |
| T-23 | Fetched content carries instructions and the model proposes an action from them. | High × High | Mitigate — C-01 | Active |
| T-24 | A URL makes the system fetch a loopback or private address (SSRF). | High × High | Mitigate — C-16. **Must be adversarially tested.** | Active |
| T-25 | A fetched resource is unbounded or never completes. | Medium × Medium | Mitigate — C-17 | Active |
| T-26 | Extraction invokes an external tool with an input-derived argument. | Medium × High | Mitigate — C-18 | Active |
| T-27 | A fetch reveals the owner's interests to a third-party server. | Medium × Low | Accept | Active |
| T-28 | A capability that moves money or places an order becomes reachable. | Low × Critical | **Eliminate** — no such tool exists anywhere. The finance domain only records; it never transacts. | Active |
| T-29 | A stored copy of brokerage positions diverges from the brokerage. | Medium × High | Eliminate — no copy kept | Cycle 2 |
| T-30 | Brokerage credentials are exposed to an agent. | Low × High | Mitigate — C-23 | Cycle 2 |
| T-31 | **A figure is stated from an input that could not be retrieved or is stale** (FX rate, nisab metal price, and later screening inputs). | Medium × High | Mitigate — refuse with a reason. Every figure carries its source and as-of time (FR.01.3.2, FR.01.5.2). | Active |
| T-32 | A command outside the intended set runs on the host. | Medium × Critical | Mitigate — C-06 | Active |
| T-33 | An allowlisted command is composed or parameterised to do more than intended. | Medium × High | Mitigate — whole-invocation matching (C-06) | Active |
| T-34 | Recurring work is scheduled and runs unreviewed. | Low × High | Mitigate — C-05 | Active |
| T-35 | Automated restart loops forever against a component that can't recover. | Medium × Medium | Mitigate — one attempt, then escalate (NFR.04). **Resolved.** | Active |
| T-36 | A host action runs with no record of what ran. | Medium × Medium | Mitigate — Nazim reports every attempted command and its outcome in `#alerts`/`#logs` | Active |
| T-37 | An unauthorised party poses as a permitted external agent. | Medium × High | Mitigate — C-24 | Cycle 2 |
| T-38 | An external agent exceeds its scope or bypasses the gate. | Medium × Critical | Mitigate — C-24 | Cycle 2 |
| T-39 | An external agent's action is indistinguishable in the record. | Medium × Medium | Mitigate — C-13 | Cycle 2 |
| T-40 | An external agent's returned result is trusted and acted on. | High × High | Mitigate — C-19 | Cycle 2 |
| T-41 | Delegation recurses or fans out without bound. | Medium × Medium | Mitigate — C-04 | Cycle 2 |

---

## Abuse cases

`SRS.md` §7.2 holds AC.01–AC.11, each mapped to the controls above. Two call
for special care:

- **AC.02 / T-23 — injected content.** The approval gate is the control.
  Residual risk (T-08): a convincing fake request can still be approved. The
  mitigation is that every prompt states the action and its effect in plain
  terms.
- **AC.05 — secret exposure.** This has already happened once, in the prior
  iteration, and was caught before it reached git.

---

## Explicitly not a concern

- No payment card, health, biometric, third-party or children's data.
- No data residency requirement.
- No compliance framework applies (SRS §7.4). Don't invent compliance theater.

---

## Backups

These are a security control: data loss is the worst realistic outcome (SRS
§7.2). The nightly timer `nizam-backup.timer` runs:

- `pg_dump` (excluding the `litellm` schema)
- a tarball of Hermes memories and skills
- a commit + push of `nizam-vault`

The procedure is in `RUNBOOK.md`.
