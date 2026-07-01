# Nizam-OS — Services

**Last updated:** 2026-07-01

Single reference for every MCP service: port, transport, tools, consumers, DB role. For schema design and implementation detail, follow the spec links.

---

## Port map

| Port | Service | Status |
|---|---|---|
| 4000 | LiteLLM proxy (not an MCP service — model routing) | In repo |
| 8100 | `knowledge-service` | In repo (stdio now; HTTP port 8100 in Curator v1) |
| 8101 | `finance-service` | Specced |
| 8102 | `personal-service` | Specced |
| 8103 | — (unallocated) | — |
| 8104 | `crm-service` | Planned |
| 8105 | `analytics-service` | Planned |

All services run on `127.0.0.1` only. Hermes connects via `url: http://127.0.0.1:PORT/mcp`.

---

## knowledge-service

**Port:** 8100
**Transport:** stdio subprocess now → streamable-HTTP port 8100 in Curator v1
**Status:** In repo — non-functional (DB schema not run; vault dir does not exist)
**Spec:** `docs/specs/20260701-curator-v1-design.md`
**DB role:** `svc_knowledge` (RW on `knowledge.*`, INSERT on `audit.log`)
**Systemd unit:** `systemd/knowledge-service.service` (added in Curator v1)

### Consumers and tool access

| Agent | Tools included |
|---|---|
| Noor (`curator`) | All tools |
| Reem (`cto`) | `search_vault`, `get_note`, `list_notes` |
| Mira (`cmo`) | `search_vault`, `get_note`, `list_notes` |

### Tools — current (stdio, 7 tools)

| Tool | Key params | What it does |
|---|---|---|
| `search_vault` | `query`, `domain?`, `limit=10` | Hybrid BM25 + pgvector search across vault commons |
| `get_note` | `file_path` | Read full note by absolute path |
| `list_notes` | `domain?`, `tags?`, `status?`, `limit=50` | List indexed notes with optional filters |
| `add_note` | `title`, `domain`, `subdomain`, `source`, `content`, `tags`, `approved=False` | Create note — approval-gated (False=draft, True=write) |
| `update_note` | `file_path`, `approved=False`, `content?`, `title?`, `tags?`, `status?` | Update note — approval-gated |
| `ingest_url` | `url`, `approved=False`, `domain?`, `subdomain?`, `tags?` | Fetch URL → vault note. 3-pass: preview → draft → write |
| `ingest_youtube` | `url`, `approved=False`, `domain?`, `subdomain?`, `tags?` | YouTube transcript → vault note. 3-pass workflow |

### Tools — Curator v1 changes

`ingest_url` and `ingest_youtube` are replaced by one unified tool:

| Tool | Key params | What it does |
|---|---|---|
| `ingest` | `source`, `approved=False`, `domain?`, `subdomain?`, `tags?`, `media_type?` | Auto-detect: YouTube / PDF / image / web. 3-pass workflow |
| `ingest_pdf` | (merged into `ingest`) | PDF via URL or Discord CDN attachment. pymupdf extraction. |
| `ingest_image` | (merged into `ingest`) | Image via URL or Discord CDN. LiteLLM vision model describes + extracts text. |

Auto-detection order: YouTube URL → Content-Type PDF / `.pdf` extension → Content-Type image/* → web scrape. `media_type` param overrides for ambiguous sources.

### Approval workflow (all write tools)

```
Pass 1 — omit domain/subdomain  → preview (title + content excerpt, word count)
Pass 2 — supply domain/subdomain/tags, approved=False → show full draft
Pass 3 — approved=True          → write file + index in DB
```

Never skip passes. Never write with `approved=True` without user seeing the draft.

### Tunables

| Parameter | Value | Location |
|---|---|---|
| Search default limit | 10 | `search_vault` param default |
| List notes default limit | 50 | `list_notes` param default |
| RRF fusion constant (k) | 60 | `search.py` — `1/(k + rank)` |
| Embedding model | `google/gemini-embedding-2` | `embedder.py` default; overridable via model field in DB |
| Embedding dimensions | 768 | `knowledge.vault_embeddings.embedding vector(768)` |
| PDF word limit | 15,000 words | `pdf_reader.py` `WORD_LIMIT` — truncates longer PDFs |
| PDF fetch timeout | 10s | `pdf_reader.py` `TIMEOUT` |
| Image max size | 20MB | `vision.py` `MAX_BYTES` |
| Image fetch timeout | 30s | `vision.py` `TIMEOUT` |
| Vision model | `google/gemini-2.0-flash` | `vision.py` default; override via `VISION_MODEL` env var |
| Transcript tier order | youtube-transcript-api → yt-dlp VTT → YouTube Data API v3 | `transcript.py` |

---

## finance-service

**Port:** 8101
**Transport:** streamable-HTTP
**Status:** Specced
**Spec:** `docs/specs/20260701-assistant-v1-design.md` (personal tools), `docs/specs/20260701-cfo-v1-design.md` (business tools)
**Systemd unit:** `systemd/finance-service.service`

One service binary, two DB roles. Personal and business tools share the same HTTP server but connect as different PostgreSQL roles — a compromise of one does not expose the other.

### Consumers and tool access

| Agent | DB role used | Tools included |
|---|---|---|
| Ayah (`assistant`) | `svc_finance_personal` | All personal tools |
| Hala (`cfo`) | `svc_finance_business` | All business tools |
| Omar (`coo`) | `svc_finance_business` (RO subset) | `business_account_balance`, `invoice_status_report` |

### DB roles

| Role | Access |
|---|---|
| `svc_finance_personal` | RW on `finance.*` (personal), RO on `personal.*` (budget context), INSERT on `audit.log` |
| `svc_finance_business` | RW on `business.finance.*`, INSERT on `audit.log`. No access to `finance.*` personal tables. |

### Tools — personal (Ayah)

| Tool | Key params | What it does |
|---|---|---|
| `record_transaction` | `amount`, `currency`, `direction`, `category`, `date`, `approved=False` | Parse → approval gate → commit to `finance.transactions` |
| `spending_report` | `period`, `account?`, `category?` | Totals by category for a period, in original + USD |
| `budget_status` | `period?` | Current spend vs budget per category |
| `account_balance` | `account?` | Balance per account or all accounts |
| `reconcile_statement` | `source`, `period` | Bank statement (PDF or CSV via CDN URL) → diff vs ledger |
| `add_category` | `name`, `parent_id?`, `domain` | Add L1 or L2 spending category |
| `zakat_status` | — | Current hawl state, assets on record, estimated obligation |
| `calculate_zakat` | `hawl_id` | Full zakat calc at hawl end — fetches gold price, computes obligation |
| `log_riba` | `transaction_id`, `amount`, `currency`, `riba_type`, `description` | Route to `finance.riba_log`, not to P&L |
| `riba_report` | `period?` | All riba entries for a period |

### Tools — business (Hala, Omar read-subset)

| Tool | Consumers | What it does |
|---|---|---|
| `record_business_transaction` | Hala | Insert into `business.transactions`, write audit |
| `create_invoice` | Hala | Insert into `business.invoices` + `business.invoice_items` |
| `update_invoice_status` | Hala | Advance status: draft → sent → paid → void |
| `business_spending_report` | Hala | Aggregate spend by category, date range, account |
| `business_account_balance` | Hala, Omar | Current balance per account or all accounts |
| `p_and_l_report` | Hala | Income minus expenses for a period, by category |
| `invoice_status_report` | Hala, Omar | Outstanding, overdue, paid invoices for a period |

### Dependencies

`pymupdf` (statement PDF extraction), `httpx` (FX API, gold price API), `hijridate` (Hijri hawl boundary dates).

Env vars: `FX_API_KEY` (exchangerate-api.com), `GOLD_API_KEY` (metals-api.com or goldpricez.com).

### Tunables

| Parameter | Value | Notes |
|---|---|---|
| FX rate cache | Per-date, same-day reuse | `finance.fx_rates` keyed by `(date, from_currency, to_currency)` |
| FX API free tier | 1,500 requests/month | exchangerate-api.com |
| Gold price fetch | Only at hawl calculation time | Cached in `finance.zakat_hawl.gold_price_usd` |
| Base currency | USD | All amounts stored with `amount_base` in USD |
| Budget period format | `YYYY-MM` | `finance.budgets.period` |

---

## personal-service

**Port:** 8102
**Transport:** streamable-HTTP
**Status:** Specced
**Spec:** `docs/specs/20260701-assistant-v1-design.md`
**DB role:** `svc_personal` (RW on `personal.*`, INSERT on `audit.log`)
**Systemd unit:** `systemd/personal-service.service`

### Consumers and tool access

| Agent | Tools included |
|---|---|
| Ayah (`assistant`) | All tools (no filter) |

### Tools

| Tool | Key params | What it does |
|---|---|---|
| `add_habit` | `name`, `description`, `frequency` | Define a new tracked habit |
| `log_habit` | `habit_id`, `date?`, `note?` | Record completion for today (or specified date) |
| `habit_streak` | `habit_id` | Current streak and recent log |
| `habit_summary` | — | All habits, streaks, last 7 days |
| `add_goal` | `title`, `description`, `target_date` | Create a goal |
| `add_milestone` | `goal_id`, `title`, `due_date` | Add milestone to a goal |
| `update_goal` | `goal_id`, `status?`, `note?` | Change goal status or add progress note |
| `goal_summary` | — | All active goals with milestone status |
| `add_task` | `title`, `description?`, `due_date?`, `priority?`, `goal_id?` | Create a task |
| `complete_task` | `task_id` | Mark task done |
| `task_list` | `due_date?`, `goal_id?`, `status?` | Open tasks, filterable |
| `add_journal` | `entry_date`, `prompt?`, `content`, `tags?`, `approved=False` | Write journal entry — approval-gated |
| `journal_search` | `query`, `limit?` | Full-text search across journal entries |
| `journal_entry` | `entry_id` | Read a specific entry |

Habit streak computation is in Python — a gap `> 1 day` in `logged_date` breaks the streak.

### Tunables

| Parameter | Value | Notes |
|---|---|---|
| Habit streak break threshold | > 1 day gap in `logged_date` | Computed in Python, not DB |
| Journal search | Full-text (PostgreSQL `tsvector`) | No vector search — plain FTS |

---

## crm-service

**Port:** 8104
**Transport:** streamable-HTTP
**Status:** Planned — built in Phase 6c (Omar/COO)
**Spec:** `docs/specs/20260701-coo-v1-design.md`
**DB role:** `svc_crm` (RW on `crm.*`, INSERT on `audit.log`. No direct access to `business.finance.*` — Omar reads finance data via finance-service MCP tool includes.)
**Migration:** `db/migrations/0005_crm_schema.sql` (depends on `0004_business_finance_schema.sql`)
**Systemd unit:** `systemd/crm-service.service` (to be written at build time)

### Consumers and tool access

| Agent | Tools included |
|---|---|
| Omar (`coo`) | All tools (no filter) |
| Mira (`cmo`) | `client_list`, `deal_pipeline`, `client_case_studies` |
| Raha (`cos`) | `deal_pipeline` |

### Tools

| Tool | Consumers | What it does |
|---|---|---|
| `add_client` | Omar | Insert into `crm.clients` |
| `update_client` | Omar | Update client status or details |
| `add_contact` | Omar | Insert into `crm.contacts` |
| `add_deal` | Omar | Insert into `crm.deals` |
| `update_deal_stage` | Omar | Advance deal: prospect → proposal → negotiation → won / lost |
| `add_project` | Omar | Insert into `crm.projects` |
| `update_project_status` | Omar | Update project status: active → on_hold → delivered → cancelled |
| `log_interaction` | Omar | Insert into `crm.interactions` (call / email / meeting / note) |
| `client_list` | Omar, Mira | List clients, filterable by status and industry |
| `deal_pipeline` | Omar, Raha | All open deals with stage and value |
| `client_case_studies` | Mira | Won deals with outcomes — for content. Never publish client names without approval. |

---

## analytics-service

**Port:** 8105
**Transport:** streamable-HTTP
**Status:** Planned — Phase 7 (after Mira/CMO is live)
**Spec:** not yet written
**DB role:** `svc_analytics` (to be defined when spec is written)
**Migration:** `db/migrations/0006_analytics_schema.sql`

### Consumers (planned)

| Agent | Notes |
|---|---|
| Mira (`cmo`) | Owns analytics — all tools |
| Raha (`cos`) | Read-only summary views |
| Nazim (`admin`) | System-level performance views |

Tools are not specced yet. Write spec at Phase 7 start.

---

## External MCP server — GitHub

**Transport:** stdio subprocess via `npx -y @modelcontextprotocol/server-github`
**Status:** Specced (Reem / CTO, Phase 6d)
**Spec:** `docs/specs/20260701-cto-v1-design.md`

Not a nizam-os service — pulled from npm at runtime. Requires Node.js on VPS. `GITHUB_PAT` env var (read + PR review scopes only — never admin scope).

### Consumers

| Agent | Tools included |
|---|---|
| Reem (`cto`) | `list_issues`, `get_issue`, `list_pull_requests`, `get_pull_request`, `create_pull_request_review`, `list_commits`, `get_commit` |

Excluded tools: `delete_*`, `create_repository`, `manage_webhooks`, `add_collaborator`, and any other write/admin tools.

---

## Infrastructure tunables

Parameters for non-MCP components. Change locations noted — not env vars unless stated.

### LiteLLM proxy (`config/litellm.yaml`)

| Parameter | Value | Notes |
|---|---|---|
| Port | 4000 | `--port 4000` in systemd ExecStart |
| Workers | 1 | `--num_workers 1` in systemd ExecStart |
| Request timeout | 600s | `litellm_settings.request_timeout` |
| Cache type | Redis exact-match | `litellm_settings.cache_params.type: redis` |
| Cache TTL | 3600s | `litellm_settings.cache_params.ttl` |
| Cached call types | `acompletion`, `completion` | `supported_call_types` |
| DB unavailable behaviour | Allow requests | `allow_requests_on_db_unavailable: true` — proxy starts even if DB is down |
| Spend tracking | Per end-user | `store_end_user: true` — passes Hermes profile name to `SpendLogs.end_user` |

### Redis

| Parameter | Value | Notes |
|---|---|---|
| Bind | `127.0.0.1:6379` | Default Ubuntu package config |
| LiteLLM cache TTL | 3600s | Set in `config/litellm.yaml` |
| Model price cache TTL | 86400s (24h) | `scripts/metrics-llm.py` — key `nizam:openrouter:model_prices` |

### fail2ban

| Parameter | Value | Location |
|---|---|---|
| Max retries | 5 failures | Default SSH jail |
| Find time | 10 minutes | Default SSH jail |
| Ban time | 1 hour | Default SSH jail |

Change: edit `/etc/fail2ban/jail.local` (or jail.conf). Restart: `sudo systemctl restart fail2ban`.

### Prometheus

| Parameter | Value | Notes |
|---|---|---|
| Scrape interval | 15s | node-exporter default — picks up `.prom` file changes within 15s |
| Textfile dir | `/var/lib/prometheus/node-exporter/` | node-exporter `--collector.textfile.directory` |
| Grafana datasource UID | `nizam-prometheus` | Hardcoded in both dashboard JSON files — must match |

### Metrics timers

| Script | Timer interval | Output file |
|---|---|---|
| `scripts/metrics-llm.py` | Every 1 minute | `nizam-llm.prom` |
| `scripts/metrics-services.sh` | Every 5 minutes | `nizam-services.prom` |
| `scripts/metrics-toolcalls.py` | Every 5 minutes | `nizam-toolcalls.prom` |
| `scripts/watch-inventory.sh` | Hourly | Discord webhook on change |

Change timer interval: edit the corresponding `.timer` file in `systemd/`, run `sudo systemctl daemon-reload && sudo systemctl restart <name>.timer`.

### Hermes agent limits (`hermes/profiles/<name>/config.yaml`)

| Parameter | Value | Notes |
|---|---|---|
| Max turns per session | 150 | `agent.max_turns` |
| Gateway timeout | 1800s (30 min) | `agent.gateway_timeout` |
| Gateway timeout warning | 900s (15 min) | `agent.gateway_timeout_warning` — notifies before hard timeout |
| LLM API max retries | 3 | `agent.api_max_retries` |
| MCP discovery timeout | 1.5s | `mcp_discovery_timeout` — how long Hermes waits for `list_tools()` at startup |
| Tool output max bytes | 50,000 | `tool_output.max_bytes` — truncates larger tool responses |
| Tool output max lines | 2,000 | `tool_output.max_lines` |
| Compression threshold | 0.5 (50% of context used) | `compression.threshold` — triggers summarisation |
| Compression target ratio | 0.2 (keep 20% of context) | `compression.target_ratio` |
| Protected last N messages | 20 | `compression.protect_last_n` — never compressed |
