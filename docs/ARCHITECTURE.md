# Nizam-OS — Architecture & Start Here

> **How to use this document:** Read top to bottom. This is the primary reference for Claude Code sessions and Hermes agents. All design decisions are recorded here. Changes here flow into specs (`docs/specs/`) then plans (`docs/plans/`). Drill-down links at the bottom.

---

## What is nizam-os?

A private AI operating system on a VPS. Eight autonomous agents each own a domain of life or business. They connect to Discord, call MCP services (which talk to PostgreSQL), and run as systemd services. Interaction happens through Discord channels. The VPS is invisible.

**VPS:** Hostinger KVM2 — 8 GB RAM, 100 GB SSD, expires 10 Jun 2027.

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

| Agent | Persona | Discord channels | Domain | Status |
|---|---|---|---|---|
| **Nazim** | System admin | System category (`#admin`, `#alerts`, `#warning`, `#sandbox`) | Infrastructure health, incidents, restarts; Hermes guide | Live — rename Bani→Nazim pending |
| **Noor** | Knowledge curator | `#learning` (Personal) | Vault ingestion: URLs, YouTube, PDF, images | Gateway active — tools non-functional (DB schema not set up) |
| **Ayah** | Personal assistant | `#briefing`, `#finances`, `#goals`, `#chat` (Personal) | Daily briefings, expense logging, goals/tasks/habits/journal | Gateway inactive — services not built |
| **Raha** | Chief of Staff | `#strategy` (Chairman's Office), `#boardroom`, `#biz-chat` (Arc Systems) | Business synthesis, weekly reviews, delegates to business agents | Gateway inactive — SOUL.md is placeholder |
| **Hala** | CFO | `#cfo-office` (Arc Systems) | Business ledger, invoices, reconciliation | Not built |
| **Omar** | COO | `#coo-office` (Arc Systems) | Operations, CRM, client relationships | Not built |
| **Reem** | CTO | `#cto-office` (Arc Systems) | Codebase health, GitHub, technical decisions | Not built |
| **Mira** | CMO | `#cmo-office` (Arc Systems) | Content strategy, campaigns, social performance | Not built |

**Access control:** each agent sees only its channels and only the MCP tools it needs. Access control details (channels, toolsets, MCP includes) are in each agent's individual spec.

### Discord server map

```
Start:             #vision, #server-map
Personal:          #briefing, #finances, #goals, #learning, #chat
System:            #alerts, #admin, #warning, #sandbox
Chairman's Office: #strategy
Arc Systems:       #biz-chat, #boardroom, #cfo-office, #cto-office, #coo-office, #cmo-office
```

### Nazim — detail

Has access to the full System category, not just `#admin`. Also serves as the **Hermes guide**: if adding a new agent, new service, or new feature, Nazim can read the Hermes docs (available locally) and explain what is supported and how to wire it given current system state.

### Ayah — channel design

| Channel | Who drives it | What happens |
|---|---|---|
| `#briefing` | Ayah (cron) | **Morning:** spend summary, next 5 tasks, one quote. **Evening:** day's spend recap + journal thread prompt. User journals by replying in the thread — Ayah saves thread content as a journal entry. |
| `#finances` | User | User posts expenses and income. Ayah logs them. No proactive messages here. |
| `#goals` | Both | All structured tracking. Proactive posts on schedule: tasks (next 5, daily), projects (updates, less frequent), habits (check-in per repetition cadence), goals (weekly, frequency depends on scope). User adds/edits/deletes in this channel. |
| `#chat` | User | General. Anything outside structured flows. |

### Raha — delegation

Raha delegates to Hala, Omar, Reem, and Mira. Delegation mode:
- **Sync** — Raha needs the answer before continuing (blocks on sub-agent response)
- **Async** — Raha fires the task and moves on (sub-agent replies in its own time)

Hermes supports delegation via the `delegation` toolset. Verify sync/async support in Hermes official docs before implementing Raha.

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
            ├── knowledge-service  :8100  → knowledge schema (PostgreSQL)
            ├── finance-service    :8101  → finance schema  (PostgreSQL)
            ├── personal-service   :8102  → personal schema (PostgreSQL)
            └── [future services]  :8103+
                        │
                        └── audit.log (all services write here)
```

**Design rules:**

- **HTTP over stdio for MCP.** Stdio spawns a Python process per agent session — multiple active agents means multiple processes each holding a DB connection and RAM. HTTP means one process, one DB connection, fixed RAM regardless of how many agents are active. Cold start per session drops from ~2s to zero. All MCP services run as standalone systemd units. Hermes connects via `url: http://127.0.0.1:PORT/mcp`.

- **LiteLLM as the model proxy.** All LLM calls route through LiteLLM → OpenRouter. Spend tracking, token counting, tool call logging, request/response latency, rate limiting, and caching happen at this layer.

- **Caching is first-class.** LiteLLM enables two cache layers: exact cache (Redis key-match — identical prompts return instantly) and semantic cache (Redis + embeddings — similar prompts return without re-inference). Both are active. This reduces cost and latency at the most expensive point in the system.

- **`allow_lazy_installs: false`.** Hermes default allows agents to run `pip install` at runtime. This is disabled on all profiles. Every dependency must be declared in `pyproject.toml` and reviewed by the user. Agents cannot pull in packages silently.

- **Compression model pinned.** Hermes summarizes long conversation context to fit within the context window. Without pinning it uses the primary model. All profiles pin `deepseek/deepseek-v3-0324` via `custom:litellm` as the compression model. Cost: near zero.

- **Sudo is scoped.** Nazim can restart specific services only, via `/etc/sudoers.d/nazim-hermes`. No full sudo.

- **Skills: zero defaults, explicit additions.** Each profile's `config.yaml` starts with all default skills disabled. Only skills needed for the agent's mandate are enabled. Custom skills follow the agentskills.io open standard. Skills not relevant to a Linux/VPS environment (Apple, macOS, etc.) are never loaded.

- **MCP servers expose tools, prompts, and resources.** Hermes natively renders `@mcp.prompt()` templates and `@mcp.resource()` endpoints. Services should expose prompt templates for complex multi-step operations and resources for read-only data (vault index, service status). Not tools only.

---

## Services

**Architecture principle:** Services and agents are independent. A service does not know or care which agent calls it. An agent does not own a service — it connects to an HTTP endpoint. One service can serve multiple agents (finance-service serves both Ayah and Hala with different tool filters). One agent can use multiple services. Capability is added by building a service, not by modifying an agent. The agent roster and service registry grow independently.

| Service | Port | Status | Schema | Consumers |
|---|---|---|---|---|
| `knowledge-service` | 8100 | Code exists — DB not set up, non-functional | `knowledge` (needs redesign) | Noor |
| `finance-service` | 8101 | Not built | `finance.personal_transactions` | Ayah, Hala (filtered) |
| `personal-service` | 8102 | Not built | `personal.*` | Ayah |
| `math-service` | 8103 | Planned | — | Any agent needing exact arithmetic |
| `crm-service` | 8104 | Planned (Phase 4) | `crm` | Omar, Mira |
| `social-service` | — | Planned (Phase 5) | — | Mira |
| `analytics-service` | — | Planned (Phase 5) | — | Raha, Mira, Nazim |

**math-service:** LLMs are unreliable at arithmetic and exact numeric precision (financial calculations, zakat, compound interest, statistics). math-service wraps a Python evaluation engine — agents pass an expression or structured request, get back a guaranteed-correct result. No LLM in the math path.

**RAG strategies:** `knowledge-service` uses pgvector semantic search (embeddings) and ParadeDB full-text search (BM25). Both run inside PostgreSQL — no separate vector DB. Semantic search for concept similarity; full-text for exact phrase match. Hybrid re-ranking is supported. A future `research-service` (not yet specced) would run multi-step retrieval across vault and web and synthesize a briefing — distinct from ingestion (add to vault) and retrieval (query vault).

---

## Database

Single PostgreSQL instance. **Current state: empty — no schemas, no tables, LiteLLM tables not set up.** Everything below is the target design.

Each service has its own PostgreSQL role with minimum required permissions.

| Schema | Tables | Role | Used by | Migration status |
|---|---|---|---|---|
| `knowledge` | TBD — being redesigned | `svc_knowledge` | knowledge-service | Needs redesign |
| `personal` | `habits`, `habit_logs`, `goals`, `tasks`, `journal` | `svc_personal` | personal-service | Planned |
| `finance` | `personal_transactions` | `svc_personal`, `svc_finance_personal` | personal-service, finance-service | Planned |
| `audit` | `log` (append-only) | all service roles (INSERT only) | all services | Planned |
| `crm` | clients, deals, projects | `svc_crm` | future | Not specced |

**Migrations:** `db/migrations/0001_knowledge_schema.sql` (needs redesign), `0002_personal_schema.sql` (planned), `0003_audit_schema.sql` (planned).

**LiteLLM DB:** LiteLLM requires its own tables for spend tracking and user management. These are created on first run when `DATABASE_URL` is set. Run `litellm --config litellm-config.yaml` once after `DATABASE_URL` is in the environment.

---

## Infrastructure

PostgreSQL and Redis are running. LiteLLM is installed but DB tables not yet initialised — spend tracking is broken until `DATABASE_URL` is set and LiteLLM runs its migration.

| Component | What it does | Status |
|---|---|---|
| PostgreSQL + pgvector + ParadeDB | Primary database. Vector search for knowledge-service. | Running — empty (no schemas) |
| Redis | LiteLLM cache (exact + semantic) + health-monitor state | Running |
| LiteLLM proxy | Routes model calls to OpenRouter. Spend tracking. Exact and semantic caching. Rate limits. | Installed — DB not initialised |
| Prometheus + Grafana | Metrics collection and dashboards — see below | Running |
| Hermes profile watcher | Bidirectional sync: `nizam-os/hermes/profiles/` ↔ `~/.hermes/profiles/` | Running |
| Metrics collectors | Three systemd timers feeding Prometheus — see below | Running |
| Tailscale | Private VPS access | Running |
| fail2ban + ufw | SSH hardening | Running |

**Active session monitoring:** Prometheus tracks active Hermes gateway sessions (number of `hermes-gateway-*.service` units in active state). Expected value: 1 (single user). Nazim's heartbeat includes SSH session count (`who | wc -l`) and active gateway unit count. If SSH count exceeds 1, Nazim posts an alert to `#warning`.

### Observability stack

Three scripts run as systemd timers, collect metrics, and write to Prometheus node-exporter `.prom` files. Two Grafana dashboards (JSON in `grafana/`) visualise the data. After a VPS rebuild, dashboards must be re-imported from the JSON files — they are not auto-provisioned.

**Metrics collectors:**

| Script | Timer | What it collects |
|---|---|---|
| `scripts/metrics-llm.py` | every 1 min | LiteLLM API: calls, token counts (in/out/cache), spend, latency, cache hit rate — by model and by agent |
| `scripts/metrics-services.sh` | every 1 min | `systemctl is-active` for all tracked services → up/down counts, 24h state history |
| `scripts/metrics-toolcalls.py` | every 1 min | Tool call counts, error rates, wall-time duration, output size — by tool name; MCP tool calls separately |

**Grafana dashboards** (`grafana/`):

| File | Dashboard title | What it shows |
|---|---|---|
| `grafana/agents-dashboard.json` | Nizam — Agents | Spend today/month, token counts, cache hit rate + savings, latency by model, tool call counts/errors/duration by tool, spend by model/provider/agent, all-time totals, activity heatmap |
| `grafana/services-dashboard.json` | Nizam — Services | Services up/down counts, LiteLLM proxy status, 24h service state timeline, current status table |

**Rebuild steps (post VPS wipe):** `docs/plans/20260701-immediate-fixes.md` — observability setup task.

---

## Knowledge vault

Noor writes to `~/nizam-vault/` on the VPS (git repo). Notes are Markdown files with YAML frontmatter. The vault has three tiers: `personal/` (journal, fleeting, private notes — Ayah writes here), `common/` (MECE knowledge base — Noor writes here), `business/` (future).

**Ingestion workflow (2-pass):**

1. **Pass 1 — fetch and classify.** User shares a source (URL, YouTube, PDF, or image). Noor fetches the content, auto-classifies it using the MECE taxonomy defined in `AGENTS.md` (domain, subdomain, tags, title), and returns a complete draft note for review. No user input required at this stage beyond the source.
2. **Pass 2 — approve, correct, or deny.** User approves the draft → Noor writes to `~/nizam-vault/common/`. User requests changes → Noor revises and shows the updated draft. User denies → nothing is written.

Noor never writes without explicit approval. The MECE taxonomy is defined in `hermes/profiles/curator/AGENTS.md` — Noor uses it to auto-assign every field.

| Source | Status |
|---|---|
| URL / web page | Code exists — non-functional until knowledge schema is set up |
| YouTube (transcript) | Code exists — non-functional until knowledge schema is set up |
| PDF (URL or Discord attachment) | Planned — Curator v1 |
| Image (URL or Discord attachment) | Planned — Curator v1 |
| Audio / podcast | Planned (future) |
| Local video, PPT | Planned (future) |

---

## Current state (foundation)

What's already built and live on the VPS:

| Component | State |
|---|---|
| VPS infra (UFW, fail2ban, Tailscale, SSH) | In repo — deploy via Phase 1 plan |
| PostgreSQL + pgvector + ParadeDB | In repo — knowledge schema not yet run |
| Redis | In repo |
| LiteLLM proxy (port 4000) | In repo — DB tables need Prisma migration on first boot |
| Prometheus + Grafana | In repo — dashboards in `grafana/`, imported manually |
| Metrics timers (LLM, services, tool calls) | In repo |
| nizam-shared library | In repo |
| knowledge-service | In repo — stdio transport, 7 tools — non-functional until schema runs |
| Hermes profiles | admin + curator: profiles written; assistant + cos: stubs. All need Phase 2 fixes. |
| Systemd watcher units | In repo — installed via `scripts/setup/install-symlinks.sh` |
| Secrets management (sops/age) | In repo — age private key must be backed up before VPS wipe |
| Grafana dashboards | In repo — `grafana/agents-dashboard.json`, `grafana/services-dashboard.json` |

Full specification of what's built: `docs/specs/20260701-foundation-design.md`
Rebuild plan (fresh VPS → foundation): `docs/plans/20260701-foundation.md`

## What needs to happen before anything else

Config and profile fixes required before any build phase starts — agents will misbehave without them. Full list with status: `docs/ROADMAP.md` → Immediate fixes section. Step-by-step implementation: `docs/plans/20260701-immediate-fixes.md`.

---

## Build order

**Personal agents before business agents.** Personal (Noor, Nazim, Ayah) allows for mistakes and downtime. Business agents (Raha, Hala, Omar, Reem, Mira) carry compliance and risk implications — build them only after the personal side is stable and the pattern is proven. Both are fully specced now; only the implementation sequence is personal-first.

Full phase-by-phase sequence, status, and spec pointers: `docs/ROADMAP.md`

---

## Hermes profile structure

Each agent lives at `hermes/profiles/<name>/` in the repo (synced to `~/.hermes/profiles/<name>/` on VPS via the profile watcher service).

| File | Purpose | Rules |
|---|---|---|
| `SOUL.md` | Personality, tone, communication style | Personality only. No mandates, tool lists, file paths, or workflow rules. |
| `AGENTS.md` | Mandate, operating rules, pointers | Auto-injected at session start. The agent's authoritative instruction set. |
| `config.yaml` | Hermes config: model, MCP servers, toolsets, Discord settings | `allowed_channels` restricts channels. `disabled_toolsets` removes tools. `skills` lists only needed skills. |
| `user.md` | Pre-seeded user context | Loaded at session start. Contains: user name, timezone, preferences, and any context the agent should know about the person it serves. |
| `.env` (VPS only, not in repo) | `DISCORD_TOKEN`, `DISCORD_GUILD_ID` | Never commit. Two vars only. All other env vars come from `secrets/nizam.env`. |
| `PROTOCOL.md` | Agent-specific escalation/incident protocol | Optional. Referenced from AGENTS.md. |
| `HEARTBEAT.md` | Scheduled check procedure | Nazim-specific. Referenced from AGENTS.md. |

**TOOLS.md is dropped.** Hermes auto-discovers MCP tools. TOOLS.md is not auto-loaded and is dead prompt weight. Delete wherever it exists.

### Skills configuration

Every profile's `config.yaml` starts with all default Hermes skills disabled. Only skills explicitly needed for the agent's mandate are re-enabled. Skill list for each agent is defined in that agent's individual spec under the "Hermes toolsets" section.

Custom skills that agents need (beyond what Hermes ships) are written as standalone skill files following the [agentskills.io open standard](https://agentskills.io). They live in `hermes/skills/` and are referenced by name in each profile's `config.yaml`.

Skills that are never loaded on any profile: Apple, macOS, iOS, Xcode, Homebrew (system is Linux/VPS only).

---

## Drill-down index

### Specs

| Spec | File | Phase |
|---|---|---|
| Foundation (what's built now) | `docs/specs/20260701-foundation-design.md` | 1 (done) |
| Curator v1 (Noor) | `docs/specs/20260701-curator-v1-design.md` | 3 |
| Admin v1 (Nazim) | `docs/specs/20260701-admin-v1-design.md` | 4 |
| Assistant v1 (Ayah) | `docs/specs/20260701-assistant-v1-design.md` | 5 |
| CoS v1 (Raha) | `docs/specs/20260701-cos-v1-design.md` | 6a |
| CFO v1 (Hala) | `docs/specs/20260701-cfo-v1-design.md` | 6b |
| COO v1 (Omar) | `docs/specs/20260701-coo-v1-design.md` | 6c |
| CTO v1 (Reem) | `docs/specs/20260701-cto-v1-design.md` | 6d |
| CMO v1 (Mira) | `docs/specs/20260701-cmo-v1-design.md` | 6e |

### Plans (step-by-step implementation guides)

| Plan | File | Prerequisite |
|---|---|---|
| Foundation rebuild (fresh VPS → current state) | `docs/plans/20260701-foundation.md` | Age private key backup |
| Immediate fixes | `docs/plans/20260701-immediate-fixes.md` | Phase 1 live |
| Curator v1 | `docs/plans/20260701-curator-v1.md` | Phase 2 complete |
| Admin v1 | `docs/plans/20260701-admin-v1.md` | Phase 2 complete |
| Assistant v1 | `docs/plans/20260701-assistant-v1.md` | Phase 2 complete |
| CoS v1 | written at Phase 6a start | Phase 5 live |
| CFO v1 | written at Phase 6b start | Phase 6a live |
| COO v1 | written at Phase 6c start | Phase 6b live |
| CTO v1 | written at Phase 6d start | Phase 6c live |
| CMO v1 | written at Phase 6e start | Phase 6d live |

### Quick-reference docs

`docs/AGENTS.md` — all 8 agents: channels, toolsets, MCP access, key constraints

`docs/SERVICES.md` — port map, all MCP tools, consumer access matrix, DB roles

`docs/SCHEMAS.md` — all DB schemas: tables, columns, FK constraints, role grants

`docs/HERMES.md` — Hermes config.yaml reference: toolsets, MCP config, SOUL/AGENTS.md rules, skills, cron

`docs/SECRETS.md` — all env vars: purpose, consumer, rotation procedure

`docs/INTEGRATIONS.md` — external services: OpenRouter, Discord, YouTube, FX, GitHub, Tailscale

`docs/RUNBOOK.md` — day-to-day ops: service management, secret rotation, adding agents, common fixes

`docs/SECURITY.md` — threat model, VPS hardening, agent controls, prompt injection, audit trail, known gaps

`docs/GLOSSARY.md` — domain terms, Hermes terms, nizam-os patterns

### Master status tracker

`docs/ROADMAP.md`
