# Nizam-OS — Services

**Last updated:** 2026-07-01

Personal MCP services (Phases 3–5). For business services (Phases 6b+): `docs/future/SERVICES.md`.

---

## Port map

| Port | Service | Status |
|---|---|---|
| 4000 | LiteLLM proxy (not an MCP service — model routing) | In repo |
| 8100 | `knowledge-service` | In repo (stdio now; HTTP port 8100 in Curator v1) |
| 8101 | `finance-service` | Specced |
| 8102 | `personal-service` | Specced |

Business service ports (8103–8105): `docs/future/SERVICES.md`.

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
Pass 1 — agent ingests content: extracts/transcribes, suggests areas/tags/title, shows full note draft in Discord
Pass 2 — user approves → write file + index in DB
         user rejects  → discard
         user requests edit → agent revises → repeat Pass 2
```

Agent suggests classification. User never supplies domain/areas/tags manually — that is the agent's job. Never write with `approved=True` without user seeing the draft.

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
| Search strategy | `hybrid` (default) | `search_vault` `strategy` param: `keyword` (ParadeDB BM25 only), `semantic` (pgvector cosine only), `hybrid` (RRF combining both). Agent picks based on query type. |

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

DB role grants: `docs/SCHEMAS.md` → DB roles.

### Tools — personal (Ayah)

| Tool | Key params | What it does |
|---|---|---|
| `record_transaction` | `amount`, `currency`, `direction`, `category`, `date`, `approved=False` | Parse → approval gate → commit to `finance_personal.transactions` |
| `spending_report` | `period`, `account?`, `category?` | Totals by category for a period, in original currency + converted to `default_currency` (configurable tunable — e.g. SAR if you have SAR/AED/INR accounts) |
| `budget_status` | `period?` | Current spend vs budget per category |
| `account_balance` | `account?` | Balance per account or all accounts |
| `reconcile_statement` | `source`, `period` | Bank statement (PDF or CSV via CDN URL) → diff vs ledger |
| `add_category` | `name`, `parent_id?`, `domain` | Add L1 or L2 spending category |
| `zakat_status` | — | Current hawl state, assets on record, estimated obligation |
| `calculate_zakat` | `hawl_id` | Full zakat calc at hawl end — fetches gold price, computes obligation |
| `log_riba` | `transaction_id`, `amount`, `currency`, `riba_type`, `description` | Route to `finance_personal.riba_log`, not to P&L |
| `riba_report` | `period?` | All riba entries for a period |

**Hawl tracking:** `zakat_status` checks whether total assets across all accounts have exceeded the nisab threshold and, if so, when. `start_date` in `finance_personal.zakat_hawl` is the date nisab was first crossed. `end_date = start_date + 354 days`. When `end_date` is reached, `calculate_zakat` fetches the current gold price and computes the obligation. Open a new hawl record each time nisab is crossed after a gap.

Business finance tools (Hala, Omar): `docs/future/SERVICES.md`.

### Dependencies

`pymupdf` (statement PDF extraction), `httpx` (FX API, gold price API), `hijridate` (Hijri hawl boundary dates).

Env vars: `FX_API_KEY` (exchangerate-api.com), `GOLD_API_KEY` (metals-api.com or goldpricez.com).

### Tunables

| Parameter | Value | Notes |
|---|---|---|
| FX rate cache | Per-date, same-day reuse | `finance.fx_rates` keyed by `(date, from_currency, to_currency)` |
| FX API free tier | 1,500 requests/month | exchangerate-api.com |
| Gold price fetch | Only at hawl calculation time | Cached in `finance.zakat_hawl.gold_price_usd` |
| Default currency | SAR (configurable) | All amounts stored in `amount_base` converted to `default_currency`. Change via `DEFAULT_CURRENCY` env var in `nizam.env`. |
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
| `add_habit` | `name`, `description`, `frequency`, `rest_days?` | Define a tracked habit. `frequency` is an RRule string (e.g. `FREQ=DAILY`, `FREQ=WEEKLY;BYDAY=MO,WE,FR`). `rest_days` lists days that don't break the streak (e.g. `['Saturday', 'Sunday']`). |
| `log_habit` | `habit_id`, `date?`, `note?` | Record completion for today (or specified date) |
| `habit_streak` | `habit_id` | Current streak and recent log |
| `habit_summary` | — | All habits, streaks, last 7 days |
| `add_goal` | `title`, `description`, `target_date` | Create a goal |
| `add_milestone` | `goal_id`, `title`, `due_date` | Add milestone to a goal |
| `update_goal` | `goal_id`, `status?`, `note?` | Change goal status or add progress note |
| `goal_summary` | — | All active goals with milestone status |
| `add_task` | `title`, `description?`, `due_date?`, `priority?`, `energy?`, `goal_id?` | Create a task. `energy` = low/medium/high effort level required. |
| `complete_task` | `task_id` | Mark task done |
| `task_list` | `due_date?`, `goal_id?`, `status?` | Open tasks, filterable |
| `add_journal` | `entry_date`, `prompt?`, `content`, `approved=False` | Write journal entry — approval-gated |
| `journal_search` | `query`, `limit?` | Full-text search across journal entries |
| `journal_entry` | `entry_id` | Read a specific entry |

Habit streak computation is in Python — a gap `> 1 day` in `logged_date` breaks the streak, unless the day is in `rest_days`.

**Goals vs milestones:** Goals are outcome targets with a target date (e.g. "Read 20 books this year"). Milestones are checkpoints within a goal with their own due dates (e.g. "Read 5 books by March"). Use `add_milestone` to break a goal into steps.

### Tunables

| Parameter | Value | Notes |
|---|---|---|
| Habit streak break threshold | > 1 day gap in `logged_date` (excluding rest_days) | Computed in Python, not DB |
| Journal search | ParadeDB BM25 | Consistent with vault search — no tsvector |

---

## Infrastructure tunables

Infrastructure tunables apply to both personal and business deployments.

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

Config defaults and edit location: `docs/SECURITY.md` → VPS hardening.

### Prometheus

| Parameter | Value | Notes |
|---|---|---|
| Scrape interval | 15s | node-exporter default — picks up `.prom` file changes within 15s. Grafana dashboard auto-refresh should match (set to 15s in dashboard settings). |
| Textfile dir | `/var/lib/prometheus/node-exporter/` | node-exporter `--collector.textfile.directory` |
| Grafana datasource UID | `nizam-prometheus` | Hardcoded in both dashboard JSON files — must match |

### Metrics timers

| Script | Timer interval | OnCalendar offset | Output file |
|---|---|---|---|
| `scripts/metrics-llm.py` | Every 1 minute | :00 | `nizam-llm.prom` |
| `scripts/metrics-services.sh` | Every 5 minutes | :02 | `nizam-services.prom` |
| `scripts/metrics-toolcalls.py` | Every 5 minutes | :04 | `nizam-toolcalls.prom` |
| `scripts/watch-inventory.sh` | Hourly | :30 | Discord webhook on change |

Timers are staggered by offset so load does not peak simultaneously.

Change timer interval: edit the corresponding `.timer` file in `systemd/`, run `sudo systemctl daemon-reload && sudo systemctl restart <name>.timer`.

### Hermes agent limits

Tunable values (max_turns, gateway_timeout, compression): `docs/HERMES.md` → Agent limits.