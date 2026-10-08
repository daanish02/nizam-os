---
type: convention
title: PostgreSQL — Dialect-Specific Rules
description: PostgreSQL-specific conventions covering RLS, native types, online DDL, pgBouncer, advisory locks, and SKIP LOCKED — load alongside conventions/cross-stack/database.md.
applies_to: [all]
tags: [database, sql, postgresql, postgres]
---

# PostgreSQL — Dialect-Specific Rules

Load alongside `conventions/cross-stack/database.md`. This file covers only what is specific to PostgreSQL.

---

## Row-Level Security (RLS)

PostgreSQL enforces tenant isolation at the engine level via RLS policies — the strongest available isolation guarantee.

```sql
-- Enable RLS on every tenant-scoped table
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders FORCE ROW LEVEL SECURITY;  -- applies to table owner too

-- Policy: each connection sees only its tenant's rows
CREATE POLICY tenant_isolation ON orders
  USING (tenant_id = current_setting('app.tenant_id')::uuid);
```

Application sets the tenant context at the start of every transaction:

```sql
SET LOCAL app.tenant_id = '<tenant-uuid>';
```

`SET LOCAL` is transaction-scoped — cleared automatically on `COMMIT`/`ROLLBACK`. Never use `SET` (session-scoped — leaks across transactions in a pooled connection).

The `migrator` role bypasses RLS (`BYPASSRLS` privilege). The `app_rw` and `app_ro` roles do not.

---

## Native Types

Prefer PostgreSQL native types over generic equivalents:

| Use case | Type |
| :--- | :--- |
| UUID primary key | `UUID` (native, 16 bytes vs 36-char string) |
| Timestamps | `TIMESTAMPTZ` — always with timezone; `TIMESTAMP` (no tz) is a footgun |
| IP addresses | `INET` / `CIDR` — not `VARCHAR` |
| JSON | `JSONB` — binary, indexable; `JSON` only when you need to preserve exact input formatting |
| Arrays | Native array types (`TEXT[]`, `INTEGER[]`) for simple list columns |
| Currency / money | `NUMERIC(precision, scale)` — never `FLOAT` or `MONEY` (`MONEY` is locale-dependent) |
| Full-text search | `TSVECTOR` + `TSQUERY` + GIN index — not `LIKE '%term%'` |

---

## UUID Strategy

Generate UUID v7 in the application layer (time-ordered, globally unique). PostgreSQL 17+ has `gen_random_uuid()` (v4) built in; for v7 use the `pg_uuidv7` extension or generate in the app.

Store as native `UUID` type, not `CHAR(36)` — 16 bytes vs 36, faster comparisons, proper indexing.

---

## Online DDL (Zero-Downtime Migrations)

PostgreSQL `ALTER TABLE` takes `ACCESS EXCLUSIVE` lock, blocking all reads and writes. For tables with significant data:

```sql
-- Index creation: use CONCURRENTLY — no table lock, but cannot run inside a transaction block
CREATE INDEX CONCURRENTLY idx_orders_customer_id ON orders(customer_id);

-- Adding a NOT NULL column safely (PG 11+: adding with a non-volatile DEFAULT is instant)
ALTER TABLE orders ADD COLUMN status TEXT NOT NULL DEFAULT 'pending';
-- No backfill needed for constant defaults in PG 11+

-- Dropping a column: mark unused first (instant), then drop in a later migration
ALTER TABLE orders ALTER COLUMN old_col DROP NOT NULL;
-- Deploy and verify, then in a later migration:
ALTER TABLE orders DROP COLUMN old_col;
```

Never run `CREATE INDEX` (without `CONCURRENTLY`) on a large production table during business hours.

---

## Connection Pooling — PgBouncer

Never let the application open connections directly to PostgreSQL in production. `PgBouncer` in **transaction mode** sits between app and DB:

- Transaction mode: connection returned to pool on `COMMIT`/`ROLLBACK` — highest density.
- Do not use session mode with PgBouncer transaction pooling — session-level features (`SET`, prepared statements, advisory locks) do not work reliably.
- Advisory locks and `LISTEN`/`NOTIFY` require a dedicated persistent connection, not a pooled one.
- Pool size: `(cpu_cores * 2) + effective_spindle_count` per PostgreSQL docs. Start there, tune under load.

---

## Advisory Locks

For distributed mutex patterns (cron deduplication, leader election, job claiming) without a separate lock service:

```sql
-- Session-level: held until released or session ends
SELECT pg_advisory_lock(hashtext('my-job-name'));
-- ... do work ...
SELECT pg_advisory_unlock(hashtext('my-job-name'));

-- Transaction-level: auto-released on COMMIT/ROLLBACK (preferred)
SELECT pg_advisory_xact_lock(hashtext('my-job-name'));
```

Advisory locks are session-scoped by default — dangerous with connection pooling (session returned to pool still holds the lock). Always use transaction-level advisory locks (`pg_advisory_xact_lock`) with PgBouncer transaction mode.

---

## `SELECT FOR UPDATE SKIP LOCKED`

Queue-style job claiming — workers compete for pending rows without blocking each other:

```sql
SELECT id, payload
FROM jobs
WHERE status = 'pending'
ORDER BY created_at
LIMIT 1
FOR UPDATE SKIP LOCKED;
```

`SKIP LOCKED` skips rows already locked by another transaction, so workers never block each other. Without it, workers queue up behind the lock.

---

## Partial and Expression Indexes

```sql
-- Partial index: only active rows
CREATE INDEX idx_orders_pending ON orders(created_at)
  WHERE status = 'pending';

-- Expression index: case-insensitive email lookup
CREATE INDEX idx_users_email_lower ON users(lower(email));
```

Partial indexes are dramatically smaller and faster than full-column indexes for filtered queries. Use them whenever a query consistently filters on a fixed predicate.

---

## `EXPLAIN ANALYZE` — Required Format

```sql
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) SELECT ...;
```

Look for: `Seq Scan` on large tables (add index), `Hash Join` vs `Nested Loop` (check row estimates), `Rows Removed by Filter` (index not selective enough), high `Buffers: hit` miss ratio (cold cache or missing index).

---

## Python (asyncpg / SQLAlchemy)

- `asyncpg` for raw async PostgreSQL access — fastest Python driver, PostgreSQL-native protocol.
- `SQLAlchemy` async (`AsyncSession`, `create_async_engine`) for ORM or Core usage — use Core for query-heavy services, ORM for domain-model-heavy services.
- Never use `psycopg2` in an async service — it is synchronous and blocks the event loop.
- Connection pool via `asyncpg.create_pool()` or SQLAlchemy's `AsyncEngine` pool — not raw per-request connections.

## Go (pgx)

- `pgx/v5` for PostgreSQL access — native protocol, faster than `database/sql` with the `lib/pq` driver.
- `pgxpool.Pool` for connection pooling — not `pgx.Conn` directly in a web service.
- Use `pgx.Batch` for sending multiple queries in a single round trip.
- `pgx.RowToStructByName` for struct scanning — avoids positional column order bugs.
