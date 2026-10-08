# Architecture

Nizam-OS is a private AI operating system on a single VPS. A collection of autonomous agents each own a domain of life or business. They communicate through Discord, call MCP services over HTTP, and run as systemd services under a single user account. All interaction happens through Discord. The VPS is invisible.

**VPS:** Hostinger KVM2 — 8 GB RAM, 100 GB SSD, Ubuntu 24.04 LTS, 10 Jun 2027, 107.89 USD.

---

## Components

```mermaid
flowchart TD
    Discord[Discord Message]
    Gateway[Hermes Gateway]
    Agent[Agent]
    Tools[Native Tools]
    MCP[MCP Services]
    DB[(PostgreSQL)]

    Discord --> Gateway --> Agent
    Agent --> Tools
    Agent --> MCP --> DB
```

**Infrastructure layer:**

| Component | Role |
|-----------|------|
| PostgreSQL + pgvector + ParadeDB | Primary database. pgvector for semantic search; ParadeDB for BM25 full-text search. |
| Redis | LiteLLM exact-match cache. Future: semantic cache. |
| LiteLLM proxy | Routes all model calls to OpenRouter. Spend tracking, caching, token counting, rate limits. |
| Langfuse | LLM observability — traces prompts, responses, latency, and cost. Enabled on-demand for debugging only; disabled in normal operation. |
| Prometheus + node-exporter | Metrics collection. Custom `.prom` textfiles for LLM spend and service health. |
| Loki + Promtail | Log aggregation. Promtail tails `nizam-os/logs/*.log` and ships to Loki. Grafana reads logs via Loki datasource. |
| Grafana | Dashboards over Prometheus, Loki, and PostgreSQL. Two dashboards: Personal and Business. |
| Tailscale | VPN for VPS management. Not used by agents. |
| fail2ban + ufw | SSH hardening. |

---

## Agent roster

Ten agents across three domains (personal, business, shared). All run as Hermes profiles on the same VPS.

| Agent | Persona | Domain |
|-------|---------|--------|
| Nazim | System admin | Personal |
| Noor | Knowledge curator | Personal |
| Ayah | Personal assistant | Personal |
| Rashid | Investor | Personal |
| Hakim | Researcher | Shared |
| Raha | Chief of staff (orchestrator) | Business |
| Hala | CFO | Business |
| Omar | COO | Business |
| Reem | CTO | Business |
| Mira | CMO | Business |

> Agent channels, toolsets, MCP access, and command allowlists: [SERVICES](SERVICES.md).

---

## Load-bearing design decisions

### HTTP over stdio for MCP

Stdio MCP spawns a Python process per agent session — multiple active agents means multiple processes, each holding a DB connection and RAM. HTTP means one process, one DB connection, fixed RAM regardless of active agent count. Cold start per session drops to zero. All MCP services run as standalone systemd units and expose a single HTTP endpoint.

### LiteLLM as the single model proxy

All LLM calls route through LiteLLM → OpenRouter. Switching model providers requires only a config change — no code changes to agents or services. Spend tracking, token counting, caching, and key rotation are centralized here.

### Per-service DB roles

Each service connects as its own PostgreSQL role with grants scoped to exactly the schemas it needs. Isolation is enforced at the DB layer, not by convention. A compromise of one service cannot read another service's data.

### Approval gate on mutating actions

Any action that writes, updates, or deletes — file writes, terminal commands that mutate state, MCP tool calls that persist data, memory writes — surfaces to the owner in Discord before executing via `approvals.mode: manual`. Read-only operations (searches, lookups, data fetches) do not require approval. Mutations are where errors are expensive and hard to reverse; reads are not.

### Agents are independent of services

A service does not know or care which agent calls it. One service can serve multiple agents with different tool filters. Adding capability means building a new service or updating existing service — not modifying an existing agent.

### Skills: zero defaults, explicit additions

Each Hermes profile starts with all default skills disabled. Only skills required for the agent's mandate are enabled. This prevents skill surface creep and keeps each agent's capability set auditable.

### Skills as task encapsulation

Specific behavior lives in skills, not in the base agent context. The agent context file defines the mandate and constraints; skills carry the domain knowledge and task patterns for each work type the agent performs. This keeps base contexts lean regardless of how many tasks an agent can do, and makes capability additions auditable — adding a capability means writing a skill, not editing the agent.

### `allow_lazy_installs: false` on all profiles

The Hermes default allows agents to run `pip install` at runtime. This is disabled everywhere. Every dependency must be declared in `pyproject.toml` and reviewed. Agents cannot pull in packages silently.

---

## Knowledge vault

`~/nizam-vault/` on the VPS (git repo). Notes are Markdown with YAML frontmatter. Three subdirectories exist in the vault: 

- `commons/`
- `personal/`
- `business/`

Notes use an `areas` field (multi-value controlled vocabulary) instead of a strict single-domain taxonomy. Overlap is expected — a note on stoicism can be both `philosophy-ethics` and `personal-development`. Area vocabulary is enforced at write time by knowledge-service.

---

## Cross-cutting constraints

- All internal services bind to `127.0.0.1` only. Nothing is publicly reachable except SSH.
- **Observability:** systemd timers write `.prom` metric files scraped by Prometheus via node-exporter's textfile collector. Promtail tails all service and script logs and ships to Loki. Grafana dashboards visualize system metrics and logs across many dimensions — spend, health, throughput, latency, and more — so the system is always under observation and analytics inform operational decisions. The Grafana PostgreSQL datasource connects as the `grafana` DB role (SELECT-only).
- **Staggered scheduling:** timers, cron jobs, and periodic processes are offset from each other. No two heavy processes start at the same wall-clock time. Prevents memory and CPU spikes from concurrent startup.
- No agent connects directly to any external model API. All inference routes through LiteLLM.
- `cron_mode: deny` on most profiles. Nazim and Raha have `cron_mode: manual`.
- `redact_secrets: true` on all profiles. Hermes scrubs known secret patterns from tool output.
- **Subagent delegation:** every agent cannot delegate tasks to subagents. Depth and number of children enforced on a per-agent basis.
- **Single secrets file:** all secrets live in `secrets/nizam-os.env`. No per-service `.env` files for MCP services. Per-agent secrets are the only exception — each Hermes profile has `secrets/<agent>.env.enc`. Hermes reads the profile's `.env.enc` at startup; a symlink at `hermes/profiles/<agent>/.env.enc` → `secrets/<agent>.env.enc` keeps the profile directory clean while secrets stay in `secrets/`.
- **Minimal config files:** tunables for a service live in one `config.yaml` per service directory symlinked per-service `config.yaml` → `config/<service-name>-config.yaml`. Agent profile configs live in `hermes/profiles/<agent>/config.yaml`. Convenience symlinks at `hermes/profiles/<agent>/config.yaml` → `config/<agent>-config.yaml` allow all configs to be browsed from one place. Changing a tunable requires editing one file and restarting the service.
- **Idempotent phase scripts:** each phase ships one orchestrator script (`scripts/setup/00N-<phase-name>.sh`) that can be re-run safely to reach or verify that phase's exit criteria. Running a phase script twice must produce the same end state as running it once. This is the canonical way to set up, recover, or verify any phase.
- **Uniform logging:** two log targets, same JSON format. MCP services log to `logs/<service-name>.log` via systemd stdout/stderr redirect — fixed fields: `ts`, `level`, `service`, `module`, `func`, `msg`; all services using `nizam-shared` get this automatically. Bash scripts log to `logs/scripts.log` via `_log.sh` — fields: `ts`, `level`, `script`, `msg`. Both rotated by `config/logrotate.nizam-os`, both tailed by Promtail. Log verbosity is controlled by `LOG_LEVEL` in `config/nizam-os.yaml` (default `INFO`). Bash scripts emit `INFO`/`WARN`/`ERROR`; Python services use the full Python logging hierarchy (`DEBUG`/`INFO`/`WARNING`/`ERROR`/`CRITICAL`) — both filter at the configured level.
- **Agent skills and memories:** each Hermes profile has `hermes/profiles/<agent>/skills/` for domain skills and `hermes/profiles/<agent>/memories/` for persistent memory. Both are symlinked from `.hermes/profiles/<agent>/memories/` and `.hermes/profiles/<agent>/memories/` to `hermes/profiles/<agent>/memories/` and `hermes/profiles/<agent>/memories/` respectively. Skills and memory toolsets are disabled on all profiles by default; enabled per-profile once the governance mechanism is operational.

> Security model: [SECURITY](docs/SECURITY.md).
