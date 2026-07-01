# Assistant v1 — design spec

**Status:** approved, pending implementation
**Date:** 2026-07-01
**Scope:** Make Ayah functional as a personal assistant — personal finance (multicurrency, zakat, riba), habits, goals, tasks, and journaling. Two new MCP services and a proper agent profile.

---

## Problem

The `assistant` profile exists but has only the default Hermes SOUL.md placeholder. No MCP services are wired. No database schemas exist for personal data. Ayah cannot do anything useful today.

---

## What this spec covers

| Area | Change |
|---|---|
| `hermes/profiles/assistant/SOUL.md` | Rewrite: Ayah's personality and tone ONLY |
| `hermes/profiles/assistant/AGENTS.md` | New: mandate, finance rules, habit/goal/journal rules, channel context |
| `hermes/profiles/assistant/config.yaml` | Wire finance-service and personal-service MCPs (HTTP), set channels |
| `services/finance-service/` | New service: personal finance ledger |
| `services/personal-service/` | New service: habits, goals, tasks, journal |
| `systemd/finance-service.service` | New: HTTP MCP service on port 8101 |
| `systemd/personal-service.service` | New: HTTP MCP service on port 8102 |
| `db/migrations/0002_personal_schema.sql` | New: all personal + finance schemas |
| `db/migrations/0003_audit_schema.sql` | New: shared audit log schema |
| `secrets/nizam.env.example` | Add: `POSTGRES_SVC_FINANCE_PERSONAL_PASS`, `POSTGRES_SVC_PERSONAL_PASS`, `FX_API_KEY`, `GOLD_API_KEY` |

> **TOOLS.md dropped.** MCP auto-discovers all tools at startup. Not needed.
>
> **DB role rename:** `svc_finance` → `svc_finance_personal` throughout (aligns with business spec isolation requirement).

## Out of scope (future specs)

- Business finance schema (separate service, separate migration — shares finance-service binary)
- CRM, invoicing
- Morning brief cron job (needs personal-service live first, wire after)
- Business read access for Ayah (revenue headlines) — Phase 2
- Voice journaling

---

## Database schemas

All personal data lives in PostgreSQL. Two new schemas created in migration `0002`. A third migration `0003` creates the shared audit log.

### `personal` schema — life management

```sql
-- Habits
personal.habits        (id, name, description, frequency, active, created_at)
personal.habit_logs    (id, habit_id, logged_date, note, created_at)

-- Goals
personal.goals         (id, title, description, target_date, status, created_at)
personal.milestones    (id, goal_id, title, due_date, completed_at)

-- Tasks
personal.tasks         (id, title, description, due_date, priority, status, goal_id nullable, created_at)

-- Journal
personal.journal       (id, entry_date, prompt, content, tags, created_at)
```

### `finance` schema — personal ledger

```sql
-- Accounts (cash, bank, savings — personal only)
finance.accounts       (id, name, type, currency, is_active)

-- Categories (two-level: L1 > L2)
finance.categories     (id, name, parent_id nullable, domain)

-- Transactions (every entry — income or expense)
finance.transactions   (
    id, account_id, category_id,
    amount_original, currency_original,
    amount_base, currency_base,   -- USD
    fx_rate, fx_date,
    direction,                     -- 'in' | 'out'
    counterparty, description,
    transaction_date, receipt_ref,
    is_riba,                       -- boolean, default false
    created_at
)

-- FX rate cache
finance.fx_rates       (date, from_currency, to_currency, rate, source, fetched_at)

-- Budgets
finance.budgets        (id, category_id, period, amount, currency, starts_at)

-- Zakat tracking
finance.zakat_hawl     (id, start_date, end_date, nisab_gold_grams, gold_price_usd,
                        nisab_usd, zakatable_base_usd, obligation_usd, status,
                        calculated_at)
finance.zakat_assets   (id, hawl_id, asset_type, amount_usd, description)

-- Riba ledger (separate — never counted in P&L or net worth)
finance.riba_log       (id, transaction_id, amount_original, currency_original,
                        amount_usd, riba_type, description, logged_at)
```

### `audit` schema — shared, append-only

```sql
audit.log (
    id, schema_name, table_name, operation,
    actor,          -- agent profile name
    row_id,
    before_state,   -- JSONB
    after_state,    -- JSONB
    created_at
)
```

No `DELETE` or `UPDATE` granted to any service user on `audit.log`. Insert-only.

### DB users

| Service | Role | Access |
|---|---|---|
| `finance-service` | `svc_finance_personal` | RW on `finance`, RO on `personal` (budget context), INSERT on `audit` |
| `personal-service` | `svc_personal` | RW on `personal`, INSERT on `audit` |

---

## `finance-service` — design

New service at `services/finance-service/`. FastMCP stdio server, same pattern as knowledge-service.

### MCP tools

| Tool | What it does |
|---|---|
| `record_transaction` | Parse NL input → structured transaction → approval gate → commit |
| `spending_report` | Totals by category for a period, in original + USD |
| `budget_status` | Current spend vs budget per category |
| `account_balance` | Balance per account, all currencies |
| `reconcile_statement` | Upload bank statement → diff against recorded transactions |
| `add_category` | Add L1 or L2 category |
| `zakat_status` | Current hawl state, assets on record, estimated obligation |
| `calculate_zakat` | Full zakat calc at hawl end — fetches gold price, computes obligation |
| `log_riba` | Record riba income/expense to riba_log, flag on transaction |
| `riba_report` | All riba entries for a period |

### Natural language entry flow

```
User: "spent 500 AED on groceries today"

Ayah → LLM parses → structured:
  {amount: 500, currency: AED, direction: out,
   category: "Expenses > Food > Groceries", date: today}

→ fetch USD FX rate for AED/USD at today's date
→ record_transaction(approved=False) → show draft to user
→ user confirms → record_transaction(approved=True) → commit
→ audit.log entry written
```

LLM parses, code commits. Ayah never writes to the DB without user confirmation.

### Bank statement reconciliation flow

```
User: uploads PDF or CSV to #finances (monthly)

Ayah → reconcile_statement(source=<discord CDN URL>, period="2026-06")
     → finance-service downloads statement
     → PDF: pymupdf text extraction
     → CSV: direct parse
     → extract transactions: date, amount, description
     → compare against finance.transactions for the period
     → return:
         matched:    N transactions reconciled
         unmatched:  transactions in bank not in ledger (list)
         ledger_only: transactions in ledger not in bank (list)
         interest:   riba candidate lines (interest payments / receipts)

Ayah presents diff → user approves what to add → record_transaction per item
Riba candidates flagged explicitly: "Interest received: $12.50 — log to riba ledger?"
```

### FX rates

Fetched at transaction time from a free-tier API. Key: `FX_API_KEY`.

Candidate: `api.exchangerate-api.com` (free tier: 1500 calls/month — sufficient for daily use).

Cached in `finance.fx_rates` by date — same-day rate reused, no duplicate API calls.

If API is unavailable: Ayah asks user to supply the rate manually. Never blocks the transaction.

### Zakat

Gold price from `metals-api.com` or `goldpricez.com` (free tier). Key: `GOLD_API_KEY`.

Fetched only at hawl calculation time, not continuously. Cached in `finance.zakat_hawl`.

Hijri year calculation: use `hijridate` Python library for hawl boundary dates.

---

## `personal-service` — design

New service at `services/personal-service/`. FastMCP stdio server.

### MCP tools

| Tool | What it does |
|---|---|
| `log_habit` | Record habit completion for today |
| `habit_streak` | Current streak and recent log for a habit |
| `habit_summary` | All habits, streaks, last 7 days |
| `add_habit` | Define a new habit |
| `add_goal` | Create a goal with target date |
| `add_milestone` | Add milestone to a goal |
| `update_goal` | Change status, add progress note |
| `goal_summary` | All active goals with milestone status |
| `add_task` | Create a task, optionally linked to a goal |
| `complete_task` | Mark task done |
| `task_list` | Open tasks, optionally filtered by due date or goal |
| `add_journal` | Write a journal entry (approval-gated) |
| `journal_search` | Full-text search across journal entries |
| `journal_entry` | Read a specific entry |

Habit streaks computed in Python (not LLM). A streak breaks if `logged_date` has a gap > 1 day.

---

## Ayah profile — design

### SOUL.md

**Personality and tone only.** No file paths, tool names, or workflow rules.

```markdown
You are Ayah, a personal assistant.

You are proactive and concise. You surface what matters without being asked:
budget nearing limit, habit streak at risk, goal milestone due. You do not
wait to be asked — you notice and mention.

You do not use emojis. All numbers are formatted with commas and currency codes.
Tables use Discord code blocks. You never pad responses with pleasantries.
```

### AGENTS.md

`hermes/profiles/assistant/AGENTS.md` — mandate and rules. Auto-injected at session start.

```markdown
# Ayah — Personal Assistant

## Mandate
You manage Danish's personal finances, habits, goals, tasks, and journal.
All financial writes require user confirmation before committing.

## Finance rules
- Every transaction must show original currency + USD equivalent + fx_rate before approval.
- Never commit a transaction with approved=False. Always show draft first, wait for confirmation.
- Riba (interest) lines must be flagged explicitly and routed to log_riba, not record_transaction.
- Budget approaching limit (>80%): mention unprompted in the next message.
- Multicurrency: AED, SAR, USD all valid. Convert to USD base via finance-service FX fetch.

## Habit/goal/task rules
- Habit streak: compute from logged_date gaps — a gap >1 day breaks the streak.
- Never mark a task complete without user confirmation.
- Surface goal milestones due within 7 days unprompted.

## Journal rules
- Journal entries require approval before write (approved=False → approved=True flow).
- Never read journal entries aloud unprompted. Only on explicit request.

## Bank statement reconciliation
- Accept PDF or CSV from Discord attachment. Pass CDN URL to reconcile_statement tool.
- Surface unmatched transactions and interest lines. Require per-item confirmation before adding.

## Channel context
Channel IDs are set in config.yaml channel_prompts. In #finances: focus on finance.
In #journal: focus on reflection. In #habits: focus on streak and logging.
```

### config.yaml changes

```yaml
discord:
  allow_any_attachment: true
  allowed_channels: "<finances_id>,<journal_id>,<habits_id>,<goals_tasks_id>,<chat_id>"
  # free_response_channels: mention-free, inline replies (no threading)
  free_response_channels:
    - <finances_channel_id>
    - <journal_channel_id>
    - <habits_channel_id>
    - <goals_tasks_channel_id>
  # channel_prompts: ephemeral per-channel system context
  channel_prompts:
    "<finances_channel_id>": "User is in #finances. Focus on financial queries and transactions."
    "<journal_channel_id>":  "User is in #journal. Focus on reflection, writing, and journal search."
    "<habits_channel_id>":   "User is in #habits. Focus on habit logging and streak tracking."
    "<goals_tasks_channel_id>": "User is in #goals-tasks. Focus on goals and task management."
  # channel IDs are Discord snowflake integers — fill in actual values at deploy time

mcp_servers:
  finance:
    url: http://127.0.0.1:8101/mcp
    tools:
      include:
        - record_transaction
        - spending_report
        - budget_status
        - account_balance
        - reconcile_statement
        - add_category
        - zakat_status
        - calculate_zakat
        - log_riba
        - riba_report
  personal:
    url: http://127.0.0.1:8102/mcp

agent:
  disabled_toolsets:
    - browser
    - code_execution
    - cronjob
    - delegation
    - file
    - image_gen
    - terminal
    - tts
    - vision
    - web

security:
  allow_lazy_installs: false
  redact_secrets: true

approvals:
  mode: manual

auxiliary:
  compression:
    provider: custom:litellm
    model: deepseek/deepseek-v3-0324
```

### Systemd units for new services

**`systemd/finance-service.service`:**

```ini
[Unit]
Description=Nizam-OS finance-service (MCP HTTP)
After=network.target postgresql.service

[Service]
Type=simple
User=vazir
EnvironmentFile=/home/vazir/nizam-os/secrets/nizam.env
ExecStart=/home/vazir/.local/bin/uv run \
    --directory /home/vazir/nizam-os/services/finance-service \
    --env-file /home/vazir/nizam-os/secrets/nizam.env \
    python server.py
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

**`systemd/personal-service.service`:** identical pattern, port 8102.

Add HTTP entrypoint to both services' `server.py`:

```python
if __name__ == "__main__":
    mcp.run(transport="streamable-http", host="127.0.0.1", port=PORT)
```

Port constants: `finance-service` = 8101, `personal-service` = 8102.

### Discord channels

| Channel | Purpose |
|---|---|
| `#chat` | General personal assistant queries |
| `#finances` | Finance entry, budget check, reconciliation |
| `#habits` | Habit logging, streak check |
| `#goals-tasks` | Goal/task management |
| `#journal` | Journal entries and search |

All five are `free_response_channels` (no @mention needed, inline replies).

---

## Shared dependencies

Both new services extend `nizam-shared`. New deps needed in each service's `pyproject.toml`:

| Service | New deps |
|---|---|
| `finance-service` | `pymupdf` (statement PDF), `httpx` (FX API, gold API), `hijridate` |
| `personal-service` | nothing new beyond `nizam-shared` |

`nizam-shared` itself does not change — DB connection and audit log patterns are reused as-is.

---

## Multicurrency rules

Enforced at the code level, not the LLM level:

- Every transaction stored with `amount_original`, `currency_original`, `amount_base` (USD), `fx_rate`, `fx_date`
- Reports always show original currency + USD equivalent
- Budgets defined in one currency; budget comparisons convert at the rate used at transaction time
- SAR: schema supports it from day 1 (no special handling needed — just another currency code)

---

## Audit trail

Every `finance-service` write (insert, update) triggers an `audit.log` insert:

```
actor:        "assistant"
schema_name:  "finance"
table_name:   "transactions"
operation:    "INSERT"
after_state:  {full row as JSONB}
```

`svc_finance_personal` role has INSERT-only on `audit.log`. No UPDATE, no DELETE — ever.

---

## Implementation order

1. Write migration `0002_personal_schema.sql` (personal + finance schemas; use `svc_finance_personal`)
2. Write migration `0003_audit_schema.sql`
3. Run migrations, create DB roles
4. Build `personal-service` (simpler, no external APIs); add HTTP entrypoint port 8102
5. Build `finance-service` (NL entry + FX first; reconciliation + zakat second); add HTTP entrypoint port 8101
6. Write systemd units for both services; install + start
7. Write Ayah `SOUL.md` (personality only) and `AGENTS.md` (mandate + rules)
8. Update assistant `config.yaml` (MCP `url:`, Discord channels, `allow_any_attachment`)
9. Enable assistant gateway

---

## Grafana: personal dashboard

File: `grafana/personal-dashboard.json`
Built in: Assistant v1 plan — Task 11 (after all services are functional)

**Datasource:** PostgreSQL direct (Grafana native — not Prometheus). One dedicated `grafana` PostgreSQL role with `SELECT` only on `personal.*`, `finance.*`, `audit.log`. No write access. Role created in migration `0002_personal_schema.sql`.

The knowledge vault panels (from `docs/specs/20260701-curator-v1-design.md`) are appended as a section in this same dashboard — all personal tracking in one place.

**Panels:**

| Section | Panel | Type | Query target |
|---|---|---|---|
| Habits | Active habits | stat | `COUNT(*) WHERE is_active = true` |
| Habits | Completed today | stat | `habit_logs WHERE logged_for = CURRENT_DATE` |
| Habits | Completion rate by habit — 7d | bargauge | `habit_logs` grouped by habit, last 7 days |
| Habits | Completion heatmap — 30d | heatmap | `habit_logs` by day |
| Goals | Active goals | stat | `goals WHERE status = 'active'` |
| Goals | Goals by status | bargauge | `goals` grouped by status |
| Goals | Due this month | table | `goals WHERE due_date <= end_of_month` — title, due_date, status |
| Tasks | Due today | stat | `tasks WHERE due_date = CURRENT_DATE AND status != 'done'` |
| Tasks | Overdue | stat (red if > 0) | `tasks WHERE due_date < CURRENT_DATE AND status != 'done'` |
| Tasks | Completed this week | stat | `tasks WHERE completed_at >= start_of_week` |
| Journal | Entries this month | stat | `journal WHERE DATE_TRUNC('month', entry_date) = current month` |
| Journal | Last entry | stat | `MAX(entry_date)` |
| Journal | Entries per day — 30d | timeseries | `journal` grouped by entry_date |
| Finance | Spend today | stat (AED) | `personal_transactions WHERE txn_date = today AND direction = 'expense'` |
| Finance | Spend this month | stat (AED) | `personal_transactions WHERE month = current AND direction = 'expense'` |
| Finance | Budget utilisation | bargauge (%) | `personal_transactions` vs `budgets` by category |
| Finance | Spend by category | bargauge (AED) | `personal_transactions` this month grouped by category |
| Knowledge | (panels defined in curator-v1 spec) | — | `knowledge.*` |

**Rebuild:** In Grafana — Connections → Data Sources → Add → PostgreSQL → configure with `grafana` role credentials. Then Dashboards → Import → upload `grafana/personal-dashboard.json`.

---

## What "done" looks like

- Ayah responds in `#finances` with no @mention required
- "spent 200 AED on lunch" → draft shown → confirmed → stored with AED + USD + fx_rate
- Bank statement PDF upload → reconciliation diff returned within 30 seconds
- Interest line in statement → flagged, added to riba_log on approval
- "log Quran habit" → streak updated, confirmation sent
- "what are my open tasks?" → formatted task list returned
- Journal entry written → searchable, logged to audit
- All finance writes appear in `audit.log`
- Personal dashboard imports without error and shows live data
