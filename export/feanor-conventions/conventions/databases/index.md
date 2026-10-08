---
type: meta
title: Database Dialect Conventions Index
description: Catalog of RDBMS dialect-specific convention files — each supplements conventions/cross-stack/database.md with engine-specific rules.
applies_to: [all]
tags: [database, sql, index]
---

# Database Dialect Conventions

Always load `conventions/cross-stack/database.md` first (RDBMS-agnostic rules), then the dialect file for the engine in use.

| Engine | File | Production-ready? |
| :----- | :--- | :--- |
| PostgreSQL | [postgresql.md](./postgresql.md) | Yes |
| MySQL 8.0+ | [mysql.md](./mysql.md) | Yes |
| MariaDB 10.6+ | [mariadb.md](./mariadb.md) | Yes |
| SQL Server 2019+ / Azure SQL | [sqlserver.md](./sqlserver.md) | Yes |
| Oracle Database 19c+ | [oracle.md](./oracle.md) | Yes |
| SQLite | [sqlite.md](./sqlite.md) | Dev/test only |

## Tag Mapping (for context-resolver.md)

| Tag | Files loaded |
| :--- | :--- |
| `database`, `sql` | `cross-stack/database.md` |
| `postgresql`, `postgres` | `cross-stack/database.md` + `databases/postgresql.md` |
| `mysql` | `cross-stack/database.md` + `databases/mysql.md` |
| `mariadb` | `cross-stack/database.md` + `databases/mariadb.md` |
| `sqlserver`, `mssql` | `cross-stack/database.md` + `databases/sqlserver.md` |
| `oracle`, `oracledb` | `cross-stack/database.md` + `databases/oracle.md` |
| `sqlite` | `cross-stack/database.md` + `databases/sqlite.md` |
