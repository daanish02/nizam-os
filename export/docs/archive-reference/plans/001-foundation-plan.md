# Phase 1 Foundation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the infrastructure layer (PostgreSQL, Redis, LiteLLM, audit schema, nizam-shared refactor, systemd units, observability) that all future phases run on, delivered as one idempotent `scripts/setup/001-foundation.sh`.

**Architecture:** A single shell script (`001-foundation.sh`) installs packages, configures services, runs migrations, and wires systemd units — detecting fresh vs rebuild automatically from presence of `secrets/nizam-os.env.enc`. All secrets live in `secrets/nizam-os.env` (age-encrypted at rest via sops). The nizam-shared library is refactored so all MCP services share the same `POSTGRES_DSN` connection pattern via per-service systemd ExecStart wrappers.

**Tech Stack:** Ubuntu 24.04, PostgreSQL 16 + pgvector + ParadeDB, Redis 7, LiteLLM (uv tool), sops + age, Python 3.12+, uv, systemd, Prometheus node-exporter textfile collector.

## Before You Start

Dashboard JSON files now live in `docs/grafana/` (inside `docs/`, so they survive the wipe). Nothing to back up separately — just make sure `docs/grafana/personal-dashboard.json` is committed before wiping. The Business dashboard is in later scope and does not exist at Phase 1.

**Prerequisite:** `~/nizam-dotfiles/docs/001-setup-guide.md` complete (Ubuntu 24.04, SSH hardening, UFW, fail2ban, Tailscale, Prometheus, Grafana, Loki, node-exporter). Phase 1 builds on top of that baseline.

---

## Global Constraints

- User: `vazir`. All nizam-os services run as `vazir`.
- All internal services bind `127.0.0.1` only.
- All service logs → `~/nizam-os/logs/<service-name>.log` via systemd `StandardOutput=append:`.
- Single secrets file: `secrets/nizam-os.env`. No per-service `.env` for MCP services.
- Python 3.12+. All Python tooling via `uv`.
- PostgreSQL 16 (Ubuntu 24.04 default apt).
- All paths in this plan are relative to `~/nizam-os/` unless stated.
- **All generated passwords must use `openssl rand -hex 32`.** Passwords appear verbatim in `LITELLM_DB_URL` and `REDIS_URL`. Base64 output contains `/` which breaks URL parsers — Prisma returns P1013 "invalid port number", Redis returns "ValueError: invalid port". Hex is alphanumeric only.
- **PostgreSQL setup must run before LiteLLM/prisma steps.** `prisma db push` connects as `svc_litellm` to the `litellm` schema — both created by `setup-db.sh`. Running prisma first causes auth failure.

---

## File Map

**Created:**

| File | Purpose |
|------|---------|
| `scripts/shared/_log.sh` | Shared bash logging helper (sourced by other scripts) |
| `scripts/env/encrypt-env.sh` | Manual: nizam-os.env → nizam-os.env.enc |
| `scripts/env/decrypt-env.sh` | Manual: nizam-os.env.enc → nizam-os.env |
| `scripts/watchers/watch-env.sh` | Long-running: auto-encrypt on nizam-os.env close_write |
| `scripts/generate-packages-inventory.sh` | Print apt packages + local bins |
| `scripts/watchers/watch-inventory.sh` | Diff package inventory hourly, post Discord embed if changed, commit to git |
| `scripts/metrics/metrics-llm.py` | Write nizam-llm.prom (LLM spend metrics) |
| `scripts/metrics/metrics-services.sh` | Write nizam-services.prom (service health) |
| `scripts/metrics/metrics-toolcalls.py` | Write nizam-toolcalls.prom (tool call counts) |
| `scripts/setup/setup-db.sh` | Idempotent: create nizam DB, svc_litellm role, litellm schema |
| `scripts/setup/install-symlinks.sh` | Wire repo files → system locations |
| `scripts/setup/001-foundation.sh` | **Main entry point** — idempotent Phase 1 setup |
| `db/migrations/001_audit_schema.sql` | Create audit schema + audit.log table |
| `secrets/nizam-os.env.example` | Keys-only template (no values) — committed to git |
| `inventory/tracked-services.txt` | Services polled by metrics-services.sh for Prometheus textfile |
| `config/litellm.yaml` | LiteLLM proxy config |
| `config/redis.conf` | Redis config (bind, requirepass placeholder, maxmemory) |
| `config/loki.yaml` | Loki server config (local storage, port 3100) |
| `config/promtail.yaml` | Promtail config (tails logs/*.log, ships to Loki) |
| `config/logrotate.nizam-os` | Log rotation for nizam-os/logs/*.log |
| `systemd/litellm-proxy.service` | LiteLLM on :4000 |
| `systemd/watcher-env.service` | Auto-encrypt watcher (persistent) |
| `systemd/watcher-inventory.service` | Inventory diff (oneshot) |
| `systemd/watcher-inventory.timer` | Hourly trigger |
| `systemd/metrics-llm.service` | LLM metrics writer (oneshot) |
| `systemd/metrics-llm.timer` | 1-minute trigger |
| `systemd/metrics-services.service` | Service health writer (oneshot) |
| `systemd/metrics-services.timer` | 5-minute trigger |
| `systemd/metrics-toolcalls.service` | Tool call metrics writer (oneshot) |
| `systemd/metrics-toolcalls.timer` | 5-minute trigger |

**Modified:**

| File | Change |
|------|--------|
| `services/shared/nizam_shared/logger.py` | Add `service`, `module`, `func` fields; drop `logger` field |
| `services/shared/nizam_shared/base.py` | Read `POSTGRES_DSN` env var; drop hardcoded `svc_knowledge` |
| `services/shared/nizam_shared/audit.py` | Write to `audit.log` with generic schema; drop knowledge-specific fields |

---

## Task 1: Repo skeleton + secrets template

**Files:**
- Create: `secrets/nizam-os.env.example`
- Create dirs: `logs/`, `db/migrations/`, `inventory/`

- [ ] **Step 1: Create secrets/nizam-os.env.example**

This is the committed keys-only template. The `watcher-env.service` regenerates this on every encrypt, but include it in the plan so the fresh clone has it before any secrets exist.

```bash
# Phase 1 variables — fill all values in nizam-os.env (never commit nizam-os.env)
OPENROUTER_API_KEY=
LITELLM_MASTER_KEY=
POSTGRES_SVC_LITELLM_PASS=
LITELLM_DB_URL=
REDIS_PASSWORD=
REDIS_URL=
```

- [ ] **Step 2: Generate passwords + create required directories**

Generate strong passwords for the three secret values that need them (run before filling nizam-os.env):

```bash
# Must use hex — passwords appear verbatim in LITELLM_DB_URL and REDIS_URL (see Global Constraints)
openssl rand -hex 32   # → LITELLM_MASTER_KEY    (LiteLLM admin key)
openssl rand -hex 32   # → POSTGRES_SVC_LITELLM_PASS  (svc_litellm PostgreSQL role)
openssl rand -hex 32   # → REDIS_PASSWORD        (Redis requirepass)
```

Create directory structure:
```bash
mkdir -p logs db/migrations inventory docs/grafana
touch logs/.gitkeep inventory/.gitkeep docs/grafana/.gitkeep
```

Add to root `.gitignore` if not already present:
```
logs/*.log
secrets/nizam-os.env
secrets/nizam-age-key.txt
inventory/packages.txt
inventory/*.sha256
inventory/last.diff
```

- [ ] **Step 4: Verify**

```bash
ls secrets/.gitignore secrets/nizam-os.env.example
# Expected: both files exist
cat secrets/nizam-os.env.example
# Expected: 6 KEY= lines, no values
```

---

## Task 2: Secrets management scripts + watcher

**Files:**
- Create: `scripts/shared/_log.sh`
- Create: `scripts/env/encrypt-env.sh`
- Create: `scripts/env/decrypt-env.sh`
- Create: `scripts/watchers/watch-env.sh`
- Create: `systemd/watcher-env.service`

- [ ] **Step 1: Create scripts/shared/_log.sh**

Sourced by every one-shot bash script. Set `SCRIPT_NAME` before sourcing. Outputs JSON with a `script` key (bash logs use `script`, Python service logs use `service` — Promtail extracts both as labels).

```bash
#!/usr/bin/env bash
# Shared logging helper for nizam-os scripts.
# Usage: SCRIPT_NAME=my-script source scripts/shared/_log.sh
# Writes JSON to ~/nizam-os/logs/scripts.log and stdout.
# Format: {"ts":"...","level":"INFO","script":"watch-inventory","msg":"..."}

NIZAM_LOG="${NIZAM_LOG:-$HOME/nizam-os/logs/scripts.log}"
mkdir -p "$(dirname "$NIZAM_LOG")"

_nizam_log() {
    local level="$1"; shift
    local msg="$*"
    local ts; ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    # Escape backslashes and double-quotes in msg for valid JSON
    local escaped_msg="${msg//\\/\\\\}"
    escaped_msg="${escaped_msg//\"/\\\"}"
    local line="{\"ts\":\"${ts}\",\"level\":\"${level}\",\"script\":\"${SCRIPT_NAME:-script}\",\"msg\":\"${escaped_msg}\"}"
    echo "$line"
    echo "$line" >> "$NIZAM_LOG"
}

log_info()  { _nizam_log "INFO"  "$@"; }
log_warn()  { _nizam_log "WARN"  "$@"; }
log_error() { _nizam_log "ERROR" "$@"; }
```

- [ ] **Step 2: Create scripts/env/encrypt-env.sh**

```bash
#!/usr/bin/env bash
# Encrypt nizam-os.env → nizam-os.env.enc using sops + age.
# Run manually: bash scripts/env/encrypt-env.sh
# Also called by watcher-env.service on every nizam-os.env save.
set -euo pipefail

export SOPS_AGE_KEY_FILE="$HOME/nizam-os/secrets/nizam-age-key.txt"

PUBKEY=$(grep "public key" "$SOPS_AGE_KEY_FILE" | awk '{print $NF}')

sops \
  --encrypt \
  --input-type dotenv \
  --output-type dotenv \
  --age "$PUBKEY" \
  "$HOME/nizam-os/secrets/nizam-os.env" \
  > "$HOME/nizam-os/secrets/nizam-os.env.enc"
```

- [ ] **Step 3: Create scripts/env/decrypt-env.sh**

```bash
#!/usr/bin/env bash
# Decrypt nizam-os.env.enc → nizam-os.env using sops + age.
# Run manually after git clone or when .enc is updated.
set -euo pipefail

export SOPS_AGE_KEY_FILE="$HOME/nizam-os/secrets/nizam-age-key.txt"

sops \
  --decrypt \
  --input-type dotenv \
  --output-type dotenv \
  "$HOME/nizam-os/secrets/nizam-os.env.enc" \
  > "$HOME/nizam-os/secrets/nizam-os.env"
```

- [ ] **Step 4: Create scripts/watchers/watch-env.sh**

Runs as a long-lived service. On every save of `nizam-os.env`, re-encrypts and regenerates `.env.example`.

```bash
#!/usr/bin/env bash
# Watch nizam-os.env and auto-encrypt + update .env.example on every save.
# Runs as watcher-env.service (persistent via inotifywait).
set -euo pipefail

NIZAM_OS="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_NAME="watch-env"
source "$NIZAM_OS/scripts/shared/_log.sh"

ENV_FILE="$NIZAM_OS/secrets/nizam-os.env"
EXAMPLE_FILE="$NIZAM_OS/secrets/nizam-os.env.example"

update_example() {
    grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$ENV_FILE" \
        | sed 's/=.*/=/' \
        > "$EXAMPLE_FILE"
}

log_info "watching $ENV_FILE"

while inotifywait -e close_write "$ENV_FILE"; do
    log_info "encrypting nizam-os.env"
    "$NIZAM_OS/scripts/env/encrypt-env.sh"
    log_info "updating .env.example"
    update_example
done
```

- [ ] **Step 5: Create systemd/watcher-env.service**

```ini
[Unit]
Description=Watch nizam-os.env and encrypt on changes

[Service]
Type=simple
User=vazir
ExecStart=/home/vazir/nizam-os/scripts/watchers/watch-env.sh
Restart=always
RestartSec=2
StandardOutput=append:/home/vazir/nizam-os/logs/watcher-env.log
StandardError=append:/home/vazir/nizam-os/logs/watcher-env.log

[Install]
WantedBy=multi-user.target
```

- [ ] **Step 6: Verify**

```bash
bash -n scripts/shared/_log.sh && echo "_log.sh: OK"
bash -n scripts/env/encrypt-env.sh && echo "encrypt-env.sh: OK"
bash -n scripts/env/decrypt-env.sh && echo "decrypt-env.sh: OK"
bash -n scripts/watchers/watch-env.sh && echo "watch-env.sh: OK"
# Expected: all 4 print OK
```

---

## Task 3: Database setup + audit schema migration

**Files:**
- Create: `scripts/setup/setup-db.sh`
- Create: `db/migrations/001_audit_schema.sql`

- [ ] **Step 1: Create scripts/setup/setup-db.sh**

Idempotent — safe to re-run. Creates the `nizam` database, `svc_litellm` role, and `litellm` schema. Requires `POSTGRES_SVC_LITELLM_PASS` in environment (sourced from `nizam-os.env` by `001-foundation.sh`).

```bash
#!/usr/bin/env bash
# Idempotent PostgreSQL setup for Phase 1.
# Creates: nizam database, svc_litellm role, litellm schema, pgvector, pg_search.
# Run via 001-foundation.sh (POSTGRES_SVC_LITELLM_PASS must be in env).
set -euo pipefail

: "${POSTGRES_SVC_LITELLM_PASS:?Set POSTGRES_SVC_LITELLM_PASS before running this script}"

sudo -u postgres psql <<SQL
-- Database
SELECT 'CREATE DATABASE nizam'
  WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'nizam')
\gexec

-- Role
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'svc_litellm') THEN
        CREATE USER svc_litellm WITH PASSWORD '${POSTGRES_SVC_LITELLM_PASS}';
    ELSE
        ALTER USER svc_litellm WITH PASSWORD '${POSTGRES_SVC_LITELLM_PASS}';
    END IF;
END\$\$;

GRANT CONNECT ON DATABASE nizam TO svc_litellm;
SQL

sudo -u postgres psql nizam <<SQL
-- Extensions
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_search;

-- litellm schema (Prisma will create tables on first LiteLLM start)
CREATE SCHEMA IF NOT EXISTS litellm AUTHORIZATION svc_litellm;
GRANT ALL ON SCHEMA litellm TO svc_litellm;
ALTER DEFAULT PRIVILEGES IN SCHEMA litellm GRANT ALL ON TABLES TO svc_litellm;
ALTER DEFAULT PRIVILEGES IN SCHEMA litellm GRANT ALL ON SEQUENCES TO svc_litellm;
SQL

echo ""
echo "Database setup complete."
echo ""
echo "Verify LITELLM_DB_URL in nizam-os.env:"
echo "  LITELLM_DB_URL=postgresql://svc_litellm:PASSWORD@localhost:5432/nizam?schema=litellm"
```

> The `?schema=litellm` suffix tells LiteLLM's Prisma ORM to create spend-tracking tables inside the `litellm` schema instead of `public`. This is required — without it, Prisma pollutes the public schema.

- [ ] **Step 2: Create db/migrations/001_audit_schema.sql**

Run once during Phase 1 setup. Creates the shared append-only audit table. No grants are given here — each service's own migration adds `INSERT` for its role when that phase runs.

```sql
-- 001_audit_schema.sql
-- Shared audit log. Append-only by grant (no UPDATE/DELETE ever granted).
-- Service roles receive INSERT in their own phase migrations.

CREATE SCHEMA IF NOT EXISTS audit;

CREATE TABLE IF NOT EXISTS audit.log (
    id           BIGSERIAL    PRIMARY KEY,
    schema_name  TEXT         NOT NULL,
    table_name   TEXT         NOT NULL,
    operation    TEXT         NOT NULL,   -- INSERT | UPDATE | DELETE
    actor        TEXT         NOT NULL,   -- Hermes profile name
    row_id       BIGINT,                  -- PK of affected row; NULL for bulk ops
    before_state JSONB,                   -- row before mutation; NULL for INSERT
    after_state  JSONB,                   -- row after mutation; NULL for DELETE
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
```

- [ ] **Step 3: Verify**

```bash
bash -n scripts/setup/setup-db.sh && echo "setup-db.sh: OK"

# Check SQL syntax (requires psql installed locally)
psql --help >/dev/null && \
  psql -v ON_ERROR_STOP=1 --no-psqlrc -f db/migrations/001_audit_schema.sql \
    "postgresql://postgres@localhost/postgres" 2>&1 | head -5 || true
# If psql is not yet installed, just check the file exists:
ls db/migrations/001_audit_schema.sql && echo "migration file: OK"
```

---

## Task 4: nizam-shared library refactor

**Files:**
- Modify: `services/shared/nizam_shared/logger.py`
- Modify: `services/shared/nizam_shared/base.py`
- Modify: `services/shared/nizam_shared/audit.py`

**Context:** The existing library hardcodes the `svc_knowledge` PostgreSQL role and writes to `knowledge.vault_audit`. This blocks all other services from using ServiceBase. The refactor makes the connection generic (read from `POSTGRES_DSN` env var) and points the audit logger at the shared `audit.log` table.

- [ ] **Step 1: Replace services/shared/nizam_shared/logger.py**

New format adds `service`, `module`, `func` fields matching the spec. `service` = logger name = service name passed to `ServiceBase(name=...)`. `module` = Python's `record.module` (the `__name__` of the calling file). `func` = `record.funcName`.

```python
import json
import logging
import sys
from datetime import datetime, timezone


class _JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        entry: dict = {
            "ts": datetime.now(timezone.utc).isoformat(timespec="milliseconds") + "Z",
            "level": record.levelname,
            "service": record.name,
            "module": record.module,
            "func": record.funcName,
            "msg": record.getMessage(),
        }
        if record.exc_info:
            entry["exc"] = self.formatException(record.exc_info)
        return json.dumps(entry, default=str)


def get_logger(name: str) -> logging.Logger:
    """Return a JSON-to-stderr logger. Pass the service name (e.g. 'knowledge-service')."""
    logger = logging.getLogger(name)
    if not logger.handlers:
        handler = logging.StreamHandler(sys.stderr)
        handler.setFormatter(_JsonFormatter())
        logger.addHandler(handler)
        logger.setLevel(logging.INFO)
        logger.propagate = False
    return logger
```

- [ ] **Step 2: Replace services/shared/nizam_shared/base.py**

Reads `POSTGRES_DSN` from env. This env var is set per-service in each unit's `ExecStart` wrapper (see Task 5 and individual service tasks). The rest of ServiceBase (db context manager, Redis client) is unchanged.

```python
import os
from contextlib import contextmanager
from typing import Generator

import psycopg
import redis
from psycopg.rows import dict_row

from .audit import AuditLogger
from .logger import get_logger


class ServiceBase:
    """Common wiring for all nizam-os MCP services.

    Provides:
    - JSON structured logger (stderr → systemd → logs/<service>.log)
    - psycopg3 connection factory (dict rows, auto commit/rollback)
    - AuditLogger writing to audit.log
    - Redis client for short-lived caching

    Requires env vars:
      POSTGRES_DSN  — full PostgreSQL DSN for this service's role
                      Set via ExecStart wrapper in the systemd unit.
      REDIS_URL     — optional, defaults to redis://localhost:6379/0
    """

    def __init__(self, name: str) -> None:
        self.name = name
        self.logger = get_logger(name)

        self.dsn = os.environ["POSTGRES_DSN"]
        self.audit = AuditLogger(self.dsn)

        redis_url = os.environ.get("REDIS_URL", "redis://localhost:6379/0")
        self.cache: redis.Redis = redis.from_url(redis_url, decode_responses=True)

    @contextmanager
    def db(self) -> Generator[psycopg.Connection, None, None]:
        """Yield a psycopg3 connection with dict row factory.

        Commits on clean exit, rolls back on exception.
        """
        with psycopg.connect(self.dsn, row_factory=dict_row) as conn:
            yield conn
```

- [ ] **Step 3: Replace services/shared/nizam_shared/audit.py**

Writes to `audit.log` with the generic schema. Opens its own autocommit connection so audit records survive caller transaction rollbacks.

```python
import psycopg


class AuditLogger:
    """Write append-only audit records to audit.log."""

    def __init__(self, dsn: str) -> None:
        self._dsn = dsn

    def log(
        self,
        *,
        actor: str,
        schema_name: str,
        table_name: str,
        operation: str,
        row_id: int | None = None,
        before_state: dict | None = None,
        after_state: dict | None = None,
    ) -> None:
        """Insert one audit record.

        Opens its own autocommit connection — commits even if caller's
        transaction rolls back. operation must be INSERT, UPDATE, or DELETE.
        """
        with psycopg.connect(self._dsn, autocommit=True) as conn:
            conn.execute(
                """
                INSERT INTO audit.log
                    (schema_name, table_name, operation, actor,
                     row_id, before_state, after_state)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
                """,
                (
                    schema_name,
                    table_name,
                    operation,
                    actor,
                    row_id,
                    before_state,
                    after_state,
                ),
            )
```

- [ ] **Step 4: Verify services/shared/nizam_shared/__init__.py is unchanged**

```python
from .base import ServiceBase
from .logger import get_logger
from .audit import AuditLogger

__all__ = ["ServiceBase", "get_logger", "AuditLogger"]
```

The `pyproject.toml` requires no changes (psycopg[binary]>=3.2, redis>=5.0 are correct).

- [ ] **Step 5: Syntax-check all three files**

```bash
python3 -c "
import ast, pathlib
for f in ['services/shared/nizam_shared/logger.py',
          'services/shared/nizam_shared/base.py',
          'services/shared/nizam_shared/audit.py']:
    ast.parse(pathlib.Path(f).read_text())
    print(f'{f}: OK')
"
# Expected: 3 OK lines
```

---

## Task 5: LiteLLM proxy config + systemd unit

**Files:**
- Create: `config/litellm.yaml`
- Create: `systemd/litellm-proxy.service`

- [ ] **Step 1: Create config/litellm.yaml**

```yaml
model_list:
  # Explicit entry for cost tracking on embedding calls.
  # Without this, the wildcard match cannot resolve model-specific pricing
  # for gemini-embedding-2 and LiteLLM logs $0 spend for embeddings.
  - model_name: "google/gemini-embedding-2"
    litellm_params:
      model: "openrouter/google/gemini-embedding-2"
      api_key: os.environ/OPENROUTER_API_KEY
      api_base: https://openrouter.ai/api/v1
      extra_headers:
        HTTP-Referer: "https://nizam-os"
        X-Title: "Nizam-OS"
  - model_name: "*"
    litellm_params:
      model: "openrouter/*"
      api_key: os.environ/OPENROUTER_API_KEY
      api_base: https://openrouter.ai/api/v1
      extra_headers:
        HTTP-Referer: "https://nizam-os"
        X-Title: "Nizam-OS"

litellm_settings:
  cache: true
  cache_params:
    type: redis
    redis_url: os.environ/REDIS_URL
    ttl: 3600
    supported_call_types:
      - acompletion
      - completion
  drop_params: false
  request_timeout: 600
  store_end_user: true

general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY
  database_url: os.environ/LITELLM_DB_URL
  disable_spend_logs: false
  allow_requests_on_db_unavailable: true
  database_connection_pool_limit: 3
  database_connection_timeout: 30
```

- [ ] **Step 2: Create systemd/litellm-proxy.service**

```ini
[Unit]
Description=LiteLLM Proxy — OpenRouter gateway with spend tracking
Documentation=https://docs.litellm.ai
After=network.target postgresql.service redis-server.service
Requires=postgresql.service redis-server.service

[Service]
Type=simple
User=vazir
Group=vazir
WorkingDirectory=/home/vazir/nizam-os
EnvironmentFile=/home/vazir/nizam-os/secrets/nizam-os.env
Environment=LITELLM_LOCAL_MODEL_COST_MAP=True
Environment=MALLOC_TRIM_THRESHOLD_=100000
ExecStart=/home/vazir/.local/bin/litellm \
    --config /home/vazir/nizam-os/config/litellm.yaml \
    --port 4000 \
    --num_workers 1
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=litellm-proxy

[Install]
WantedBy=multi-user.target
```

- [ ] **Step 3: Verify**

```bash
python3 -c "import yaml; yaml.safe_load(open('config/litellm.yaml'))" && \
  echo "litellm.yaml: valid YAML"
# Expected: litellm.yaml: valid YAML
```

---

## Task 6: Inventory watcher

**Files:**
- Create: `scripts/generate-packages-inventory.sh`
- Create: `scripts/watchers/watch-inventory.sh`
- Create: `inventory/tracked-services.txt`
- Create: `systemd/watcher-inventory.service`
- Create: `systemd/watcher-inventory.timer`

- [ ] **Step 1: Create scripts/generate-packages-inventory.sh**

```bash
#!/usr/bin/env bash
# Print installed apt packages and local binaries to stdout.
# Piped to inventory/packages.txt by watch-inventory.sh.
set -euo pipefail

echo "=== APT PACKAGES ==="
apt-mark showmanual | while read -r pkg; do
    dpkg-query -W -f='${Package} | ${Version}\n' "$pkg" 2>/dev/null
done | sort

echo ""
echo "=== LOCAL BINARIES ==="
find /usr/local/bin -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | sort

if [ -d "$HOME/.local/bin" ]; then
    find "$HOME/.local/bin" -maxdepth 1 -type f -printf '%f\n' | sort
fi
```

- [ ] **Step 2: Create scripts/watchers/watch-inventory.sh**

```bash
#!/usr/bin/env bash
# Detect software inventory changes and notify via Discord logs webhook.
# Runs hourly via watcher-inventory.timer.
# On first run, writes baseline and exits silently.
# On subsequent runs, diffs against baseline; POSTs diff to webhook if changed.
set -euo pipefail

NIZAM_OS="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_NAME="watch-inventory"
source "$NIZAM_OS/scripts/shared/_log.sh"

BASE="$NIZAM_OS/inventory"
mkdir -p "$BASE"

SOFTWARE="$BASE/software.txt"
SOFTWARE_HASH="$BASE/packages.sha256"
DIFF_FILE="$BASE/last.diff"

TMP_SOFTWARE=$(mktemp)
trap 'rm -f "$TMP_SOFTWARE"' EXIT

"$NIZAM_OS/scripts/generate-packages-inventory.sh" > "$TMP_SOFTWARE"

SOFTWARE_NEW_HASH=$(sha256sum "$TMP_SOFTWARE" | awk '{print $1}')

if [ ! -f "$SOFTWARE" ]; then
    cp "$TMP_SOFTWARE" "$SOFTWARE"
    echo "$SOFTWARE_NEW_HASH" > "$SOFTWARE_HASH"
    log_info "baseline written"
    exit 0
fi

SOFTWARE_OLD_HASH=$(cat "$SOFTWARE_HASH")

if [ "$SOFTWARE_NEW_HASH" = "$SOFTWARE_OLD_HASH" ]; then
    exit 0
fi

diff -u "$SOFTWARE" "$TMP_SOFTWARE" > "$DIFF_FILE" || true

cp "$TMP_SOFTWARE" "$SOFTWARE"
echo "$SOFTWARE_NEW_HASH" > "$SOFTWARE_HASH"

log_info "software inventory changed"

ENV_FILE="$NIZAM_OS/secrets/nizam-os.env"
if [ -f "$ENV_FILE" ]; then
    # shellcheck source=/dev/null
    set -a; source "$ENV_FILE"; set +a
fi

if [ -n "${DISCORD_WEBHOOK_LOGS:-}" ]; then
    curl -s \
        -F "payload_json={\"content\":\"Software inventory changed on nizam-vps. Diff attached.\"}" \
        -F "file=@${DIFF_FILE};filename=inventory.diff" \
        "$DISCORD_WEBHOOK_LOGS" > /dev/null
fi
```

- [ ] **Step 3: Create inventory/tracked-services.txt**

Phase 1 subset only. Hermes gateway/profile-watcher services added in Phase 2.

```
cron.service
fail2ban.service
ufw.service
unattended-upgrades.service
ssh.socket
grafana-server.service
postgresql.service
prometheus-node-exporter.service
prometheus.service
redis-server.service
tailscaled.service
loki.service
promtail.service
litellm-proxy.service
watcher-env.service
watcher-inventory.timer
metrics-llm.timer
metrics-services.timer
metrics-toolcalls.timer
```

- [ ] **Step 4: Create systemd/watcher-inventory.service**

```ini
[Unit]
Description=Generate software inventory diff and notify on change

[Service]
Type=oneshot
User=vazir
ExecStart=/home/vazir/nizam-os/scripts/watchers/watch-inventory.sh
StandardOutput=append:/home/vazir/nizam-os/logs/watcher-inventory.log
StandardError=append:/home/vazir/nizam-os/logs/watcher-inventory.log

[Install]
WantedBy=multi-user.target
```

- [ ] **Step 5: Create systemd/watcher-inventory.timer**

```ini
[Unit]
Description=Run inventory watcher hourly

[Timer]
OnCalendar=*:05:00
Persistent=true

[Install]
WantedBy=timers.target
```

- [ ] **Step 6: Verify**

```bash
bash -n scripts/generate-packages-inventory.sh && echo "generate-software: OK"
bash -n scripts/watchers/watch-inventory.sh && echo "watch-inventory: OK"
ls inventory/tracked-services.txt && echo "tracked-services.txt: OK"
# Expected: 3 OK lines
```

---

## Task 7: Metrics collection scripts + units

**Files:**
- Create: `scripts/metrics/metrics-llm.py`
- Create: `systemd/metrics-llm.service`
- Create: `systemd/metrics-llm.timer`
- Create: `scripts/metrics/metrics-services.sh`
- Create: `systemd/metrics-services.service`
- Create: `systemd/metrics-services.timer`
- Create: `scripts/metrics/metrics-toolcalls.py`
- Create: `systemd/metrics-toolcalls.service`
- Create: `systemd/metrics-toolcalls.timer`

All three write to `/var/lib/prometheus/node-exporter/nizam-*.prom` (created by `001-foundation.sh`). Prometheus node-exporter picks them up via its textfile collector.

- [ ] **Step 1: Create scripts/metrics/metrics-llm.py**

Runs every 60s. Queries LiteLLM `/spend/logs` API and writes cumulative counters + daily gauges. Uses inline script metadata so `uv run` installs deps automatically.

```python
#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.12"
# dependencies = ["requests", "redis"]
# ///
"""
LLM metrics textfile writer for Prometheus node-exporter.
Runs every 60s via metrics-llm.timer.

Metrics written:
  Counters (cumulative):
    nizam_llm_requests_total{model,provider,profile}
    nizam_llm_input_tokens_total{model,provider,profile}
    nizam_llm_output_tokens_total{model,provider,profile}
    nizam_llm_cache_read_tokens_total{model,profile}
    nizam_llm_cache_creation_tokens_total{model,profile}
    nizam_llm_spend_usd_total{model,provider,profile}

  Gauges (pre-aggregated for stat panels):
    nizam_llm_requests_today
    nizam_llm_input_tokens_today
    nizam_llm_output_tokens_today
    nizam_llm_spend_usd_today
    nizam_llm_spend_usd_this_month
    nizam_llm_cache_hit_rate_alltime      (0.0–1.0)
    nizam_llm_cache_savings_usd_today
    nizam_llm_cache_savings_usd_total
    nizam_llm_avg_latency_ms_1h{model}

  Status:
    nizam_llm_proxy_up
"""

import json
import logging
import os
import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

import redis
import requests

logging.basicConfig(
    stream=sys.stdout,
    level=logging.INFO,
    format="%(asctime)s [%(levelname)-5s] [metrics-llm] %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%SZ",
)
log = logging.getLogger("metrics-llm")

OUT = Path("/var/lib/prometheus/node-exporter/nizam-llm.prom")
TMP = OUT.with_suffix(".prom.tmp")

LITELLM_URL = "http://localhost:4000"
LITELLM_KEY = os.environ.get("LITELLM_MASTER_KEY", "")
OPENROUTER_API_KEY = os.environ.get("OPENROUTER_API_KEY", "")
REDIS_URL = os.environ.get("REDIS_URL", "redis://localhost:6379/0")

REDIS_PRICE_KEY = "nizam:openrouter:model_prices"
REDIS_PRICE_TTL = 86400  # 24h


def get_redis() -> redis.Redis | None:
    try:
        r = redis.from_url(REDIS_URL, socket_connect_timeout=2, decode_responses=True)
        r.ping()
        return r
    except Exception:
        return None


def get_model_prices(r: redis.Redis | None) -> dict:
    if r is not None:
        cached = r.get(REDIS_PRICE_KEY)
        if cached:
            try:
                return json.loads(cached)
            except Exception:
                pass

    if not OPENROUTER_API_KEY:
        return {}

    try:
        resp = requests.get(
            "https://openrouter.ai/api/v1/models",
            headers={"Authorization": f"Bearer {OPENROUTER_API_KEY}"},
            timeout=10,
        )
        resp.raise_for_status()

        prices: dict = {}
        for model in resp.json().get("data", []):
            model_id = model.get("id", "")
            if not model_id:
                continue
            pricing = model.get("pricing", {})

            def _price(key: str) -> float | None:
                v = pricing.get(key)
                if v is None:
                    return None
                try:
                    f = float(v)
                    return f if f > 0 else None
                except (TypeError, ValueError):
                    return None

            prices[model_id] = {
                "prompt": _price("prompt"),
                "completion": _price("completion"),
                "cache_read": _price("cache_read"),
                "cache_creation": _price("cache_creation"),
            }

        if r is not None:
            try:
                r.set(REDIS_PRICE_KEY, json.dumps(prices), ex=REDIS_PRICE_TTL)
            except Exception:
                pass

        return prices
    except Exception:
        return {}


def label(**kwargs: str) -> str:
    parts = [f'{k}="{v}"' for k, v in kwargs.items() if v]
    return "{" + ",".join(parts) + "}" if parts else ""


def check_proxy_up() -> int:
    try:
        r = requests.get(f"{LITELLM_URL}/health/liveliness", timeout=3)
        return 1 if r.status_code == 200 else 0
    except Exception:
        return 0


def clean_model(raw: str) -> str:
    while raw.startswith("openrouter/"):
        raw = raw[len("openrouter/"):]
    return raw


def provider_from_model(model: str) -> str:
    parts = model.split("/")
    return parts[0] if len(parts) >= 2 else "unknown"


def parse_time(ts: str | None) -> datetime | None:
    if not ts:
        return None
    try:
        return datetime.fromisoformat(ts.rstrip("Z")).replace(tzinfo=timezone.utc)
    except Exception:
        return None


def write_fallback(proxy_up: int) -> None:
    lines = [
        "# HELP nizam_llm_proxy_up LiteLLM proxy reachable (1=yes, 0=no)",
        "# TYPE nizam_llm_proxy_up gauge",
        f"nizam_llm_proxy_up {proxy_up}",
    ]
    TMP.write_text("\n".join(lines) + "\n")
    TMP.replace(OUT)
    log.warning("proxy_up=%d — wrote fallback only", proxy_up)


def fetch_logs() -> list | None:
    if not LITELLM_KEY:
        log.error("LITELLM_MASTER_KEY not set")
        return None
    try:
        resp = requests.get(
            f"{LITELLM_URL}/spend/logs",
            params={"limit": 10000},
            headers={"Authorization": f"Bearer {LITELLM_KEY}"},
            timeout=15,
        )
        resp.raise_for_status()
        data = resp.json()
        log.info("fetched %d spend log entries", len(data))
        return data
    except Exception as e:
        log.error("fetch_logs failed: %s", e)
        return None


def main() -> None:
    proxy_up = check_proxy_up()
    logs = fetch_logs()
    if logs is None:
        write_fallback(proxy_up)
        return

    now = datetime.now(timezone.utc)
    today_date = now.date()
    month_start = today_date.replace(day=1)
    one_hour_ago = now.timestamp() - 3600

    r = get_redis()
    model_prices = get_model_prices(r)
    lines: list[str] = []

    def section(help_text: str, metric_type: str, name: str) -> None:
        lines.append(f"# HELP {name} {help_text}")
        lines.append(f"# TYPE {name} {metric_type}")

    totals: dict = defaultdict(lambda: {
        "requests": 0, "input_tokens": 0, "output_tokens": 0,
        "spend": 0.0, "cache_read": 0, "cache_create": 0,
    })

    today_req = today_in = today_out = 0
    today_spend = 0.0
    today_cache_hits = 0
    month_spend = 0.0
    latency_by_model: dict = defaultdict(list)
    today_cache_read_by_model: dict = defaultdict(int)

    for entry in logs:
        model = entry.get("model", "") or ""
        profile = entry.get("user", "") or "unknown"
        in_tok = int(entry.get("prompt_tokens") or 0)
        out_tok = int(entry.get("completion_tokens") or 0)

        litellm_spend = float(entry.get("spend") or 0)
        if litellm_spend == 0.0 and (in_tok or out_tok):
            mc = clean_model(model)
            pricing = model_prices.get(mc) or model_prices.get(model)
            if pricing:
                spend = (in_tok * (pricing.get("prompt") or 0.0) +
                         out_tok * (pricing.get("completion") or 0.0))
            else:
                spend = 0.0
        else:
            spend = litellm_spend

        meta = entry.get("metadata") or {}
        usage_obj = meta.get("usage_object") or {}
        ptd = usage_obj.get("prompt_tokens_details") or {}
        cache_read = int(ptd.get("cached_tokens") or 0)
        cache_create = int(ptd.get("cache_write_tokens") or 0)

        key = (model, profile)
        totals[key]["requests"] += 1
        totals[key]["input_tokens"] += in_tok
        totals[key]["output_tokens"] += out_tok
        totals[key]["spend"] += spend
        totals[key]["cache_read"] += cache_read
        totals[key]["cache_create"] += cache_create

        start_ts = parse_time(entry.get("startTime"))
        end_ts = parse_time(entry.get("endTime"))

        if start_ts:
            start_date = start_ts.date()
            if start_date == today_date:
                today_req += 1
                today_in += in_tok
                today_out += out_tok
                today_spend += spend
                if cache_read > 0:
                    today_cache_hits += 1
                today_cache_read_by_model[model] += cache_read
            if start_date >= month_start:
                month_spend += spend
            if start_ts.timestamp() >= one_hour_ago:
                dur = entry.get("request_duration_ms")
                if dur is None and end_ts:
                    dur = (end_ts.timestamp() - start_ts.timestamp()) * 1000
                if dur is not None:
                    latency_by_model[clean_model(model)].append(float(dur))

    section("LiteLLM proxy reachable (1=yes, 0=no)", "gauge", "nizam_llm_proxy_up")
    lines.append(f"nizam_llm_proxy_up {proxy_up}")

    section("Cumulative LLM request count", "counter", "nizam_llm_requests_total")
    for (m, profile), v in totals.items():
        mc = clean_model(m)
        lines.append(f"nizam_llm_requests_total{label(model=mc, provider=provider_from_model(mc), profile=profile)} {v['requests']}")

    section("Cumulative input tokens", "counter", "nizam_llm_input_tokens_total")
    for (m, profile), v in totals.items():
        mc = clean_model(m)
        lines.append(f"nizam_llm_input_tokens_total{label(model=mc, provider=provider_from_model(mc), profile=profile)} {v['input_tokens']}")

    section("Cumulative output tokens", "counter", "nizam_llm_output_tokens_total")
    for (m, profile), v in totals.items():
        mc = clean_model(m)
        lines.append(f"nizam_llm_output_tokens_total{label(model=mc, provider=provider_from_model(mc), profile=profile)} {v['output_tokens']}")

    section("Cumulative LLM spend USD", "counter", "nizam_llm_spend_usd_total")
    for (m, profile), v in totals.items():
        mc = clean_model(m)
        lines.append(f"nizam_llm_spend_usd_total{label(model=mc, provider=provider_from_model(mc), profile=profile)} {v['spend']:.8f}")

    section("Cumulative cache read tokens", "counter", "nizam_llm_cache_read_tokens_total")
    for (m, profile), v in totals.items():
        mc = clean_model(m)
        lines.append(f"nizam_llm_cache_read_tokens_total{label(model=mc, profile=profile)} {v['cache_read']}")

    section("Cumulative cache creation tokens", "counter", "nizam_llm_cache_creation_tokens_total")
    for (m, profile), v in totals.items():
        mc = clean_model(m)
        lines.append(f"nizam_llm_cache_creation_tokens_total{label(model=mc, profile=profile)} {v['cache_create']}")

    section("LLM requests today", "gauge", "nizam_llm_requests_today")
    lines.append(f"nizam_llm_requests_today {today_req}")

    section("Input tokens today", "gauge", "nizam_llm_input_tokens_today")
    lines.append(f"nizam_llm_input_tokens_today {today_in}")

    section("Output tokens today", "gauge", "nizam_llm_output_tokens_today")
    lines.append(f"nizam_llm_output_tokens_today {today_out}")

    section("LLM spend USD today", "gauge", "nizam_llm_spend_usd_today")
    lines.append(f"nizam_llm_spend_usd_today {today_spend:.6f}")

    total_req = sum(v["requests"] for v in totals.values())
    total_cache_req = sum(1 for v in totals.values() if v["cache_read"] > 0)
    alltime_chr = (total_cache_req / total_req) if total_req > 0 else 0.0
    section("All-time cache hit rate (0.0–1.0)", "gauge", "nizam_llm_cache_hit_rate_alltime")
    lines.append(f"nizam_llm_cache_hit_rate_alltime {alltime_chr:.4f}")

    section("LLM spend USD this calendar month", "gauge", "nizam_llm_spend_usd_this_month")
    lines.append(f"nizam_llm_spend_usd_this_month {month_spend:.6f}")

    all_cache_read_by_model: dict = defaultdict(int)
    for (m, _profile), v in totals.items():
        all_cache_read_by_model[m] += v["cache_read"]

    def _calc_savings(cache_by_model: dict) -> float:
        s = 0.0
        for m, cr in cache_by_model.items():
            mc = clean_model(m)
            pricing = model_prices.get(mc) or model_prices.get(m)
            if not pricing:
                continue
            prompt_price = pricing.get("prompt")
            cache_read_price = pricing.get("cache_read")
            if prompt_price is not None and cache_read_price is not None:
                s += cr * (prompt_price - cache_read_price)
        return s

    section("Estimated USD saved via provider prompt cache today", "gauge", "nizam_llm_cache_savings_usd_today")
    lines.append(f"nizam_llm_cache_savings_usd_today {_calc_savings(today_cache_read_by_model):.6f}")

    section("Estimated USD saved via provider prompt cache all time", "gauge", "nizam_llm_cache_savings_usd_total")
    lines.append(f"nizam_llm_cache_savings_usd_total {_calc_savings(all_cache_read_by_model):.6f}")

    if latency_by_model:
        section("Average LLM response latency ms over last 1h by model", "gauge", "nizam_llm_avg_latency_ms_1h")
        for m, durations in latency_by_model.items():
            avg_ms = sum(durations) / len(durations)
            lines.append(f'nizam_llm_avg_latency_ms_1h{{model="{m}"}} {avg_ms:.1f}')

    TMP.write_text("\n".join(lines) + "\n")
    TMP.replace(OUT)
    OUT.chmod(0o644)
    log.info(
        "wrote %d series, today: %d req / %d+%d tok / $%.4f, month: $%.4f",
        len(totals), today_req, today_in, today_out, today_spend, month_spend,
    )


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Create systemd/metrics-llm.service**

```ini
[Unit]
Description=Write LLM spend metrics to Prometheus node-exporter textfile

[Service]
Type=oneshot
User=vazir
EnvironmentFile=/home/vazir/nizam-os/secrets/nizam-os.env
ExecStart=/home/vazir/.local/bin/uv run /home/vazir/nizam-os/scripts/metrics/metrics-llm.py
StandardOutput=append:/home/vazir/nizam-os/logs/metrics-llm.log
StandardError=append:/home/vazir/nizam-os/logs/metrics-llm.log

[Install]
WantedBy=multi-user.target
```

- [ ] **Step 3: Create systemd/metrics-llm.timer**

```ini
[Unit]
Description=Run LLM metrics collector every minute

[Timer]
OnCalendar=*:0/1
Persistent=true

[Install]
WantedBy=timers.target
```

- [ ] **Step 4: Create scripts/metrics/metrics-services.sh**

Reads `inventory/services.txt` (written by `watcher-inventory`) and emits per-service up/down gauges.

```bash
#!/usr/bin/env bash
# Write nizam-services.prom for Prometheus node-exporter.
# Runs every 5 min via metrics-services.timer.
# Reads inventory/services.txt written by watcher-inventory.
set -euo pipefail

NIZAM_OS="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_NAME="metrics-services"
source "$NIZAM_OS/scripts/shared/_log.sh"

SERVICES_FILE="$NIZAM_OS/inventory/services.txt"
OUT="/var/lib/prometheus/node-exporter/nizam-services.prom"
TMP="${OUT}.tmp"

if [ ! -f "$SERVICES_FILE" ]; then
    log_error "services.txt not found — skipping (run watcher-inventory.timer first)"
    exit 1
fi

total=0
up=0
metric_lines=()

while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    svc=$(echo "$line" | cut -d'|' -f1 | tr -d ' ')
    type=$(echo "$line" | cut -d'|' -f2 | tr -d ' ')
    status=$(echo "$line" | cut -d'|' -f3 | tr -d ' ')
    [[ -z "$svc" ]] && continue

    val=0
    [[ "$status" == "active" ]] && val=1

    metric_lines+=("nizam_service_up{service=\"${svc}\",type=\"${type}\"} ${val}")
    total=$((total + 1))
    up=$((up + val))
done < "$SERVICES_FILE"

{
    echo "# HELP nizam_service_up Service is active (1) or not (0)"
    echo "# TYPE nizam_service_up gauge"
    for m in "${metric_lines[@]}"; do
        echo "$m"
    done

    echo "# HELP nizam_services_total Total number of tracked services"
    echo "# TYPE nizam_services_total gauge"
    echo "nizam_services_total ${total}"

    echo "# HELP nizam_services_up_total Number of tracked services currently active"
    echo "# TYPE nizam_services_up_total gauge"
    echo "nizam_services_up_total ${up}"
} > "$TMP"

mv "$TMP" "$OUT"
chmod 644 "$OUT"
log_info "wrote ${up}/${total} services up"
```

- [ ] **Step 5: Create systemd/metrics-services.service**

```ini
[Unit]
Description=Write Prometheus metrics for tracked service health
After=network.target

[Service]
Type=oneshot
User=vazir
ExecStart=/bin/bash /home/vazir/nizam-os/scripts/metrics/metrics-services.sh
StandardOutput=append:/home/vazir/nizam-os/logs/metrics-services.log
StandardError=append:/home/vazir/nizam-os/logs/metrics-services.log

[Install]
WantedBy=multi-user.target
```

- [ ] **Step 6: Create systemd/metrics-services.timer**

```ini
[Unit]
Description=Run metrics-services every 5 minutes

[Timer]
OnCalendar=*:1/5
Persistent=true

[Install]
WantedBy=timers.target
```

- [ ] **Step 7: Create scripts/metrics/metrics-toolcalls.py**

Parses Hermes agent.log files across all profiles (including rotated files) and counts tool calls.

```python
#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""
Tool call metrics textfile writer for Prometheus node-exporter.
Runs every 5 min via metrics-toolcalls.timer.
Parses Hermes agent.log files across all profiles (including rotated .1/.2/.3).

Metrics written:
  nizam_tool_calls_total{profile,tool}
  nizam_tool_errors_total{profile,tool}
  nizam_tool_calls_today{profile,tool}
  nizam_tool_duration_seconds_total{profile,tool}
  nizam_tool_output_chars_total{profile,tool}
  nizam_tool_output_chars_today{profile,tool}
"""

import logging
import re
import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

logging.basicConfig(
    stream=sys.stdout,
    level=logging.INFO,
    format="%(asctime)s [%(levelname)-5s] [metrics-toolcalls] %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%SZ",
)
log = logging.getLogger("metrics-toolcalls")

HERMES_PROFILES = Path.home() / ".hermes" / "profiles"
OUT = Path("/var/lib/prometheus/node-exporter/nizam-toolcalls.prom")
TMP = OUT.with_suffix(".prom.tmp")

_RE_TOOL = re.compile(
    r"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}),\d+"
    r".*?agent\.tool_executor: [Tt]ool ([\w]+) "
    r"(completed|returned error)"
    r".*?\((\d+(?:\.\d+)?)s"
    r"(?:,\s*(\d+)\s*chars)?"
)


def parse_ts(ts_str: str) -> datetime | None:
    try:
        return datetime.strptime(ts_str, "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)
    except Exception:
        return None


def main() -> None:
    now = datetime.now(timezone.utc)
    today_midnight = now.replace(hour=0, minute=0, second=0, microsecond=0)

    counts: dict = defaultdict(lambda: defaultdict(
        lambda: {"calls": 0, "errors": 0, "duration_s": 0.0, "chars": 0}
    ))
    today: dict = defaultdict(lambda: defaultdict(lambda: {"calls": 0, "chars": 0}))

    if not HERMES_PROFILES.exists():
        log.warning("~/.hermes/profiles not found — no Hermes profiles yet")
    else:
        for profile_dir in sorted(HERMES_PROFILES.iterdir()):
            if not profile_dir.is_dir():
                continue
            profile = profile_dir.name
            agent_log = profile_dir / "logs" / "agent.log"
            if not agent_log.exists():
                continue

            candidates = sorted(
                agent_log.parent.glob(agent_log.name + "*"),
                key=lambda p: p.stat().st_mtime,
            )

            for path in candidates:
                if not path.is_file():
                    continue
                try:
                    for line in path.read_text(errors="replace").splitlines():
                        m = _RE_TOOL.match(line)
                        if not m:
                            continue
                        ts = parse_ts(m.group(1))
                        if ts is None:
                            continue
                        tool = m.group(2)
                        is_error = m.group(3) == "returned error"
                        duration_s = float(m.group(4))
                        chars = int(m.group(5)) if m.group(5) else 0
                        counts[profile][tool]["calls"] += 1
                        counts[profile][tool]["duration_s"] += duration_s
                        counts[profile][tool]["chars"] += chars
                        if is_error:
                            counts[profile][tool]["errors"] += 1
                        if ts >= today_midnight:
                            today[profile][tool]["calls"] += 1
                            today[profile][tool]["chars"] += chars
                except Exception as e:
                    log.warning("failed reading %s: %s", path, e)

    lines: list[str] = []

    def section(help_text: str, metric_type: str, name: str) -> None:
        lines.append(f"# HELP {name} {help_text}")
        lines.append(f"# TYPE {name} {metric_type}")

    section("Hermes tool calls across retained logs", "counter", "nizam_tool_calls_total")
    for profile, tools in sorted(counts.items()):
        for tool, v in sorted(tools.items()):
            lines.append(f'nizam_tool_calls_total{{profile="{profile}",tool="{tool}"}} {v["calls"]}')

    section("Hermes tool errors across retained logs", "counter", "nizam_tool_errors_total")
    for profile, tools in sorted(counts.items()):
        for tool, v in sorted(tools.items()):
            if v["errors"] > 0:
                lines.append(f'nizam_tool_errors_total{{profile="{profile}",tool="{tool}"}} {v["errors"]}')

    section("Hermes tool wall time seconds across retained logs", "counter", "nizam_tool_duration_seconds_total")
    for profile, tools in sorted(counts.items()):
        for tool, v in sorted(tools.items()):
            lines.append(f'nizam_tool_duration_seconds_total{{profile="{profile}",tool="{tool}"}} {v["duration_s"]:.3f}')

    section("Hermes tool output chars across retained logs", "counter", "nizam_tool_output_chars_total")
    for profile, tools in sorted(counts.items()):
        for tool, v in sorted(tools.items()):
            lines.append(f'nizam_tool_output_chars_total{{profile="{profile}",tool="{tool}"}} {v["chars"]}')

    section("Hermes tool calls since midnight UTC", "gauge", "nizam_tool_calls_today")
    for profile, tools in sorted(today.items()):
        for tool, v in sorted(tools.items()):
            lines.append(f'nizam_tool_calls_today{{profile="{profile}",tool="{tool}"}} {v["calls"]}')

    section("Hermes tool output chars since midnight UTC", "gauge", "nizam_tool_output_chars_today")
    for profile, tools in sorted(today.items()):
        for tool, v in sorted(tools.items()):
            lines.append(f'nizam_tool_output_chars_today{{profile="{profile}",tool="{tool}"}} {v["chars"]}')

    TMP.write_text("\n".join(lines) + "\n")
    TMP.replace(OUT)
    OUT.chmod(0o644)

    total_series = sum(len(t) for t in counts.values())
    log.info("wrote %d series across %d profiles", total_series, len(counts))


if __name__ == "__main__":
    main()
```

- [ ] **Step 8: Create systemd/metrics-toolcalls.service**

```ini
[Unit]
Description=Write Hermes tool call metrics to Prometheus node-exporter textfile

[Service]
Type=oneshot
User=vazir
ExecStart=/home/vazir/.local/bin/uv run /home/vazir/nizam-os/scripts/metrics/metrics-toolcalls.py
StandardOutput=append:/home/vazir/nizam-os/logs/metrics-toolcalls.log
StandardError=append:/home/vazir/nizam-os/logs/metrics-toolcalls.log

[Install]
WantedBy=multi-user.target
```

- [ ] **Step 9: Create systemd/metrics-toolcalls.timer**

```ini
[Unit]
Description=Run tool call metrics collector every 5 minutes

[Timer]
OnCalendar=*:3/5
Persistent=true

[Install]
WantedBy=timers.target
```

- [ ] **Step 10: Verify**

```bash
python3 -c "
import ast, pathlib
for f in ['scripts/metrics/metrics-llm.py', 'scripts/metrics/metrics-toolcalls.py']:
    ast.parse(pathlib.Path(f).read_text())
    print(f'{f}: OK')
"
bash -n scripts/metrics/metrics-services.sh && echo "metrics-services.sh: OK"
# Expected: 3 OK lines
```

---

## Task 8: Config files + symlinks installer + logrotate

**Files:**
- Create: `config/redis.conf`
- Create: `config/loki.yaml`
- Create: `config/promtail.yaml`
- Create: `config/logrotate.nizam-os`
- Create: `scripts/setup/install-symlinks.sh`

- [ ] **Step 1: Create config/redis.conf**

The `${REDIS_PASSWORD}` placeholder is substituted by `001-foundation.sh` using `envsubst` before copying to `/etc/redis/redis.conf`.

`save ""` disables RDB persistence — Redis is used as a pure cache. Without `dir` set, Redis tries to save RDB to `/` on shutdown and hangs; `save ""` prevents that. Use `stop → write config → start` pattern in foundation.sh, not `restart`, to avoid the shutdown hang.

```
bind 127.0.0.1
requirepass ${REDIS_PASSWORD}
maxmemory 256mb
maxmemory-policy allkeys-lru
dir /var/lib/redis
dbfilename dump.rdb
save ""
appendonly no
stop-writes-on-bgsave-error no
```

- [ ] **Step 2: Create config/loki.yaml**

```yaml
auth_enabled: false

server:
  http_listen_address: 127.0.0.1
  http_listen_port: 3100
  grpc_listen_port: 9096

common:
  instance_addr: 127.0.0.1
  path_prefix: /var/lib/loki
  storage:
    filesystem:
      chunks_directory: /var/lib/loki/chunks
      rules_directory: /var/lib/loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

limits_config:
  reject_old_samples: false
```

- [ ] **Step 3: Create config/promtail.yaml**

Tails all `logs/*.log` files. Python service logs carry a `service` key; bash script logs carry a `script` key. The pipeline extracts both — missing keys produce no label, so each log line gets the label that exists.

```yaml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /var/lib/promtail/positions.yaml

clients:
  - url: http://localhost:3100/loki/api/v1/push

scrape_configs:
  - job_name: nizam-os
    static_configs:
      - targets:
          - localhost
        labels:
          job: nizam-os
          host: nizam-vps
          __path__: /home/vazir/nizam-os/logs/*.log
    pipeline_stages:
      - json:
          expressions:
            level: level
            service: service
            script: script
      - labels:
          level:
          service:
          script:
```

- [ ] **Step 4: Create config/logrotate.nizam-os**

```
/home/vazir/nizam-os/logs/*.log {
    su vazir vazir
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 0644 vazir vazir
}
```

- [ ] **Step 5: Create scripts/setup/install-symlinks.sh**

Wires all repo files into system locations. Safe to re-run (ln -sf overwrites stale links). Called by `001-foundation.sh`.

```bash
#!/usr/bin/env bash
# Wire all nizam-os systemd files into system locations via symlinks.
# Run with: sudo bash scripts/setup/install-symlinks.sh
# Safe to re-run — ln -sf overwrites stale links.
set -euo pipefail

NIZAM_OS="$(cd "$(dirname "$0")/../.." && pwd)"

# Systemd system units
ln -sf "$NIZAM_OS/systemd/litellm-proxy.service"       /etc/systemd/system/litellm-proxy.service
ln -sf "$NIZAM_OS/systemd/watcher-env.service"         /etc/systemd/system/watcher-env.service
ln -sf "$NIZAM_OS/systemd/watcher-inventory.service"   /etc/systemd/system/watcher-inventory.service
ln -sf "$NIZAM_OS/systemd/watcher-inventory.timer"     /etc/systemd/system/watcher-inventory.timer
ln -sf "$NIZAM_OS/systemd/metrics-llm.service"         /etc/systemd/system/metrics-llm.service
ln -sf "$NIZAM_OS/systemd/metrics-llm.timer"           /etc/systemd/system/metrics-llm.timer
ln -sf "$NIZAM_OS/systemd/metrics-services.service"    /etc/systemd/system/metrics-services.service
ln -sf "$NIZAM_OS/systemd/metrics-services.timer"      /etc/systemd/system/metrics-services.timer
ln -sf "$NIZAM_OS/systemd/metrics-toolcalls.service"   /etc/systemd/system/metrics-toolcalls.service
ln -sf "$NIZAM_OS/systemd/metrics-toolcalls.timer"     /etc/systemd/system/metrics-toolcalls.timer

# Config files — copied not symlinked (root-owned daemons require root-owned files)
# logrotate
cp "$NIZAM_OS/config/logrotate.nizam-os" /etc/logrotate.d/nizam-os
chown root:root /etc/logrotate.d/nizam-os
chmod 644 /etc/logrotate.d/nizam-os

# Loki + Promtail (apt-installed services read from /etc/<service>/)
mkdir -p /etc/loki /etc/promtail
cp "$NIZAM_OS/config/loki.yaml" /etc/loki/config.yaml
cp "$NIZAM_OS/config/promtail.yaml" /etc/promtail/config.yaml
chown root:root /etc/loki/config.yaml /etc/promtail/config.yaml
chmod 644 /etc/loki/config.yaml /etc/promtail/config.yaml

# Redis — substitute password placeholder before copying
if [ -n "${REDIS_PASSWORD:-}" ]; then
    envsubst '${REDIS_PASSWORD}' < "$NIZAM_OS/config/redis.conf" > /etc/redis/redis.conf
    chown redis:redis /etc/redis/redis.conf 2>/dev/null || chown root:root /etc/redis/redis.conf
    chmod 640 /etc/redis/redis.conf
    echo "  redis.conf written"
else
    echo "  WARNING: REDIS_PASSWORD not set — redis.conf not written. Source nizam-os.env first."
fi

systemctl daemon-reload
echo "  reloaded system daemon"

# Hermes user units and profile symlinks are Phase 2 — not wired here.

echo ""
echo "Symlinks installed:"
ls -la \
    /etc/systemd/system/litellm-proxy.service \
    /etc/systemd/system/watcher-env.service \
    /etc/systemd/system/watcher-inventory.service \
    /etc/systemd/system/watcher-inventory.timer \
    /etc/systemd/system/metrics-llm.service \
    /etc/systemd/system/metrics-llm.timer \
    /etc/systemd/system/metrics-services.service \
    /etc/systemd/system/metrics-services.timer \
    /etc/systemd/system/metrics-toolcalls.service \
    /etc/systemd/system/metrics-toolcalls.timer

echo ""
echo "Grafana manual step (after 001-foundation.sh):"
echo "  Datasource 1: Prometheus @ http://localhost:9090, uid=nizam-prometheus"
echo "  Datasource 2: Loki @ http://localhost:3100, uid=nizam-loki"
echo "  Dashboard: docs/grafana/personal-dashboard.json"
echo "  (Business dashboard is Phase 8 scope)"
```

- [ ] **Step 6: Verify**

```bash
bash -n scripts/setup/install-symlinks.sh && echo "install-symlinks.sh: OK"
python3 -c "import yaml; yaml.safe_load(open('config/loki.yaml'))" && echo "loki.yaml: OK"
python3 -c "import yaml; yaml.safe_load(open('config/promtail.yaml'))" && echo "promtail.yaml: OK"
ls config/redis.conf config/logrotate.nizam-os && echo "other configs: OK"
# Expected: 4 OK lines
```

---

## Task 9: `001-foundation.sh` — main entry point

**Files:**
- Create: `scripts/setup/001-foundation.sh`

This is the single command that builds Phase 1 from a fresh Ubuntu 24.04 machine (after nizam-dotfiles is done). Every block is idempotent — safe to re-run after partial failure.

Key deviations from original plan (found during VPS debugging):
- **Version pins** at top (`SOPS_VERSION`, `DBMATE_VERSION`, `PGSEARCH_VERSION`, `LITELLM_VERSION`) — reproducible rebuilds
- **Pre-step** installs sops + dbmate as pinned binaries from GitHub releases (packagecloud returned 402 for ParadeDB)
- **ParadeDB** installed via direct .deb from GitHub releases, not packagecloud
- **Redis**: `stop → write config → start` not `restart` — avoids RDB-save hang on shutdown
- **PostgreSQL before LiteLLM** — `prisma db push` needs `svc_litellm` role + `litellm` schema from `setup-db.sh`
- **dbmate** for migrations (not `psql -f`)
- **Output**: colored human-readable (`_step`/`_ok`/`_note`/`_err`) not JSON log lines

- [ ] **Step 1: Create scripts/setup/001-foundation.sh**

```bash
#!/usr/bin/env bash
# Idempotent Phase 1 foundation setup for nizam-os.
# Prerequisite: ~/nizam-dotfiles/scripts/setup/001-machine-setup.sh complete.
#
# Rebuild (reusing encrypted creds):
#   git clone <repo> ~/nizam-os
#   cp <backup>/nizam-age-key.txt ~/nizam-os/secrets/nizam-age-key.txt
#   sudo bash ~/nizam-os/scripts/setup/001-foundation.sh
#
# Fresh (new creds):
#   git clone <repo> ~/nizam-os
#   sudo apt-get install -y age
#   age-keygen -o ~/nizam-os/secrets/nizam-age-key.txt
#   chmod 600 ~/nizam-os/secrets/nizam-age-key.txt
#   cp ~/nizam-os/secrets/nizam-os.env.example ~/nizam-os/secrets/nizam-os.env
#   nano ~/nizam-os/secrets/nizam-os.env   # fill all values
#   sudo bash ~/nizam-os/scripts/setup/001-foundation.sh
set -euo pipefail

# Pinned tool versions — bump here when upgrading
SOPS_VERSION="v3.13.2"
DBMATE_VERSION="v2.33.0"
PGSEARCH_VERSION="v0.24.1"
LITELLM_VERSION="1.91.0"

VAZIR_HOME="/home/vazir"
NIZAM_OS="$VAZIR_HOME/nizam-os"

BLD='\033[1m'
CYN='\033[36m'
GRN='\033[32m'
YLW='\033[33m'
RED='\033[31m'
RST='\033[0m'

_step() { printf "\n${BLD}${CYN}==> %s${RST}\n" "$*"; }
_ok()   { printf "${GRN}  %s${RST}\n" "$*"; }
_note() { printf "${YLW}  %s${RST}\n" "$*"; }
_err()  { printf "${RED}  ERROR: %s${RST}\n" "$*" >&2; }

if [ "$EUID" -ne 0 ]; then
    echo "Run with: sudo bash scripts/setup/001-foundation.sh" >&2
    exit 1
fi

printf "${BLD}${CYN}==> Phase 1 foundation setup${RST}\n"

# Pre-step: cryptography + migration tools (needed before secrets check)
_step "Cryptography and migration tools"
apt-get install -y -q age gettext-base

if ! command -v sops &>/dev/null; then
    curl -fsSL -o /usr/local/bin/sops \
        "https://github.com/getsops/sops/releases/download/${SOPS_VERSION}/sops-${SOPS_VERSION}.linux.amd64"
    chmod +x /usr/local/bin/sops
    _ok "sops ${SOPS_VERSION} installed"
else
    _ok "sops already installed"
fi

if ! command -v dbmate &>/dev/null; then
    curl -fsSL -o /usr/local/bin/dbmate \
        "https://github.com/amacneil/dbmate/releases/download/${DBMATE_VERSION}/dbmate-linux-amd64"
    chmod +x /usr/local/bin/dbmate
    _ok "dbmate ${DBMATE_VERSION} installed"
else
    _ok "dbmate already installed"
fi

_ok "age and gettext-base ready"

# Step 1: Secrets — detect fresh vs rebuild
_step "Secrets"
ENC="$NIZAM_OS/secrets/nizam-os.env.enc"
ENV="$NIZAM_OS/secrets/nizam-os.env"
AGE_KEY="$NIZAM_OS/secrets/nizam-age-key.txt"

if [ -f "$AGE_KEY" ]; then
    chmod 600 "$AGE_KEY"
fi

if [ -f "$ENV" ]; then
    _note "using existing nizam-os.env"
elif [ -f "$ENC" ] && [ -f "$AGE_KEY" ]; then
    _note "no nizam-os.env found — decrypting from nizam-os.env.enc"
    sudo -u vazir bash "$NIZAM_OS/scripts/env/decrypt-env.sh"
else
    _err "no secrets found"
    _err "rebuild: restore nizam-age-key.txt + nizam-os.env.enc, then decrypt manually"
    _err "fresh:   copy nizam-os.env.example → nizam-os.env and fill values"
    exit 1
fi

required_vars=(OPENROUTER_API_KEY LITELLM_MASTER_KEY POSTGRES_SVC_LITELLM_PASS LITELLM_DB_URL REDIS_URL REDIS_PASSWORD)
missing=()
for var in "${required_vars[@]}"; do
    val=$(grep "^${var}=" "$ENV" 2>/dev/null | cut -d= -f2- || true)
    [ -z "$val" ] && missing+=("$var")
done

if [ ${#missing[@]} -gt 0 ]; then
    _err "missing values in nizam-os.env: ${missing[*]}"
    _err "fill them in and re-run"
    exit 1
fi

set -a
# shellcheck source=/dev/null
source "$ENV"
set +a
_ok "secrets loaded"

# Step 2: System packages
_step "System packages"
apt-get install -y -q \
    postgresql postgresql-client postgresql-contrib \
    redis-server \
    inotify-tools
_ok "done"

# Step 3: pgvector
_step "pgvector"
apt-get install -y -q postgresql-16-pgvector
_ok "done"

# Step 4: ParadeDB (pg_search) — pinned via PGSEARCH_VERSION
# Uses direct .deb from GitHub releases (packagecloud returns 402)
_step "ParadeDB pg_search"
if ! dpkg -l postgresql-16-pg-search &>/dev/null; then
    PGSEARCH_DEB="postgresql-16-pg-search_${PGSEARCH_VERSION#v}-1PARADEDB-noble_amd64.deb"
    curl -fsSL -o /tmp/pg-search.deb \
        "https://github.com/paradedb/paradedb/releases/download/${PGSEARCH_VERSION}/${PGSEARCH_DEB}"
    apt-get install -y -q /tmp/pg-search.deb
    rm /tmp/pg-search.deb
    _ok "installed ${PGSEARCH_VERSION}"
else
    _ok "already installed"
fi

# Step 5: Redis
# stop → write config → start avoids RDB-save hang that occurs on restart
_step "Redis"
systemctl enable redis-server
systemctl stop redis-server 2>/dev/null || true
envsubst '${REDIS_PASSWORD}' < "$NIZAM_OS/config/redis.conf" > /etc/redis/redis.conf
chown redis:redis /etc/redis/redis.conf 2>/dev/null || chown root:root /etc/redis/redis.conf
chmod 640 /etc/redis/redis.conf
systemctl start redis-server
_ok "configured and started"

# Step 6: nizam-os Promtail config
# Loki is managed by nizam-dotfiles (port 3100). This copies the config for a
# separate promtail-nizam-os.service (symlinked in step 11) that scrapes
# ~/nizam-os/logs/ without touching dotfiles promtail.
_step "nizam-os Promtail config"
mkdir -p /etc/promtail
cp "$NIZAM_OS/config/promtail.yaml" /etc/promtail/promtail-nizam-os.yaml
chmod 644 /etc/promtail/promtail-nizam-os.yaml
_ok "config deployed to /etc/promtail/promtail-nizam-os.yaml"

# Step 7: PostgreSQL
# Must run before LiteLLM — prisma db push needs svc_litellm role + litellm schema
_step "PostgreSQL"
systemctl enable postgresql
systemctl start postgresql

PG_CONF="/etc/postgresql/16/main/postgresql.conf"
if ! grep -q "pg_search" "$PG_CONF"; then
    echo "shared_preload_libraries = 'pg_search'" >> "$PG_CONF"
    systemctl restart postgresql
    _note "pg_search added to shared_preload_libraries — restarted"
fi

sudo -u postgres psql -c "DO \$\$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'vazir') THEN
    CREATE USER vazir SUPERUSER;
  END IF;
END \$\$;" > /dev/null
_ok "vazir superuser role ready"

POSTGRES_SVC_LITELLM_PASS="$POSTGRES_SVC_LITELLM_PASS" \
    bash "$NIZAM_OS/scripts/setup/setup-db.sh"
_ok "database ready"

# Step 8: uv + LiteLLM
# Runs after PostgreSQL so prisma db push can connect to svc_litellm/litellm schema
_step "uv + LiteLLM"
if ! sudo -u vazir bash -c 'command -v uv >/dev/null 2>&1'; then
    sudo -u vazir bash -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'
    _ok "uv installed"
else
    _ok "uv already installed"
fi
sudo -u vazir bash -c "PATH=\"\$HOME/.local/bin:\$PATH\" uv tool install --with prisma 'litellm[proxy]==${LITELLM_VERSION}'"
LITELLM_BIN="$VAZIR_HOME/.local/share/uv/tools/litellm/bin"
SCHEMA="$VAZIR_HOME/.local/share/uv/tools/litellm/lib/python3.12/site-packages/litellm/proxy/schema.prisma"
sudo -u vazir bash -c "PATH=\"${LITELLM_BIN}:\$PATH\" DATABASE_URL=\"${LITELLM_DB_URL}\" prisma generate --schema='${SCHEMA}'"
sudo -u vazir bash -c "PATH=\"${LITELLM_BIN}:\$PATH\" DATABASE_URL=\"${LITELLM_DB_URL}\" prisma db push --schema='${SCHEMA}' --accept-data-loss"
_ok "litellm ${LITELLM_VERSION} installed"

# Step 9: Database migrations (dbmate)
_step "Database migrations"
sudo -u vazir bash -c "cd '$NIZAM_OS' && \
    DATABASE_URL='postgresql:///nizam?host=/var/run/postgresql' \
    dbmate --no-dump-schema -d db/migrations up"
_ok "migrations applied"

# Step 10: Prometheus textfile dir
_step "Prometheus textfile directory"
mkdir -p /var/lib/prometheus/node-exporter
chown vazir:vazir /var/lib/prometheus/node-exporter
_ok "done"

# Step 11: Symlinks
_step "Installing symlinks"
bash "$NIZAM_OS/scripts/setup/install-symlinks.sh"

systemctl daemon-reload
systemctl enable --now promtail-nizam-os.service
_ok "promtail-nizam-os started (pushes to dotfiles Loki at :3100)"

# Step 12: Encrypt secrets
_step "Encrypt secrets"
if [ ! -f "$ENC" ]; then
    sudo -u vazir bash "$NIZAM_OS/scripts/env/encrypt-env.sh"
    _ok "nizam-os.env.enc created — commit this file"
else
    _ok "already encrypted"
fi

# Step 13: Phase 1 systemd units
_step "Enabling Phase 1 units"
systemctl enable --now \
    watcher-env.service \
    watcher-inventory.timer \
    metrics-llm.timer \
    metrics-services.timer \
    metrics-toolcalls.timer
systemctl enable litellm-proxy.service
systemctl start litellm-proxy.service
_ok "done"

# Step 14: Wait for LiteLLM
_step "Waiting for LiteLLM (up to 60s)"
for i in $(seq 1 30); do
    if curl -sf http://localhost:4000/health/liveliness >/dev/null 2>&1; then
        _ok "LiteLLM is up"
        break
    fi
    sleep 2
    if [ "$i" -eq 30 ]; then
        _err "LiteLLM did not come up in 60s"
        _err "check: journalctl -u litellm-proxy -n 50"
        exit 1
    fi
done

# Step 15: Confirm Loki reachable (managed by dotfiles)
_step "Confirming Loki reachable (up to 30s)"
for i in $(seq 1 15); do
    if curl -sf http://localhost:3100/ready >/dev/null 2>&1; then
        _ok "Loki is up at :3100"
        break
    fi
    sleep 2
    if [ "$i" -eq 15 ]; then
        _err "Loki not reachable at :3100"
        _err "check: systemctl status loki && journalctl -u loki -n 30"
        exit 1
    fi
done

printf "\n${BLD}${CYN}====================================================================================${RST}\n"
printf "${BLD}${GRN}Phase 1 foundation complete.${RST}\n"
printf "\n${BLD}Manual steps remaining:${RST}\n"
printf "  1. Open Grafana: http://<tailscale-ip>:3000\n"
printf "  2. Connections → Data Sources → Add → Prometheus\n"
printf "       URL: http://localhost:9090  |  UID: nizam-prometheus\n"
printf "  3. Connections → Data Sources → Add → Loki\n"
printf "       URL: http://localhost:3100  |  UID: nizam-loki\n"
printf "  4. Dashboards → Import → grafana/001-personal-dashboard.json\n"
printf "${BLD}${CYN}====================================================================================${RST}\n"
```

- [ ] **Step 2: Verify syntax**

```bash
bash -n scripts/setup/001-foundation.sh && echo "001-foundation.sh: OK"
# Expected: 001-foundation.sh: OK
```

---

## Self-Review Checklist

**Spec coverage:**

| Spec section | Covered in |
|-------------|-----------|
| Delivery model (fresh vs rebuild) + password gen | Task 9: 001-foundation.sh; Task 1: Step 3 |
| Secrets (sops+age, watcher, example) | Tasks 1, 2 |
| nizam-os.env Phase 1 vars (6 vars) | Task 1: nizam-os.env.example |
| PostgreSQL 16 + pgvector + pg_search | Task 9: Steps 3, 4, 8 |
| setup-db.sh idempotent | Task 3 |
| 001_audit_schema.sql | Task 3 |
| audit.log columns + append-only | Task 3 |
| Redis config file (config/redis.conf, envsubst) | Task 8: Steps 1, 5 |
| Loki (port 3100, local storage, config/loki.yaml) | Task 8: Step 2 |
| Promtail (config/promtail.yaml, JSON pipeline) | Task 8: Step 3 |
| LiteLLM config (gemini-embedding-2, wildcard, cache, store_end_user) | Task 5 |
| Uniform logging — Python JSON (service/module/func) | Task 4 |
| Uniform logging — bash JSON (_log.sh) | Task 2: Step 1 |
| StandardOutput=append for all units | Tasks 5, 6, 7 |
| nizam-shared ServiceBase refactor (POSTGRES_DSN) | Task 4 |
| AuditLogger refactor (audit.log, generic schema) | Task 4 |
| Systemd units (all 8 Phase 1 units + loki + promtail) | Tasks 5, 6, 7 |
| install-symlinks.sh (units + redis/loki/promtail configs) | Task 8: Step 5 |
| logrotate (daily, 14 days, compress) | Task 8: Step 4 |
| Prometheus textfile dir owned by vazir | Task 9: Step 10 |
| Loki + Promtail install + health check | Task 9: Steps 6, 15 |
| Exit criteria (incl. Loki check) | Task 9: Step 1 (printed at end) |
| Grafana manual steps (Prometheus + Loki datasources) | Task 9: Step 1 (printed at end) |
| metrics-llm.py | Task 7 |
| metrics-toolcalls.py | Task 7 |
| metrics-services.sh | Task 7 |
| docs/grafana/ for dashboard JSON | Task 1: Step 3 |

**DSN pattern:** `POSTGRES_DSN` env var in ServiceBase, set via ExecStart wrapper in each service's systemd unit. The wrapper pattern looks like:
```ini
ExecStart=/bin/sh -c 'POSTGRES_DSN=$POSTGRES_DSN_KNOWLEDGE exec uv run ...'
```
This wrapper is NOT included here — it belongs in each service's own phase plan (Phase 4 for knowledge-service, Phase 5 for finance/personal-service). Phase 1 has no MCP services active.

**metrics-toolcalls.service** no longer has `EnvironmentFile` — it parses log files and needs no env vars from `nizam-os.env`. Removed.

**tracked-services.txt** excludes `watcher-hermes-profile.service` and all `hermes-gateway-*` units — those are Phase 2.

---

## Execution

Plan complete and saved to `docs/plans/001-foundation.md`.

**To execute:** `sudo bash scripts/setup/001-foundation.sh`

Run from `~/nizam-os/` after the fresh git clone on the new VPS. The script is the plan — no further interpretation needed.

**Phase 2 plan** covers: Hermes install, Discord server + bot tokens, all Hermes profile configs, LiteLLM virtual keys per agent, sudoers entry for Nazim, watcher-hermes-profile user service, hermes gateway services.