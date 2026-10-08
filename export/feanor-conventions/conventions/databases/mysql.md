---
type: convention
title: MySQL — Dialect-Specific Rules
description: MySQL-specific conventions covering InnoDB, character sets, online DDL, JSON, locking, and driver guidance — load alongside conventions/cross-stack/database.md.
applies_to: [all]
tags: [database, sql, mysql]
---

# MySQL — Dialect-Specific Rules

Load alongside `conventions/cross-stack/database.md`. This file covers only what is specific to MySQL (8.0+). For MariaDB, see `conventions/databases/mariadb.md` — they have diverged significantly despite sharing syntax.

---

## Storage Engine

**InnoDB only.** MyISAM, MEMORY, and other engines are not acceptable for application data:
- InnoDB: ACID transactions, FK enforcement, row-level locking, crash recovery.
- MyISAM: no transactions, no FK support, table-level locking — only valid for legacy read-only full-text search (superseded by InnoDB full-text in MySQL 5.6+).

Verify: `SHOW TABLE STATUS WHERE Engine != 'InnoDB'` — any non-InnoDB application table is a bug.

---

## Character Set and Collation

**`utf8mb4` with `utf8mb4_unicode_ci` collation everywhere.** MySQL's `utf8` is a lie — it stores only 3-byte UTF-8 (no emoji, no supplementary characters). `utf8mb4` is real UTF-8.

Set at server, database, table, and column level:

```sql
CREATE DATABASE myapp CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE users (
  email VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL
);
```

For case-sensitive comparisons (passwords, tokens, binary data): use `utf8mb4_bin` on that column specifically.

Never mix collations in a JOIN — silent data loss or wrong results.

---

## No Native UUID Type

MySQL 8.0 has no native UUID type (unlike PostgreSQL). Store UUID v7 as:
- `BINARY(16)` — most efficient (16 bytes, fast comparison, proper indexing). Store/retrieve with `UUID_TO_BIN()` / `BIN_TO_UUID()`.
- `CHAR(36)` — readable but 36 bytes, slower index comparisons. Acceptable for low-volume tables.

Do not use `VARCHAR(36)` with hyphen-formatted UUIDs on high-volume tables — the string comparison overhead compounds at scale.

---

## Enum Type Caution

MySQL has a native `ENUM` column type but it has dangerous behaviour:
- Adding a new value requires `ALTER TABLE` (locking, unless online DDL).
- Removing a value does not error — existing rows keep the old value as a numeric ordinal.
- The underlying storage is an integer ordinal, making dumps non-obvious.

**Prefer `VARCHAR` + `CHECK` constraint** for value sets that may change. Use native `ENUM` only for truly stable, small value sets where the DDL lock is acceptable.

---

## Online DDL (Zero-Downtime Migrations)

MySQL 8.0 supports online DDL via `ALGORITHM` and `LOCK` clauses:

```sql
-- Add column online (no lock)
ALTER TABLE orders
  ADD COLUMN notes TEXT,
  ALGORITHM=INPLACE, LOCK=NONE;

-- Add index online (no lock)
ALTER TABLE orders
  ADD INDEX idx_orders_customer_id (customer_id),
  ALGORITHM=INPLACE, LOCK=NONE;
```

Not all operations support `ALGORITHM=INPLACE, LOCK=NONE` — check the MySQL 8.0 online DDL reference for each operation type. For operations that require a copy (`ALGORITHM=COPY`), use `pt-online-schema-change` or `gh-ost` for large tables to avoid production locks.

---

## JSON Column

MySQL 8.0 has a native `JSON` type (binary storage, validated on insert, path expression queries):

```sql
CREATE TABLE events (
  id BINARY(16) NOT NULL,
  payload JSON NOT NULL
);

-- Query JSON path
SELECT * FROM events WHERE JSON_EXTRACT(payload, '$.type') = 'order.placed';

-- Generated column + index on JSON field (the correct way to index JSON)
ALTER TABLE events
  ADD COLUMN event_type VARCHAR(64) GENERATED ALWAYS AS (JSON_UNQUOTE(JSON_EXTRACT(payload, '$.type'))) STORED,
  ADD INDEX idx_event_type (event_type);
```

Do not index `JSON` columns directly — generate a stored column and index that instead.

---

## Transactions and Locking

- Always use InnoDB — only engine with row-level locking.
- `SELECT ... FOR UPDATE` supported. `SKIP LOCKED` supported from MySQL 8.0 — use for queue patterns.
- `LOCK IN SHARE MODE` (`FOR SHARE` in 8.0+) for read locks that block writes.
- Deadlocks are normal — the application must handle `ER_LOCK_DEADLOCK` (1213) with a retry. InnoDB detects and rolls back the shorter transaction automatically.

---

## Connection Pooling

- Use `ProxySQL` or application-level pool (`mysql-connector-python` pool, `sqlx` pool in Go).
- `max_connections` on MySQL server is a hard cap — size pool accordingly. Default 151 is often too low for multi-instance deployments.
- `wait_timeout` and `interactive_timeout` will close idle connections — configure pool `keepalive` ping to avoid `MySQL server has gone away` errors.

---

## Strict Mode

Ensure `sql_mode` includes `STRICT_TRANS_TABLES` and `NO_ZERO_DATE`:

```sql
SET GLOBAL sql_mode = 'STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION';
```

Without strict mode, MySQL silently truncates strings, coerces invalid dates, and inserts zero values — produces corrupt data with no error.

---

## Python (mysql-connector / PyMySQL / SQLAlchemy)

- `aiomysql` for async access (asyncio-native).
- `SQLAlchemy` with `aiomysql` dialect for async ORM/Core.
- Set `charset='utf8mb4'` explicitly in the connection string — drivers may default to `utf8`.
- Use `autocommit=False` explicitly — rely on explicit `BEGIN`/`COMMIT`, not autocommit mode.

## Go (go-sql-driver/mysql)

- `github.com/go-sql-driver/mysql` is the standard driver.
- Connection string: `user:pass@tcp(host:3306)/db?parseTime=true&charset=utf8mb4&collation=utf8mb4_unicode_ci`
- `parseTime=true` — parses `DATETIME`/`TIMESTAMP` into `time.Time` automatically.
- Use `database/sql` pool (`SetMaxOpenConns`, `SetConnMaxIdleTime`) — driver does not pool by default.
