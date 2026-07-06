# Roadmap

Build order and exit criteria by phase. No dates — phases are sequenced by dependency, not calendar.

**Principle:** Personal agents before business agents. Within personal, Nazim is critical infrastructure — he maintains all other services. Nail Nazim before Noor and Ayah; failures in Noor and Ayah are recoverable, failures in Nazim take down everyone. Business agents build on lessons from all three personal agents.

---

## Phase 1 — Foundation

**What:** Bare VPS → working infrastructure. No agents yet. The base layer everything else runs on.

**Includes:**
- Ubuntu 24.04 LTS, UFW, fail2ban, SSH hardening, Tailscale
- PostgreSQL + pgvector + ParadeDB
- Redis
- LiteLLM proxy with OpenRouter
- Prometheus + node-exporter
- Loki + Promtail (log aggregation)
- Grafana (Personal dashboard + Business dashboard skeleton)
- age encryption setup; `secrets/nizam-os.env` populated
- `audit` schema migration run

**Exit criteria:** LiteLLM proxy reachable at `localhost:4000`. PostgreSQL running with `nizam` database and `audit.log` table. Grafana loading at `localhost:3000`. 

---

## Phase 2 — Hermes baseline

**What:** Hermes configured correctly across all profiles before any agent goes live.

**Includes:**
- Hermes installed
- Discord server created: categories, channels, one bot application per agent, tokens in place
- `DISCORD_GUILD_ID` and all `DISCORD_TOKEN` vars populated in `nizam-os.env`
- `allow_lazy_installs: false` on all profiles
- Models pinned on all profiles
- `DISCORD_ALLOWED_USERS` set on all profiles
- `discord.allowed_channels` set on all profiles
- LiteLLM Prisma migration run (spend tracking active)
- `/etc/sudoers.d/nazim-nizam` created
- Metrics timers wired up (LLM spend, service health, tool call counts)

**Exit criteria:** Discord server exists with all channels and all bot tokens available. Hermes can connect to Discord. All Hermes profile configs pass the security checklist in [SECURITY](docs/SECURITY.md). Spend tracking recording in LiteLLM DB.

---

## Phase 3 — Nazim (system admin)

**What:** System monitoring and self-healing live.

**Includes:**
- Nazim's Hermes profile active in Discord
- Nazim can restart all defined services via `command_allowlist`
- Incident reporting to Discord verified
- Metrics dashboards showing service health

**Exit criteria:** Nazim detects a service failure, restarts it, and posts an incident report in Discord without owner intervention.

---

## Phase 4 — Noor (knowledge curator)

**What:** Knowledge ingestion and vault search live.

**Includes:**
- `knowledge` schema migration
- `knowledge-service` running as systemd unit
- Vault directory created (`~/nizam-vault/commons/`)
- Noor's Hermes profile active in Discord
- Ingestion from URL, YouTube, PDF, image working
- Approval workflow verified end-to-end

**Exit criteria:** Noor can ingest a URL, present a draft in Discord, and write to vault after owner approval. Search returns results.

---

## Phase 5 — Ayah (personal assistant)

**What:** Personal finance, habits, goals, tasks, journaling, and daily briefings live.

**Includes:**
- `personal` schema migration
- `finance_personal` schema migration
- `personal-service` running as systemd unit
- `finance-service` running as systemd unit
- Ayah's Hermes profile active in Discord
- Morning briefing and evening recap cron verified
- Finance logging, reconciliation, and zakat calculation verified
- Habit logging and goal tracking verified
- Journal entry workflow verified

**Exit criteria:** Ayah delivers a morning briefing. Owner can log a transaction, a habit completion, and a journal entry via Discord. Zakat calculation runs on demand.

---

## Phase 6a — Raha (chief of staff)

**What:** Business coordination layer. Raha orchestrates C-suite agents via kanban — no direct data access.

**Includes:**
- Raha's Hermes profile active in Discord
- Kanban toolset configured
- C-suite delegation workflow verified

**Exit criteria:** Raha creates a kanban task that a C-suite agent picks up and executes.

**Prerequisite:** All personal phases stable.

**Status:** TBP

---

## Phase 6b — Hala (CFO)

**What:** Business finance tracking and reporting.

**Includes:**
- `finance_business` schema migration
- `finance-service` extended with business finance tools and `svc_finance_business` role
- Hala's Hermes profile active

**Exit criteria:** Hala can log a business expense and generate a financial report.

**Prerequisite:** Raha working

**Status:** TBP

---

## Phase 6c — Omar (CRO)

**What:** CRM and pipeline management.

**Includes:**
- `crm` schema migration
- `crm-service` running on port 8104
- Omar's Hermes profile active

**Exit criteria:** Omar can create a contact, log an interaction, and update a pipeline stage.

**Prerequisite:** Raha working

**Status:** TBP

---

## Phase 6d — Reem (CTO)

**What:** Developer tooling, GitHub review, and delegated research.

**Includes:**
- Reem's Hermes profile active
- GitHub MCP configured and pinned to a specific version
- Sandbox delegation workflow verified

**Exit criteria:** Reem reviews a PR, delegates a research task to a sandbox agent, and synthesizes the output in `#cto-office`.

**Prerequisite:** Raha working

**Status:** TBP

---

## Phase 6e — Mira (CMO)

**What:** Marketing analytics and content performance.

**Includes:**
- `analytics` schema migration
- `analytics-service` running on port 8105
- Mira's Hermes profile active

**Exit criteria:** Mira can report on campaign performance and surface content metrics.

**Prerequisite:** Raha working

**Status:** TBP
