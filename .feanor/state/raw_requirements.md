# Raw Requirements
## nizam-os — /document run — 2026-09-03

---

## Problem / Why

- **Status:** Covered
- **Source:** VISION.md (verified against codebase structure)
- **Content:** Owner's cognitive overhead from tracking, logging, monitoring, and organizing personal and business operations is offloaded to a team of autonomous agents. Attention stays on decisions and creative work. Agents handle everything that doesn't require judgment. Not task automation — overhead elimination.

---

## Users / Personas

- **Status:** Covered
- **Source:** VISION.md (verified — single-user system confirmed by `DISCORD_ALLOWED_USERS` scoped to one ID in all profiles)
- **Content:** One person: the owner (Danish Ahmed). Technical owner — full vocabulary, direct constraint questions apply. Not a multi-tenant system. No other users, no external access surface.

---

## Core Workflows

- **Status:** Partial
- **Source:** VISION.md, ROADMAP.md, SERVICES.md (derived-from-code)
- **Content:** Derived workflows:
  1. **Knowledge ingestion** — owner drops URL/YouTube link in Discord → curator fetches, classifies, presents draft → owner approves → vault write. (Two-pass: draft → approval → write.)
  2. **Morning briefing** — cron triggers assistant → briefs total balance, month-to-date spend, upcoming tasks, a quote.
  3. **Evening recap** — cron triggers assistant → summarizes spend, balance, tasks, opens journal thread.
  4. **System monitoring** — admin watches services → detects failure → attempts restart → posts incident report to Discord.
  5. **Finance logging** — owner speaks to assistant → transaction logged, balance updated.
  6. **Research** — business agent delegates to researcher via cos kanban → researcher gathers + synthesizes → output to vault.
  7. **Investment screening** — investor reads IBKR watchlist → delegates annual report analysis to researcher → screens for Shariah compliance → synthesizes decision.
- **Missing:** Concrete daily interaction sequences from owner's POV. Agent escalation paths when a task is ambiguous. What "done" looks like per workflow from owner's perspective.

---

## Scope Boundaries

- **Status:** Covered
- **Source:** VISION.md (verified — agent configs confirm domain isolation)
- **Content:**
  - In scope: 10-agent personal + business AI OS for one person. Discord as sole interaction surface. VPS infrastructure entirely self-hosted.
  - Explicitly out of scope: Multi-tenant / SaaS distribution. General-purpose assistant behavior. Agents acting outside their defined domain. Order placement to IBKR (current scope: read + advise only). Direct external API access by agents (all inference through LiteLLM).

---

## Non-Functional Constraints

- **Status:** Partial
- **Source:** ARCHITECTURE.md (verified — confirmed against systemd unit files and codebase)
- **Content (confirmed):**
  - All services bind to `127.0.0.1` only. No public exposure except SSH.
  - Single VPS: Hostinger KVM2, 8 GB RAM, 100 GB SSD, Ubuntu 24.04 LTS.
  - Approval gate on all mutating actions — no autonomous writes.
  - Staggered scheduling — no two heavy processes start simultaneously.
  - `allow_lazy_installs: false` on all profiles.
  - `redact_secrets: true` on all profiles.
  - Uniform JSON logging format (`ts`, `level`, `service`, `module`, `func`, `msg`).
  - Idempotent phase scripts — each phase has an `00N-*.sh` orchestrator.
- **Missing:** Explicit latency targets (e.g. search response SLA). Uptime target. Behavior/fallback when LiteLLM proxy is down. Acceptable agent response time range.

---

## Integrations / External Dependencies

- **Status:** Covered
- **Source:** ARCHITECTURE.md, SERVICES.md (verified against env vars in code and config files)
- **Content:**
  - Discord — sole interaction surface for all agents. Per-agent bot tokens.
  - PostgreSQL + pgvector + ParadeDB — primary DB. Per-service roles with scoped grants.
  - Redis — LiteLLM exact-match cache.
  - LiteLLM proxy (localhost:4000) — routes all inference to OpenRouter. Spend tracking, caching, token counting.
  - OpenRouter — model provider. All inference routes through here; no agent connects directly to any model API.
  - Langfuse — LLM observability. On-demand only, disabled in normal operation.
  - Prometheus + node-exporter — metrics. Custom `.prom` textfiles for LLM spend and service health.
  - Loki + Promtail — log aggregation. Promtail tails `logs/*.log`.
  - Grafana — dashboards over Prometheus, Loki, PostgreSQL.
  - Tailscale — VPS management VPN. Not used by agents.
  - IBKR Client Portal API — investor agent, read-only.
  - Supadata API — YouTube transcript fallback (confirmed via env var in code).
  - yt-dlp — local YouTube transcript extraction (confirmed in transcript.py).

---

## Budget / Timeline

- **Status:** Partial
- **Source:** ARCHITECTURE.md (VPS cost), ROADMAP.md ("no dates")
- **Content (confirmed):** VPS: 107.89 USD/year (expires 10 Jun 2027). Roadmap is dependency-sequenced, not calendar-dated.
- **Missing:** OpenRouter monthly spend budget/limit. Total monthly infrastructure cost target. Whether any phase has a soft deadline.

---

## Success Metrics

- **Status:** Partial
- **Source:** VISION.md (qualitative descriptions only)
- **Content (derived):** Vision describes success qualitatively: knowledge captured without friction, system self-heals overnight, morning briefings run, habits/finances tracked without opening an app.
- **Missing:** Measurable primary metric. What does "working" mean numerically? (e.g. briefing delivered by X time, vault has Y notes per week, system uptime Z%).

---

## Failure Modes / Edge Cases

- **Status:** Missing
- **Source:** N/A — no documentation exists
- **Content:** Not documented anywhere in code or docs. Key risks visible from code: LiteLLM proxy down → all agents lose inference (unhandled in knowledge-service). Discord API down → all interaction surface gone. Agent hallucinates classification → wrong vault taxonomy. Embedder crash → vault unsearchable. DB full → writes fail silently.

---

## Competitive / Market Context

- **Status:** N/A
- **N/A reason:** Personal infrastructure for one owner. Not market-facing. No competitors relevant to PRD scope.
