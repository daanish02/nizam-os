# Services — Nizam-OS

Reference for all MCP services. Each service is a `uv` workspace member under `services/`. Full schemas in `migrations/`. Tool implementations in `services/<name>/`.

---

## Domain Taxonomy

Everything tracked falls into one of three types:

| Type | What | Examples |
|---|---|---|
| **Goals** | Outcomes with a deadline | "Save $10k emergency fund by Q3", "Ship CRM v1 by July" |
| **Tasks** | Discrete, completable actions | "Email client re invoice", "Review architecture doc" |
| **Habits** | Recurring behaviours to track | Daily Quran, 10k steps, no spending impulse |

Goals link to tasks. Habits are independent. All three live in `personal` schema, managed by `personal-service`.

---

## Services Overview

| Service | Schema | Primary Consumer(s) | Status |
|---|---|---|---|
| `finance-service` | `finance` | Alex (personal), Omar (business) | Step 4 |
| `personal-service` | `personal` | Alex | Step 5 |
| `crm-service` | `crm` | Hala, Mira | Step 6 |
| `knowledge-service` | `knowledge` + vault files | Arwa, Mira, Alex | Step 6 |
| `social-service` | external APIs | Mira | Step 7 |
| `analytics-service` | all schemas (read-only) | Raha, Bani | Step 7 |
| `math-service` | stateless | any profile | Step 7 |

---

## finance-service

Two sub-schemas: `finance.personal` and `finance.business`. Same service, scoped by caller.

### Personal tools

| Tool | Description |
|---|---|
| `add_transaction(amount, category, note, date?)` | Log income or expense |
| `budget_status(month?)` | Budgets vs actuals. Redis-cached 15 min. |
| `fund_status()` | Emergency fund, travel fund, etc. Redis-cached 15 min. |
| `zakat_status()` | Nisab check, estimated zakat due. Redis-cached 1 hour. |
| `set_budget(category, amount, period)` | Create/update budget |
| `add_to_fund(fund_name, amount)` | Contribute to a named fund |
| `spending_report(period, group_by?)` | Aggregated spend by category/period |
| `net_worth_snapshot()` | Assets minus liabilities |

### Business tools

| Tool | Description |
|---|---|
| `log_revenue(amount, client_id, description, date?)` | Record revenue |
| `log_expense(amount, category, description, date?)` | Record business expense |
| `pl_statement(month?)` | P&L for period |
| `cash_flow_forecast(weeks?)` | Rolling cashflow projection |
| `create_invoice(client_id, line_items)` | Generate invoice record |
| `mark_paid(invoice_id, date?)` | Mark invoice as paid |
| `outstanding_invoices()` | Unpaid invoices with age |
| `business_headlines()` | Revenue, costs, pipeline value. Redis-cached 30 min. |

### Key tables (finance schema)

```
transactions(id, domain, amount, currency, category, description, date, created_at)
budgets(id, domain, category, amount, period, created_at)
funds(id, name, balance, target, created_at)
gold_holdings(id, grams, purchase_price_per_gram, date)
invoices(id, client_id, status, total, issued_at, paid_at)
invoice_items(id, invoice_id, description, qty, unit_price)
```

---

## personal-service

Goals, tasks, habits, daily notes.

### Tools

| Tool | Description |
|---|---|
| `add_goal(title, description, deadline, area?)` | Create a goal |
| `list_goals(area?, status?)` | Active goals with linked tasks |
| `add_task(title, goal_id?, due_date?, effort?)` | Add a task |
| `complete_task(task_id)` | Mark done, log completion time |
| `today_tasks()` | Tasks due today or overdue |
| `log_habit(habit_name, date?, notes?)` | Record habit completion |
| `habit_streak(habit_name)` | Current and best streak. Cached until next log. |
| `habits_today()` | All habits with today's status |
| `add_note(content, tags?)` | Append to daily journal |
| `morning_brief()` | Habits today, budget status, overdue tasks, top goal |

### Key tables (personal schema)

```
goals(id, title, description, area, status, deadline, created_at)
tasks(id, goal_id, title, effort, status, due_date, completed_at)
habits(id, name, frequency, created_at)
habit_log(id, habit_id, date, notes)
notes(id, content, tags, created_at)
```

---

## crm-service

Client, contact, project, pipeline tracking for Arc Systems.

### Tools

| Tool | Description |
|---|---|
| `add_client(name, contact_info, source?)` | Onboard a new client |
| `client_list(status?)` | All clients with status. Redis-cached 15 min. |
| `get_client(client_id)` | Full client record + project history |
| `add_project(client_id, title, value, start_date, deadline)` | Create project |
| `update_project_status(project_id, status, notes?)` | Move project along |
| `add_interaction(client_id, type, notes, date?)` | Log meeting, email, call |
| `pipeline_value()` | Total value of active + pending projects |
| `add_lead(name, contact, source, estimated_value?)` | Add to pipeline |
| `convert_lead(lead_id, client_data)` | Lead → client |
| `open_items(client_id?)` | Pending actions with age |

### Key tables (crm schema)

```
clients(id, name, contact_info, source, status, created_at)
projects(id, client_id, title, value, status, start_date, deadline, created_at)
interactions(id, client_id, type, notes, date, created_at)
leads(id, name, contact, source, estimated_value, status, created_at)
```

---

## knowledge-service

Hybrid search over PostgreSQL + Obsidian vault files. Primary tool for "find relevant context" queries.

### Tools

| Tool | Description |
|---|---|
| `search(query, domain?, limit?)` | Hybrid search (BM25 + pgvector). Returns ranked chunks. |
| `add_note(title, content, tags, domain)` | Write to vault + index for search |
| `get_note(note_id_or_path)` | Retrieve full note |
| `list_notes(domain?, tags?)` | Browse vault |
| `upsert_embedding(note_id)` | Recompute embedding (auto-called on write) |
| `domain_summary(domain)` | High-level overview of what's in a vault domain |

### Vault Layout

```
/personal       — private (Alex access only)
  /finance      — money notes, context behind numbers
  /health       — fitness, nutrition context
  /relationships
/business       — Arc Systems (C-suite access)
  /clients      — meeting prep, notes, context
  /products
  /ops          — SOPs, processes
/commons        — shared learning (read: all, write: Alex w/ approval)
  /books
  /courses
  /reference
```

### Knowledge schema

```
knowledge_nodes(id, domain, path, title, content_hash, created_at, updated_at)
knowledge_chunks(id, node_id, chunk_index, content, embedding vector(1536))
```

Embeddings via configured embedding model in `config/litellm.yaml`. Recomputed only on `content_hash` change.

---

## social-service

Thin wrapper over social APIs. Operates on behalf of Mira (CMO).

### Tools

| Tool | Description |
|---|---|
| `draft_post(platform, content, schedule_at?)` | Create a draft |
| `publish_post(draft_id)` | Publish immediately |
| `get_analytics(platform, period)` | Engagement, reach, follower delta |
| `list_drafts()` | Pending drafts |

**Platforms:** LinkedIn (priority), Twitter/X, Instagram (future). API keys per platform in `nizam.env`.

---

## analytics-service

Read-only cross-schema aggregations. Used by Raha for business summaries and by Bani for system health.

### Tools

| Tool | Description |
|---|---|
| `llm_usage_summary(period?)` | Token spend, cost, cache savings per profile/model |
| `business_snapshot()` | Revenue, pipeline, active clients, open tasks |
| `personal_snapshot()` | Budget health, habit streaks, goal progress |
| `service_health()` | All systemd services status, Prometheus metrics |
| `audit_log(entity?, limit?)` | Recent writes across all schemas |

---

## math-service

Stateless computational tools. Any profile can call these.

### Tools

| Tool | Description |
|---|---|
| `compound_growth(principal, rate, years, contributions?)` | Investment/savings projections |
| `loan_schedule(principal, rate, term_months)` | Amortisation table |
| `zakat_calc(assets)` | Nisab check + zakat amount |
| `currency_convert(amount, from, to)` | Live rate via free API |
| `vat_breakdown(amount, rate?)` | Inclusive/exclusive |

---

## Grafana Dashboards

One dashboard (`agents-dashboard.json`, uid: `nizam-agents`). Dense — all panels in one place.

### Current panels (Step 1 — LLM observability)

| Panel | Query | Notes |
|---|---|---|
| Proxy Status | `nizam_llm_proxy_up` | Stat, green/red |
| Calls Today | `sum(increase(nizam_llm_requests_total[1d]))` | |
| Total Cost Today | `sum(increase(nizam_llm_cost_usd_total[1d]))` | |
| Cache Hit Rate | requests / cache misses | |
| Cost by Model | `nizam_llm_cost_usd_total` group by model | Timeseries |
| Cost by Profile | group by profile | Timeseries |
| Cache Tokens — Creation vs Read | separate series | |
| Cache Savings Today | `increase(nizam_llm_cache_savings_usd_total[1d])` | |

Template variables: `$datasource`, `$model`, `$profile`

### Planned rows (added per step)

| Step | Panels to add |
|---|---|
| Step 4 (finance) | Budget health, fund progress, spend by category, zakat status |
| Step 5 (personal) | Habit streaks, goal progress, tasks overdue |
| Step 6 (business) | Pipeline value, open invoices, client count, project status |
| Step 7 (analytics) | Cross-agent token usage, service health tiles |

---

## Flow Examples

### "What's my budget looking like this month?"

```
You → #alex
Alex → finance-service.budget_status()
     ← Redis cache hit (or DB query → cached)
Alex → finance-service.spending_report(period="this_month")
Alex → synthesises both → "You've spent $1,240 of $2,000 personal budget. Over in dining ($180 vs $120 limit), under in transport."
```

### "Onboard new client Apex Tech"

```
You → #raha
Raha → routes to Hala (ops domain)
Hala → crm-service.add_client("Apex Tech", ...)
     ← client_id: 42
Hala → crm-service.add_project(42, "Website Redesign", ...)
Hala → "Client added. Project created. Invoice due May 15. What's the kickoff date?"
```

### "Bani, deploy the finance-service changes"

```
You → #bani
Bani → terminal: git -C ~/.nizam-os pull
Bani → terminal: uv sync --project services/finance-service
Bani → terminal: sudo systemctl restart finance-service
Bani → terminal: systemctl is-active finance-service
Bani → "Deployed. finance-service running. 3 commits pulled."
```
