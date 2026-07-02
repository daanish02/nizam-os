# Nizam-OS — master roadmap

**Last updated:** 2026-07-01

One-page status of everything. States: **In repo** (code + plan written, not yet deployed), **Specced** (design approved, not built), **Planned** (known need, not yet specced), **Pending** (awaiting prior phase).

---

## Infrastructure

Full infrastructure spec and rebuild plan: `docs/specs/20260701-foundation-design.md` + `docs/plans/20260701-foundation.md`

| Component | Status | Notes |
|---|---|---|
| VPS baseline (UFW, fail2ban, unattended-upgrades, Tailscale, SSH hardening) | **In repo** | All config documented in foundation spec |
| PostgreSQL + pgvector + ParadeDB | **In repo** | knowledge schema not yet run (Task 9 of foundation plan) |
| Redis | **In repo** | Exact-match cache for LiteLLM; price cache for metrics-llm.py |
| LiteLLM proxy | **In repo** | DB tables need Prisma migration on first boot with DATABASE_URL set |
| Prometheus + node-exporter | **In repo** | Textfile dir `/var/lib/prometheus/node-exporter/` needs creation |
| Grafana + dashboards | **In repo** | Dashboards must be imported manually after install |
| Hermes profile watcher | **In repo** | User service — enable after install-symlinks.sh |
| Env watcher | **In repo** | System service — enabled by install-symlinks.sh |
| Metrics timers (LLM, services, tool calls) | **In repo** | System timers — enabled by install-symlinks.sh |
| Inventory watcher | **In repo** | Timer — enabled by install-symlinks.sh |
| Secrets (sops/age) | **In repo** | nizam.env.enc committed; age private key must be backed up before wipe |
| System health monitor | **Specced** | `docs/specs/20260701-admin-v1-design.md` |
| `~/nizam-vault/` | **Pending** | Created in Task 9 of foundation plan |

---

## Agents

| Agent | Profile | Status | Notes |
|---|---|---|---|
| Nazim | `admin` | **In repo** — profile needs rename Bani→Nazim (Phase 2) | Health check manual; cron not wired |
| Noor | `curator` | **In repo** — tools non-functional until knowledge schema runs (Phase 1 Task 9) | PDF + image ingestion not built yet |
| Ayah | `assistant` | **In repo** — stub profile, gateway not enabled | SOUL.md is default placeholder |
| Raha | `cos` | **In repo** — stub profile, gateway not enabled | SOUL.md is default placeholder |
| Hala | `cfo` | Not built | — |
| Omar | `coo` | Not built | — |
| Reem | `cto` | Not built | — |
| Mira | `cmo` | Not built | — |

---

## Specs

Personal specs: `docs/ARCHITECTURE.md` → Drill-down index → Specs.
Business specs: `docs/future/ARCHITECTURE.md` → Drill-down index.

---

## Services

Port map and tool specs: `docs/SERVICES.md`. Status per service is in the Build order table below.

---

## Database migrations

Migration index, schema status, and DB roles: `docs/SCHEMAS.md` → Migration index.

---

## Knowledge ingestion (Noor)

| Source type | Status |
|---|---|
| YouTube transcript | **In repo** |
| URL / web page | **In repo** |
| PDF (URL or Discord attachment) | **Specced** |
| Image (URL or Discord attachment) | **Specced** |
| Audio / podcast | Planned |
| PPT / slides | Planned |
| RSS feeds / newsletters | Planned |

---

## Immediate fixes needed (before any new implementation)

Correctness issues in existing config and profile files — not new features. Must be resolved before Phase 3 (Curator v1).

Implementation steps: `docs/plans/20260701-immediate-fixes.md`

| Fix | Profile / location | Status |
|---|---|---|
| Rename Bani → Nazim | `admin` profile | Pending |
| Fix admin SOUL.md + write AGENTS.md | `admin` profile | Pending |
| Write Ayah SOUL.md + AGENTS.md | `assistant` profile | Pending |
| Write Raha SOUL.md + AGENTS.md | `cos` profile | Pending |
| Fix curator SOUL.md + write AGENTS.md | `curator` profile | Pending |
| Write `user.md` per profile | all profiles | Pending |
| Pre-seed memory per profile | all profiles (VPS) | Pending |
| Set `DISCORD_ALLOWED_USERS` | all profiles `.env` | Pending |
| Set `discord.allowed_channels` | all profiles `config.yaml` | Pending |
| `allow_lazy_installs: false` | all profiles `config.yaml` | Pending |
| Pin compression model | all profiles `config.yaml` | Pending |
| Disable default skills | all profiles `config.yaml` | Pending |
| Delete TOOLS.md | `admin`, `curator` | Pending |
| Add Nazim sudoers entry | VPS `/etc/sudoers.d/` | Pending |
| Create `~/nizam-vault/` | VPS | Pending |
| Initialise LiteLLM DB tables | VPS | Pending |
| Redesign knowledge schema | `db/migrations/0001_knowledge_schema.sql` | Pending |
| Set up observability (post-wipe) | VPS — Prometheus, Grafana, metric timers | Pending |

---

## Build order

Personal agents first — they tolerate mistakes. Business agents follow only after personal side is stable. See `docs/ARCHITECTURE.md` for the design rationale.

| Phase | What | Spec | Plan | Status |
|---|---|---|---|---|
| 1 | Foundation — VPS, infra, knowledge-service, admin + curator profiles | `20260701-foundation-design.md` | `20260701-foundation.md` | **In repo** |
| 2 | Immediate fixes — profile cleanup, AGENTS.md, security settings | — | `20260701-immediate-fixes.md` | Pending |
| 3 | Curator v1 — Noor: PDF + image, HTTP MCP, unified ingest | `20260701-curator-v1-design.md` | `20260701-curator-v1.md` | Pending |
| 4 | Admin v1 — Nazim: health monitor + cron | `20260701-admin-v1-design.md` | `20260701-admin-v1.md` | Pending |
| 5 | Assistant v1 — Ayah: personal + finance services | `20260701-assistant-v1-design.md` | `20260701-assistant-v1.md` | Pending |
| 6a | CoS v1 — Raha: delegation, weekly review | `docs/future/specs/20260701-cos-v1-design.md` | TBD | Pending |
| 6b | CFO v1 — Hala: business finance | `docs/future/specs/20260701-cfo-v1-design.md` | TBD | Pending |
| 6c | COO v1 — Omar: CRM, operations | `docs/future/specs/20260701-coo-v1-design.md` | TBD | Pending |
| 6d | CTO v1 — Reem: GitHub MCP | `docs/future/specs/20260701-cto-v1-design.md` | TBD | Pending |
| 6e | CMO v1 — Mira: content, CRM read | `docs/future/specs/20260701-cmo-v1-design.md` | TBD | Pending |

---

## What is NOT being built (by design)

| Item | Reason |
|---|---|
| True tamper-proof audit log | PostgreSQL append-only is good enough for internal use; court-grade needs WORM storage |
| Real-time gold price tracking | API rate limits; zakat calc at hawl time is sufficient |
| Obsidian local sync | Not needed until vault is mature; Syncthing setup is a separate future spec |
| WhatsApp for client comms | Configured when Omar (COO) is built |
| Voice journaling | Phase 2 — Ayah must be functional first |
| Firejail sandboxing for Reem | Planned — spec when Reem is being built |
