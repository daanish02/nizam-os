# Nizam-OS Vision

> Captured from user conversation 2026-06-29. This is the intended future state — not current state.

---

## What This Is

Personal agentic OS. Team of AI agents covering personal life, business (Arc Systems), and learning. Single interface: Discord. VPS-hosted. Hermes framework.

---

## Three Domains

### 1. Personal

Agent: **Alex** (Executive Assistant)

Responsibilities:
- **Finance** — personal finances, multicurrency, Islamic compliance
- **Goals** — track long-term goals, progress
- **Projects** — personal projects (non-business)
- **Tasks** — daily/weekly tasks
- **Habits** — habit tracking and streaks
- **Journaling** — structured or freeform entries
- **Learning** — pull from knowledge domain on demand
- **LinkedIn** — personal brand (to clarify: posting? drafting?)
- **Personal website** — (to clarify: updates? content?)

### 2. Business — Arc Systems (arcsystems.tech)

Services delivered: ML/AI/data analytics, dashboards, model building, RAG pipelines, chatbots, AI agents, consulting.

Agents:

| Role | Codename | Responsibilities |
|------|----------|-----------------|
| Chief of Staff | **Raha** | Cross-domain coordination, owner briefings, ops oversight |
| CFO | **Omar** | Business finances, invoicing, payroll, audit-ready records |
| CTO | **Arwa** | Tech delivery, code review, architecture, client tech proposals |
| CMO | **Mira** | Marketing, content, LinkedIn (business), social presence |
| COO | **Hala** | Operations, client onboarding, comms, project delivery |

You = Chairman & CEO. Agents advise, you decide on cross-domain matters.

### 3. Commons — Knowledge & Learning

Agent: **Noor** (Curator) — passive, read-mostly

- Obsidian vault: flat structure, kebab-case filenames, YAML frontmatter (tags + links), Karpathy-style atomic notes
- Sources: books, articles, YouTube/video, research papers, fleeting notes, web
- Vault walker: on-demand AI that traverses vault, connects ideas, reasons across notes, returns findings/insights
- Access model: agents pull from Commons when needed; only Alex can write new notes, with your approval

---

## Finance System (Critical — Audit-Grade)

### Currencies
- **Active**: INR, AED, USD
- **Future**: SAR (design must accommodate without schema changes)
- Every transaction stored as: amount_original, currency_original, amount_base, currency_base (USD), fx_rate, fx_date

### Requirements
- **Multicurrency**: INR, AED, USD (SAR future-ready)
- **Two-level categories**: e.g. `Expenses > Travel > Flights`, `Income > Services > Consulting`
- **Double-entry bookkeeping** — audit-grade
- **Audit trail**: every write logged with timestamp, actor, before/after state. Immutable append-only log
- **Separation**: personal vs business in separate schemas from day 1. Physical separation possible later without refactor

### Islamic Compliance

**Zakat:**
- Nisab = 85g gold equivalent (gold price fetched at calculation time)
- Hawl = 1 lunar Hijri year
- Zakatable base = all assets (savings, gold, silver, business receivables, inventory) MINUS liabilities and expenses
- Agent calculates obligation at hawl completion, presents report
- Rate: 2.5% of net zakatable wealth above nisab

**Riba:**
- Track all riba-based income (interest received) and riba-based expense (interest paid)
- Stored in separate riba ledger — NOT counted in P&L or net worth
- Personal: riba income means nothing spiritually, tracked only for awareness/removal
- Business: tracked strictly for compliance; never counted as usable income; flagged in all reports
- Agent flags every riba transaction at entry, cannot be miscategorized as normal income

### Invoicing (Arc Systems)
- Generate professional PDF invoices
- Track payment status (draft → sent → partially paid → paid → overdue)
- Auto-remind clients at configurable intervals
- Multi-currency invoice support
- Link invoice → payment transaction in ledger

### What "audit-ready" means
- Every transaction: date, amount, currency, FX rate, counterparty, L1+L2 category, description, receipt reference
- Reconciliation reports on demand
- No LLM writes financial records directly — LLM parses/suggests, code commits
- Full transaction history never deleted, only reversed with contra-entry

---

## Agent Design Principles

### Minimal toolsets / minimal blast radius
- Each agent gets only tools it needs for its role
- Read-only tools default; write tools explicitly granted
- No agent has cross-domain write access without explicit bridge
- If agent goes rogue: damage bounded to its tool scope

### LLM does LLM things, code does code things
- Financial calculations: Python, not LLM
- Data transforms, aggregations, report generation: code
- NLP tasks: parsing natural language inputs, drafting, reasoning — LLM
- Rule: if it can be deterministic, make it deterministic

### Logging — everything
- Every tool call: logged (agent, tool, args, result, timestamp)
- Every write operation: before/after state logged
- Every skill update: logged + human review required
- Finance writes: immutable audit log separate from main DB
- System: structured JSON logs, queryable

### Skill self-update oversight
- Hermes can update its own skills (Curator feature)
- Risk: unchecked updates could change agent behavior silently
- Requirement: all skill updates logged, diff captured, flagged for human review before activation OR quarantined until reviewed

### Personal / Business separation
- Day 1: separate Hermes profiles + separate DB schemas
- Future: can move to separate VPS with zero refactor needed
- No agent crosses domain boundaries by default

---

## System Health Agent

Separate agent or automated check (not full LLM — mostly code):
- Monitor all services: Hermes gateway, MCP servers, DB, cron jobs
- Check: process alive, response time, error rates, disk space, memory
- Auto-fix: safe restarts only (no data deletion, no config changes)
- Alert: Discord notification on failures
- Cannot destroy: read-only access to system state, write access only to restart specific safe services

---

## Hermes Meta-Agent

Agent that knows Hermes deeply:
- Answers questions about Hermes capabilities, configs, skills
- Helps debug Hermes issues (gateway, profile, MCP, skill errors)
- Suggests improvements to the Nizam-OS setup
- Reads Hermes logs, skill files, config — does NOT modify without your explicit instruction

---

## Interface — Discord

Single interface for all agents. No other UI except Discord (+ Obsidian for vault visualization).

Channel structure (rough):
- `#alex` — personal assistant
- `#omar` — business finance
- `#arwa` — tech
- `#mira` — marketing
- `#hala` — ops/clients
- `#raha` — chief of staff (CoS)
- `#noor` — knowledge/vault
- `#system` — health alerts
- `#audit-log` — finance audit trail (read-only channel)

---

## What Must Be Coded (Not LLM)

| Component | Why code |
|-----------|----------|
| Finance transaction entry & validation | Audit-grade accuracy |
| Currency conversion at transaction time | Deterministic, no hallucination risk |
| Zakat nisab calculator | Gold price lookup + fixed formula |
| Riba flag rules | Rule-based pattern matching |
| Habit streak counter | Simple stateful counter |
| Obsidian note writer | File I/O, frontmatter formatting |
| System health checks | Uptime monitoring |
| Skill update diff capture | Git-style diff of skill files |
| Audit log writer | Append-only, tamper-evident |

---

## Open Questions (to clarify with user)

1. **Currencies** — INR, AED, USD active; SAR future ✓
2. **Zakat scope** — gold + silver + cash savings + business assets? Or gold-only for nisab threshold?
3. **Riba** — flag-and-report only? Or also suggest halal alternatives?
4. **Journaling format** — voice, typed, or both? Daily prompts or freeform?
5. **LinkedIn/Website** — Alex drafts posts for approval, or also publishes?
6. **Client comms channel** — email only, or WhatsApp/Slack too?
7. **Obsidian vault location** — local only, or synced to VPS?
8. **Vault-walker AI** — one-shot on demand, or periodic scheduled run?
9. **Vault-walker output** — Discord message, markdown file, or both?
10. **Personal website** — static (Hugo/Astro) or dynamic? What does agent manage?
11. **Skill update review** — who reviews? Manual Discord approval flow?
12. **System fix permissions** — restart which services? Only Hermes? Also Postgres?
13. **Invoice management** — Arc Systems invoices: generate PDF, track payment, send to client?
14. **CRM** — existing tool (HubSpot, Notion) or build lightweight custom?
