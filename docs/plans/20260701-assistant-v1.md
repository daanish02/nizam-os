# Assistant v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build two new MCP services (personal-service and finance-service), run DB migrations to create the personal and audit schemas, fix shared library parameterization, and configure Ayah's profile to connect to both services.

**Architecture:** `ServiceBase` in `nizam-shared` is parameterized with `db_role` and `db_pass_env` (backwards-compatible defaults). `personal-service` owns habits, goals, tasks, and journal (all in the `personal` schema). `finance-service` owns personal transactions in the `finance` schema and exposes FX conversion and zakat calculation. Both run as standalone HTTP MCP services. Ayah's profile connects via `url:` with `tools.include` filters so she sees only her tool set — finance-service business tools (future Hala scope) are excluded at the MCP filter level.

**Tech Stack:** FastMCP, psycopg3 (via nizam-shared), httpx (for FX and gold APIs), Python 3.12, PostgreSQL, systemd.

## Global Constraints

- **Never run `git commit`** — user commits manually.
- `ServiceBase` changes must be backwards-compatible: `knowledge-service` must not require any changes to keep working.
- `personal-service` runs on port `8102`. `finance-service` runs on port `8101`.
- Migration files run as the postgres superuser. Passwords are never in SQL files — role creation uses a separate VPS step with env vars.
- `svc_personal` role accesses `personal.*` + `finance.personal_transactions`. `svc_finance_personal` accesses `finance.personal_transactions` only (no personal schema reads).
- Both new roles also get `INSERT` on `audit.log` (from `audit` schema, created in `0003_audit_schema.sql`).
- `POSTGRES_SVC_PERSONAL_PASS` maps to `svc_personal`. `POSTGRES_SVC_FINANCE_PERSONAL_PASS` maps to `svc_finance_personal`.
- FX API calls are cached with a short TTL to avoid hitting rate limits (httpx, no extra library needed — just cache in a module-level dict with timestamp).
- Prerequisite: Plan 1 (immediate fixes) complete. Prerequisite: Plans 2 + 3 are independent — can run after Plan 1.

---

## File Map

**Modified:**
- `services/shared/nizam_shared/base.py` — add `db_role`, `db_pass_env` params (backwards compat)
- `services/shared/nizam_shared/audit.py` — add `write_audit_log()` standalone function
- `secrets/nizam.env.example` — add 4 new env vars
- `hermes/profiles/assistant/config.yaml` — MCP urls, disabled_toolsets, allowed_channels, channel_prompts

**Created:**
- `db/migrations/0002_personal_schema.sql` — personal + finance.personal_transactions tables
- `db/migrations/0003_audit_schema.sql` — audit.log table
- `services/personal-service/pyproject.toml`
- `services/personal-service/server.py`
- `services/personal-service/tests/__init__.py`
- `services/personal-service/tests/test_server.py`
- `services/finance-service/pyproject.toml`
- `services/finance-service/server.py`
- `services/finance-service/tests/__init__.py`
- `services/finance-service/tests/test_server.py`
- `systemd/personal-service.service`
- `systemd/finance-service.service`

**VPS (not in repo):**
- Run `0002_personal_schema.sql` and `0003_audit_schema.sql`
- Create DB users with passwords from env
- Grant schema permissions
- Install + enable systemd units
- Enable Ayah gateway

---

## Task 1: Add env vars to nizam.env.example

**Files:**
- Modify: `secrets/nizam.env.example`

- [ ] **Step 1: Append new vars**

In `secrets/nizam.env.example`, append:
```
POSTGRES_SVC_PERSONAL_PASS=
POSTGRES_SVC_FINANCE_PERSONAL_PASS=
FX_API_KEY=
GOLD_API_KEY=
```

- [ ] **Step 2: Verify**

```bash
grep "SVC_PERSONAL\|SVC_FINANCE_PERSONAL\|FX_API_KEY\|GOLD_API_KEY" secrets/nizam.env.example
```
Expected: 4 lines found.

---

## Task 2: Parameterize ServiceBase

**Files:**
- Modify: `services/shared/nizam_shared/base.py`

Current `ServiceBase.__init__` hardcodes `svc_knowledge` and `POSTGRES_SVC_KNOWLEDGE_PASS`. Finance and personal services need different roles.

- [ ] **Step 1: Read the current implementation**

Read `services/shared/nizam_shared/base.py` to confirm exact current signature before editing.

- [ ] **Step 2: Add db_role and db_pass_env parameters**

Find the `__init__` signature (currently: `def __init__(self, name: str) -> None:`). Replace:
```python
def __init__(self, name: str) -> None:
    pg_pass = os.environ["POSTGRES_SVC_KNOWLEDGE_PASS"]
    self.dsn = f"postgresql://svc_knowledge:{pg_pass}@{pg_host}:{pg_port}/{pg_db}"
```
with:
```python
def __init__(
    self,
    name: str,
    db_role: str = "svc_knowledge",
    db_pass_env: str = "POSTGRES_SVC_KNOWLEDGE_PASS",
) -> None:
    pg_pass = os.environ[db_pass_env]
    self.dsn = f"postgresql://{db_role}:{pg_pass}@{pg_host}:{pg_port}/{pg_db}"
```

- [ ] **Step 3: Verify knowledge-service still works (no change needed)**

```bash
cd services/knowledge-service && uv run python -c "from nizam_shared.base import ServiceBase; ServiceBase('test')"
```
Expected: exits without error (or KeyError if env var not set — that's fine, means the import works).

---

## Task 3: Add write_audit_log to audit.py

**Files:**
- Modify: `services/shared/nizam_shared/audit.py`

The existing `AuditLogger.log` writes to `knowledge.vault_audit`. New services need to write to `audit.log` in the `audit` schema. Add a standalone function (not a method) so services call it with their own connection.

- [ ] **Step 1: Read the current implementation**

Read `services/shared/nizam_shared/audit.py` to see imports and exact structure.

- [ ] **Step 2: Add import and standalone function**

At the top of `audit.py`, ensure `import json` is present. Then at the end of the file, add:

```python
def write_audit_log(
    conn,
    *,
    schema_name: str,
    table_name: str,
    operation: str,
    actor: str,
    row_id: str | None = None,
    before_state: dict | None = None,
    after_state: dict | None = None,
) -> None:
    """Write a record to audit.log (shared append-only audit table).

    conn: open psycopg connection with INSERT permission on audit.log.
    operation: 'INSERT' | 'UPDATE' | 'DELETE'
    actor: agent profile name (e.g. 'assistant', 'finance')
    """
    conn.execute(
        """
        INSERT INTO audit.log
            (schema_name, table_name, operation, actor, row_id, before_state, after_state)
        VALUES (%s, %s, %s, %s, %s, %s, %s)
        """,
        (
            schema_name,
            table_name,
            operation,
            actor,
            row_id,
            json.dumps(before_state) if before_state else None,
            json.dumps(after_state) if after_state else None,
        ),
    )
```

- [ ] **Step 3: Verify import still works**

```bash
cd services/knowledge-service && uv run python -c "from nizam_shared.audit import AuditLogger, write_audit_log; print('ok')"
```
Expected: `ok`

---

## Task 4: Write database migrations

**Files:**
- Create: `db/migrations/0002_personal_schema.sql`
- Create: `db/migrations/0003_audit_schema.sql`

- [ ] **Step 1: Verify migrations directory exists**

```bash
ls db/migrations/ 2>/dev/null || (ls db/ 2>/dev/null && echo "no migrations subdir") || echo "no db dir"
```
Note the result — create the directory structure if needed.

- [ ] **Step 2: Create migrations directory if missing**

```bash
mkdir -p db/migrations
```

- [ ] **Step 3: Write 0002_personal_schema.sql**

Create `db/migrations/0002_personal_schema.sql`:

```sql
-- 0002_personal_schema.sql
-- Personal data: habits, goals, tasks, journal, personal finance transactions.
-- Run as postgres superuser. Role creation done separately (see plan Task 9).

BEGIN;

CREATE SCHEMA IF NOT EXISTS personal;
CREATE SCHEMA IF NOT EXISTS finance;

-- Habits: define recurring practices
CREATE TABLE IF NOT EXISTS personal.habits (
    id          SERIAL PRIMARY KEY,
    name        TEXT NOT NULL UNIQUE,
    frequency   TEXT NOT NULL DEFAULT 'daily',  -- daily | weekly
    unit        TEXT NOT NULL DEFAULT 'times',
    goal_count  NUMERIC NOT NULL DEFAULT 1,
    active      BOOLEAN NOT NULL DEFAULT true,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Habit logs: occurrence records
CREATE TABLE IF NOT EXISTS personal.habit_logs (
    id         SERIAL PRIMARY KEY,
    habit_id   INTEGER NOT NULL REFERENCES personal.habits(id),
    value      NUMERIC NOT NULL DEFAULT 1,
    logged_for DATE NOT NULL,
    logged_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS habit_logs_habit_date
    ON personal.habit_logs (habit_id, logged_for);

-- Goals: medium-term objectives
CREATE TABLE IF NOT EXISTS personal.goals (
    id          SERIAL PRIMARY KEY,
    title       TEXT NOT NULL,
    description TEXT,
    target_date DATE,
    status      TEXT NOT NULL DEFAULT 'active',  -- active | completed | paused
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Tasks: discrete steps toward a goal
CREATE TABLE IF NOT EXISTS personal.tasks (
    id         SERIAL PRIMARY KEY,
    goal_id    INTEGER REFERENCES personal.goals(id),
    title      TEXT NOT NULL,
    due_date   DATE,
    status     TEXT NOT NULL DEFAULT 'pending',  -- pending | done | cancelled
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS tasks_goal_id ON personal.tasks (goal_id);
CREATE INDEX IF NOT EXISTS tasks_status ON personal.tasks (status, due_date);

-- Journal: dated text entries with optional mood
CREATE TABLE IF NOT EXISTS personal.journal (
    id         SERIAL PRIMARY KEY,
    content    TEXT NOT NULL,
    mood       TEXT,  -- great | good | neutral | low | rough
    entry_date DATE NOT NULL DEFAULT CURRENT_DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS journal_date ON personal.journal (entry_date DESC);

-- Personal transactions: income and expenses
CREATE TABLE IF NOT EXISTS finance.personal_transactions (
    id          SERIAL PRIMARY KEY,
    amount      NUMERIC(12, 2) NOT NULL,
    currency    CHAR(3) NOT NULL DEFAULT 'AED',
    type        TEXT NOT NULL,  -- income | expense
    category    TEXT NOT NULL,
    description TEXT,
    txn_date    DATE NOT NULL DEFAULT CURRENT_DATE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS fin_personal_txn_date
    ON finance.personal_transactions (txn_date DESC);
CREATE INDEX IF NOT EXISTS fin_personal_category
    ON finance.personal_transactions (category, txn_date DESC);

COMMIT;
```

- [ ] **Step 4: Write 0003_audit_schema.sql**

Create `db/migrations/0003_audit_schema.sql`:

```sql
-- 0003_audit_schema.sql
-- Shared append-only audit log. All services write here with their own role.
-- Run as postgres superuser after 0002.

BEGIN;

CREATE SCHEMA IF NOT EXISTS audit;

CREATE TABLE IF NOT EXISTS audit.log (
    id           BIGSERIAL PRIMARY KEY,
    schema_name  TEXT NOT NULL,
    table_name   TEXT NOT NULL,
    operation    TEXT NOT NULL,  -- INSERT | UPDATE | DELETE
    actor        TEXT NOT NULL,  -- agent profile name
    row_id       TEXT,
    before_state JSONB,
    after_state  JSONB,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS audit_log_schema_table
    ON audit.log (schema_name, table_name, created_at DESC);
CREATE INDEX IF NOT EXISTS audit_log_actor
    ON audit.log (actor, created_at DESC);

-- Prevent UPDATE and DELETE on audit.log (append-only enforcement)
CREATE OR REPLACE RULE audit_no_update AS ON UPDATE TO audit.log DO INSTEAD NOTHING;
CREATE OR REPLACE RULE audit_no_delete AS ON DELETE TO audit.log DO INSTEAD NOTHING;

COMMIT;
```

- [ ] **Step 5: Verify file count**

```bash
ls db/migrations/000*.sql
```
Expected: 0001, 0002, 0003 (at minimum).

---

## Task 5: Write personal-service

**Files:**
- Create: `services/personal-service/pyproject.toml`
- Create: `services/personal-service/server.py`
- Create: `services/personal-service/tests/__init__.py`
- Create: `services/personal-service/tests/test_server.py`

### Step 5a: Write failing tests first

- [ ] **Step 1: Write pyproject.toml**

Create `services/personal-service/pyproject.toml`:

```toml
[project]
name = "personal-service"
version = "0.1.0"
requires-python = ">=3.12"
dependencies = [
    "nizam-shared",
    "fastmcp>=2.0",
]

[tool.uv.sources]
nizam-shared = { workspace = true }
```

- [ ] **Step 2: Write tests/__init__.py**

Create `services/personal-service/tests/__init__.py` (empty).

- [ ] **Step 3: Write tests/test_server.py**

Create `services/personal-service/tests/test_server.py`:

```python
"""Tests for personal-service MCP tools.

All DB calls are mocked — tests verify tool logic and return shape, not SQL.
"""

from unittest.mock import MagicMock, patch

import pytest


@pytest.fixture
def mock_svc():
    svc = MagicMock()
    return svc


# ---------------------------------------------------------------------------
# add_habit
# ---------------------------------------------------------------------------

def test_add_habit_returns_id(mock_svc):
    from server import add_habit

    row = {"id": 1, "name": "Reading", "frequency": "daily", "goal_count": 30, "unit": "minutes"}
    mock_svc.fetchone.return_value = row

    with patch("server.svc", mock_svc):
        result = add_habit(name="Reading", frequency="daily", goal_count=30, unit="minutes")

    assert result["id"] == 1
    assert result["name"] == "Reading"


def test_add_habit_validates_frequency(mock_svc):
    from server import add_habit

    with patch("server.svc", mock_svc):
        result = add_habit(name="Test", frequency="hourly", goal_count=1, unit="times")

    assert "error" in result
    assert "frequency" in result["error"].lower()


# ---------------------------------------------------------------------------
# log_habit
# ---------------------------------------------------------------------------

def test_log_habit_success(mock_svc):
    from server import log_habit

    mock_svc.fetchone.side_effect = [
        {"id": 1, "name": "Reading", "goal_count": 30},  # habit lookup
        {"habit_id": 1, "value": 25, "logged_for": "2026-07-01"},  # insert result
    ]

    with patch("server.svc", mock_svc):
        result = log_habit(habit_name="Reading", value=25)

    assert "error" not in result
    assert result["status"] == "logged"


def test_log_habit_unknown_name(mock_svc):
    from server import log_habit

    mock_svc.fetchone.return_value = None  # habit not found

    with patch("server.svc", mock_svc):
        result = log_habit(habit_name="Nonexistent", value=1)

    assert "error" in result
    assert "not found" in result["error"].lower()


# ---------------------------------------------------------------------------
# add_goal
# ---------------------------------------------------------------------------

def test_add_goal_returns_id(mock_svc):
    from server import add_goal

    mock_svc.fetchone.return_value = {"id": 3, "title": "Read 24 books", "status": "active"}

    with patch("server.svc", mock_svc):
        result = add_goal(title="Read 24 books", description="One book every 2 weeks")

    assert result["id"] == 3


# ---------------------------------------------------------------------------
# add_task / complete_task
# ---------------------------------------------------------------------------

def test_add_task_returns_id(mock_svc):
    from server import add_task

    mock_svc.fetchone.return_value = {"id": 7, "title": "Buy 3 books", "goal_id": 3, "status": "pending"}

    with patch("server.svc", mock_svc):
        result = add_task(title="Buy 3 books", goal_id=3)

    assert result["id"] == 7
    assert result["status"] == "pending"


def test_complete_task_updates_status(mock_svc):
    from server import complete_task

    mock_svc.fetchone.side_effect = [
        {"id": 7, "title": "Buy 3 books", "status": "pending"},
        {"id": 7, "title": "Buy 3 books", "status": "done"},
    ]

    with patch("server.svc", mock_svc):
        result = complete_task(task_id=7)

    assert result["status"] == "done"


def test_complete_task_not_found(mock_svc):
    from server import complete_task

    mock_svc.fetchone.return_value = None

    with patch("server.svc", mock_svc):
        result = complete_task(task_id=999)

    assert "error" in result


# ---------------------------------------------------------------------------
# add_journal_entry
# ---------------------------------------------------------------------------

def test_add_journal_entry_returns_id(mock_svc):
    from server import add_journal_entry

    mock_svc.fetchone.return_value = {"id": 10, "entry_date": "2026-07-01", "mood": "good"}

    with patch("server.svc", mock_svc):
        result = add_journal_entry(content="Had a productive day.", mood="good")

    assert result["id"] == 10


def test_add_journal_entry_validates_mood(mock_svc):
    from server import add_journal_entry

    with patch("server.svc", mock_svc):
        result = add_journal_entry(content="Test.", mood="amazing")

    assert "error" in result
    assert "mood" in result["error"].lower()
```

- [ ] **Step 4: Run tests — expect ImportError**

```bash
cd services/personal-service && uv run pytest tests/ -v 2>&1 | head -15
```
Expected: `ModuleNotFoundError: No module named 'server'`

### Step 5b: Write the implementation

- [ ] **Step 5: Write server.py**

Create `services/personal-service/server.py`:

```python
"""Personal service MCP server — habits, goals, tasks, journal."""

import os
from datetime import date

from fastmcp import FastMCP
from nizam_shared.audit import write_audit_log
from nizam_shared.base import ServiceBase

mcp = FastMCP("personal-service")
svc = ServiceBase(
    "personal-service",
    db_role="svc_personal",
    db_pass_env="POSTGRES_SVC_PERSONAL_PASS",
)

VALID_FREQUENCIES = {"daily", "weekly"}
VALID_MOODS = {"great", "good", "neutral", "low", "rough"}
ACTOR = "assistant"


@mcp.tool()
def add_habit(
    name: str,
    frequency: str = "daily",
    goal_count: float = 1,
    unit: str = "times",
) -> dict:
    """Define a new recurring habit.

    Args:
        name: Unique habit name (e.g. 'Morning run').
        frequency: 'daily' or 'weekly'.
        goal_count: Target count per frequency period.
        unit: Unit of measurement (e.g. 'minutes', 'times', 'km').
    """
    if frequency not in VALID_FREQUENCIES:
        return {"error": f"Invalid frequency '{frequency}'. Valid: {sorted(VALID_FREQUENCIES)}."}

    row = svc.fetchone(
        """
        INSERT INTO personal.habits (name, frequency, goal_count, unit)
        VALUES (%s, %s, %s, %s)
        ON CONFLICT (name) DO NOTHING
        RETURNING id, name, frequency, goal_count, unit
        """,
        (name, frequency, goal_count, unit),
    )
    if row is None:
        return {"error": f"Habit '{name}' already exists."}

    return dict(row)


@mcp.tool()
def log_habit(
    habit_name: str,
    value: float = 1,
    for_date: str | None = None,
) -> dict:
    """Log a habit occurrence.

    Args:
        habit_name: Name of the habit to log.
        value: Amount completed (default 1).
        for_date: Date to log for in YYYY-MM-DD format (default: today).
    """
    target_date = for_date or str(date.today())

    habit = svc.fetchone(
        "SELECT id, name, goal_count FROM personal.habits WHERE name = %s AND active = true",
        (habit_name,),
    )
    if habit is None:
        return {"error": f"Habit '{habit_name}' not found or inactive."}

    row = svc.fetchone(
        """
        INSERT INTO personal.habit_logs (habit_id, value, logged_for)
        VALUES (%s, %s, %s)
        ON CONFLICT (habit_id, logged_for) DO UPDATE SET value = EXCLUDED.value
        RETURNING habit_id, value, logged_for
        """,
        (habit["id"], value, target_date),
    )
    return {
        "status": "logged",
        "habit": habit_name,
        "value": float(row["value"]),
        "for_date": str(row["logged_for"]),
        "goal_count": float(habit["goal_count"]),
        "on_track": float(row["value"]) >= float(habit["goal_count"]),
    }


@mcp.tool()
def list_habits(active_only: bool = True) -> dict:
    """List all habits with today's log status."""
    rows = svc.fetchall(
        """
        SELECT h.id, h.name, h.frequency, h.goal_count, h.unit,
               hl.value AS today_value
        FROM personal.habits h
        LEFT JOIN personal.habit_logs hl
            ON hl.habit_id = h.id AND hl.logged_for = CURRENT_DATE
        WHERE (%s = false OR h.active = true)
        ORDER BY h.name
        """,
        (active_only,),
    )
    return {"habits": [dict(r) for r in rows]}


@mcp.tool()
def add_goal(
    title: str,
    description: str | None = None,
    target_date: str | None = None,
) -> dict:
    """Create a new goal.

    Args:
        title: Goal title.
        description: Optional detail.
        target_date: Target completion date (YYYY-MM-DD).
    """
    row = svc.fetchone(
        """
        INSERT INTO personal.goals (title, description, target_date)
        VALUES (%s, %s, %s)
        RETURNING id, title, description, target_date, status
        """,
        (title, description, target_date),
    )
    return dict(row)


@mcp.tool()
def list_goals(status: str = "active") -> dict:
    """List goals with their task counts.

    Args:
        status: 'active' | 'completed' | 'paused' | 'all'
    """
    if status == "all":
        rows = svc.fetchall(
            """
            SELECT g.id, g.title, g.status, g.target_date,
                   COUNT(t.id) AS task_count,
                   COUNT(t.id) FILTER (WHERE t.status = 'done') AS done_count
            FROM personal.goals g
            LEFT JOIN personal.tasks t ON t.goal_id = g.id
            GROUP BY g.id ORDER BY g.created_at DESC
            """,
        )
    else:
        rows = svc.fetchall(
            """
            SELECT g.id, g.title, g.status, g.target_date,
                   COUNT(t.id) AS task_count,
                   COUNT(t.id) FILTER (WHERE t.status = 'done') AS done_count
            FROM personal.goals g
            LEFT JOIN personal.tasks t ON t.goal_id = g.id
            WHERE g.status = %s
            GROUP BY g.id ORDER BY g.created_at DESC
            """,
            (status,),
        )
    return {"goals": [dict(r) for r in rows]}


@mcp.tool()
def add_task(
    title: str,
    goal_id: int | None = None,
    due_date: str | None = None,
) -> dict:
    """Add a task, optionally linked to a goal.

    Args:
        title: Task title.
        goal_id: ID of the parent goal (optional).
        due_date: Due date in YYYY-MM-DD format.
    """
    row = svc.fetchone(
        """
        INSERT INTO personal.tasks (title, goal_id, due_date)
        VALUES (%s, %s, %s)
        RETURNING id, title, goal_id, due_date, status
        """,
        (title, goal_id, due_date),
    )
    return dict(row)


@mcp.tool()
def complete_task(task_id: int) -> dict:
    """Mark a task as done."""
    existing = svc.fetchone(
        "SELECT id, title, status FROM personal.tasks WHERE id = %s",
        (task_id,),
    )
    if existing is None:
        return {"error": f"Task {task_id} not found."}

    row = svc.fetchone(
        """
        UPDATE personal.tasks SET status = 'done'
        WHERE id = %s RETURNING id, title, status
        """,
        (task_id,),
    )
    return dict(row)


@mcp.tool()
def list_tasks(
    goal_id: int | None = None,
    status: str = "pending",
) -> dict:
    """List tasks filtered by goal or status.

    Args:
        goal_id: Filter by goal (optional).
        status: 'pending' | 'done' | 'all'
    """
    if goal_id and status != "all":
        rows = svc.fetchall(
            "SELECT * FROM personal.tasks WHERE goal_id = %s AND status = %s ORDER BY due_date NULLS LAST",
            (goal_id, status),
        )
    elif goal_id:
        rows = svc.fetchall(
            "SELECT * FROM personal.tasks WHERE goal_id = %s ORDER BY due_date NULLS LAST",
            (goal_id,),
        )
    elif status != "all":
        rows = svc.fetchall(
            "SELECT * FROM personal.tasks WHERE status = %s ORDER BY due_date NULLS LAST",
            (status,),
        )
    else:
        rows = svc.fetchall(
            "SELECT * FROM personal.tasks ORDER BY due_date NULLS LAST"
        )
    return {"tasks": [dict(r) for r in rows]}


@mcp.tool()
def add_journal_entry(
    content: str,
    mood: str | None = None,
    entry_date: str | None = None,
) -> dict:
    """Add a journal entry.

    Args:
        content: The journal text.
        mood: 'great' | 'good' | 'neutral' | 'low' | 'rough' (optional).
        entry_date: Date in YYYY-MM-DD format (default: today).
    """
    if mood and mood not in VALID_MOODS:
        return {"error": f"Invalid mood '{mood}'. Valid: {sorted(VALID_MOODS)}."}

    target_date = entry_date or str(date.today())
    row = svc.fetchone(
        """
        INSERT INTO personal.journal (content, mood, entry_date)
        VALUES (%s, %s, %s)
        RETURNING id, entry_date, mood
        """,
        (content, mood, target_date),
    )
    return dict(row)


@mcp.tool()
def list_journal_entries(
    from_date: str | None = None,
    to_date: str | None = None,
    limit: int = 10,
) -> dict:
    """List journal entries in reverse chronological order.

    Args:
        from_date: Start date YYYY-MM-DD (optional).
        to_date: End date YYYY-MM-DD (optional).
        limit: Max entries to return (default 10, max 50).
    """
    limit = min(limit, 50)
    rows = svc.fetchall(
        """
        SELECT id, entry_date, mood, LEFT(content, 200) AS content_preview
        FROM personal.journal
        WHERE (%s IS NULL OR entry_date >= %s::date)
          AND (%s IS NULL OR entry_date <= %s::date)
        ORDER BY entry_date DESC
        LIMIT %s
        """,
        (from_date, from_date, to_date, to_date, limit),
    )
    return {"entries": [dict(r) for r in rows]}


if __name__ == "__main__":
    mcp.run(transport="streamable-http", host="127.0.0.1", port=8102)
```

- [ ] **Step 6: Run tests — expect all pass**

```bash
cd services/personal-service && uv run pytest tests/ -v
```
Expected: 9 tests pass.

---

## Task 6: Write finance-service

**Files:**
- Create: `services/finance-service/pyproject.toml`
- Create: `services/finance-service/server.py`
- Create: `services/finance-service/tests/__init__.py`
- Create: `services/finance-service/tests/test_server.py`

### Step 6a: Write failing tests

- [ ] **Step 1: Write pyproject.toml**

Create `services/finance-service/pyproject.toml`:

```toml
[project]
name = "finance-service"
version = "0.1.0"
requires-python = ">=3.12"
dependencies = [
    "nizam-shared",
    "fastmcp>=2.0",
    "httpx>=0.27",
]

[tool.uv.sources]
nizam-shared = { workspace = true }
```

- [ ] **Step 2: Write tests/__init__.py**

Create `services/finance-service/tests/__init__.py` (empty).

- [ ] **Step 3: Write tests/test_server.py**

Create `services/finance-service/tests/test_server.py`:

```python
"""Tests for finance-service MCP tools."""

from unittest.mock import MagicMock, patch

import pytest


@pytest.fixture
def mock_svc():
    return MagicMock()


# ---------------------------------------------------------------------------
# log_transaction
# ---------------------------------------------------------------------------

def test_log_transaction_income(mock_svc):
    from server import log_transaction

    mock_svc.fetchone.return_value = {
        "id": 1, "amount": 5000.0, "currency": "AED",
        "type": "income", "category": "salary", "txn_date": "2026-07-01",
    }
    with patch("server.svc", mock_svc):
        result = log_transaction(amount=5000, type="income", category="salary")

    assert result["id"] == 1
    assert result["type"] == "income"


def test_log_transaction_validates_type(mock_svc):
    from server import log_transaction

    with patch("server.svc", mock_svc):
        result = log_transaction(amount=100, type="transfer", category="food")

    assert "error" in result
    assert "type" in result["error"].lower()


def test_log_transaction_validates_positive_amount(mock_svc):
    from server import log_transaction

    with patch("server.svc", mock_svc):
        result = log_transaction(amount=-50, type="expense", category="food")

    assert "error" in result
    assert "amount" in result["error"].lower()


# ---------------------------------------------------------------------------
# list_transactions
# ---------------------------------------------------------------------------

def test_list_transactions_returns_rows(mock_svc):
    from server import list_transactions

    mock_svc.fetchall.return_value = [
        {"id": 1, "amount": 100.0, "currency": "AED", "type": "expense",
         "category": "food", "txn_date": "2026-07-01"},
    ]
    with patch("server.svc", mock_svc):
        result = list_transactions()

    assert len(result["transactions"]) == 1


# ---------------------------------------------------------------------------
# get_monthly_summary
# ---------------------------------------------------------------------------

def test_get_monthly_summary_groups_by_category(mock_svc):
    from server import get_monthly_summary

    mock_svc.fetchall.return_value = [
        {"type": "expense", "category": "food", "total": 1200.0, "count": 15},
        {"type": "income", "category": "salary", "total": 10000.0, "count": 1},
    ]
    with patch("server.svc", mock_svc):
        result = get_monthly_summary(year=2026, month=7)

    assert "breakdown" in result
    assert result["year"] == 2026
    assert result["month"] == 7


# ---------------------------------------------------------------------------
# convert_fx
# ---------------------------------------------------------------------------

def test_convert_fx_happy_path():
    from server import convert_fx

    mock_resp = MagicMock()
    mock_resp.json.return_value = {
        "result": "success",
        "conversion_rate": 3.67,
    }
    mock_resp.raise_for_status = MagicMock()

    with patch("server.httpx.get", return_value=mock_resp):
        result = convert_fx(amount=100, from_currency="USD", to_currency="AED")

    assert "error" not in result
    assert result["converted_amount"] == pytest.approx(367.0)
    assert result["rate"] == pytest.approx(3.67)


def test_convert_fx_same_currency():
    from server import convert_fx

    result = convert_fx(amount=100, from_currency="AED", to_currency="AED")
    assert result["converted_amount"] == 100.0
    assert result["rate"] == 1.0


def test_convert_fx_api_error():
    from server import convert_fx

    import httpx
    with patch("server.httpx.get", side_effect=httpx.TimeoutException("timeout")):
        result = convert_fx(amount=100, from_currency="USD", to_currency="AED")

    assert "error" in result


# ---------------------------------------------------------------------------
# calc_zakat
# ---------------------------------------------------------------------------

def test_calc_zakat_above_nisab():
    from server import calc_zakat

    mock_resp = MagicMock()
    mock_resp.json.return_value = {"price_gram_24k": 300.0}  # gold price USD/g
    mock_resp.raise_for_status = MagicMock()

    with patch("server.httpx.get", return_value=mock_resp):
        result = calc_zakat(cash_savings=50000, gold_grams=0)

    # Nisab = 85g * $300/g = $25,500. $50,000 > $25,500 so zakat due.
    assert result["zakat_due"] is True
    assert result["zakat_amount"] > 0


def test_calc_zakat_below_nisab():
    from server import calc_zakat

    mock_resp = MagicMock()
    mock_resp.json.return_value = {"price_gram_24k": 300.0}
    mock_resp.raise_for_status = MagicMock()

    with patch("server.httpx.get", return_value=mock_resp):
        result = calc_zakat(cash_savings=1000, gold_grams=0)

    # $1,000 < $25,500 nisab so no zakat.
    assert result["zakat_due"] is False
    assert result["zakat_amount"] == 0.0
```

- [ ] **Step 4: Run tests — expect ImportError**

```bash
cd services/finance-service && uv run pytest tests/ -v 2>&1 | head -15
```
Expected: `ModuleNotFoundError: No module named 'server'`

### Step 6b: Write the implementation

- [ ] **Step 5: Write server.py**

Create `services/finance-service/server.py`:

```python
"""Finance service MCP server — personal transactions, FX, zakat."""

import os
import time
from datetime import date

import httpx
from fastmcp import FastMCP
from nizam_shared.audit import write_audit_log
from nizam_shared.base import ServiceBase

mcp = FastMCP("finance-service")
svc = ServiceBase(
    "finance-service",
    db_role="svc_finance_personal",
    db_pass_env="POSTGRES_SVC_FINANCE_PERSONAL_PASS",
)

FX_API_KEY = os.environ.get("FX_API_KEY", "")
GOLD_API_KEY = os.environ.get("GOLD_API_KEY", "")
ACTOR = "assistant"

VALID_TYPES = {"income", "expense"}
NISAB_GOLD_GRAMS = 85.0  # Nisab threshold in gold grams
ZAKAT_RATE = 0.025       # 2.5%

# Module-level FX cache: {"{from}_{to}": (rate, timestamp)}
_fx_cache: dict[str, tuple[float, float]] = {}
FX_CACHE_TTL = 3600  # 1 hour


@mcp.tool()
def log_transaction(
    amount: float,
    type: str,
    category: str,
    description: str | None = None,
    currency: str = "AED",
    txn_date: str | None = None,
) -> dict:
    """Log a personal income or expense transaction.

    Args:
        amount: Positive number. The transaction amount.
        type: 'income' or 'expense'.
        category: Category label (e.g. 'food', 'salary', 'rent', 'transport').
        description: Optional notes.
        currency: 3-letter currency code (default: AED).
        txn_date: Date in YYYY-MM-DD (default: today).
    """
    if type not in VALID_TYPES:
        return {"error": f"Invalid type '{type}'. Valid: income, expense."}
    if amount <= 0:
        return {"error": f"Amount must be positive. Got: {amount}."}

    target_date = txn_date or str(date.today())
    row = svc.fetchone(
        """
        INSERT INTO finance.personal_transactions
            (amount, currency, type, category, description, txn_date)
        VALUES (%s, %s, %s, %s, %s, %s)
        RETURNING id, amount, currency, type, category, description, txn_date
        """,
        (amount, currency.upper(), type, category, description, target_date),
    )
    return dict(row)


@mcp.tool()
def list_transactions(
    from_date: str | None = None,
    to_date: str | None = None,
    category: str | None = None,
    type: str | None = None,
    limit: int = 20,
) -> dict:
    """List personal transactions with optional filters.

    Args:
        from_date: Start date YYYY-MM-DD (optional).
        to_date: End date YYYY-MM-DD (optional).
        category: Filter by category (optional).
        type: 'income' or 'expense' (optional).
        limit: Max rows (default 20, max 100).
    """
    limit = min(limit, 100)
    rows = svc.fetchall(
        """
        SELECT id, amount, currency, type, category, description, txn_date
        FROM finance.personal_transactions
        WHERE (%s IS NULL OR txn_date >= %s::date)
          AND (%s IS NULL OR txn_date <= %s::date)
          AND (%s IS NULL OR category = %s)
          AND (%s IS NULL OR type = %s)
        ORDER BY txn_date DESC, id DESC
        LIMIT %s
        """,
        (from_date, from_date, to_date, to_date, category, category, type, type, limit),
    )
    return {"transactions": [dict(r) for r in rows]}


@mcp.tool()
def get_monthly_summary(year: int, month: int) -> dict:
    """Get income/expense breakdown by category for a given month.

    Args:
        year: 4-digit year.
        month: Month number (1-12).
    """
    rows = svc.fetchall(
        """
        SELECT type, category, SUM(amount) AS total, COUNT(*) AS count
        FROM finance.personal_transactions
        WHERE EXTRACT(YEAR FROM txn_date) = %s
          AND EXTRACT(MONTH FROM txn_date) = %s
        GROUP BY type, category
        ORDER BY type, total DESC
        """,
        (year, month),
    )
    breakdown = [dict(r) for r in rows]
    total_income = sum(r["total"] for r in breakdown if r["type"] == "income")
    total_expense = sum(r["total"] for r in breakdown if r["type"] == "expense")
    return {
        "year": year,
        "month": month,
        "total_income": float(total_income),
        "total_expense": float(total_expense),
        "net": float(total_income - total_expense),
        "breakdown": breakdown,
    }


@mcp.tool()
def convert_fx(
    amount: float,
    from_currency: str,
    to_currency: str,
) -> dict:
    """Convert an amount between currencies using live exchange rates.

    Args:
        amount: Amount to convert.
        from_currency: Source currency code (e.g. 'USD').
        to_currency: Target currency code (e.g. 'AED').
    """
    from_c = from_currency.upper()
    to_c = to_currency.upper()

    if from_c == to_c:
        return {"from_currency": from_c, "to_currency": to_c, "amount": amount,
                "converted_amount": amount, "rate": 1.0}

    cache_key = f"{from_c}_{to_c}"
    cached = _fx_cache.get(cache_key)
    if cached and time.time() - cached[1] < FX_CACHE_TTL:
        rate = cached[0]
    else:
        try:
            resp = httpx.get(
                f"https://v6.exchangerate-api.com/v6/{FX_API_KEY}/pair/{from_c}/{to_c}",
                timeout=10,
            )
            resp.raise_for_status()
            data = resp.json()
            if data.get("result") != "success":
                return {"error": f"FX API error: {data.get('error-type', 'unknown')}"}
            rate = data["conversion_rate"]
            _fx_cache[cache_key] = (rate, time.time())
        except httpx.TimeoutException:
            return {"error": "FX API timed out (10s)."}
        except httpx.HTTPStatusError as e:
            return {"error": f"FX API HTTP {e.response.status_code}."}

    return {
        "from_currency": from_c,
        "to_currency": to_c,
        "amount": amount,
        "converted_amount": round(amount * rate, 2),
        "rate": rate,
    }


@mcp.tool()
def calc_zakat(
    cash_savings: float,
    gold_grams: float = 0,
    currency: str = "USD",
) -> dict:
    """Calculate zakat obligation based on current gold price (nisab = 85g gold).

    Args:
        cash_savings: Total liquid savings.
        gold_grams: Physical gold held in grams (default 0).
        currency: Currency of cash_savings (default USD).
    """
    try:
        resp = httpx.get(
            "https://www.goldapi.io/api/XAU/USD",
            headers={"x-access-token": GOLD_API_KEY},
            timeout=10,
        )
        resp.raise_for_status()
        data = resp.json()
        gold_price_usd_per_gram = data["price_gram_24k"]
    except httpx.TimeoutException:
        return {"error": "Gold API timed out (10s)."}
    except (httpx.HTTPStatusError, KeyError) as e:
        return {"error": f"Gold API error: {e}"}

    # Normalize savings to USD if needed
    if currency.upper() != "USD":
        fx_result = convert_fx(cash_savings, currency, "USD")
        if "error" in fx_result:
            return fx_result
        savings_usd = fx_result["converted_amount"]
    else:
        savings_usd = cash_savings

    gold_value_usd = gold_grams * gold_price_usd_per_gram
    total_wealth_usd = savings_usd + gold_value_usd

    nisab_usd = NISAB_GOLD_GRAMS * gold_price_usd_per_gram
    zakat_due = total_wealth_usd >= nisab_usd
    zakat_amount = round(total_wealth_usd * ZAKAT_RATE, 2) if zakat_due else 0.0

    return {
        "zakat_due": zakat_due,
        "zakat_amount": zakat_amount,
        "zakat_currency": "USD",
        "total_wealth_usd": round(total_wealth_usd, 2),
        "nisab_usd": round(nisab_usd, 2),
        "gold_price_usd_per_gram": gold_price_usd_per_gram,
    }


if __name__ == "__main__":
    mcp.run(transport="streamable-http", host="127.0.0.1", port=8101)
```

- [ ] **Step 6: Run tests — expect all pass**

```bash
cd services/finance-service && uv run pytest tests/ -v
```
Expected: 10 tests pass.

---

## Task 7: Write systemd units

**Files:**
- Create: `systemd/personal-service.service`
- Create: `systemd/finance-service.service`

- [ ] **Step 1: Write personal-service.service**

Create `systemd/personal-service.service`:

```ini
[Unit]
Description=Nizam-OS personal-service (MCP HTTP)
After=network.target postgresql.service

[Service]
Type=simple
User=vazir
EnvironmentFile=/home/vazir/nizam-os/secrets/nizam.env
ExecStart=/home/vazir/.local/bin/uv run \
    --directory /home/vazir/nizam-os/services/personal-service \
    --env-file /home/vazir/nizam-os/secrets/nizam.env \
    python server.py
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

- [ ] **Step 2: Write finance-service.service**

Create `systemd/finance-service.service`:

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

- [ ] **Step 3: Verify both units**

```bash
grep "Description\|Port\|ExecStart" systemd/personal-service.service systemd/finance-service.service
```
Expected: personal-service shows port 8102 in ExecStart path; finance-service shows 8101.

---

## Task 8: Update Ayah's config.yaml

**Files:**
- Modify: `hermes/profiles/assistant/config.yaml`

Ayah needs MCP connections to both personal-service and finance-service, with `tools.include` filters so she only sees personal-scope finance tools (not future Hala business tools).

- [ ] **Step 1: Read current config.yaml**

Read `hermes/profiles/assistant/config.yaml` to see current structure before editing.

- [ ] **Step 2: Add MCP servers block**

Add to `hermes/profiles/assistant/config.yaml`:

```yaml
mcp_servers:
  personal:
    url: http://127.0.0.1:8102/mcp
    tools:
      prompts: false
      resources: false
      include:
        - add_habit
        - log_habit
        - list_habits
        - add_goal
        - list_goals
        - add_task
        - complete_task
        - list_tasks
        - add_journal_entry
        - list_journal_entries

  finance_personal:
    url: http://127.0.0.1:8101/mcp
    tools:
      prompts: false
      resources: false
      include:
        - log_transaction
        - list_transactions
        - get_monthly_summary
        - convert_fx
        - calc_zakat
```

- [ ] **Step 3: Add discord section (channel IDs filled on VPS)**

Add to config.yaml:

```yaml
discord:
  # Enable Developer Mode in Discord: Settings → Advanced → Developer Mode
  # Right-click each channel → Copy Channel ID, then replace the placeholder IDs below.
  allowed_channels: "FINANCES_CHANNEL_ID,HABITS_CHANNEL_ID,GOALS_TASKS_CHANNEL_ID,JOURNAL_CHANNEL_ID,CHAT_CHANNEL_ID"
  channel_prompts:
    "FINANCES_CHANNEL_ID": "You are in the #finances channel. Help with personal expense tracking, budgeting, FX conversions, and zakat calculations. Use the finance_personal MCP tools."
    "HABITS_CHANNEL_ID": "You are in the #habits channel. Track habits and log completions. Use the personal MCP tools."
    "GOALS_TASKS_CHANNEL_ID": "You are in the #goals-tasks channel. Manage goals and tasks. Use the personal MCP tools."
    "JOURNAL_CHANNEL_ID": "You are in the #journal channel. Help with personal journal entries. Be warm and brief. Use the personal MCP tools."
    "CHAT_CHANNEL_ID": "You are in the #chat channel. General personal assistant. Use any available tool that fits the request."
```

- [ ] **Step 4: Verify MCP blocks present**

```bash
grep -c "personal:\|finance_personal:" hermes/profiles/assistant/config.yaml
```
Expected: `2`

---

## Task 9: VPS setup

**Run on the VPS.** All commands require the VPS environment with postgres access.

- [ ] **Step 1: Set passwords in nizam.env**

Edit `/home/vazir/nizam-os/secrets/nizam.env` on the VPS:

```bash
# Generate strong passwords
python3 -c "import secrets; print(secrets.token_urlsafe(32))"
```

Set `POSTGRES_SVC_PERSONAL_PASS` and `POSTGRES_SVC_FINANCE_PERSONAL_PASS` to the generated values. Also set `FX_API_KEY` (from https://www.exchangerate-api.com/) and `GOLD_API_KEY` (from https://www.goldapi.io/).

- [ ] **Step 2: Run migrations**

```bash
psql -U postgres -d nizam -f /home/vazir/nizam-os/db/migrations/0002_personal_schema.sql
psql -U postgres -d nizam -f /home/vazir/nizam-os/db/migrations/0003_audit_schema.sql
```

Verify:
```bash
psql -U postgres -d nizam -c "\dt personal.*" -c "\dt finance.*" -c "\dt audit.*"
```
Expected: tables for personal.habits, personal.habit_logs, personal.goals, personal.tasks, personal.journal, finance.personal_transactions, audit.log.

- [ ] **Step 3: Create DB users**

```bash
source ~/nizam-os/secrets/nizam.env

psql -U postgres -d nizam -c "
CREATE USER svc_personal WITH PASSWORD '${POSTGRES_SVC_PERSONAL_PASS}';
GRANT USAGE ON SCHEMA personal, finance, audit TO svc_personal;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA personal TO svc_personal;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA personal TO svc_personal;
GRANT SELECT, INSERT ON finance.personal_transactions TO svc_personal;
GRANT USAGE ON SEQUENCE finance.personal_transactions_id_seq TO svc_personal;
GRANT INSERT ON audit.log TO svc_personal;
"

psql -U postgres -d nizam -c "
CREATE USER svc_finance_personal WITH PASSWORD '${POSTGRES_SVC_FINANCE_PERSONAL_PASS}';
GRANT USAGE ON SCHEMA finance, audit TO svc_finance_personal;
GRANT SELECT, INSERT ON finance.personal_transactions TO svc_finance_personal;
GRANT USAGE ON SEQUENCE finance.personal_transactions_id_seq TO svc_finance_personal;
GRANT INSERT ON audit.log TO svc_finance_personal;
"
```

- [ ] **Step 4: Install systemd units**

```bash
sudo ln -s /home/vazir/nizam-os/systemd/personal-service.service /etc/systemd/system/
sudo ln -s /home/vazir/nizam-os/systemd/finance-service.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable personal-service.service finance-service.service
sudo systemctl start personal-service.service finance-service.service
```

- [ ] **Step 5: Verify both services running**

```bash
systemctl is-active personal-service.service finance-service.service
curl -s http://127.0.0.1:8102/mcp -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/list","id":1}' | python3 -m json.tool | grep '"name"' | head -10
curl -s http://127.0.0.1:8101/mcp -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/list","id":1}' | python3 -m json.tool | grep '"name"' | head -5
```
Expected: both `active`; personal-service lists habit/goal/task/journal tools; finance-service lists transaction/FX/zakat tools.

- [ ] **Step 6: Fill channel IDs in Ayah config**

Get channel IDs from Discord (Developer Mode → right-click channel → Copy Channel ID). Edit `hermes/profiles/assistant/config.yaml` to replace placeholder IDs with real snowflake IDs.

- [ ] **Step 7: Set DISCORD_ALLOWED_USERS in Ayah .env**

```bash
# ~/.hermes/profiles/assistant/.env (not in repo)
echo "DISCORD_ALLOWED_USERS=YOUR_DISCORD_USER_ID" >> ~/.hermes/profiles/assistant/.env
```

- [ ] **Step 8: Enable Ayah gateway**

```bash
hermes gateway install assistant
systemctl --user enable hermes-gateway-assistant.service
systemctl --user start hermes-gateway-assistant.service
systemctl --user is-active hermes-gateway-assistant.service
```
Expected: `active`

- [ ] **Step 9: Add services to health monitor inventory**

Edit `inventory/tracked-services.txt` to set personal-service and finance-service to active:

```
personal-service.service | system | active  # critical
finance-service.service | system | active  # critical
```

---

## Task 10: Smoke test end-to-end (VPS)

All tests run from Ayah's Discord channels.

- [ ] **Step 1: Test habit logging**

In `#habits`:
```
@Ayah I just finished 20 minutes of reading. Log it.
```
Expected: Ayah calls `add_habit` if needed, then `log_habit`. Replies with confirmation including streak/on-track status.

- [ ] **Step 2: Test expense tracking**

In `#finances`:
```
@Ayah I spent 45 AED on lunch today.
```
Expected: Ayah calls `log_transaction(amount=45, type="expense", category="food", currency="AED")`. Replies with ID.

```
@Ayah What did I spend on food this month?
```
Expected: Ayah calls `get_monthly_summary(year=2026, month=7)`. Returns categorized breakdown.

- [ ] **Step 3: Test FX conversion**

In `#finances`:
```
@Ayah Convert 1000 USD to AED.
```
Expected: Ayah calls `convert_fx`. Replies with current rate + result.

- [ ] **Step 4: Test zakat**

In `#finances`:
```
@Ayah Calculate my zakat. I have 25000 USD in savings and 10g of gold.
```
Expected: Ayah calls `calc_zakat(cash_savings=25000, gold_grams=10, currency="USD")`. Returns zakat_due, amount, and nisab context.

- [ ] **Step 5: Test goal and task creation**

In `#goals-tasks`:
```
@Ayah Create a goal: Read 24 books this year (target: Dec 31 2026).
Then add a task: Buy 3 books this weekend.
```
Expected: goal created, task linked.

- [ ] **Step 6: Test journal**

In `#journal`:
```
@Ayah Today was a productive day. I finished the admin v1 implementation. Mood: great.
```
Expected: Ayah calls `add_journal_entry`. Confirms the entry was saved.

- [ ] **Step 7: Verify tools.include filter works**

Ayah should NOT have access to future Hala-scoped business finance tools. Since finance-service only exposes personal tools (no business schema in this migration), this is implicitly satisfied.

Verify by attempting in `#finances`:
```
@Ayah Show me the business ledger.
```
Expected: Ayah says she doesn't have access to business financials (that's Hala's domain), not a tool call error.

---

## Task 11: Create personal dashboard in Grafana (VPS)

**Run on VPS after personal-service and finance-service are live.**

- [ ] **Step 1: Create grafana PostgreSQL role**

```sql
-- Run as postgres superuser
CREATE USER grafana WITH PASSWORD '<generate_strong_password>';

-- personal schema
GRANT CONNECT ON DATABASE nizam TO grafana;
GRANT USAGE ON SCHEMA personal TO grafana;
GRANT SELECT ON ALL TABLES IN SCHEMA personal TO grafana;
ALTER DEFAULT PRIVILEGES IN SCHEMA personal GRANT SELECT ON TABLES TO grafana;

-- finance schema (personal transactions only)
GRANT USAGE ON SCHEMA finance TO grafana;
GRANT SELECT ON ALL TABLES IN SCHEMA finance TO grafana;
ALTER DEFAULT PRIVILEGES IN SCHEMA finance GRANT SELECT ON TABLES TO grafana;

-- audit schema (read-only view into writes)
GRANT USAGE ON SCHEMA audit TO grafana;
GRANT SELECT ON audit.log TO grafana;
```

Add `GRAFANA_DB_PASS=<password>` to `secrets/nizam.env`.

- [ ] **Step 2: Verify grafana role — no writes**

```sql
-- As the grafana user, this must fail:
INSERT INTO personal.habits (name) VALUES ('test');
```
Expected: `ERROR: permission denied for table habits`

- [ ] **Step 3: Add PostgreSQL datasource to Grafana**

Navigate to `http://<vps_ip>:3000` → Connections → Data Sources → Add → PostgreSQL.

```
Host:     localhost:5432
Database: nizam
User:     grafana
Password: <GRAFANA_DB_PASS>
TLS mode: disable (localhost)
```

Click "Save & test". Expected: "Database Connection OK".

- [ ] **Step 4: Build dashboard panels**

Create a new dashboard named "Nizam — Personal". Add a row per section (Habits, Goals, Tasks, Journal, Finance). For each panel follow the query targets in `docs/specs/20260701-assistant-v1-design.md` — Grafana section.

Key queries:

```sql
-- Habits completed today
SELECT h.name, CASE WHEN hl.id IS NOT NULL THEN 1 ELSE 0 END AS done
FROM personal.habits h
LEFT JOIN personal.habit_logs hl ON hl.habit_id = h.id AND hl.logged_for = CURRENT_DATE
WHERE h.is_active = true;

-- Overdue tasks (should always be 0)
SELECT COUNT(*) FROM personal.tasks
WHERE due_date < CURRENT_DATE AND status != 'done';

-- Spend this month
SELECT COALESCE(SUM(amount_aed), 0) AS spend
FROM finance.personal_transactions
WHERE direction = 'expense'
  AND DATE_TRUNC('month', txn_date) = DATE_TRUNC('month', CURRENT_DATE);

-- Spend by category this month
SELECT category, SUM(amount_aed) AS total
FROM finance.personal_transactions
WHERE direction = 'expense'
  AND DATE_TRUNC('month', txn_date) = DATE_TRUNC('month', CURRENT_DATE)
GROUP BY category ORDER BY total DESC;
```

- [ ] **Step 5: Export dashboard as JSON and save to repo**

In Grafana: Dashboard settings (gear icon) → JSON Model → copy all.

Save to `grafana/personal-dashboard.json` in the repo.

- [ ] **Step 6: Verify all panels show data**

Log a habit, add a task, record a transaction, write a journal entry — confirm panels update.

Expected: no "No data" panels. Finance panel shows AED amounts. Habits panel shows today's completion state.
