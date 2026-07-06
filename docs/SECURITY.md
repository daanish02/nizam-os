# Security

Security model across all layers. When adding a new agent or service, every section here applies — new components must fit the model, not bypass it.

---

## Threat model

| Threat | Source | Primary control |
|--------|--------|-----------------|
| External attacker on VPS | Internet | UFW + fail2ban + SSH key-only + Tailscale |
| Agent doing too much | Rogue LLM output | Tool scoping, command_allowlist, sudoers, DB role isolation |
| Prompt injection | Discord messages, web content, ingested PDFs, vault content | Manual approvals + DISCORD_ALLOWED_USERS + redact_secrets |
| Secret leakage | Agent tool output, git commits | redact_secrets + age encryption + gitignore |
| Cross-agent data access | Agent reading another agent's domain | DB role grants, MCP tool include lists |
| Silent package install | Agent running pip at runtime | allow_lazy_installs: false on all profiles |
| Rogue cron creation | Agent scheduling arbitrary jobs | cron_mode: deny on most profiles |
| Spend abuse | Agent making excessive LLM calls | LiteLLM virtual keys + spend tracking |
| Delegation chain overreach | Sub-agent spawning further sub-agents | depth and concurrent per-agent basis |
| Supply chain | npm / pip packages at runtime | uv lockfile + allow_lazy_installs: false |

---

## Trust boundaries

**Owner → agents:** The owner communicates through Discord. `DISCORD_ALLOWED_USERS` restricts which Discord user IDs can interact with each agent. Only the owner's ID is listed.

**Agent → tools:** Mutating tool calls (writes, updates, deletes, terminal commands that change state) surface to the owner in Discord before executing via `approvals.mode: manual`. Read-only tool calls do not require approval.

**Agent → MCP services:** Each agent's `config.yaml` specifies exactly which MCP tools it can call. Tools not in `tools.include` are invisible to the agent.

**Service → database:** Each service connects as its own PostgreSQL role. Roles hold grants only on the schemas they need. DB-layer isolation — not convention.

**LiteLLM as the single LLM chokepoint:** No agent connects directly to any external model API. All inference routes through `localhost:4000`. Spend tracking, caching, and key rotation are centralized here.

---

## VPS hardening

**Firewall:** UFW — allow inbound SSH (22), HTTP/HTTPS (80/443 for Let's Encrypt if needed). Default deny inbound. Tailscale subnet allowed.

**SSH:** Key-only authentication. Password auth disabled. Tailscale IP is the intended management path.

**fail2ban:** Default SSH jail. Bans after repeated failed login attempts.

**unattended-upgrades:** Auto-applies Ubuntu security updates. Does not auto-restart services.

---

## Network boundaries

All internal services bind to `127.0.0.1` only. No service is publicly reachable except SSH.

| Layer | Binding |
|-------|---------|
| PostgreSQL | 127.0.0.1:5432 |
| Redis | 127.0.0.1:6379 |
| LiteLLM proxy | 127.0.0.1:4000 |
| All MCP services | 127.0.0.1:PORT |
| Prometheus | 127.0.0.1:9090 |
| Loki | 127.0.0.1:3100 |
| Grafana | 127.0.0.1:3000 (access via Tailscale) |

---

## Secrets

**At rest:** All secrets stored in `secrets/nizam-os.env`, encrypted with age. The age private key (`secrets/nizam-age-key.txt`) must be backed up externally — it decrypts everything. Plaintext secrets are never committed to git.

**In transit:** Agent → LiteLLM → OpenRouter over HTTPS. Agent → MCP services over HTTP on localhost (loopback only — TLS not needed). Grafana → PostgreSQL via local socket.

**In agent output:** `redact_secrets: true` on all profiles — Hermes scrubs known secret patterns from tool output before returning to the agent. Best-effort filter, not a guarantee.

---

## Database roles

| Role | Grants | Cannot access |
|------|--------|--------------|
| `svc_litellm` | Owns `litellm` schema | Everything else |
| `svc_knowledge` | RW `knowledge.*`, INSERT `audit.log` | Everything else |
| `svc_finance_personal` | RW `finance_personal.*`, INSERT `audit.log` | Everything else |
| `svc_personal` | RW `personal.*`, INSERT `audit.log` | Everything else |
| `svc_finance_business` | RW `finance_business.*`, INSERT `audit.log` | Everything else |
| `svc_crm` | RW `crm.*`, INSERT `audit.log` | Everything else |
| `svc_analytics` | RW `analytics.*`, INSERT `audit.log` | Everything else |
| `grafana` | SELECT on all schemas | Any write |

**Audit invariant:** No service role holds UPDATE or DELETE on `audit.log`. Insert-only by grant.

---

## Agent autonomy controls

Applied to all profiles without exception. Any new profile must include all of these.

| Control | Rule |
|---------|------|
| `allow_lazy_installs: false` | No runtime pip install — any agent can pull arbitrary code otherwise |
| `approvals.mode: manual` | Mutating tool calls (writes, updates, deletes, state-changing terminal commands) require Discord approval. Reads do not. |
| `cron_mode: deny` | No persistent scheduled jobs without explicit setup approval |
| `redact_secrets: true` | Hermes scrubs secret patterns from tool output |
| `DISCORD_ALLOWED_USERS` | Only the owner's Discord user ID can interact with any agent |
| `discord.allowed_channels` | Each agent sees only its own channels |
| Compression model pinned | Cheap and fast model; prevents cost bleed |

### Terminal restrictions

| Agent | Terminal | Restriction |
|-------|----------|-------------|
| Admin | Enabled | `command_allowlist` + `/etc/sudoers.d/admin-nizam` (service restart only — not full sudo) |
| CTO | Enabled | `command_allowlist` — read-only diagnostics only, no restarts, no installs |
| All others | Disabled | `terminal` toolset not loaded |

---

## Prompt injection

**Untrusted input surfaces:** Discord messages, web search results, PDF content, image descriptions from vision model, YouTube transcripts, bank statement content.

**Controls:** `DISCORD_ALLOWED_USERS` limits message senders. `approvals.mode: manual` means every mutating tool call surfaces to the owner — injection cannot write, delete, or execute without human confirmation. `redact_secrets: true` reduces exfiltration value. Minimal tool surface per agent limits blast radius.

**Residual risk:** A sufficiently convincing injection could trick the owner into approving a malicious action. The owner sees the tool call but must recognize it as malicious. No automated content inspection is in place.

---

## Delegation security

Delegation is opt-in per profile. Most agents have no delegation toolset — it is explicitly enabled only where the mandate requires spawning subagents.

- `subagent_auto_approve: false` on all profiles with delegation — subagent tool calls still require Discord approval.
- `max_spawn_depth` and `max_concurrent_children` are set per profile; values live in each profile's `config.yaml`. See [SERVICES](docs/SERVICES.md) for per-agent values.
- Subagents never post to Discord directly. The parent agent synthesizes and posts.
- Delegation depth and concurrency limits are enforced by Hermes — a subagent cannot exceed the depth budget set by its parent's profile.

---

## Sandbox

CTO's delegated subagents run inside a firejail sandbox. Firejail restricts each subagent process to a contained environment.

- **Filesystem:** read-only outside the designated workspace directory. No writes to system paths or other agent directories.
- **Network:** outbound limited to `127.0.0.1` only — LiteLLM and MCP services. No direct internet access.
- **Process visibility:** restricted `/proc` view — subagent cannot see or signal processes outside its namespace.

**Why:** CTO's subagents execute code as part of technical research and diagnosis workflows. Firejail contains a misbehaving subagent to its task scope — it cannot affect the host, other agents, or the database even if its tool calls are malicious.

**Integration:** Hermes spawns sandboxed subagents via `sandbox.firejail: true` in CTO's profile. `subagent_auto_approve: false` ensures all subagent tool calls still surface to the owner before executing.

---

## Supply chain

**Python:** All dependencies declared in `pyproject.toml` per service and pinned in `uv.lock`. `allow_lazy_installs: false` prevents runtime installation.

**Node/npx:** GitHub MCP server (`@modelcontextprotocol/server-github`) is pulled from npm at Hermes session start. This is a trust surface — a compromised npm package could execute arbitrary code. Mitigation: pin a specific version when cto is built.

**Hermes:** Treated as a trusted third-party binary. Never manually patched. Updated only via its official update mechanism.

**tirith (Hermes built-in security):** Enabled on all profiles. `tirith_fail_open: true` — a tirith timeout allows the request through. Accepted risk at current scale.

---

## Checklist — adding a new agent

- [ ] `allow_lazy_installs: false`
- [ ] `redact_secrets: true`
- [ ] `approvals.mode: manual`
- [ ] `cron_mode: deny` (or `manual` if cron is part of the mandate)
- [ ] `discord.allowed_channels` set to the agent's specific channel IDs
- [ ] `DISCORD_ALLOWED_USERS` set to owner's Discord user ID
- [ ] Compression model pinned
- [ ] `tools.include` specified — no unrestricted MCP access
- [ ] `terminal` disabled unless mandate requires it; if enabled, `command_allowlist` set
- [ ] Dedicated DB role created with minimum required grants
- [ ] Delegation toolset disabled for all except selected agents with appropriate depth and concurrent workers

## Checklist — adding a new service

- [ ] Binds to `127.0.0.1` only — never `0.0.0.0`
- [ ] Dedicated PostgreSQL role — no shared roles
- [ ] Role grants verified: only the schemas/tables the service needs
- [ ] INSERT-only on `audit.log` — no UPDATE or DELETE
- [ ] No secrets hardcoded — all via environment variables from `nizam-os.env`
- [ ] Service added to [SERVICES](docs/SERVICES.md) and [SCHEMAS](docs/SCHEMAS.md)
- [ ] systemd unit reads secrets from `secrets/nizam-os.env`
