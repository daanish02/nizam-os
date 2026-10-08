---
type: convention
title: Oracle Database — Dialect-Specific Rules
description: Oracle-specific conventions covering schemas, sequences, VPD/RLS, Transparent Data Encryption, temporal queries, PL/SQL discipline, and driver guidance — load alongside conventions/cross-stack/database.md.
applies_to: [all]
tags: [database, sql, oracle, oracledb]
---

# Oracle Database — Dialect-Specific Rules

Load alongside `conventions/cross-stack/database.md`. Covers Oracle Database 19c+ (Long-Term Release). Oracle's SQL dialect (PL/SQL) and architecture differ more from ANSI SQL than any other major RDBMS — these conventions call out the most consequential differences.

---

## Schema = User in Oracle

In Oracle, a schema and a database user are the same object. Every user owns a schema of the same name. This is different from SQL Server (schema is a namespace) and PostgreSQL (schema and user are separate):

- Create one application user/schema per service: `app_orders`, `app_billing`, `app_auth`.
- Application connects as a low-privilege user (`app_rw`) that has been granted access to the schema objects — it does not connect as the schema owner.
- Schema owner is used only for DDL (migrations) — never for the running application.
- Cross-schema references: `schema_name.table_name` — explicit, never rely on synonyms for core app queries (synonyms hide the real object location and break during refactors).

---

## UUID Strategy

Oracle 18c+ has no native UUID type. Store as:
- `RAW(16)` — most efficient (16 bytes, binary comparison). Use `SYS_GUID()` for Oracle-generated GUIDs (not UUID v4 — Oracle GUIDs are not RFC 4122 compliant but are 128-bit unique). For UUID v7: generate in the application and insert as `HEXTORAW(REPLACE(:uuid, '-', ''))`.
- `VARCHAR2(36)` — readable, 36 bytes. Acceptable for low-volume tables, but `RAW(16)` is preferred.

Oracle 23c introduces the `UUID` type — use it if on 23c+.

---

## Sequences

Oracle uses explicit `SEQUENCE` objects for auto-increment — there is no `SERIAL` or `AUTO_INCREMENT`:

```sql
CREATE SEQUENCE orders_seq START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;

-- In INSERT (pre-12c):
INSERT INTO orders (id, ...) VALUES (orders_seq.NEXTVAL, ...);

-- In INSERT (12c+ identity column, preferred):
id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY
```

For distributed systems use the application-generated UUID approach (above) to avoid sequence contention across nodes.

`NOCACHE` prevents gaps from being lost on instance restart. `CACHE` (default 20) is faster but leaves gaps. For order numbers or invoice numbers where gaps are unacceptable (audit requirement), use `NOCACHE ORDER`.

---

## NULL Behaviour — Oracle Diverges from ANSI

**Oracle treats empty string `''` as `NULL`.** This is non-standard and a frequent source of bugs:

```sql
-- In Oracle, these are identical:
WHERE col = ''     -- never matches anything (NULL != anything)
WHERE col IS NULL  -- correct check for empty string or null

-- INSERT '' is stored as NULL
INSERT INTO users (name) VALUES ('');  -- name is NULL, not empty string
```

Never compare against empty string — always use `IS NULL` / `IS NOT NULL`. When the application sends an empty string that should be stored as empty, store a sentinel value instead (space, or redesign the schema to not need empty strings).

---

## Virtual Private Database (VPD) — Row-Level Security

Oracle's equivalent of PostgreSQL RLS and SQL Server RLS:

```sql
-- Policy function: returns a WHERE clause predicate
CREATE OR REPLACE FUNCTION auth.tenant_filter(
  schema_name IN VARCHAR2,
  table_name  IN VARCHAR2
) RETURN VARCHAR2 AS
BEGIN
  RETURN 'tenant_id = SYS_CONTEXT(''APP_CTX'', ''TENANT_ID'')';
END;

-- Apply policy to table
DBMS_RLS.ADD_POLICY(
  object_schema   => 'ORDERS',
  object_name     => 'ORDER',
  policy_name     => 'TENANT_ISOLATION',
  function_schema => 'AUTH',
  policy_function => 'TENANT_FILTER',
  statement_types => 'SELECT, INSERT, UPDATE, DELETE'
);
```

Application sets context at session start:

```sql
DBMS_SESSION.SET_CONTEXT('APP_CTX', 'TENANT_ID', :tenant_id);
```

VPD policies are enforced transparently — the predicate is appended to every query on the table, invisible to the application. Schema owner and users with `EXEMPT ACCESS POLICY` bypass VPD — never grant that privilege to the application user.

---

## Transparent Data Encryption (TDE)

Oracle TDE encrypts data files, redo logs, and backups at rest. Enabled at tablespace level:

```sql
CREATE TABLESPACE app_data
  DATAFILE 'app_data01.dbf' SIZE 100M
  ENCRYPTION USING AES256
  DEFAULT STORAGE (ENCRYPT);
```

TDE encryption is transparent to the application — no code changes required. Keys managed via Oracle Wallet or Oracle Key Vault. Always enable TDE for production databases handling PII, financial data, or regulated content.

For column-level encryption (selective, like SQL Server Always Encrypted): Oracle DBMS_CRYPTO — specialist use, requires explicit encrypt/decrypt calls in SQL and PL/SQL.

---

## Temporal Queries (Flashback)

Oracle Flashback — query historical data without a separate history table:

```sql
-- Query as of a timestamp (within undo retention period)
SELECT * FROM orders AS OF TIMESTAMP (SYSTIMESTAMP - INTERVAL '1' HOUR);

-- Query as of an SCN (System Change Number — precise)
SELECT * FROM orders AS OF SCN 123456789;

-- Flashback entire table to a point in time (DDL — requires privilege)
FLASHBACK TABLE orders TO TIMESTAMP (SYSTIMESTAMP - INTERVAL '30' MINUTE);
```

Flashback is governed by `UNDO_RETENTION` — data is available only within the retention window (default 15 minutes, often tuned to hours for production). Not a substitute for proper audit tables for long-term history.

For permanent row history: Oracle Workspace Manager or manual history tables — Flashback is for recovery and short-term investigation, not compliance audit trails.

---

## PL/SQL Discipline

PL/SQL (Oracle's procedural SQL extension) is powerful but creates tight coupling between the database and application logic. Rules:

- **No business logic in PL/SQL procedures/functions** — business logic belongs in the application layer. PL/SQL is acceptable for: data migrations, batch jobs, triggers for audit logging, and complex set-based data transformations that are genuinely faster in the DB.
- **Triggers**: only for audit logging and enforcing DB-level constraints that cannot be expressed as CHECK constraints. Never for business logic that should be testable in the application. Document every trigger — they are invisible to most query analysis.
- **Stored procedures**: document the exact caller(s) — a stored procedure with no documented caller is dead code the migrator role cannot safely drop.
- `EXECUTE IMMEDIATE` (dynamic SQL): parameterize everything — it is as vulnerable to SQL injection as application-layer string concatenation.

---

## Online DDL (12c+)

```sql
-- Add column online (instant in most cases)
ALTER TABLE orders ADD (notes CLOB);

-- Add index online
CREATE INDEX idx_orders_customer_id ON orders(customer_id) ONLINE;

-- Redefine table online (major restructuring without lock)
-- Use DBMS_REDEFINITION for complex DDL on large tables
EXEC DBMS_REDEFINITION.START_REDEF_TABLE('ORDERS', 'ORDER', 'ORDER_NEW', ...);
```

`ONLINE` index creation in Oracle is equivalent to PostgreSQL's `CONCURRENTLY` — the table remains accessible. For large-scale table restructuring, `DBMS_REDEFINITION` is the Oracle equivalent of `gh-ost`.

---

## Connection Pooling

Oracle requires connection pooling — spawning a new Oracle connection is expensive (process-based architecture on older versions, threaded on 12c+, but still heavyweight vs. PostgreSQL).

- **DRCP (Database Resident Connection Pooling)**: pool at the DB server level — useful for many short-lived application processes (serverless, ephemeral workers). Enabled with `CONNECTION_CLASS` in the connection string.
- **Application-side pool**: standard pool via the driver (`cx_Oracle`/`oracledb` pool in Python, Go's `database/sql` pool).
- Oracle `SERVICE_NAME` preferred over `SID` in connection strings — `SERVICE_NAME` supports failover and RAC routing; `SID` is instance-specific.

---

## Python (python-oracledb)

- `python-oracledb` (successor to `cx_Oracle`) — Oracle's official Python driver. Thin mode requires no Oracle Client installation (19c+ server); Thick mode for older server features.
- Async: `python-oracledb` supports async from 2.0+ (`AsyncConnection`, `AsyncPool`).
- Named bind variables (`:name`) preferred over positional — more readable in complex queries.
- `arraysize` and `prefetchrows` tuning for bulk fetches — defaults are conservative.

## Go (godror)

- `github.com/godror/godror` — Go Oracle driver using ODPI-C. Requires Oracle Instant Client.
- `database/sql` interface — use standard pool (`SetMaxOpenConns`, `SetConnMaxIdleTime`).
- Named parameters via `sql.Named("name", value)` — Oracle uses `:name` syntax.
- `godror.DSN` for connection string construction — avoids manual formatting of Oracle DSN format.
