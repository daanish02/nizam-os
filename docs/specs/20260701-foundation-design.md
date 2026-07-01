# Foundation — design spec

**Status:** live (partially functional — see gaps below)
**Covers:** VPS setup, infra stack, knowledge-service current state, Hermes profiles current state, systemd units, secrets, observability scripts, Grafana dashboards
**Date captured:** 2026-07-01

This spec documents what has already been built. Its primary purpose is rebuild fidelity — reading it with `docs/plans/20260701-foundation.md` gives everything needed to reproduce the current state on a fresh VPS.

---

## VPS baseline

**Provider:** Hostinger KVM2 VPS
**OS:** Ubuntu 22.04 LTS
**Resources:** 8 GB RAM, 4 vCPU, 100 GB NVMe SSD
**User:** `vazir` (non-root), sudo access
**Expires:** 2027-06-10

**Security stack (all active):**
- `ufw` — allows: 22 (SSH), 80, 443, Tailscale subnet. Default deny inbound.
- `fail2ban` — default SSH jail, bans after 5 failures in 10 min, 1h ban
- `unattended-upgrades` — auto-applies security updates
- `ssh.socket` — key-only auth; password auth disabled in sshd_config
- `tailscaled` — Tailscale VPN for management access

---

## Python toolchain

**Package manager:** `uv` — installed to `~/.local/bin/uv` via official installer

**Workspace:** root `pyproject.toml` defines a uv workspace:
```toml
[tool.uv.workspace]
members = ["services/*"]
```

This means all services under `services/` share a single lockfile (`services/uv.lock`). `nizam-shared` is a local workspace dependency — services declare it as `nizam-shared = { workspace = true }`.

**Python version:** 3.12 across all services.

**Dev tooling:** `ruff` (lint + format), `mypy` (strict), `pytest` + `pytest-asyncio`.

---

## Infrastructure services

### PostgreSQL

**Package:** `postgresql` (Ubuntu apt, 15.x)
**Extensions:**
- `pgvector` — vector similarity search (`<=>` cosine ops, HNSW index)
- `pg_search` (ParadeDB) — BM25 full-text search via `@@@` operator + `paradedb.score()`

**Database:** `nizam` — single database for all services
**Roles created so far:**
- `svc_litellm` — owns `litellm` schema (LiteLLM Prisma tables)
- `svc_knowledge` — SELECT + INSERT + UPDATE on `knowledge.*`

**svc_litellm setup:** `scripts/setup/setup-db.sh` — creates DB, user, grants. Run once.
**svc_knowledge setup:** grants are embedded in `db/migrations/0001_knowledge_schema.sql` — run separately.

### Redis

**Package:** `redis-server` (Ubuntu apt)
**Bind:** localhost only (127.0.0.1:6379)
**Used for:**
- LiteLLM exact-match response cache (TTL: 3600s, set in `config/litellm.yaml`)
- Model price cache in `scripts/metrics-llm.py` (key: `nizam:openrouter:model_prices`, TTL: 86400s)
- ServiceBase Redis client in `nizam-shared` (available to all MCP services, not yet used for app-level caching)

### LiteLLM proxy

**Port:** 4000 (localhost only)
**Systemd:** `litellm-proxy.service` → symlinked to `/etc/systemd/system/`
**Config:** `config/litellm.yaml`

Routing:
- `google/gemini-embedding-2` → `openrouter/google/gemini-embedding-2` (explicit, for embedding cost tracking)
- `*` → `openrouter/*` (wildcard — all other models route via OpenRouter)

Headers added to all requests: `HTTP-Referer: nizam-os`, `X-Title: Nizam-OS` (OpenRouter attribution).

Caching:
- **Exact-match Redis cache** — identical prompt+model → cache hit. TTL 3600s.
- Semantic cache not yet configured (planned).

Spend tracking:
- `store_end_user: true` — passes Hermes profile name (`user` field) through to `SpendLogs.end_user`
- `database_url: os.environ/LITELLM_DB_URL` — PostgreSQL spend log storage
- `allow_requests_on_db_unavailable: true` — proxy starts even if DB is down
- **Current state: LiteLLM DB tables not initialized** — `svc_litellm` exists but Prisma migration hasn't run

**Virtual keys per profile:** `scripts/setup/setup-litellm-keys.sh` — creates one LiteLLM virtual key per Hermes profile, writes it to each profile's `.env` as `LITELLM_MASTER_KEY`. The master key in `nizam.env` stays the master; profiles get virtual keys. This enables per-profile spend tracking via `user_id` in LiteLLM logs.

### Prometheus + node-exporter + Grafana

**Packages:** `prometheus`, `prometheus-node-exporter`, `grafana` (Ubuntu apt or Grafana apt repo)
**Prometheus port:** 9090
**Grafana port:** 3000
**node-exporter textfile dir:** `/var/lib/prometheus/node-exporter/`

All three services are live. Prometheus scrapes node-exporter (which picks up `.prom` files from the textfile dir). Grafana connects to Prometheus.

Two dashboards committed to `grafana/`:
- `agents-dashboard.json` — 28 panels: LLM spend/tokens/cache/latency/tool calls. Uses `nizam_llm_*` and `nizam_tool_*` metrics.
- `services-dashboard.json` — service health panels. Uses `nizam_service_*` metrics.

Both use `nizam-prometheus` as the Prometheus datasource UID.

---

## Secrets management

**Primary env file:** `secrets/nizam.env` — shared vars for all system services.
- Gitignored (never committed plain)
- Encrypted to `secrets/nizam.env.enc` using sops/age
- Loaded by: `litellm-proxy.service` (via `EnvironmentFile=`), `metrics-llm.py` (via `EnvironmentFile=` in service unit), `metrics-services.sh` (for `NIZAM_INVENTORY_WATCHER`), `watch-env.sh` (watches for changes)

Variables in `nizam.env` (see `nizam.env.example` for keys, values are secrets):
```
OPENROUTER_API_KEY        — LiteLLM upstream auth
LITELLM_MASTER_KEY        — LiteLLM admin operations
LITELLM_DB_PASSWORD       — svc_litellm PostgreSQL password
LITELLM_DB_URL            — full PostgreSQL DSN for LiteLLM
DATABASE_URL              — legacy alias (same value as LITELLM_DB_URL or unused)
POSTGRES_SVC_KNOWLEDGE_PASS — svc_knowledge PostgreSQL password
VAULT_ROOT                — path to nizam-vault (default: ~/nizam-vault)
REDIS_URL                 — redis://localhost:6379/0
DISCORD_ADMIN_WEBHOOK     — webhook for admin alerts
YOUTUBE_API_KEY           — YouTube Data API v3 (Tier 3 transcript fallback)
YOUTUBE_COOKIES_FILE      — path to cookies.txt for yt-dlp auth
```

Note: `NIZAM_INVENTORY_WATCHER` (Discord webhook for inventory change notifications) is used by `watch-inventory.sh` but is missing from `nizam.env.example` — add to secrets on rebuild.

**Encryption tool:** `sops` + `age` keypair
- Age private key: `secrets/nizam-age-key.txt` (gitignored, back up separately before VPS wipe)
- `scripts/encrypt-env.sh` — encrypts nizam.env → nizam.env.enc
- `scripts/decrypt-env.sh` — decrypts nizam.env.enc → nizam.env
- `scripts/watch-env.sh` — runs as `watcher-env.service`, inotifywait on nizam.env, auto-encrypts on close_write

**Per-profile secrets:** each profile directory has a `.env` (gitignored) and `.env.enc` (committed). Contains `DISCORD_TOKEN`, `DISCORD_GUILD_ID`, and the profile's LiteLLM virtual key (`LITELLM_MASTER_KEY`).
- `scripts/encrypt-profile-env.sh <profile>` — encrypts one profile's .env
- `scripts/decrypt-profile-env.sh <profile>` — decrypts one profile's .env

---

## nizam-shared library

**Location:** `services/shared/nizam_shared/`
**Package:** `nizam-shared` (workspace dependency)

Three modules:

**`base.py` — `ServiceBase`**
- Takes `name: str`
- Wires: JSON logger (`get_logger`), psycopg3 connection factory (`svc.db()`), AuditLogger, Redis client
- DB connects as `svc_knowledge` (hardcoded — will need per-service parameterisation for future services)
- `svc.db()` is a context manager: yields `psycopg.Connection` with dict row factory, auto commit/rollback

**`audit.py` — `AuditLogger`**
- Writes to `knowledge.vault_audit` table (not the future `audit.log` table from planned audit schema)
- Opens its own autocommit connection — audit record commits even if the caller's transaction rolls back
- Signature: `log(profile, action, approved, file_path=None, title=None, details=None)`

**`logger.py` — `get_logger`**
- Returns a JSON-to-stderr logger (not to file — systemd/journald captures stderr)
- Merges `extra={...}` kwargs into JSON output

**Key gap:** `ServiceBase` hardcodes `svc_knowledge` as DB user. Future services (finance-service, personal-service) need their own role. Plan: parameterise with `role` or pass DSN directly. The `AuditLogger` also hardcodes `knowledge.vault_audit` — future services need the shared `audit.log` table from the planned `audit` schema.

---

## knowledge-service (current state)

**Location:** `services/knowledge-service/`
**Transport:** stdio (FastMCP default) — Hermes spawns the process on demand
**Config reference:** `hermes/profiles/curator/config.yaml` → `mcp_servers.knowledge`

```yaml
mcp_servers:
  knowledge:
    command: /home/vazir/.local/bin/uv
    args: [run, --directory, /home/vazir/nizam-os/services/knowledge-service,
           --env-file, /home/vazir/nizam-os/secrets/nizam.env, python, server.py]
```

Hermes spawns one process per session, kills it on session end. No persistent port.

**Tools (7 total):**
- `search_vault(query, domain=None, limit=10)` — hybrid BM25 + vector via RRF
- `get_note(file_path)` — read full note content
- `list_notes(domain=None, tags=None, status=None, limit=50)` — filtered listing
- `add_note(title, domain, subdomain, source, content, tags, approved=False, ...)` — approval-gated create
- `update_note(file_path, approved=False, ...)` — approval-gated update
- `ingest_url(url, approved=False, domain=None, ...)` — fetch URL → note
- `ingest_youtube(url, approved=False, domain=None, ...)` — transcript → note

**Vault layout:**
- Root: `$VAULT_ROOT` (env var, default `~/nizam-vault`)
- Commons dir: `$VAULT_ROOT/commons/` — flat directory, all Noor-managed notes here
- File naming: `{domain}--{subdomain}--{title-slug}.md`
- Format: YAML frontmatter + markdown body (via `python-frontmatter`)

**10 MECE domains:** technology, science, business, finance-economics, philosophy-ethics, health-wellness, arts-culture, history-society, language-communication, personal-development

**Search implementation:**
- BM25: ParadeDB `@@@` operator with `paradedb.boolean(should=[parse(title), parse(content)])`. Falls back to `ts_rank` + `tsvector` if ParadeDB unavailable.
- Vector: pgvector cosine similarity (`<=>`) via HNSW index, 768-dim embeddings
- RRF fusion: both result sets ranked, fused with `1/(k+rank)` where k=60
- Embeddings: `google/gemini-embedding-2` via LiteLLM proxy, skips re-embed if `content_hash` unchanged

**YouTube transcript — 3-tier fallback:**
- Tier 1: `youtube-transcript-api` (no key, fastest)
- Tier 2: `yt-dlp --write-auto-subs` (VTT parse + dedup, uses `YOUTUBE_COOKIES_FILE` if set)
- Tier 3: YouTube Data API v3 (needs `YOUTUBE_API_KEY`, tries captions download then falls back to description)

**Approval workflow:**
1. `approved=False` → returns draft for user review, writes audit record with `approved=False`
2. `approved=True` → writes note to vault, indexes in DB, embeds, writes audit record with `approved=True`
Every write is logged to `knowledge.vault_audit`.

**Current state:** code is complete and tested manually. DB not yet running this schema (PostgreSQL is live but `0001_knowledge_schema.sql` has not been run, and `svc_knowledge` role has not been created). `~/nizam-vault/commons/` does not exist on VPS.

**Delta from Curator v1 spec:** v1 will switch transport to `streamable-http` (port 8100, persistent process), replace `ingest_url` + `ingest_youtube` with unified `ingest` tool (auto-detects media type), add PDF and image ingestion.

---

## Hermes profiles (current state)

All profiles live in `hermes/profiles/<name>/` in nizam-os. The profile-watcher syncs them bidirectionally to `~/.hermes/profiles/<name>/` via symlinks.

### admin (Nazim)

**Gateway:** `hermes-gateway-admin.service` — **active**
**Model:** `deepseek/deepseek-v4-flash` via `custom:litellm`
**Discord:** `discord.allowed_channels` = 5 channel IDs (hardcoded in config.yaml)
**Toolsets (discord):** only `hermes-cli` loaded. All Discord toolsets disabled: browser, code_execution, cronjob, delegation, file, image_gen, terminal, todo, tts, vision.
**MCP:** none
**Files:** SOUL.md, PROTOCOL.md, HEARTBEAT.md, TOOLS.md, config.yaml + memories/ (USER.md, MEMORY.md)

**Gaps:**
- SOUL.md references "Bani" (wrong name, should be "Nazim")
- PROTOCOL.md references "Bani"
- HEARTBEAT.md references "Bani"
- TOOLS.md present (should be deleted — Hermes does not auto-load it)
- No AGENTS.md (mandate is in SOUL.md — should be split)
- `allow_lazy_installs: true` (should be false)
- Compression model not pinned (provider: auto)
- `DISCORD_ALLOWED_USERS` not set in .env
- No sudoers entry for Nazim restart permissions

### curator (Noor)

**Gateway:** `hermes-gateway-curator.service` — **active**
**Model:** `deepseek/deepseek-v4-flash` via `custom:litellm`
**Discord:** `discord.allowed_channels` empty, `require_mention: true`
**Toolsets (discord):** browser, code_execution, cronjob, delegation, file, image_gen, terminal, todo, tts, vision, web — all disabled
**MCP:** knowledge-service via stdio (spawns `uv run python server.py`)
**Files:** SOUL.md, TOOLS.md, config.yaml

**Gaps:**
- SOUL.md mixes mandate + personality (vault rules, taxonomy, failure instructions) — should split personality to SOUL.md, mandate to AGENTS.md
- TOOLS.md present (should be deleted)
- `discord.allowed_channels` empty — Noor responds to any channel
- `allow_lazy_installs: true`
- Compression model not pinned
- `DISCORD_ALLOWED_USERS` not set
- No user.md pre-seeded

**Functional gap:** knowledge-service DB not set up — MCP loads but all tools fail at DB connection.

### assistant (Ayah)

**Gateway:** `hermes-gateway-assistant.service` — **inactive**
**Config:** all platform toolsets enabled (default config, no restrictions applied)
**Discord:** `discord.allowed_channels` empty
**MCP:** none
**Files:** SOUL.md (default placeholder), config.yaml

### cos (Raha)

**Gateway:** `hermes-gateway-cos.service` — **inactive**
**Config:** all platform toolsets enabled (default config, no restrictions applied)
**Discord:** `discord.allowed_channels` empty
**MCP:** none
**Files:** SOUL.md (default placeholder), config.yaml

---

## Systemd unit map

All units in `systemd/` are symlinked to `/etc/systemd/system/` (system units) or `~/.config/systemd/user/` (user units) via `scripts/setup/install-symlinks.sh`.

**Exception:** `config/logrotate.nizam` is COPIED (not symlinked) to `/etc/logrotate.d/nizam` — logrotate rejects config files not root-owned, and symlinks to user-owned files are refused.

| Unit | Type | Schedule | What |
|---|---|---|---|
| `litellm-proxy.service` | system | persistent | LiteLLM on :4000 |
| `metrics-llm.service` | system | oneshot | Write nizam-llm.prom |
| `metrics-llm.timer` | system | every 1 min | Trigger metrics-llm.service |
| `metrics-services.service` | system | oneshot | Write nizam-services.prom |
| `metrics-services.timer` | system | every 5 min | Trigger metrics-services.service |
| `metrics-toolcalls.service` | system | oneshot | Write nizam-toolcalls.prom |
| `metrics-toolcalls.timer` | system | every 5 min | Trigger metrics-toolcalls.service |
| `watcher-env.service` | system | persistent | inotifywait on nizam.env → auto-encrypt |
| `watcher-inventory.service` | system | oneshot | Generate inventory + diff |
| `watcher-inventory.timer` | system | hourly | Trigger watcher-inventory.service |
| `hermes-profile-watcher.service` | user | persistent | Bidirectional sync nizam-os ↔ ~/.hermes/profiles |
| `hermes-skill-watcher.service` | user | persistent | Watch pending skills, post Discord approvals (disabled — SAVE governance not active) |

**Hermes gateway units** (`hermes-gateway-admin`, `hermes-gateway-curator`, etc.) are created by `hermes profile create <name>` and managed by Hermes itself — not in nizam-os systemd/ directory.

---

## Operational scripts

### Metric collectors

**`scripts/metrics-llm.py`** (uv inline script, no venv needed)
- Queries LiteLLM `/spend/logs?limit=10000`
- Uses OpenRouter `/api/v1/models` for real-time pricing (cached in Redis for 24h)
- Writes `nizam-llm.prom` (atomic: write to .tmp then rename)
- 30+ Prometheus metrics: cumulative counters per model/provider/profile + today gauges + cache hit rate + cache savings + 1h latency

**`scripts/metrics-services.sh`**
- Reads `inventory/services.txt` (format: `name | type | status`)
- Writes `nizam-services.prom` with `nizam_service_up{service, type}` per entry

**`scripts/metrics-toolcalls.py`** (uv inline script)
- Parses `~/.hermes/profiles/*/logs/agent.log` and rotated `.log.1`, `.log.2`, `.log.3`
- Regex matches tool executor log lines, extracts tool name + outcome + duration
- Writes `nizam-toolcalls.prom`: calls_total, errors_total, duration_seconds_total, output_chars_total (cumulative) + calls_today, output_chars_today (since midnight UTC)

### Watchers

**`scripts/watch-env.sh`** (watcher-env.service)
- inotifywait on `secrets/nizam.env` close_write
- Runs `encrypt-env.sh` + updates `nizam.env.example` (strips values, keeps keys)

**`scripts/watch-hermes-profiles.sh`** (hermes-profile-watcher.service)
- Three concurrent inotifywait watchers:
  1. nizam-os → .hermes: new *.md/.env/config.yaml in `hermes/profiles/` → auto-symlink into `~/.hermes/profiles/<name>/`
  2. .hermes → nizam-os: new non-symlink file in `~/.hermes/profiles/<name>/` → migrate to nizam-os, replace with symlink back. Covers: `hermes profile create`, SAVE-created skills
  3. .env close_write → auto-encrypt via `encrypt-profile-env.sh <profile>`

**`scripts/watch-inventory.sh`** (watcher-inventory.timer)
- Runs `generate-services-inventory.sh` + `generate-software-inventory.sh`
- sha256-compares against previous snapshots
- On change: writes `inventory/last.diff`, sends diff to Discord via `NIZAM_INVENTORY_WATCHER` webhook

### Setup scripts

**`scripts/setup/install-symlinks.sh`** — run once as sudo after clone:
- Symlinks all system units to `/etc/systemd/system/`
- Copies logrotate config to `/etc/logrotate.d/nizam`
- Symlinks user service to `~/.config/systemd/user/`
- Symlinks profile files for all existing profiles in `~/.hermes/profiles/`

**`scripts/setup/wire-hermes-profile.sh <name>`** — run after `hermes profile create <name>`:
- Merges skills/, memories/ from ~/.hermes/profiles/<name>/ into nizam-os, replaces with symlinks
- Symlinks *.md, .env, config.yaml from nizam-os into ~/.hermes/profiles/<name>/
- Decrypts .env.enc → .env if .env is missing (for post-clone rebuild)

**`scripts/setup/setup-db.sh`** — run once:
- Creates `nizam` database, `svc_litellm` user, `litellm` schema
- Prints DSN to add to nizam.env

**`scripts/setup/setup-litellm-keys.sh`** — run after LiteLLM DB is initialized:
- Creates one LiteLLM virtual key per profile (user_id = profile name)
- Updates each profile's config.yaml to use `custom:litellm` (if not already)
- Writes virtual key to each profile's .env as `LITELLM_MASTER_KEY`

---

## DB migration: 0001_knowledge_schema.sql

Tables in `knowledge` schema:

**`knowledge.vault_index`** — one row per note
- `id`, `file_path` (UNIQUE), `title`, `domain`, `subdomain`, `source`, `source_url`, `source_author`
- `tags TEXT[]`, `status`, `confidence`, `content`, `content_hash`
- `fts_vector TSVECTOR` — GENERATED ALWAYS AS (tsvector of title + content)
- `date_created DATE`, `date_modified DATE`, `indexed_at`, `updated_at TIMESTAMPTZ`
- Indexes: GIN(fts_vector), btree(domain, subdomain), GIN(tags), btree(status), BM25 via ParadeDB

**`knowledge.vault_embeddings`** — one row per note (1:1 with vault_index via file_path FK)
- `note_path` FK → `vault_index.file_path` ON DELETE CASCADE
- `content_hash` — skip re-embed if content unchanged
- `embedding vector(768)`, `model`
- HNSW index: `vector_cosine_ops`

**`knowledge.vault_audit`** — append-only audit trail
- `profile`, `action`, `file_path`, `title`, `approved BOOLEAN`, `details JSONB`, `created_at`
- Note: this is the knowledge-service audit table. It is NOT the shared `audit.log` table planned in future `0003_audit_schema.sql`. Future services will use a separate shared audit schema.

Grants: `svc_knowledge` gets SELECT + INSERT + UPDATE on vault_index and vault_embeddings; SELECT + INSERT on vault_audit; USAGE + SELECT on sequences.

**Current state:** migration not yet run. DB is live but knowledge schema does not exist. `svc_knowledge` role does not exist.

---

## Logrotate

`config/logrotate.nizam` — copied to `/etc/logrotate.d/nizam` (not symlinked):
- Rotates `logs/*.log` daily, 14 copies, compress + delaycompress
- `su vazir vazir` — runs as the vazir user

Logs directory: `/home/vazir/nizam-os/logs/`. Populated by scripts that use `_log.sh`.

---

## Known gaps (delta from intended design)

These are items where current state differs from what the architecture intends. Most are captured in `docs/plans/20260701-immediate-fixes.md` and in Phase 0/0.5 of the build order.

| Gap | Current state | What it should be |
|---|---|---|
| knowledge-service transport | stdio (spawned by Hermes) | HTTP streamable-http port 8100 (Curator v1) |
| knowledge-service ingest tools | `ingest_url` + `ingest_youtube` (separate tools) | single `ingest` tool (Curator v1) |
| AuditLogger target | `knowledge.vault_audit` | shared `audit.log` table (future `audit` schema) |
| ServiceBase DB user | hardcoded `svc_knowledge` | parameterised per service |
| Admin SOUL.md | references "Bani" | rename to "Nazim" throughout |
| Admin PROTOCOL.md / HEARTBEAT.md | references "Bani" | rename to "Nazim" |
| TOOLS.md | present in admin + curator | delete (Hermes does not auto-load) |
| AGENTS.md | missing everywhere | needed in all 4 existing profiles |
| Compression model | `provider: auto` (all profiles) | `deepseek/deepseek-v3-0324` via `custom:litellm` |
| `allow_lazy_installs` | `true` (all profiles) | `false` |
| `discord.allowed_channels` | empty in assistant + cos | set to specific channel IDs |
| `DISCORD_ALLOWED_USERS` | not set (any user can chat) | set per profile .env |
| Nazim sudoers | not set | `/etc/sudoers.d/nazim-hermes` with targeted NOPASSWD |
| `~/nizam-vault/` | does not exist on VPS | create before knowledge-service goes live |
| LiteLLM DB tables | not initialized | run LiteLLM once with DATABASE_URL set |
| `NIZAM_INVENTORY_WATCHER` | missing from nizam.env.example | add to secrets on rebuild |
| hermes-skill-watcher.service | deployed but disabled | enable when SAVE governance is ready (not yet specced) |
| SAVE governance scripts | exist in `scripts/save/` but unused | part of future Hermes governance (not in scope) |

---

## Done criteria (rebuild verification)

A successful rebuild of the foundation state means:

- [ ] All system services active: litellm-proxy, postgresql, redis-server, prometheus, grafana-server, prometheus-node-exporter, metrics-llm.timer, metrics-services.timer, metrics-toolcalls.timer, watcher-env, watcher-inventory.timer, fail2ban, ufw
- [ ] User service active: hermes-profile-watcher
- [ ] Hermes gateways active: hermes-gateway-admin, hermes-gateway-curator
- [ ] LiteLLM reachable: `curl http://localhost:4000/health/liveliness` → 200
- [ ] Redis reachable: `redis-cli ping` → PONG
- [ ] Grafana reachable: `curl -s http://localhost:3000/api/health` → `{"database":"ok"}`
- [ ] Prometheus scraping: `curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool | grep health` → `"health": "up"`
- [ ] `.prom` files fresh: `ls -la /var/lib/prometheus/node-exporter/*.prom` — all recent timestamps
- [ ] Both Grafana dashboards imported and showing data
- [ ] Noor can respond in Discord (even though vault tools will fail until DB is set up)
- [ ] Nazim can respond in Discord
- [ ] nizam.env decrypted and loaded
- [ ] Profile .envs decrypted (admin, curator have working DISCORD_TOKEN)
