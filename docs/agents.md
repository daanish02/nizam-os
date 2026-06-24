# Agents — Nizam-OS

Reference for all Hermes profiles. Full SOUL.md content and skill files live in `hermes/profiles/<name>/`.

---

## Agent Roster

| Profile | Name | Model | Role | Priority |
|---|---|---|---|---|
| `admin` | Bani | Sonnet | System admin — builds/repairs the OS | 1 |
| `assistant` | Alex | Sonnet | Personal life — finances, habits, goals, tasks | 2 |
| `cos` | Raha | Sonnet | Chief of Staff — orchestrates C-suite | 3 |
| `cto` | Arwa | Opus | Technology — architecture, code, dev decisions | 4 |
| `cfo` | Omar | Sonnet | Finance — projections, invoicing, P&L | 5 |
| `coo` | Hala | Sonnet | Operations — client delivery, processes | 6 |
| `cmo` | Mira | Sonnet | Marketing — content, campaigns, social | 7 |

---

## Profile Summaries

### Bani — admin

System administrator for nizam-os itself. Knows the stack top to bottom: systemd units, PostgreSQL schemas, Redis, Prometheus textfile pattern, uv workspace, symlink deployment.

**Responsibilities:**
- Deploy and update services (git pull → systemctl reload)
- Debug failures (journal logs, metrics, health checks)
- Run setup scripts for new steps
- Watch Grafana alerts and self-heal where possible
- Report anything requiring human decision

**Access:** Full system terminal (no Firejail). Direct `sudo` for service management. No MCP services — talks to the system directly.

**Channel:** `#admin`

---

### Alex — assistant

Personal assistant. First and most frequently used. Knows your finances, habits, goals, and tasks. Proactive: surfaces what matters without being asked.

**Responsibilities:**
- Track income, expenses, budgets, funds, zakat
- Log and review habits and streaks
- Manage goals and task lists (personal Kanban)
- Morning brief and weekly review
- Context for personal decisions (trade-offs, not just data)

**Access:** `finance-service` (personal schemas), `personal-service`, `knowledge-service` (read + write w/ approval), business headlines (read-only aggregates).

**Channel:** `#chat`, `#finances`, `#goals-tasks`, `#journal`, `#learning`

---

### Raha — cos

Chief of Staff. Routes business requests to the right C-suite member, synthesises their output, and keeps cross-functional context. Does not do deep domain work herself.

**Responsibilities:**
- Identify which C-suite member(s) a request needs
- Brief them with relevant context before delegating
- Combine their outputs into a coherent response
- Track open items across the business
- Weekly business review synthesis

**Access:** Business headlines, CRM (read), `knowledge-service` (read). Can delegate to any C-suite profile.

**Channel:** `#biz-chat`, `#boardroom`

---

### Arwa — cto

Chief Technology Officer. Architecture decisions, code reviews, technical feasibility, vendor selection. Spawns sandboxed sub-agents (Firejail) for implementation work.

**Responsibilities:**
- Architecture decisions and trade-off analysis
- Code review and technical standards
- Dev sub-agent orchestration (implementation tasks)
- Tech stack decisions and upgrades
- Project cost estimation for CFO

**Access:** `knowledge-service`, business finance read (project costs), CRM read (technical requirements). Sub-agents run under `dev-user` in Firejail.

**Channel:** `#cto`

---

### Omar — cfo

Chief Financial Officer. Source of truth for business finances. Manages projections, monitors P&L, owns invoicing. Zero delegation: all business financial writes require his explicit confirmation.

**Responsibilities:**
- Revenue and expense tracking (business)
- Monthly P&L and rolling forecasts
- Invoice generation and follow-up
- Budget vs actuals
- Cost alerts and spend governance

**Access:** `finance-service` (business schemas, RW), CRM read (for invoicing).

**Channel:** `#cfo`

---

### Hala — coo

Chief Operating Officer. Client delivery, process design, project tracking, team coordination. Owns the CRM as source of truth for client relationships.

**Responsibilities:**
- Client onboarding and delivery tracking
- SOP creation and maintenance
- Business Kanban (project-level)
- Vendor and resource coordination
- Quoting and proposals (with Omar for pricing)

**Access:** `crm-service` (RW), `finance-service` (quoting, read), `knowledge-service` (SOP reads).

**Channel:** `#coo`

---

### Mira — cmo

Chief Marketing Officer. Content strategy, social media, campaigns, lead nurturing. Operates from CRM data and Obsidian vault for content context.

**Responsibilities:**
- Content calendar and publishing
- Social media and LinkedIn strategy
- Case study and portfolio content
- Campaign tracking
- Audience insights

**Access:** `crm-service` (read — case studies, client data), `social-service`, `knowledge-service` (read — commons vault for content).

**Channel:** `#cmo`

---

## Hermes Config Skeleton

Full config lives at `config/hermes.yaml`. Schema: [Hermes docs](https://docs.hermes-agent.nousresearch.com).

```yaml
gateway:
  discord:
    token: ${DISCORD_BOT_TOKEN}
    channel_map:
      "0000000000000001": admin       # #bani
      "0000000000000002": assistant   # #alex
      "0000000000000003": cos         # #raha
      "0000000000000004": cto         # #arwa
      "0000000000000005": cfo         # #omar
      "0000000000000006": coo         # #hala
      "0000000000000007": cmo         # #mira

llm:
  endpoint: http://localhost:4000
  api_key: ${LITELLM_MASTER_KEY}

profiles:
  admin:
    name: Bani
    model: anthropic/claude-sonnet-4-6
    soul: hermes/profiles/admin/SOUL.md
    tools:
      - terminal
      - file
      - web
      - memory

  assistant:
    name: Alex
    model: anthropic/claude-sonnet-4-6
    soul: hermes/profiles/assistant/SOUL.md
    tools:
      - memory
    mcp:
      - finance-service
      - personal-service
      - knowledge-service

  cos:
    name: Raha
    model: anthropic/claude-sonnet-4-6
    soul: hermes/profiles/cos/SOUL.md
    tools:
      - memory
    mcp:
      - analytics-service
    delegates:
      - cto
      - cfo
      - coo
      - cmo

  cto:
    name: Arwa
    model: anthropic/claude-opus-4-8
    soul: hermes/profiles/cto/SOUL.md
    tools:
      - memory
      - web
    mcp:
      - knowledge-service
      - analytics-service
    sub_agents:
      sandbox: firejail
      user: dev-user
      max_concurrent: 2

  cfo:
    name: Omar
    model: anthropic/claude-sonnet-4-6
    soul: hermes/profiles/cfo/SOUL.md
    zero_delegation: true
    tools:
      - memory
    mcp:
      - finance-service
      - analytics-service

  coo:
    name: Hala
    model: anthropic/claude-sonnet-4-6
    soul: hermes/profiles/coo/SOUL.md
    tools:
      - memory
    mcp:
      - crm-service
      - finance-service
      - knowledge-service

  cmo:
    name: Mira
    model: anthropic/claude-sonnet-4-6
    soul: hermes/profiles/cmo/SOUL.md
    tools:
      - memory
    mcp:
      - crm-service
      - social-service
      - knowledge-service
```

---

## Delegation Hierarchy

```
You
├── Bani (admin)     — system tasks, OS maintenance
├── Alex (assistant) — personal requests
└── Raha (cos) — business context needed
      ├── Arwa (cto) — technical domain
      │     └── dev sub-agents (sandboxed, Firejail)
      ├── Omar (cfo) — financial domain, zero delegation
      ├── Hala (coo) — operations domain
      └── Mira (cmo) — marketing domain
```

**Rules:**
- Alex never talks to C-suite directly — Raha is the gateway
- C-suite can talk to each other directly — Raha consolidates
- Max delegation depth: 3 hops (You → Alex → Raha → C-suite)
- Max 4 concurrent sub-agents system-wide

---

## Discord Channels

| Channel | Profile | Purpose |
|---|---|---|
| `#admin` | Bani | System admin, deploy, debug |
| `#chat` | Alex | Personal — daily driver |
| `#biz-chat` | Raha | Business — daily driver |
| `#cto` | Arwa | Tech decisions, code |
| `#cfo` | Omar | Business finances |
| `#coo` | Hala | Ops, clients, delivery |
| `#cmo` | Mira | Marketing, content |
| `#alerts` | System | Grafana + service alerts |
| `#logs` | System | Traces, raw tool output |

---

## Kanban Design

Separate boards per profile. Backed by SQLite (Hermes-managed).

| Board | Columns | Owner |
|---|---|---|
| Personal | Backlog → This Week → Today → Done | Alex |
| Business | Backlog → In Progress → Review → Done | Raha / Hala |
| Tech | Backlog → Sprint → In Review → Shipped | Arwa |

Cards carry: title, description, effort (S/M/L), deadline, profile, MCP service affected.

---

## CoS Mechanics (Raha)

Raha's core loop on each business request:
1. Classify domain(s) — tech / finance / ops / marketing
2. Pull relevant context (CRM status, last meeting notes, open items)
3. Brief the appropriate C-suite member(s) with that context
4. Collect their outputs
5. Synthesise into a single coherent response
6. Update open items Kanban

For multi-domain requests: Raha runs the members in parallel, resolves conflicts herself.

---

## SAVE Framework

SAVE = Skills, Actions, Values, Examples. Lives in each profile's SOUL.md.

| Section | What it contains |
|---|---|
| Skills | Named capabilities with TTL and health score. Git-tracked. Approval-gated to add/remove. |
| Actions | Tool/MCP calls available. Per-tool permission scope documented. |
| Values | Core principles that override instructions (e.g. "never fabricate data"). |
| Examples | 3–5 few-shot samples of good responses for that profile. |

Skill health score drops if a skill is unused for 90 days or produces errors. Below threshold → flagged for review or removal.

---

## Cron Schedule

All crons are systemd timers. Timer files live in `systemd/`.

| Schedule | Profile | Job |
|---|---|---|
| 08:00 daily | Alex | Morning brief (habits, budget, tasks) |
| 08:30 daily | Raha | Business brief (open items, pipeline, alerts) |
| Every Monday 09:00 | Alex | Weekly personal review |
| Every Monday 09:30 | Raha | Weekly business review |
| 1st of month 08:00 | Omar | Monthly P&L and forecast |
| 02:00 daily | System | Backup: pg_dump + SQLite + vault git push |
| Every minute | System | metrics-llm.py collector |
