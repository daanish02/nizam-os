# Roadmap

Build order and exit criteria by phase. No dates — phases are sequenced by dependency, not calendar.

**Principle:** Personal agents before business agents. Within personal, admin is critical infrastructure — he maintains all other services. Nail admin before curator and assistant; failures in curator and assistant are recoverable, failures in admin take down everyone. Business agents build on lessons from all previous agents.

**Convention:** Each phase ships one idempotent orchestrator script (`scripts/setup/00N-<phase-name>.sh`) that can be re-run safely to reach or verify that phase's exit criteria. The script is the canonical way to set up or recover that phase.

---

## Phase 1 — Foundation

**What:** Bare VPS → working infrastructure. No agents yet. The base layer everything else runs on.

**Includes:**
- Ubuntu 24.04 LTS, UFW, fail2ban, SSH hardening, Tailscale
- PostgreSQL + pgvector + ParadeDB
- Redis
- LiteLLM proxy with OpenRouter
- Prometheus + node-exporter
- Loki + Promtail
- Grafana (Personal dashboard skeleton)
- age encryption setup; `secrets/nizam-os.env` populated
- `audit` schema migration run
- `scripts/setup/001-foundation.sh` — idempotent orchestrator for this phase

**Exit criteria:** LiteLLM proxy reachable at `localhost:4000`. PostgreSQL running with `nizam` database and `audit.log` table. Loki reachable at `localhost:3100`. Grafana loading at `localhost:3000`.

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
- `/etc/sudoers.d/admin-nizam` created
- Metrics timers wired up
- `scripts/setup/002-hermes.sh` — idempotent orchestrator for this phase

**Exit criteria:** Discord server exists with all channels and all bot tokens available. Hermes can connect to Discord. All Hermes profile configs pass the security checklist in [SECURITY](docs/SECURITY.md). Spend tracking recording in LiteLLM DB.

---

## Phase 3 — Nazim (system admin)

**What:** System monitoring, self-healing, and system knowledge base live.

**Includes:**
- Admin's Hermes profile active in Discord
- Admin can restart all defined services via `command_allowlist`
- Incident reporting to Discord verified
- Metrics dashboards showing service health
- Read access to `nizam-os/docs/` and `nizam-dotfiles/docs/` — admin can answer questions about system design, agent roster, specs, plans, and guides
- Read access to Hermes documentation — admin can answer questions about Hermes framework behavior, profile config options, and skill configuration

**Exit criteria:** Admin detects a service failure, restarts it, and posts an incident report in Discord without owner intervention. Owner can ask admin a question about the system or Hermes framework and receive an accurate answer.

---

## Phase 4 — Noor (knowledge curator)

**What:** Knowledge ingestion and vault search live.

**Includes:**
- `knowledge` schema migration
- `knowledge-service` running as systemd unit
- Vault directory created (`~/nizam-vault/commons/`)
- Curator's Hermes profile active in Discord
- Ingestion from URL, YouTube, PDF, image working
- Approval workflow verified end-to-end

**Exit criteria:** Curator can ingest content, present a draft in Discord, and write to vault after owner approval. Search returns results.

---

## Phase 5 — Ayah (personal assistant)

**What:** Personal finance, habits, goals, tasks, journaling, and daily briefings live.

**Includes:**
- `personal` schema migration
- `finance_personal` schema migration
- `personal-service` running as systemd unit
- `finance-service` running as systemd unit
- Assistant's Hermes profile active in Discord
- Morning briefing and evening recap cron verified
- Finance logging, reconciliation, and zakat calculation verified
- Habit logging and goal tracking verified
- Journal entry workflow verified

**Exit criteria:** Assistant delivers a morning briefing. Owner can log a transaction, a habit completion, and a journal entry via Discord. Zakat calculation runs on demand.

---

## Phase 6 — Hakim (researcher)

**What:** Shared research capability across all domains.

**Includes:**
- Researcher's Hermes profile active in Discord (`#research` channel)
- File toolset enabled — research output written to temp files before vault
- `knowledge-service` write access for curated research findings
- Chief of staff's kanban wired to accept research task delegation from business agents

**Exit criteria:** Researcher completes a multi-source research task, writes output to file, stores curated findings to vault. A business agent delegates a research request via cos and receives results.

**Prerequisite:** All personal phases stable. Working cos.

**Status:** TBP

---

## Phase 7 — Rashid (investor)

**What:** Investment due diligence with Shariah compliance screening. Replaces manual IBKR + report workflow.

**Includes:**
- `investment-service` running on port 8104 — IBKR Client Portal API wrapper (read-only)
- Investor's Hermes profile active in Discord (`#investment` channel)
- Researcher integration — investor delegates report reading and research, owns compliance and analysis
- Screening results and due diligence notes written to vault via `knowledge-service`

**No schema migration** — IBKR is the source of truth for portfolio and watchlist data. Vault stores qualitative output.

**Exit criteria:** Investor reads the IBKR watchlist, delegates annual report analysis to researcher, screens a company for Shariah compliance (industry filter + debt ratio + interest income ratio + receivables ratio), calculates purification obligation, computes real return vs inflation, and presents a structured investment decision to the owner.

**Prerequisite:** Researcher working.

**Future scope:** Order placement with approval gate, portfolio rebalancing, portfolio manager expansion.

**Status:** TBP

---

## Phase 8 — Raha (chief of staff)

**What:** Business coordination layer. Raha orchestrates C-suite agents via kanban — no direct data access.

**Includes:**
- Chief of staff's Hermes profile active in Discord
- Kanban toolset configured
- C-suite delegation workflow verified
- Grafana (Business dashboard skeleton)

**Exit criteria:** Chief of staff creates a kanban task that a C-suite agent picks up and executes.

**Prerequisite:** All previous phases tested and stable.

**Status:** TBP

---

## Phase 9 — Hala (CFO)

**What:** Business finance tracking and reporting.

**Includes:**
- `finance_business` schema migration
- `finance-service` extended with business finance tools and `svc_finance_business` role
- CFO's Hermes profile active

**Exit criteria:** CFO can log a business expense and generate financial reports.

**Prerequisite:** CoS working

**Status:** TBP

---

## Phase 10 — Reem (CTO)

**What:** Developer tooling, GitHub review, and delegated research.

**Includes:**
- CTO's Hermes profile active
- GitHub MCP configured and pinned to a specific version
- Sandbox delegation workflow verified

**Exit criteria:** CTO reviews a PR, delegates a research task to a sandbox agent, and synthesizes the output in `#cto-office`.

**Prerequisite:** CoS working

**Status:** TBP

---

## Phase 11 — Mira (CMO)

**What:** Marketing analytics and content performance.

**Includes:**
- `analytics` schema migration
- `analytics-service` running on port 8106
- Mira's Hermes profile active

**Exit criteria:** Mira can report on campaign performance and surface content metrics.

**Prerequisite:** CoS working

**Status:** TBP

---

## Phase 12 — Omar (COO)

**What:** CRM and pipeline management.

**Includes:**
- `crm` schema migration
- `crm-service` running on port 8105
- COO's Hermes profile active

**Exit criteria:** COO can create a contact, log an interaction, and update a pipeline stage.

**Prerequisite:** CoS working

**Status:** TBP
