---
type: convention
title: SQL Server — Dialect-Specific Rules
description: SQL Server-specific conventions covering schemas, T-SQL, online index operations, row-level security, Always Encrypted, temporal tables, and driver guidance — load alongside conventions/cross-stack/database.md.
applies_to: [all]
tags: [database, sql, sqlserver, mssql]
---

# SQL Server — Dialect-Specific Rules

Load alongside `conventions/cross-stack/database.md`. Covers SQL Server 2019+ and Azure SQL Database. T-SQL has meaningful differences from ANSI SQL — these conventions call out the most consequential ones.

---

## Schema Organisation

SQL Server has a four-part naming hierarchy: `server.database.schema.table`. Within a database, use **schemas** to namespace application domains — not separate databases per domain:

```sql
CREATE SCHEMA orders;
CREATE SCHEMA billing;
CREATE SCHEMA auth;

CREATE TABLE orders.order (id UNIQUEIDENTIFIER NOT NULL PRIMARY KEY DEFAULT NEWSEQUENTIALID(), ...);
CREATE TABLE billing.invoice (id UNIQUEIDENTIFIER NOT NULL PRIMARY KEY DEFAULT NEWSEQUENTIALID(), ...);
```

`dbo` schema is the default — reserve it for shared/system objects only, not application tables. Each domain gets its own schema.

---

## UUID / UNIQUEIDENTIFIER

SQL Server's native UUID type is `UNIQUEIDENTIFIER`. Use `NEWSEQUENTIALID()` as the default (not `NEWID()`):

```sql
id UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY
```

`NEWSEQUENTIALID()` generates time-ordered GUIDs — avoids the index fragmentation caused by `NEWID()` (random), which inserts values in random positions in the clustered index. For application-generated UUIDs (UUID v7), insert directly — SQL Server will store them in the `UNIQUEIDENTIFIER` column without conversion.

---

## Clustered vs Non-Clustered Indexes

SQL Server clustered indexes store the actual data rows in index order — choose the clustered index carefully:
- The primary key is clustered by default. If you use a random UUID PK, change the clustered index to a `NEWSEQUENTIALID()` PK or a dedicated `created_at` + surrogate key.
- Each table has exactly one clustered index. All non-clustered indexes contain the clustered key as a lookup pointer — wide clustered keys bloat every non-clustered index.
- Use `INCLUDE` on non-clustered indexes to create covering indexes without widening the key:

```sql
CREATE INDEX idx_orders_customer_id
  ON orders.order(customer_id)
  INCLUDE (status, created_at);
```

---

## Row-Level Security (RLS)

SQL Server 2016+ has native RLS — same pattern as PostgreSQL but different syntax:

```sql
-- Security predicate function
CREATE FUNCTION auth.fn_tenant_filter(@tenant_id UNIQUEIDENTIFIER)
RETURNS TABLE WITH SCHEMABINDING AS
RETURN SELECT 1 AS result
  WHERE @tenant_id = CAST(SESSION_CONTEXT(N'TenantId') AS UNIQUEIDENTIFIER);

-- Apply to table
CREATE SECURITY POLICY auth.tenant_policy
  ADD FILTER PREDICATE auth.fn_tenant_filter(tenant_id) ON orders.order,
  ADD BLOCK PREDICATE auth.fn_tenant_filter(tenant_id) ON orders.order AFTER INSERT
  WITH (STATE = ON);
```

Application sets tenant context at session start:

```sql
EXEC sp_set_session_context N'TenantId', @tenantId;
```

`FILTER PREDICATE` restricts reads. `BLOCK PREDICATE` restricts writes. Use both together for full isolation.

---

## Always Encrypted

For columns containing PII, financial data, or secrets that must be encrypted at rest and in transit (keys never exposed to the DB server):

```sql
CREATE TABLE users (
  id UNIQUEIDENTIFIER NOT NULL PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
  email NVARCHAR(255) COLLATE Latin1_General_BIN2
    ENCRYPTED WITH (
      COLUMN_ENCRYPTION_KEY = users_ek,
      ENCRYPTION_TYPE = DETERMINISTIC,  -- deterministic: allows equality search
      ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256'
    ) NOT NULL
);
```

- `DETERMINISTIC` encryption: same plaintext → same ciphertext. Allows `=` comparisons, no `LIKE` or range queries.
- `RANDOMIZED` encryption: same plaintext → different ciphertext each time. More secure, no equality search.
- Column Encryption Keys (CEK) and Column Master Keys (CMK) managed outside the DB (Azure Key Vault, Windows Certificate Store).

Use Always Encrypted for: SSN, payment card data, passwords (though those should be hashed, not encrypted), health data. Not a replacement for hashing passwords — `bcrypt`/`Argon2` hashing still applies.

---

## Temporal Tables (System-Versioned — 2016+)

Built-in row history — same concept as MariaDB system-versioned tables:

```sql
CREATE TABLE orders.order (
  id UNIQUEIDENTIFIER NOT NULL PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
  status NVARCHAR(50) NOT NULL,
  amount NUMERIC(12,2) NOT NULL,
  valid_from DATETIME2 GENERATED ALWAYS AS ROW START NOT NULL,
  valid_to   DATETIME2 GENERATED ALWAYS AS ROW END   NOT NULL,
  PERIOD FOR SYSTEM_TIME (valid_from, valid_to)
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = orders.order_history));

-- Query as of a point in time
SELECT * FROM orders.order FOR SYSTEM_TIME AS OF '2024-01-15T12:00:00';
```

Use for audit-critical tables. The database enforces history — the application cannot bypass it.

---

## T-SQL Specifics

**`NOCOUNT ON`** — always set in stored procedures and scripts to suppress row-count messages:

```sql
SET NOCOUNT ON;
```

Without it, every `INSERT`/`UPDATE`/`DELETE` sends a result set counting affected rows — breaks some ORM row-count checks and adds network overhead.

**`XACT_ABORT ON`** — always set in transactions:

```sql
SET XACT_ABORT ON;
BEGIN TRANSACTION;
-- if any statement errors, transaction is automatically rolled back
COMMIT;
```

Without `XACT_ABORT`, a runtime error inside a transaction does not automatically roll it back — leaves the connection in a broken transaction state.

**`TRY...CATCH`** — use for error handling in T-SQL batches, not client-side-only handling.

---

## Online Index Operations

```sql
-- Create index online (no table lock)
CREATE INDEX idx_orders_customer_id ON orders.order(customer_id) WITH (ONLINE = ON);

-- Rebuild index online
ALTER INDEX idx_orders_customer_id ON orders.order REBUILD WITH (ONLINE = ON);
```

`ONLINE = ON` available in Enterprise and Developer editions. Standard edition: online operations require a maintenance window. Azure SQL Database: online operations always available.

---

## Locking — `WITH (UPDLOCK, READPAST)`

Queue-style row claiming (equivalent to PostgreSQL's `SKIP LOCKED`):

```sql
SELECT TOP 1 id, payload
FROM jobs WITH (UPDLOCK, ROWLOCK, READPAST)
WHERE status = 'pending'
ORDER BY created_at;
```

- `UPDLOCK`: takes an update lock on read, preventing another transaction from taking the same lock.
- `READPAST`: skips locked rows instead of blocking — workers never block each other.
- `ROWLOCK`: hint to prefer row-level over page/table locks (SQL Server escalates locks — this suppresses escalation for this query).

---

## Connection Pooling

- SQL Server does connection pooling in the ADO.NET layer (built into the driver) and `sqlx`/`database/sql` in Go.
- Pool size: configure `max pool size` in the connection string. Default varies by driver.
- `Application Name` in the connection string: always set to the service name — visible in `sys.dm_exec_sessions`, essential for diagnosing which service holds a lock or runs a slow query.
- `Connection Timeout` and `Command Timeout`: always set explicitly. Default command timeout is often 30s — too low for long reports, too high to leave dangling for short API calls.

---

## Python (pyodbc / aioodbc / SQLAlchemy)

- `pyodbc` with Microsoft ODBC Driver 18 for SQL Server — the official, maintained driver.
- `aioodbc` for async access (wraps pyodbc with thread executor — not truly async, but non-blocking for the event loop).
- SQLAlchemy: `mssql+pyodbc` dialect. Use `fast_executemany=True` on the engine for bulk inserts.
- Connection string: `Driver={ODBC Driver 18 for SQL Server};Server=...;Encrypt=yes;TrustServerCertificate=no` — always encrypt.

## Go (go-mssqldb)

- `github.com/microsoft/go-mssqldb` — Microsoft's official Go driver.
- Use `database/sql` pool (`SetMaxOpenConns`, `SetConnMaxIdleTime`).
- Connection string DSN or URL format: `sqlserver://user:pass@host?database=mydb&encrypt=true&TrustServerCertificate=false`.
- `encrypt=true` always in production — plaintext connections blocked.
