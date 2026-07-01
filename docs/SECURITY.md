# Nizam-OS — Security

**Last updated:** 2026-07-01

Security model across all layers. When adding a new agent or service, check every section — new components must fit the model, not bypass it.

---

## Threat model

| Threat | Source | Primary control |
|---|---|---|
| External attacker on VPS | Internet | UFW + fail2ban + SSH hardening + Tailscale |
| Compromised agent doing too much | Rogue LLM output | Tool scoping, command_allowlist, sudoers, DB role isolation |
| Prompt injection | Discord messages, web content, ingested PDFs, vault content | Manual approvals + DISCORD_ALLOWED_USERS + redact_secrets |
| Secret leakage | Agent tool output, git commits | redact_secrets + sops encryption + gitignore |
| Cross-agent data access | Agent reading another agent's domain | DB role grants, MCP tool include lists |
| Silent package install | Agent running pip at runtime | allow_lazy_installs: false |
| Rogue cron creation | Agent scheduling arbitrary jobs | cron_mode: deny on most profiles |
| Spend abuse | Agent making excessive LLM calls | LiteLLM virtual keys + spend tracking (pending DB init) |
| Delegation chain overreach | Sub-agent spawning further sub-agents | max_spawn_depth: 1 |
| Supply chain | npm / pip packages pulled at runtime | uv lockfile + allow_lazy_installs: false (npx is the gap) |

---

## VPS hardening

**UFW (firewall)**

```
Allowed inbound: 22 (SSH), 80, 443, Tailscale subnet (100.64.0.0/10)
Default policy:  deny inbound, allow outbound
```

Check: `sudo ufw status verbose`

**fail2ban**

Default SSH jail. Bans after 5 failed login attempts within 10 minutes. Ban duration: 1 hour.

Check: `sudo fail2ban-client status sshd`

**SSH**

Key-only authentication. Password auth disabled in `/etc/ssh/sshd_config`:
```
PasswordAuthentication no
PubkeyAuthentication yes
```

Check: `sudo sshd -T | grep -E "passwordauth|pubkeyauth"`

**Tailscale**

VPS management access via Tailscale VPN only in normal operations. SSH on public IP is allowed by UFW but Tailscale IP is the intended path. No services are publicly exposed.

Check: `sudo tailscale status`

**unattended-upgrades**

Auto-applies security updates from Ubuntu security repos. Does not auto-restart services — manual restart after kernel updates.

Check: `systemctl status unattended-upgrades`

---

## Network boundaries

All internal services bind to `127.0.0.1` only. Nothing is publicly reachable except SSH (port 22) and HTTP/HTTPS (80/443 — unused currently).

| Service | Bind address | Reachable from |
|---|---|---|
| PostgreSQL | `127.0.0.1:5432` | Localhost only |
| Redis | `127.0.0.1:6379` | Localhost only |
| LiteLLM proxy | `127.0.0.1:4000` | Localhost only |
| knowledge-service | `127.0.0.1:8100` | Localhost only (Curator v1+) |
| finance-service | `127.0.0.1:8101` | Localhost only |
| personal-service | `127.0.0.1:8102` | Localhost only |
| crm-service | `127.0.0.1:8104` | Localhost only |
| Prometheus | `127.0.0.1:9090` | Localhost only |
| Grafana | `127.0.0.1:3000` | Localhost only (access via Tailscale) |

**LiteLLM as the single LLM chokepoint.** All agent inference routes through `localhost:4000`. No agent connects directly to OpenRouter or any external model API. This means: spend tracking, caching, token counting, and key rotation all happen at one place.

---

## Secrets

**At rest**

| File | Encryption | Committed |
|---|---|---|
| `secrets/nizam.env` | sops/age (→ `.env.enc`) | No — gitignored |
| `secrets/nizam.env.enc` | sops/age | Yes |
| `hermes/profiles/<name>/.env` | sops/age (→ `.env.enc`) | No — gitignored |
| `hermes/profiles/<name>/.env.enc` | sops/age | Yes |
| `secrets/nizam-age-key.txt` | Not encrypted — **back up externally before wipe** | No — gitignored |

Unencrypted `.env` files exist only on the VPS at runtime. Never commit them. The `watcher-env.service` auto-encrypts `nizam.env` on save; `hermes-profile-watcher.service` auto-encrypts profile `.env` files on change.

**In transit**

- Agent → LiteLLM → OpenRouter: HTTPS
- Agent → Discord: HTTPS (Hermes handles)
- Agent → MCP services: HTTP on localhost (no TLS needed — loopback only)
- Grafana → PostgreSQL: local socket (no TLS needed — same host)

**In agent output**

`redact_secrets: true` in all profiles — Hermes scrubs known secret patterns from tool output before returning to the agent. This is a best-effort filter, not a guarantee. Do not rely on it as the sole control.

---

## Agent autonomy controls

Applied to all profiles. Any new profile must include all of these.

```yaml
security:
  allow_lazy_installs: false   # agents cannot run pip install at runtime
  redact_secrets: true

approvals:
  mode: manual                 # every tool call requires user confirmation in Discord
  cron_mode: deny              # agents cannot create scheduled jobs (except Nazim, Raha)
```

**`allow_lazy_installs: false` is the most important setting.** Default in Hermes is `true`. Without this, any agent can silently run `pip install <anything>` and execute arbitrary code via a new package.

**`approvals.mode: manual`** means every file write, terminal command, MCP call, and memory write surfaces to the user in Discord before executing. Agents cannot take irreversible actions autonomously.

**`cron_mode: deny`** prevents agents from creating persistent scheduled jobs without explicit approval. Nazim and Raha have `cron_mode: manual` (allowed, but each run still requires approval during setup).

### Per-agent terminal restrictions

| Agent | Terminal enabled | Restriction mechanism |
|---|---|---|
| Nazim | Yes | `command_allowlist` + `/etc/sudoers.d/nazim-hermes` |
| Reem | Yes | `command_allowlist` (read-only diagnostics only) |
| All others | No | `terminal` toolset disabled |

Exact `command_allowlist` values for Nazim and Reem are in `docs/AGENTS.md` (authoritative). Summary:
- Nazim: service restart + diagnostics only. Sudo scoped via `/etc/sudoers.d/nazim-hermes` — not full sudo.
- Reem: read-only diagnostics only. No restarts, no installs, no deployments.

Any command not in the allowlist requires manual Discord approval before execution.

### Who can talk to agents

`DISCORD_ALLOWED_USERS` in each profile's `.env` — whitelist of Discord user IDs. Only listed users can interact with the agent. Currently not set (Phase 2 fix — see Known Gaps). Until set, any server member can chat with any agent.

`discord.allowed_channels` in `config.yaml` — each agent sees only its own channels. Noor cannot read `#cfo-office`. Hala cannot read `#learning`.

---

## Access control / least privilege

### Database roles

Each service connects as its own PostgreSQL role. Roles are not shared between services.

| Role | What it can do | What it cannot do |
|---|---|---|
| `svc_knowledge` | RW `knowledge.*`, INSERT `knowledge.vault_audit` | Touch any other schema |
| `svc_finance_personal` | RW `finance.*`, RO `personal.*`, INSERT `audit.log` | Access `business.finance.*` |
| `svc_finance_business` | RW `business.finance.*`, INSERT `audit.log` | Access `finance.*` personal tables |
| `svc_personal` | RW `personal.*`, INSERT `audit.log` | Access `finance.*` or `business.*` |
| `svc_crm` | RW `crm.*`, INSERT `audit.log` | Direct access to `business.finance.*` |
| `grafana` | SELECT only on all schemas | Any write |

**Isolation is enforced at the DB layer, not just by convention.** `svc_finance_personal` has zero grants on `business.finance.*`. Verified with `\dp` in psql after each migration.

### MCP tool include lists

Each agent's `config.yaml` specifies exactly which MCP tools it can call. Tools not in `include` are invisible to the agent.

| Agent | Can call `ingest`/write tools | Rationale |
|---|---|---|
| Noor | Yes — owns vault writes | Mandate |
| Reem | No — `search_vault`, `get_note`, `list_notes` only | Read-only access |
| Mira | No — same read-only subset | Read-only access |
| Hala | Business finance tools only | No personal finance tools |
| Omar | CRM tools + 2 finance read tools | No write access to finance |

**Raha has zero MCP access.** `mcp_servers: {}` in her config. All data access via delegation to child agents. This prevents Raha from directly reading or writing any data.

### GitHub access (Reem)

PAT scopes: `Contents: Read`, `Pull requests: Read+Write`, `Issues: Read`, `Metadata: Read`.

Never admin scope. Excluded tools: `delete_*`, `create_repository`, `manage_webhooks`, `add_collaborator`. These are excluded via the MCP `tools.include` list — even if the PAT had the scope, the tool is not exposed.

---

## Prompt injection

**What it is:** A malicious string in user input (Discord), web content (Reem's `web` toolset), an ingested PDF, or a vault note that attempts to override agent instructions.

**Why it matters here:** Agents have real tool access — terminal, file writes, MCP mutations, vault ingestion. A successful injection could trigger unintended actions.

**Controls in place:**

| Control | Covers |
|---|---|
| `DISCORD_ALLOWED_USERS` whitelist | Limits who can send messages to agents |
| `approvals.mode: manual` | Every tool call surfaces to user before executing — injection cannot act without human seeing it |
| `redact_secrets: true` | Reduces value of exfiltration attempts via tool output |
| MCP tool include lists | Agents have minimal tool surface — fewer tools = less damage from injection |
| Vault approval gate | Noor's 3-pass workflow requires user confirmation before any vault write |
| `allow_lazy_installs: false` | Prevents "install this package" injection from succeeding |

**Residual risk:** Manual approval mode is the main defense. A sufficiently convincing injection could trick the user into approving a malicious action — the user sees the tool call but must recognise it as malicious. No automated content inspection is in place.

**Untrusted input sources:**
- Discord messages (primary)
- Web search results (Reem, Omar, Mira have `web` toolset)
- PDF content via `ingest_pdf`
- Image descriptions via `ingest_image` (LiteLLM vision output — secondhand trust)
- YouTube transcripts
- Bank statement content via `reconcile_statement`

Any of these can contain injection attempts. The approval gate is the last line of defense for all of them.

---

## Audit trail

Every service that mutates data writes to `audit.log` (after migration `0003_audit_schema.sql` runs).

```sql
audit.log (id, schema_name, table_name, operation, actor, row_id, before_state, after_state, created_at)
```

`actor` = Hermes profile name. Every write is attributed to the agent that made it.

**Append-only enforcement:** No `UPDATE` or `DELETE` granted to any service role on `audit.log`. Insert-only by grant, not trigger. Not court-grade tamper-proof (a DB superuser could alter rows), but sufficient for internal accountability and debugging.

**Current state:** `audit.log` does not exist yet — migration `0003` not run. `knowledge.vault_audit` is a temporary substitute (knowledge-service only, different schema).

**Grafana:** The `grafana` role has SELECT on `audit.log` — audit data can be queried and visualised without service credentials.

---

## Delegation security (Raha)

Raha is the only agent that can spawn child agents. Controls:

```yaml
delegation:
  max_spawn_depth: 1        # Raha → Hala OK. Hala → anyone: blocked.
  subagent_auto_approve: false   # child agents still require Discord approval for tool calls
  max_concurrent_children: 3
```

**Context isolation:** Raha serialises all relevant context into each `delegate_task` call. Child agents start with zero session history — they cannot read prior Raha sessions or other child agent outputs.

**Channel isolation:** Child agents (Hala, Omar, Reem, Mira) never post to Discord directly during delegation. Raha owns the reply. This prevents child agents from leaking delegation context or intermediate results to Discord.

**No MCP for Raha:** Raha cannot directly query any database or service. If she needs data, she delegates. This means Raha cannot be tricked via prompt injection into directly accessing data outside her mandate — she has no tools to do so.

---

## Supply chain

**Python deps (uv workspace)**

All Python dependencies are declared in `pyproject.toml` per service and pinned in `uv.lock`. `allow_lazy_installs: false` prevents any runtime package installation.

Adding a new dep: update `pyproject.toml` → `uv lock` → review lockfile diff → commit both files.

**npx (GitHub MCP, Reem)**

`npx -y @modelcontextprotocol/server-github` pulls the package from npm at each Hermes session start. This is a trust surface — a compromised npm package could execute arbitrary code on the VPS as `vazir`.

**Accepted risk for now.** Mitigation options (implement when Reem is built):
- Pin a specific version: `npx -y @modelcontextprotocol/server-github@<version>`
- Verify package integrity before use (npm `--dry-run`, checksum)
- Run in a restricted context if Hermes supports it

**Hermes itself**

`~/.hermes/` is installed as a trusted third-party binary. Treated as read-only runtime. Any security issue in Hermes affects all agents. Update Hermes via its official update mechanism only — never manually patch `~/.hermes/` files.

**Tirith (Hermes built-in security)**

Hermes has a built-in security framework (`tirith`) enabled in the default config:
```yaml
security:
  tirith_enabled: true
  tirith_path: tirith
  tirith_timeout: 5
  tirith_fail_open: true   # if tirith check times out, request is allowed through
```

`tirith_fail_open: true` means a tirith timeout does not block the agent. If tirith is running security checks, a slow or failed check does not deny tool calls. This is the Hermes default — note it.

---

## Known gaps (current state — Phase 1)

These are accepted risks documented here, not forgotten. All are targeted in Phase 2 (`docs/plans/20260701-immediate-fixes.md`).

| Gap | Risk | Fix |
|---|---|---|
| `DISCORD_ALLOWED_USERS` not set on any profile | Any Discord server member can chat with any active agent | Phase 2: set per profile `.env` |
| `discord.allowed_channels` not set on assistant + cos profiles | Agents may respond in unintended channels | Phase 2: set in `config.yaml` |
| `allow_lazy_installs: true` in current curator config | Agent can silently `pip install` | Phase 2: set `false` in all profiles |
| Compression model `provider: auto` | Uses primary model for compression — cost + non-determinism | Phase 2: pin to `deepseek/deepseek-v3-0324` |
| `/etc/sudoers.d/nazim-hermes` not created | Nazim has no sudo — cannot restart services | Phase 2: create sudoers entry |
| LiteLLM DB tables not initialised | No spend tracking — spend abuse undetected | Phase 2: run Prisma migration |
| `audit.log` schema not run | No cross-service audit trail | Phase 3+: run migration 0003 after personal schema |
| `knowledge.vault_index` schema needs redesign | Current schema doesn't match Curator v1 note format | Phase 3: Curator v1 |
| npx unpinned for GitHub MCP | npm supply chain risk | Phase 6d: pin version when Reem is built |
| `tirith_fail_open: true` | Tirith timeout = no security check | Accepted — Hermes default, low risk in current setup |

---

## Security checklist — adding a new agent

Before enabling a new profile gateway:

- [ ] `allow_lazy_installs: false` in `config.yaml`
- [ ] `redact_secrets: true` in `config.yaml`
- [ ] `approvals.mode: manual` in `config.yaml`
- [ ] `cron_mode: deny` (or `manual` if cron is part of the mandate)
- [ ] `discord.allowed_channels` set to specific channel IDs only
- [ ] `DISCORD_ALLOWED_USERS` set in profile `.env`
- [ ] Compression model pinned to `deepseek/deepseek-v3-0324`
- [ ] MCP `tools.include` lists specified — no unrestricted access unless justified
- [ ] `terminal` toolset disabled unless mandate requires it; if enabled, `command_allowlist` set
- [ ] DB role created with minimum required grants — verified with `\dp` in psql
- [ ] GitHub PAT (if applicable) scoped to minimum required permissions

## Security checklist — adding a new service

Before deploying a new MCP service:

- [ ] Binds to `127.0.0.1` only — never `0.0.0.0`
- [ ] Dedicated PostgreSQL role — no shared roles with other services
- [ ] Role grants verified: only the schemas/tables the service needs
- [ ] INSERT-only on `audit.log` — no UPDATE or DELETE
- [ ] No secrets hardcoded — all via environment variables from `nizam.env`
- [ ] Service added to SERVICES.md and SCHEMAS.md
- [ ] systemd unit `EnvironmentFile` points to `secrets/nizam.env`
