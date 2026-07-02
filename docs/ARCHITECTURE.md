# Nizam-OS — Architecture & Start Here

> **How to use this document:** Read top to bottom. This is the primary reference for Claude Code sessions, Hermes agents, and any other AI/LLM working in this repo. All design decisions are recorded here. Drill-down links at the bottom.

---

## What is nizam-os?

A private AI operating system on a VPS. Eight autonomous agents each own a domain of life or business. They connect to Discord, call MCP services (which talk to PostgreSQL), and run as systemd services. Interaction happens through Discord channels. The VPS is invisible.

**VPS:** Hostinger KVM2 — 8 GB RAM, 100 GB SSD, Ubuntu 24.04 LTS, expires 10 Jun 2027. Cost: 107.89 USD total.

**Rebuild context:** The VPS will be wiped and rebuilt from scratch. This repo is the complete rebuild runbook — nothing exists only on the VPS without a record here. Start from `docs/plans/20260701-foundation.md` to go from bare OS to a working system.

Full vision: `docs/VISION.md`

---

## Critical constraints

These apply to every task, every session, forever. Non-negotiable.

- **`~/.hermes/` is read-only.** Never modify Hermes source code or runtime files. Configure behaviour only via files in `hermes/profiles/<name>/`. This includes `SOUL.md`, `AGENTS.md`, `config.yaml`, and skills. No exceptions.
- **Single source of truth for config.** All shared env vars live in one file: `secrets/nizam.env` (templated as `secrets/nizam.env.example` in the repo). Per-agent `.env` on VPS contains only `DISCORD_TOKEN` and `DISCORD_GUILD_ID`. No value is defined in two places.
- **No emojis.** In code, docs, agent responses, or anywhere else.
- **Primary audience is Claude Code and Hermes agents.** Write all docs precisely and completely. Assume no prior context. Avoid ambiguous references, orphaned pronouns, and approximate values.
- **Never commit.** User commits all changes manually.

---

## Agent Roster

Eight agents across three Discord categories. Each owns a domain; each is a Hermes profile on the same VPS.

| Agent | Persona | Phase | Status |
|---|---|---|---|
| Nazim | System admin | 4 | In repo — rename Bani→Nazim pending |
| Noor | Knowledge curator | 3 | In repo — tools non-functional (schema not run) |
| Ayah | Personal assistant | 5 | In repo — stub profile |

Business agents (Phases 6a–6e): `docs/future/ARCHITECTURE.md`.

Per-agent channels, toolsets, MCP access, command allowlists, and key constraints: `docs/AGENTS.md`.
Discord server structure and channel-to-agent map: `docs/DISCORD.md`.

---

## How it's wired together

```
Discord message
    │
    ▼
Hermes Gateway (systemd user service per agent)
    │  reads: ~/.hermes/profiles/<name>/config.yaml
    │  injects: SOUL.md (personality) + AGENTS.md (mandate)
    │
    ▼
Agent (LLM via LiteLLM proxy → OpenRouter)
    │
    ├── Hermes native tools: terminal, file, memory, cronjob, skills
    │
    └── MCP servers (HTTP, localhost only)
            │
            ├── knowledge-service  :8100  → knowledge schema       (PostgreSQL)
            ├── finance-service    :8101  → finance_personal + finance_business  (PostgreSQL)
            ├── personal-service   :8102  → personal schema        (PostgreSQL)
            ├── crm-service        :8104  → crm schema             (PostgreSQL)
            └── analytics-service  :8105  → analytics schema       (PostgreSQL)
                        │
                        └── audit.log (all services write here)
```

**Design rules:**

- **HTTP over stdio for MCP.** Stdio spawns a Python process per agent session — multiple active agents means multiple processes each holding a DB connection and RAM. HTTP means one process, one DB connection, fixed RAM regardless of how many agents are active. Cold start per session drops from ~2s to zero. All MCP services run as standalone systemd units. Hermes connects via `url: http://127.0.0.1:PORT/mcp`.

- **LiteLLM as the model proxy.** All LLM calls route through LiteLLM → OpenRouter. Spend tracking, token counting, tool call logging, request/response latency, rate limiting, and caching happen at this layer. LiteLLM supports 100+ providers (Anthropic, Google, Bedrock, Mistral, and others) — switching providers means changing `model` and `base_url` in `config.yaml` only, no code changes to agents or services.

- **Caching is first-class.** LiteLLM enables two cache layers: exact cache (Redis key-match — identical prompts return instantly) and semantic cache (Redis + embeddings — similar prompts return without re-inference). Exact cache is active. Semantic cache is planned (`config/litellm.yaml`: "Semantic cache added later").

- **`allow_lazy_installs: false`.** Hermes default allows agents to run `pip install` at runtime. This is disabled on all profiles. Every dependency must be declared in `pyproject.toml` and reviewed by the user. Agents cannot pull in packages silently.

- **Compression model pinned.** Hermes summarizes long conversation context to fit within the context window. Without pinning it uses the primary model. All profiles pin `deepseek/deepseek-v3-0324` via `custom:litellm` as the compression model. Cost: near zero.

- **Sudo is scoped.** Nazim can restart specific services only, via `/etc/sudoers.d/nazim-hermes`. No full sudo.

- **Skills: zero defaults, explicit additions.** Each profile's `config.yaml` starts with all default skills disabled. Only skills needed for the agent's mandate are enabled. Custom skills follow the agentskills.io open standard. Skills not relevant to a Linux/VPS environment (Apple, macOS, etc.) are never loaded.

- **MCP servers expose tools, prompts, and resources.** Hermes natively renders `@mcp.prompt()` templates and `@mcp.resource()` endpoints. Services should expose prompt templates for complex multi-step operations and resources for read-only data (vault index, service status). Not tools only.

---

## Services

**Architecture principle:** Services and agents are independent. A service does not know or care which agent calls it. One service can serve multiple agents with different tool filters. Capability is added by building a service, not by modifying an agent.

| Service | Port | Status |
|---|---|---|
| `knowledge-service` | 8100 | In repo — non-functional (schema not run) |
| `finance-service` | 8101 | Specced |
| `personal-service` | 8102 | Specced |

Business services (crm-service/8104, analytics-service/8105, math-service/8103): `docs/future/ARCHITECTURE.md`.

Port map, tool signatures, consumer access matrix, approval workflows, and tunables: `docs/SERVICES.md`.

---

## Database

Single PostgreSQL instance. Each service connects as its own role — isolation enforced at the DB layer, not by convention.

Schemas: `knowledge`, `personal`, `finance_personal`, `audit`.

`finance_personal` is isolated from the business finance schema — separate role, separate migrations, separate service connection.

Business schemas (finance_business, crm, analytics): `docs/future/SCHEMAS.md`.

Full table definitions, FK constraints, DB roles and grants, migration index: `docs/SCHEMAS.md`.

---

## Infrastructure

| Component | What it does |
|---|---|
| PostgreSQL + pgvector + ParadeDB | Primary database. pgvector for semantic search; ParadeDB for BM25 full-text search. |
| Redis | LiteLLM exact-match cache + future semantic cache |
| LiteLLM proxy | Routes all model calls → OpenRouter. Spend tracking, caching, rate limits. |
| Prometheus + node-exporter | Metrics collection. Textfile collector for custom `.prom` files. |
| Grafana | Dashboards. Datasource UID must be `nizam-prometheus`. |
| Hermes profile watcher | Bidirectional sync: `hermes/profiles/` ↔ `~/.hermes/profiles/` |
| Metrics timers | Three systemd timers write LLM spend, service health, tool call metrics. |
| Tailscale | VPS management access via VPN |
| fail2ban + ufw | SSH hardening |

Component-level deploy status: `docs/ROADMAP.md` → Infrastructure.

Three systemd timers write `.prom` files to `/var/lib/prometheus/node-exporter/` — node-exporter picks them up every 15s. Two Grafana dashboards (`grafana/agents-dashboard.json`, `grafana/services-dashboard.json`) visualise the data. Dashboards must be re-imported after a VPS wipe.

Timer `OnCalendar` values are staggered (metrics-llm at :00, metrics-services at :02, metrics-toolcalls at :04) so load does not peak simultaneously.

Operational detail (verify metrics, Prometheus scrape health, dashboard import): `docs/RUNBOOK.md` → Observability.

---

## Knowledge vault

`~/nizam-vault/` on the VPS (git repo). Notes are Markdown with YAML frontmatter. Three subdirectories: `commons/` (Noor), `personal/` (Ayah — journal), `business/` (future).

Notes use an `areas` field (multi-value controlled vocabulary) instead of a strict single-domain taxonomy. Overlap is expected and allowed — a note on stoicism can be both `philosophy-ethics` and `personal-development`. Values are enforced by knowledge-service at write time; new areas require a code change. `tags` is separate, free-form supplementary metadata.

Ingestion workflow, approval gate, source types, area vocabulary: `docs/AGENTS.md` (Noor section) and `docs/SERVICES.md` (knowledge-service). Source status by type: `docs/ROADMAP.md` → Knowledge ingestion.

---

## Current state

Component-level status: `docs/ROADMAP.md` → Infrastructure and Agents tables.

Immediate fixes required before Phase 3: `docs/ROADMAP.md` → Immediate fixes section. Step-by-step: `docs/plans/20260701-immediate-fixes.md`.

---

## Build order

**Personal agents before business agents.** Personal (Noor, Nazim, Ayah) establishes the pattern. Within personal: Nazim is critical infrastructure — he maintains all other services and agents (their doctor). Nail Nazim before Noor and Ayah; errors in Noor and Ayah are recoverable, errors in Nazim take down everyone. Business agents (Phases 6a–6e): `docs/future/ARCHITECTURE.md`. Build them only after the personal side is stable; lessons from all three personal agents feed directly into business implementations.

Full phase-by-phase sequence, status, and spec pointers: `docs/ROADMAP.md`

---

## Hermes profile structure

Each agent lives at `hermes/profiles/<name>/` in the repo, synced to `~/.hermes/profiles/<name>/` on VPS via the profile watcher service.

Key files per profile: `config.yaml` (model, MCP, toolsets, Discord), `SOUL.md` (personality only), `AGENTS.md` (mandate + rules), `memories/USER.md` (pre-seeded user context — static, version-controlled), `.env` (Discord token + LiteLLM key — VPS only, gitignored).

`TOOLS.md` is dropped — Hermes auto-discovers MCP tools; TOOLS.md is dead prompt weight. Delete wherever it exists.

Config field reference, SOUL.md vs AGENTS.md rules, skills, cron, MCP transport patterns: `docs/HERMES.md`.

---

## Drill-down index

### Specs

| Spec | File | Phase |
|---|---|---|
| Foundation (what's built now) | `docs/specs/20260701-foundation-design.md` | 1 (done) |
| Curator v1 (Noor) | `docs/specs/20260701-curator-v1-design.md` | 3 |
| Admin v1 (Nazim) | `docs/specs/20260701-admin-v1-design.md` | 4 |
| Assistant v1 (Ayah) | `docs/specs/20260701-assistant-v1-design.md` | 5 |

Business specs: `docs/future/ARCHITECTURE.md` → Drill-down index.

### Plans (step-by-step implementation guides)

| Plan | File | Prerequisite |
|---|---|---|
| Foundation rebuild (fresh VPS → current state) | `docs/plans/20260701-foundation.md` | Age private key backup |
| Immediate fixes | `docs/plans/20260701-immediate-fixes.md` | Phase 1 live |
| Curator v1 | `docs/plans/20260701-curator-v1.md` | Phase 2 complete |
| Admin v1 | `docs/plans/20260701-admin-v1.md` | Phase 2 complete |
| Assistant v1 | `docs/plans/20260701-assistant-v1.md` | Phase 2 complete |

Business plans: `docs/future/ARCHITECTURE.md`.

### Quick-reference docs

`docs/AGENTS.md` — all 8 agents: channels, toolsets, MCP access, key constraints

`docs/SERVICES.md` — port map, all MCP tools, consumer access matrix, DB roles

`docs/SCHEMAS.md` — all DB schemas: tables, columns, FK constraints, role grants

`docs/HERMES.md` — Hermes config.yaml reference: toolsets, MCP config, SOUL/AGENTS.md rules, skills, cron

`docs/DISCORD.md` — Discord server structure, bot setup, intents, channel IDs, webhooks, DISCORD_ALLOWED_USERS

`docs/SECRETS.md` — all env vars: purpose, consumer, which phase adds them

`docs/INTEGRATIONS.md` — external services: OpenRouter, YouTube, FX, GitHub, Tailscale, Prometheus

`docs/RUNBOOK.md` — fresh VPS rebuild sequence + day-to-day ops: service management, secret rotation, adding agents, common fixes

`docs/future/ARCHITECTURE.md` — business agents, services, build order (Phases 6a–6e)

`docs/SECURITY.md` — threat model, VPS hardening, agent controls, prompt injection, audit trail, known gaps

`docs/GLOSSARY.md` — domain terms, Hermes terms, nizam-os patterns

### Master status tracker

`docs/ROADMAP.md`
