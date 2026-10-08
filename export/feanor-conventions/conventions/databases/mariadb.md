---
type: convention
title: MariaDB — Dialect-Specific Rules
description: MariaDB-specific conventions covering InnoDB/Aria, sequences, JSON, Galera, online DDL, and divergence from MySQL — load alongside conventions/cross-stack/database.md.
applies_to: [all]
tags: [database, sql, mariadb]
---

# MariaDB — Dialect-Specific Rules

Load alongside `conventions/cross-stack/database.md`. This file covers what is specific to MariaDB (10.6+ LTS). MariaDB forked from MySQL in 2009 and has diverged substantially — do not treat them as interchangeable. Most SQL syntax is shared, but behaviour, types, and features differ enough to warrant separate conventions.

---

## MariaDB vs MySQL — Key Divergences

| Area | MariaDB | MySQL |
| :--- | :--- | :--- |
| JSON type | `LONGTEXT` with JSON functions (10.2+); no binary JSON storage | Binary `JSON` type, validated on insert |
| Sequences | Native `CREATE SEQUENCE` (like PostgreSQL) | No native sequences — emulated with `AUTO_INCREMENT` tables |
| UUID type | `UUID` native type (10.7+) | No native UUID — use `BINARY(16)` |
| Window functions | Supported 10.2+ | Supported 8.0+ |
| Full-text search | Mroonga / InnoDB FTS | InnoDB FTS |
| Temporal tables | Native system-versioned tables (10.3+) | No native equivalent |
| Online DDL | Instant DDL (10.3+) for many operations | INPLACE DDL via InnoDB |
| Galera Cluster | Native multi-master via Galera | Group Replication (different model) |
| Oracle compatibility | `sql_mode=ORACLE` for PL/SQL-like syntax | No Oracle compatibility mode |

---

## Storage Engine

**InnoDB for transactional data.** Aria for internal MariaDB system use (crash-safe non-transactional — not for application data). Columnstore for analytics workloads (column-oriented, separate installation).

- InnoDB: same ACID guarantees as MySQL InnoDB — use for all application tables.
- Aria: do not use for application data. It is MariaDB's replacement for MyISAM for internal tables.
- Spider: for sharding — specialist use only, explicit architectural decision required.

---

## Native UUID Type (10.7+)

MariaDB 10.7+ has a native `UUID` type (16 bytes, stored as binary, displayed as hex-hyphen string):

```sql
CREATE TABLE users (
  id UUID NOT NULL DEFAULT uuid() PRIMARY KEY
);
```

`uuid()` generates a UUID v1 (time-based, not v4 random). For UUID v7 (time-ordered, random): generate in the application layer and insert as a string — MariaDB will coerce to the UUID type.

For 10.6 and earlier: use `BINARY(16)` with the same approach as MySQL.

---

## Character Set

Same rule as MySQL: **`utf8mb4` with `utf8mb4_unicode_ci`** everywhere. MariaDB's `utf8` is also 3-byte (same MySQL legacy). `utf8mb4` is real UTF-8.

---

## Sequences (10.3+)

MariaDB supports proper sequences — use them instead of `AUTO_INCREMENT` tables for shared counters:

```sql
CREATE SEQUENCE order_number_seq START WITH 1000 INCREMENT BY 1 NOCYCLE;

SELECT NEXT VALUE FOR order_number_seq;
-- or:
SELECT NEXTVAL(order_number_seq);
```

Sequences are gap-safe, concurrency-safe, and do not require a lock on an `AUTO_INCREMENT` table.

---

## System-Versioned Tables (Temporal — 10.3+)

Built-in historical record keeping — the DB tracks all row versions automatically:

```sql
CREATE TABLE orders (
  id UUID NOT NULL PRIMARY KEY,
  status VARCHAR(50) NOT NULL,
  amount NUMERIC(12,2) NOT NULL
) WITH SYSTEM VERSIONING;

-- Query as of a point in time
SELECT * FROM orders FOR SYSTEM_TIME AS OF '2024-01-15 12:00:00';

-- Full history of a row
SELECT *, ROW_START, ROW_END FROM orders
  FOR SYSTEM_TIME ALL
  WHERE id = 'some-uuid';
```

Use for audit-critical tables (financial records, order history, user events) instead of a manual `audit_log` table. The database enforces the history — the application cannot accidentally skip it.

---

## Online DDL — Instant (10.3+)

MariaDB `ALGORITHM=INSTANT` for many DDL operations — zero table scan, near-zero lock:

```sql
-- Add column: instant in 10.3+
ALTER TABLE orders ADD COLUMN notes TEXT, ALGORITHM=INSTANT;

-- Add index: uses INPLACE (not instant, but online)
ALTER TABLE orders ADD INDEX idx_customer_id (customer_id), ALGORITHM=INPLACE, LOCK=NONE;
```

`INSTANT` is faster than PostgreSQL's `CONCURRENTLY` and MySQL's `INPLACE` for supported operations — prefer it. Fall back to `INPLACE, LOCK=NONE` for index creation. For operations requiring `COPY`, use `pt-online-schema-change` on large tables.

---

## JSON (10.2+)

MariaDB's `JSON` type is `LONGTEXT` with a `JSON_VALID()` check constraint — not binary storage like PostgreSQL's `JSONB` or MySQL 8.0's `JSON`. Implications:
- No binary path indexing — must use generated columns for indexed JSON fields (same pattern as MySQL).
- `JSON_EXTRACT`, `JSON_UNQUOTE`, `JSON_SET` functions work the same as MySQL 8.0.
- Larger on-disk footprint than binary JSON for large documents.

```sql
-- Generated column + index for JSON field (same as MySQL)
ALTER TABLE events
  ADD COLUMN event_type VARCHAR(64)
    GENERATED ALWAYS AS (JSON_UNQUOTE(JSON_EXTRACT(payload, '$.type'))) STORED,
  ADD INDEX idx_event_type (event_type);
```

---

## Galera Cluster (Multi-Master)

If using Galera for high availability:
- All tables must use InnoDB — Galera does not replicate MyISAM or Aria tables.
- Avoid large transactions — Galera certifies entire transactions; large transactions cause certification failures and retries.
- `wsrep_sync_wait` — set appropriately for read-after-write consistency requirements.
- Auto-increment: Galera uses `wsrep_auto_increment_control` to avoid PK conflicts across nodes — do not disable it. For true globally-unique IDs, prefer UUID over `AUTO_INCREMENT`.
- DDL in Galera: use `wsrep_OSU_method=RSU` for large table DDL to avoid blocking the whole cluster.

---

## Strict Mode

Same as MySQL — ensure `STRICT_TRANS_TABLES` is in `sql_mode`:

```sql
SET GLOBAL sql_mode = 'STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO';
```

---

## Python

- `aiomysql` works with MariaDB (MariaDB's MySQL-compatible protocol).
- `mariadb` (official connector, `pip install mariadb`) for synchronous access — native protocol, supports MariaDB-specific features.
- SQLAlchemy: use the `mariadb` or `mysql+aiomysql` dialect. Specify `mariadb_engine_version` if using MariaDB-specific DDL in migrations.

## Go

- `github.com/go-sql-driver/mysql` works with MariaDB (compatible protocol).
- Connection string: same as MySQL. Add `&allowNativePasswords=true` if using `mysql_native_password` auth.
