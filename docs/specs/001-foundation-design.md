# Foundation — Design Spec

**Phase:** 1  
**Charter refs:** [ARCHITECTURE](../ARCHITECTURE.md), [SCHEMAS](../SCHEMAS.md), [SECURITY](../SECURITY.md), [INTEGRATIONS](../INTEGRATIONS.md)

---

## Prerequisite

Complete [nizam-dotfiles](~/nizam-dotfiles/docs/startup-guide.md) machine setup before this phase. That repo covers: Ubuntu 24.04, SSH hardening, UFW, fail2ban, Tailscale, zsh, Prometheus, Grafana, node-exporter, and dotfiles security metric timers. Phase 1 builds on top of that baseline — it does not repeat it.

One external backup item must exist, if reusing keys, before proceeding: `secrets/nizam-age-key.txt` (the age private key). Without it, `nizam.env.enc` cannot be decrypted. Back this up to a secure external location before any VPS wipe.

---

## Delivery model

Phase 1 delivers one entry point: `scripts/setup/foundation.sh`. Running this script produces a working Phase 1 system. The script is idempotent — each block checks state before acting, safe to re-run after a failure.

The only step that stays manual is Grafana dashboard import — Grafana has no stable CLI for this. The script prints the instruction at the end.

**Rebuild (reusing existing credentials):**
```bash
git clone <repo> ~/nizam-os
cp <backup>/nizam-age-key.txt ~/nizam-os/secrets/nizam-age-key.txt
# foundation.sh detects the .enc file and decrypts nizam.env automatically
sudo bash ~/nizam-os/scripts/setup/foundation.sh
```

**Fresh setup (new credentials):**
```bash
git clone <repo> ~/nizam-os
age-keygen -o ~/nizam-os/secrets/nizam-age-key.txt

# Generate strong passwords
openssl rand -base64 32   # → LITELLM_DB_PASSWORD
openssl rand -base64 32   # → REDIS_PASSWORD
openssl rand -base64 32   # → LITELLM_MASTER_KEY

# Populate nizam.env from template and fill all values
cp ~/nizam-os/secrets/nizam.env.example ~/nizam-os/secrets/nizam.env
nano ~/nizam-os/secrets/nizam.env
sudo bash ~/nizam-os/scripts/setup/foundation.sh
# foundation.sh detects no .enc and encrypts nizam.env after confirming vars are set
```

---

## Secrets management

**Storage model:**
- `secrets/nizam.env` — plaintext secrets file. Gitignored. Never committed.
- `secrets/nizam.env.enc` — age-encrypted. Committed to git.
- `secrets/nizam.env.example` — keys only, no values. Committed. Updated automatically by `watcher-env.service` on every encrypt.
- `secrets/nizam-age-key.txt` — age private key. Gitignored. Must be backed up externally.

**Encryption tools:** `sops` + `age`. Manual scripts: `scripts/encrypt-env.sh`, `scripts/decrypt-env.sh`.

**Auto-encrypt watcher:** `watcher-env.service` runs `inotifywait` on `nizam.env`. On every `close_write`, it re-encrypts to `nizam.env.enc` and updates `nizam.env.example`. This ensures the committed ciphertext stays current with any edit without requiring a manual step.

**`nizam.env` variables for Phase 1:**

| Variable | Phase added | Purpose |
|----------|-------------|---------|
| `OPENROUTER_API_KEY` | 1 | LiteLLM upstream auth to OpenRouter |
| `LITELLM_MASTER_KEY` | 1 | LiteLLM admin operations + virtual key parent |
| `LITELLM_DB_PASSWORD` | 1 | `svc_litellm` PostgreSQL role password |
| `LITELLM_DB_URL` | 1 | Full PostgreSQL DSN for LiteLLM Prisma (`postgresql://svc_litellm:PASS@localhost:5432/nizam`) |
| `REDIS_URL` | 1 | `redis://:PASSWORD@localhost:6379/0` |
| `REDIS_PASSWORD` | 1 | Redis `requirepass` value |
| `DISCORD_WEBHOOK_LOGS` | 1* | Webhook URL for inventory diff → `#logs` in Discord. Leave empty in Phase 1; fill in Phase 2 after Discord server is created. |

Phase 2+ vars added later to nizam.env (not Phase 1):
- `DISCORD_GUILD_ID`, per-profile `DISCORD_TOKEN` — Phase 2
- `DISCORD_WEBHOOK_ALERTS` — Phase 2; Grafana alert contact point → `#alerts` in Discord
- `POSTGRES_DSN_KNOWLEDGE`, `POSTGRES_DSN_FINANCE_PERSONAL`, etc. — added by each phase's migration when its service role is created
- `YOUTUBE_API_KEY`, `YOUTUBE_COOKIES_FILE`, `VAULT_ROOT` — Phase 4 (Noor)

Per-profile secrets (`DISCORD_TOKEN` per agent, LiteLLM virtual key per agent) are Phase 2 scope — each profile has its own `.env.enc` committed separately.

---

## PostgreSQL

**Version:** 16 (Ubuntu 24.04 default apt).

**Extensions:**
- `pgvector` — installed via apt (`postgresql-16-pgvector`). Provides vector similarity search (`<=>` cosine ops) and HNSW indexes.
- `pg_search` (ParadeDB) — installed via ParadeDB apt repo (Ubuntu 24.04 / PG 16 packages). Provides BM25 full-text search via `@@@` operator and `paradedb.score()`.

Both extensions are enabled in the `nizam` database during Phase 1 setup. Future service schemas depend on them.

**Database:** `nizam` — single database for all schemas across all phases.

**Setup script (`setup-db.sh`):** Creates the `nizam` database, `svc_litellm` role, and `litellm` schema placeholder. Prints the `LITELLM_DB_URL` to add to `nizam.env`. Run once during `foundation.sh`.

**Roles created in Phase 1:** `svc_litellm` only. All other service roles (`svc_knowledge`, `svc_finance_personal`, etc.) are created in their respective phase migrations.

---

## `audit` schema — `001_audit_schema.sql`

The `audit` schema is created first across all migrations. Every service that mutates data writes here. No service role holds UPDATE or DELETE on `audit.log` — the table is append-only by grant, not trigger.

**Table: `audit.log`**

| Column | Type | Notes |
|--------|------|-------|
| `id` | BIGSERIAL PK | |
| `schema_name` | TEXT NOT NULL | Schema of the affected table |
| `table_name` | TEXT NOT NULL | Table that was mutated |
| `operation` | TEXT NOT NULL | `INSERT`, `UPDATE`, or `DELETE` |
| `actor` | TEXT NOT NULL | Hermes profile name — every write attributed to an agent |
| `row_id` | BIGINT | PK of the affected row; NULL for bulk ops |
| `before_state` | JSONB | Row state before mutation; NULL for INSERT |
| `after_state` | JSONB | Row state after mutation; NULL for DELETE |
| `created_at` | TIMESTAMPTZ NOT NULL DEFAULT NOW() | |

**Grants:** INSERT per service role is added in each phase's own migration — not in `001`. The `grafana` role receives SELECT when created in Phase 2. This means `audit.log` exists but has zero grants at the end of Phase 1; that's correct.

**Migration numbering:** `audit` = `001`. The existing knowledge schema file renumbers from `001` to `002` (Phase 4).

---

## Redis

Installed via apt. Config file: `config/redis.conf` — committed to repo, copied to `/etc/redis/redis.conf` by `install-symlinks.sh` (copy not symlink, same reason as logrotate: Redis requires root-owned config).

Four settings in `config/redis.conf`:
- `bind 127.0.0.1` — localhost only
- `requirepass <REDIS_PASSWORD>` — placeholder; `foundation.sh` substitutes the actual value from `nizam.env` using `envsubst` before copying
- `maxmemory 256mb` + `maxmemory-policy allkeys-lru` — bounds memory use; evicts least-recently-used keys when full. Safe for a cache workload.

`REDIS_URL` in nizam.env includes the password: `redis://:PASSWORD@localhost:6379/0`.

**Used by:**
- LiteLLM exact-match cache (TTL 3600s, configured in `config/litellm.yaml`)
- `nizam-shared` `ServiceBase.cache` — Redis client available to all MCP services. Not used at Phase 1; wired in so services can use it without additional setup.

---

## LiteLLM proxy

**Config:** `config/litellm.yaml` — already in repo. No changes needed for Phase 1.

Key config decisions (documented here, not repeated in the file):
- Wildcard model routing: all models route via `openrouter/*`. `google/gemini-embedding-2` has an **additional explicit entry** — both the wildcard and the explicit entry route to the same place (OpenRouter), but without the explicit entry LiteLLM cannot correctly attribute cost for embedding calls (the wildcard match doesn't resolve model-specific pricing). The explicit entry is purely for spend tracking accuracy.
- Exact-match Redis cache: TTL 3600s, `acompletion` + `completion` call types
- `store_end_user: true` — passes Hermes profile name through to `SpendLogs.end_user` for per-agent spend tracking
- `allow_requests_on_db_unavailable: true` — proxy starts even if DB is momentarily down

**DB initialization:** On first start with a valid `LITELLM_DB_URL`, LiteLLM auto-runs its Prisma migration and creates spend tracking tables in the `litellm` schema. `foundation.sh` starts LiteLLM, waits for `/health/liveliness` to respond, then continues. This confirms the DB migration completed.

**Virtual keys:** Each Hermes profile gets its own LiteLLM virtual key (scoped under the master key) via `setup-litellm-keys.sh`. Deferred to Phase 2 — profiles don't exist yet.

---

## Logging

All services log to `~/nizam-os/logs/<service-name>.log`. Systemd achieves this with zero code changes by adding to each service unit:

```ini
StandardOutput=append:/home/vazir/nizam-os/logs/<service-name>.log
StandardError=append:/home/vazir/nizam-os/logs/<service-name>.log
```

`config/logrotate.nizam-os` rotates `logs/*.log` (daily, 14 copies, compress). Copied to `/etc/logrotate.d/nizam-os` by `install-symlinks.sh`.

**Uniform log format** — every line is JSON. Python services (via `nizam-shared`) emit the full format; bash scripts emit the compact format.

*Python services:*
```json
{"ts":"2026-07-05T12:34:56.789Z","level":"INFO","service":"knowledge-service","module":"ingestion","func":"ingest_url","msg":"fetched URL"}
```

*Bash scripts (`_log.sh`):*
```json
{"ts":"2026-07-05T12:34:56Z","level":"INFO","service":"watch-inventory","msg":"inventory changed"}
```

| Field | Python | Bash |
|-------|--------|------|
| `ts` | ISO 8601 UTC, ms precision | ISO 8601 UTC, second precision |
| `level` | `DEBUG`/`INFO`/`WARNING`/`ERROR`/`CRITICAL` | `INFO`/`WARN`/`ERROR` |
| `service` | ServiceBase `name` arg | `$SCRIPT_NAME` |
| `module` | Python `__name__` of caller | absent |
| `func` | Calling function name | absent |
| `msg` | Log message | Log message |

Promtail parses both formats — it extracts `level` and `service` as labels for Grafana Loki queries.

`logger.py` in `nizam-shared` produces the Python format. All services using `ServiceBase` get compliant logs automatically.

---

## nizam-shared library

**Path clarification:** `services/shared/` is the uv package root (contains `pyproject.toml`). `nizam_shared/` inside it is the importable Python package. This is standard Python packaging — the directory name matches the import name. Services declare `nizam-shared = { workspace = true }` and import with `from nizam_shared import ServiceBase`.

Two targeted changes are made in Phase 1:

### `base.py` — ServiceBase DB connection

**Old:** hardcodes `svc_knowledge` role and `POSTGRES_SVC_KNOWLEDGE_PASS` env var. Only worked for knowledge-service.

**New:** reads `POSTGRES_DSN` env var directly.

```python
self.dsn = os.environ["POSTGRES_DSN"]
```

**How `POSTGRES_DSN` is set:** All service DSNs live in `nizam.env` under named vars (`POSTGRES_DSN_KNOWLEDGE`, `POSTGRES_DSN_FINANCE_PERSONAL`, etc.). Each service's systemd unit uses a shell wrapper in `ExecStart` to map its named var to the generic `POSTGRES_DSN` that ServiceBase reads:

```ini
EnvironmentFile=/home/vazir/nizam-os/secrets/nizam.env
ExecStart=/bin/sh -c 'POSTGRES_DSN=$POSTGRES_DSN_KNOWLEDGE exec uv run --directory /home/vazir/nizam-os/services/knowledge-service python server.py'
```

This means: one `nizam.env`, no per-service `.env` files, no duplication. Each phase's migration adds its service's `POSTGRES_DSN_<SERVICE>=...` to `nizam.env` when it creates the role.

ServiceBase structure (constructor, `db()` context manager, `cache` Redis client) is otherwise unchanged.

### `audit.py` — AuditLogger

**Old:** writes to `knowledge.vault_audit` with knowledge-specific fields (`action`, `file_path`, `title`, `approved`, `details`).

**New:** writes to `audit.log` with the generic schema defined above.

New signature:
```python
def log(
    self,
    actor: str,
    schema_name: str,
    table_name: str,
    operation: str,          # "INSERT" | "UPDATE" | "DELETE"
    row_id: int | None = None,
    before_state: dict | None = None,
    after_state: dict | None = None,
) -> None
```

AuditLogger still opens its own autocommit connection — audit records commit even if the caller's transaction rolls back. This invariant is preserved.

---

## Loki + Promtail

**Purpose:** Loki aggregates all `nizam-os/logs/*.log` files so Grafana can show raw log panels and query by `level` and `service` labels. Promtail is the shipping agent.

**Installation:** via Grafana apt repo (same repo already added for Grafana itself).
```bash
apt-get install -y loki promtail
```

**Config files:** Both committed to repo and copied to system locations by `install-symlinks.sh`.

| Repo path | System path | Notes |
|-----------|-------------|-------|
| `config/loki.yaml` | `/etc/loki/config.yml` | Loki server — local filesystem storage |
| `config/promtail.yaml` | `/etc/promtail/config.yml` | Tails `logs/*.log`, labels by `level`+`service` |

**`config/loki.yaml` key settings:**
- `http_listen_port: 3100` — binds `127.0.0.1` (Grafana reads from here)
- `path_prefix: /var/lib/loki` — chunk and index storage
- `schema: v13`, `store: tsdb` — current recommended schema

**`config/promtail.yaml` key settings:**
- Pushes to `http://localhost:3100/loki/api/v1/push`
- `__path__: /home/vazir/nizam-os/logs/*.log` — watches entire logs directory
- Pipeline stage: JSON parser extracts `level` and `service` as labels

**Grafana datasource:** UID `nizam-loki`, URL `http://localhost:3100`. Created manually after foundation.sh (same step as nizam-prometheus).

**Data dir:** `/var/lib/loki/` — created by `foundation.sh`, owned by `loki` system user (installed by apt package).

---

## Systemd units

`scripts/setup/install-symlinks.sh` wires all units from the repo into their runtime locations. `foundation.sh` calls this, then enables and starts the Phase 1 subset.

**Units active after Phase 1:**

| Unit | Type | Purpose |
|------|------|---------|
| `litellm-proxy.service` | system, persistent | LiteLLM on `:4000` |
| `watcher-env.service` | system, persistent | Auto-encrypt `nizam.env` on change |
| `watcher-inventory.timer` | system, timer (hourly) | Inventory diff → Discord |
| `metrics-llm.timer` | system, timer (1 min) | Write `nizam-llm.prom` |
| `metrics-services.timer` | system, timer (5 min) | Write `nizam-services.prom` |
| `metrics-toolcalls.timer` | system, timer (5 min) | Write `nizam-toolcalls.prom` |

User services (`hermes-profile-watcher`, hermes gateways) start in Phase 2.

**node-exporter textfile dir:** `/var/lib/prometheus/node-exporter/` — must be owned by `vazir` so metric scripts can write `.prom` files. Created by `foundation.sh` if missing.

---

## Observability

Three Grafana dashboards total. The nizam-system dashboard is in nizam-dotfiles (OS health). nizam-os adds two domain dashboards: Personal and Business. Dashboard JSON files are stored in `docs/grafana/` (inside `docs/` so they survive a repo wipe) and imported manually into Grafana.

**Datasources required (created manually before import):**

| UID | Type | URL |
|-----|------|-----|
| `nizam-prometheus` | Prometheus | `http://localhost:9090` |
| `nizam-loki` | Loki | `http://localhost:3100` |

**Manual setup (printed by `foundation.sh`):**
1. Open Grafana at `<tailscale-ip>:3000`
2. Connections → Data Sources → Add → Prometheus → URL: `http://localhost:9090`, UID: `nizam-prometheus` → Save & Test
3. Connections → Data Sources → Add → Loki → URL: `http://localhost:3100`, UID: `nizam-loki` → Save & Test
4. Dashboards → Import → `docs/grafana/personal-dashboard.json`
5. Dashboards → Import → `docs/grafana/business-dashboard.json`

**Grafana alerts:** Grafana alerting posts to `#alerts` Discord channel via `DISCORD_WEBHOOK_ALERTS` (Phase 2). Alert contact point configured in Grafana UI, not in code.

---

### Personal Dashboard (`docs/grafana/personal-dashboard.json`)

All panels in one dashboard. Panels that depend on future-phase data show "no data" until that phase is live — that is expected and correct.

**Infrastructure panels (Phase 1 — live immediately):**

| Panel | Type | Metric / Source | Phase |
|-------|------|-----------------|-------|
| LiteLLM proxy up | Stat | `nizam_llm_proxy_up` | 1 |
| LLM spend today | Stat | `nizam_llm_spend_usd_today` | 1 |
| LLM spend this month | Stat | `nizam_llm_spend_usd_this_month` | 1 |
| Cache hit rate today | Gauge | `nizam_llm_cache_hit_rate_today` | 1 |
| Requests today | Stat | `nizam_llm_requests_today` | 1 |
| Token usage today (in/out) | Stat (2 panels) | `nizam_llm_input_tokens_today`, `nizam_llm_output_tokens_today` | 1 |
| Spend by model (personal agents) | Bar chart | `nizam_llm_spend_usd_total{profile=~"ayah\|noor\|nazim"}` | 1 |
| Avg latency by model (1h) | Time series | `nizam_llm_avg_latency_ms_1h` | 1 |
| Tool calls today by tool | Bar chart | `nizam_tool_calls_today` (personal profiles) | 1 |
| Tool error rate | Stat | `nizam_tool_errors_total / nizam_tool_calls_total` | 1 |
| Services up/down over time | State timeline | `nizam_service_up` | 1 |
| Services healthy count | Stat | `nizam_services_up_total` | 1 |
| Log level counts by service | Bar chart | Loki `count_over_time` by `level` label | 1 |
| Live logs | Logs panel | Loki `{job="nizam-os"}` | 1 |

**Knowledge panels (Phase 4 — Noor):**

| Panel | Type | Source | Phase |
|-------|------|--------|-------|
| Vault size (total notes) | Stat | PostgreSQL `knowledge` schema | 4 |
| Notes ingested per week | Time series | PostgreSQL `knowledge` schema | 4 |
| Learning heatmap (daily ingestion) | Heatmap | PostgreSQL `knowledge` schema | 4 |
| Knowledge treemap (by area) | Treemap | PostgreSQL `knowledge` schema | 4 |

**Personal finance panels (Phase 5 — Ayah):**

| Panel | Type | Source | Phase |
|-------|------|--------|-------|
| Account balances | Stat per account | PostgreSQL `finance_personal` | 5 |
| Net worth over time | Time series | PostgreSQL `finance_personal` | 5 |
| Monthly income vs expenses | Bar chart | PostgreSQL `finance_personal` | 5 |
| Expense by category | Bar chart | PostgreSQL `finance_personal` | 5 |
| Budget utilization | Gauge per category | PostgreSQL `finance_personal` | 5 |
| Savings fund progress | Gauge per fund | PostgreSQL `finance_personal` | 5 |
| Cash flow (rolling 30d) | Time series | PostgreSQL `finance_personal` | 5 |
| Upcoming amortization payments | Table | PostgreSQL `finance_personal` | 5 |
| Zakat due estimate | Stat | PostgreSQL `finance_personal` (computed) | 5 |

**Personal habits / goals panels (Phase 5 — Ayah):**

| Panel | Type | Source | Phase |
|-------|------|--------|-------|
| Habit completion rate (this week) | Stat | PostgreSQL `personal` | 5 |
| Active habit streaks | Stat per habit | PostgreSQL `personal` | 5 |
| Task completion rate | Stat | PostgreSQL `personal` | 5 |
| Journal entry heatmap | Heatmap | PostgreSQL `personal` | 5 |

---

### Business Dashboard (`docs/grafana/business-dashboard.json`)

Same structural sections as Personal but scoped to business agents and schemas.

**Infrastructure panels (Phase 1):**

Same layout as Personal dashboard infrastructure panels, but `profile=~"raha|hala|omar|reem|mira"` label filter on LLM metrics. Services panel shows full service list (business + personal).

**Business finance panels (Phase 6b — Hala):**

| Panel | Type | Source | Phase |
|-------|------|--------|-------|
| Revenue this month | Stat | PostgreSQL `finance_business` | 6b |
| Expenses this month | Stat | PostgreSQL `finance_business` | 6b |
| Burn rate | Stat | PostgreSQL `finance_business` | 6b |
| Cash position | Stat | PostgreSQL `finance_business` | 6b |
| Revenue vs expenses (monthly) | Bar chart | PostgreSQL `finance_business` | 6b |
| Expense by category | Bar chart | PostgreSQL `finance_business` | 6b |

**CRM panels (Phase 6c — Omar):**

| Panel | Type | Source | Phase |
|-------|------|--------|-------|
| Deals by pipeline stage | Bar chart | PostgreSQL `crm` | 6c |
| Interactions this week | Stat | PostgreSQL `crm` | 6c |
| Active contacts | Stat | PostgreSQL `crm` | 6c |

**Marketing panels (Phase 6e — Mira):**

| Panel | Type | Source | Phase |
|-------|------|--------|-------|
| Campaign performance | Time series | PostgreSQL `analytics` | 6e |
| Content engagement | Bar chart | PostgreSQL `analytics` | 6e |

---

## Exit criteria

```bash
# LiteLLM
curl -s http://localhost:4000/health/liveliness        # → {"status":"healthy"}

# Redis (use actual REDIS_PASSWORD from nizam.env)
source ~/nizam-os/secrets/nizam.env
redis-cli -a "$REDIS_PASSWORD" ping                    # → PONG

# PostgreSQL schemas
sudo -u postgres psql nizam -c "\dn"                   # → audit, litellm schemas present

# Loki
curl -s http://localhost:3100/ready                    # → ready

# Secrets
grep -c "=" ~/nizam-os/secrets/nizam.env               # → 7 vars

# Metric files (wait 5 min after enabling timers)
ls /var/lib/prometheus/node-exporter/nizam-*.prom      # → 3 files, recent timestamps

# Services
systemctl is-active litellm-proxy watcher-env watcher-inventory.timer \
  metrics-llm.timer metrics-services.timer metrics-toolcalls.timer \
  loki promtail
# → all active
```