---
type: convention
title: Relational Database — Cross-Stack Rules
description: RDBMS-agnostic standards for security, schema design, access control, migrations, transactions, and performance that apply regardless of database engine or application language.
applies_to: [all]
tags: [database, sql, relational]
---

# Relational Database — Cross-Stack Rules

These rules apply to every relational database engine (PostgreSQL, MySQL, MariaDB, SQL Server, Oracle). Engine-specific behaviour is documented in `conventions/databases/{engine}.md` — always load the dialect file alongside this one.

---

## Security

### SQL Injection — Zero Tolerance

Parameterized queries (prepared statements) only. Never concatenate, format, interpolate, or template user input into a SQL string.

```sql
-- BAD: string formatting
SELECT * FROM orders WHERE id = '{user_input}';

-- GOOD: parameterized
SELECT * FROM orders WHERE id = $1;   -- PostgreSQL
SELECT * FROM orders WHERE id = ?;    -- MySQL / MariaDB / SQLite
SELECT * FROM orders WHERE id = @id;  -- SQL Server
SELECT * FROM orders WHERE id = :id;  -- Oracle / SQLAlchemy
```

Dynamic `IN` clauses and column names (sort order, filter field) must use an **explicit allowlist** in application code, never raw interpolation.

### Least-Privilege DB Roles

The application never connects as a superuser or the schema owner. Create separate roles per access level:

| Role | Privileges | Used by |
| :--- | :--- | :--- |
| `app_rw` | `SELECT`, `INSERT`, `UPDATE`, `DELETE` on app tables | Application runtime |
| `app_ro` | `SELECT` only | Read replicas, analytics, reporting |
| `migrator` | `CREATE`, `ALTER`, `DROP`, schema modification | Migration runner only — not the running app |

Grant only on the specific tables/schemas the role needs. `app_rw` has no `DROP`, no `TRUNCATE`, no schema-level access.

### Multi-Tenant Isolation

When one database instance serves multiple tenants:

- Every tenant-scoped table carries a `tenant_id` column (`NOT NULL`), indexed as the leading column of the primary access-path index.
- Queries always filter by `tenant_id`. **A backstop underneath the application is mandatory, not optional** — one repository function missing its `WHERE tenant_id` is a cross-tenant breach that raises no error and writes no log line, so application discipline alone cannot be the only control. Choose one and state it in `docs/ARCHITECTURE.md`:
  - **PostgreSQL: Row-Level Security.** `ALTER TABLE … ENABLE ROW LEVEL SECURITY` plus `FORCE ROW LEVEL SECURITY`, with a policy on `tenant_id = current_setting('app.tenant_id')::uuid`. Set `app.tenant_id` per transaction. See `databases/postgresql.md`.
  - **Engines without RLS:** exactly one tenant-scoped session/repository is the only code path to those tables, and direct model access outside it is blocked in review. Weaker — it is a convention, not an enforced constraint.
- The tenant id comes from the validated token, never from a request body, header, or query parameter. See `access-control.md`.
- The application sets the active tenant context at the start of every request and clears it on teardown. With a connection pool, clear it on release — a leaked setting means the next request runs as the previous tenant.
- **Test isolation explicitly:** seed two tenants, authenticate as one, and assert the other's rows are invisible through every endpoint. Nothing else proves the property holds.

### Secrets

- Connection strings in environment variables only (`DATABASE_URL`). Never in source code, config files, or migration scripts.
- Production connections require TLS/SSL (`sslmode=require` / `ssl=true` / equivalent). Plaintext connections to production are forbidden.
- Credentials rotated on schedule and immediately on any suspected exposure.

### Audit Columns

Every application table carries:

```sql
created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
updated_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,  -- updated by trigger or app
```

Soft-delete preferred over hard delete for any data with an audit or compliance requirement:

```sql
deleted_at  TIMESTAMP NULL DEFAULT NULL,  -- NULL = active; set = soft-deleted
```

Sensitive operations (authentication events, privilege changes, financial mutations) get an append-only `audit_log` table — never overwritten, never deleted by the application role.

---

## Schema Design

### Naming

- **snake_case** for all identifiers: tables, columns, indexes, constraints, sequences, schemas.
- Table names: **singular** (`order`, `user`, `invoice`) — not `orders`, `users`.
- No abbreviations (`usr`, `inv`, `acct`) — spell it out. Abbreviations rot as the team changes.
- Constraint names are explicit and follow a pattern: `{table}_{column(s)}_{type}` — e.g. `order_customer_id_fk`, `user_email_uq`, `invoice_amount_ck`.

### Primary Keys

- Application-generated **UUID v7** as the default: time-ordered, globally unique, safe for distributed systems, does not leak row counts or insertion order to external callers.
- Auto-increment integers (`SERIAL`, `AUTO_INCREMENT`, `IDENTITY`) only for internal join/lookup tables never exposed to external APIs.
- Primary key column named `id` on every table.

### Foreign Keys

- Always declared explicitly — never rely on application logic alone to maintain referential integrity.
- `ON DELETE` behaviour chosen deliberately per relationship:
  - `RESTRICT` — safe default; blocks deletion of a referenced row.
  - `CASCADE` — only when child rows are genuinely owned by the parent and have no meaning without it (e.g. `order_items` → `orders`). Document the choice with a comment.
  - `SET NULL` — only when the reference is optional and a null FK is semantically valid.
- FK columns always have an index (most engines do not create one automatically).

### NULL Discipline

- `NOT NULL` is the default. A nullable column is a deliberate design decision — document why null is semantically distinct from "empty" or "zero".
- No nullable booleans. A `BOOLEAN NULL` means three states (true / false / unknown) which is almost never what you want. Use an enum or split into two columns.
- No nullable foreign keys unless the relationship is genuinely optional and `SET NULL` is the correct delete behaviour.

### Enumerated Values

- Use the database's native enum type where available (see dialect file). Where not available or where the value set changes frequently, use `VARCHAR` + a `CHECK` constraint + a documented domain comment.
- Never use raw integers for enum-like fields with no enum type — the meaning is opaque in queries, pg_dump, and tooling.

### No Wide Tables

A table with 30+ columns is a domain model smell. Split into a core table and one or more extension tables joined by primary key. Each table should model one cohesive entity.

---

## Access Control (Application-Level RBAC)

The database enforces **structural** access control (row ownership, tenant isolation, role privileges). Application-level RBAC (who can perform what action) is enforced in the application layer — not solely in SQL.

Pattern:
1. DB role (`app_rw` / `app_ro`) controls *what tables and operations* are accessible.
2. Application middleware checks the authenticated user's role/permission before issuing the query.
3. For sensitive resources: combine both — the query filters by owner/tenant AND the application checks the permission.

Never use DB user accounts to model application users (one DB user per app user does not scale and is not manageable).

---

## Migrations

### Forward-Only

No `down` migrations in production. A bad migration gets a new forward migration that corrects it. Rollback scripts can exist for local development only and are never run against staging or production.

### Sequential Numbering

`001_init.sql`, `002_add_invoices.sql` — integer prefix, zero-padded to three digits. No timestamps in filenames (causes merge conflicts, hard to read order). One concern per file.

### Non-Destructive in Stages

Never make a breaking change in a single migration step. Zero-downtime pattern:

1. **Add** the new column/table (nullable or with default) — deploy.
2. **Backfill** existing rows — deploy.
3. **Add constraint** (`NOT NULL`, unique, FK) — deploy.
4. **Drop** the old column/table only after the new code is fully deployed and verified.

### Re-Runnable After a Partial Failure

A migration can fail halfway — the job is killed, the connection drops, the lock times out. The migration tool records a version as applied only on success, so the *whole file* is retried, including the statements that already ran.

Write each step so re-running it is harmless: `CREATE TABLE IF NOT EXISTS`, `ADD COLUMN IF NOT EXISTS`, `DROP ... IF EXISTS`, and guard a backfill with a `WHERE` clause that excludes rows it already updated. A migration that only succeeds on a clean first attempt turns a transient failure into manual database surgery at the worst possible moment.

Where the tool supports it, wrap the migration in a transaction so a failure leaves nothing applied — PostgreSQL supports transactional DDL, MySQL does not, so on MySQL the guards above are the only protection. Backfills over large tables are the exception: batch them outside a single transaction (see "Locks" below) and make each batch independently re-runnable.

Idempotency for API endpoints and retried transactions is a different problem, covered in [api-design.md](./api-design.md) and [db-connection.md](./db-connection.md).

### No Auto-Run at Startup

The application never runs migrations at startup in production. Migrations run as a separate, gated job before the new application version starts — with a rollback plan if the migration fails. "Run migrations on startup" is acceptable for local development only.

### Locks

Any DDL operation on a large table can lock reads and writes. Review every migration that touches a table with significant data volume:
- Prefer engine-specific online DDL options (see dialect file).
- Never run a locking migration during peak traffic without a maintenance window.

---

## Transactions

### Explicit Boundaries

Every write that spans more than one table goes in an explicit transaction. No implicit autocommit for multi-step writes. If any step fails, the whole transaction rolls back — never leave the database in a half-written state.

### Short Transactions

Transactions must not hold locks across slow operations. Any work that could be slow (HTTP call, file upload, LLM inference, email send) must happen **outside** the transaction. The transaction does only the DB writes, as fast as possible.

### Isolation Level

`READ COMMITTED` is the default and correct level for most OLTP workloads. Escalate only when you have a concrete concurrency problem that requires it:
- `REPEATABLE READ` — for read-then-write patterns where the read must be stable.
- `SERIALIZABLE` — for correctness-critical financial or inventory operations.

Document the reason when using anything above `READ COMMITTED`.

### Pessimistic Locking (`SELECT FOR UPDATE`)

Use when you need to lock a row before modifying it (inventory reservation, credit check, job claiming). With `SKIP LOCKED` (or engine equivalent) for queue-style patterns where workers compete for tasks. Never lock more rows than necessary — `FOR UPDATE` on a query returning many rows is a deadlock hazard.

---

## Performance

### Index Discipline

- Every FK column gets an index. Most engines do not create FK indexes automatically.
- Index every column used in a `WHERE`, `ORDER BY`, or `JOIN ON` that filters to < ~10–15% of rows.
- No index on low-cardinality columns alone (boolean, status with 2–3 values) — the optimizer will ignore it.
- Composite indexes: most selective column first, unless the composite is covering a specific `ORDER BY` pattern.
- Review indexes periodically — unused indexes waste write performance and storage.

### Query Plans

`EXPLAIN` / `EXPLAIN ANALYZE` (or engine equivalent) is mandatory before merging any query that:
- Touches a table with more than 10,000 rows, or
- Runs in a hot path (per-request, high-frequency background job).

A full table scan on a large table is a blocker — add the index or rewrite the query before merging.

### N+1 Queries — Forbidden

Any loop that issues one query per iteration is a bug. Use:
- `WHERE id = ANY($1)` / `WHERE id IN (...)` batch fetch
- `JOIN` to load related data in one query
- CTEs for multi-step logic in one round trip

### Connection Pooling

The application never opens connections directly to the database without a pool. Pool configuration is explicit (min/max connections, idle timeout) — never rely on driver defaults for a production service. Pool is sized to the database's connection limit, not unbounded.

### Read Replicas

Non-critical reads (reports, analytics, audit log queries, cache-warming) route to a read replica. Application code declares intent explicitly — never implicit routing. Primary handles all writes and latency-sensitive reads.

---

## Cross-Links

Load the dialect file alongside this one for engine-specific rules:

| Engine | File |
| :----- | :--- |
| PostgreSQL | `conventions/databases/postgresql.md` |
| MySQL | `conventions/databases/mysql.md` |
| MariaDB | `conventions/databases/mariadb.md` |
| SQL Server | `conventions/databases/sqlserver.md` |
| Oracle | `conventions/databases/oracle.md` |
| SQLite | `conventions/databases/sqlite.md` (dev/test only) |
