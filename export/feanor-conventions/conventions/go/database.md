---
type: convention
title: Database
description: Go database rules covering pgx/sqlx library choice, parameterized queries, connection pooling configuration, and migration tooling.
applies_to: [go]
tags: [go, database, sql]
---

# Database

## Library Choice

- `pgx` for PostgreSQL specifically (faster, PostgreSQL-native features). `sqlx` when portability across databases matters. No ORMs (GORM, ent) — they generate unpredictable queries and hide the actual SQL being run.
- SQL lives in `.sql` files under each domain package's `queries/`, same as `python/project-layout.md` — never a raw string literal buried in Go code.

## Rules

- Parameterized queries only — never concatenate user input into SQL. Dynamic `IN` clauses and column names use an explicit allowlist, never raw interpolation.
- Every DB call uses the `*Context` method variant (`QueryContext`, `ExecContext`) and propagates the caller's `context.Context`.
- Distinguish "not found" explicitly: `errors.Is(err, sql.ErrNoRows)`, not a generic error check.
- `defer rows.Close()` on every `Query`/`QueryContext` call — an unclosed `Rows` leaks the connection.
- Struct scanning: nullable columns use pointer fields or `sql.NullXxx` types, never a zero-value guess.
- Connection pool configured explicitly (`SetMaxOpenConns`, `SetConnMaxIdleTime`) — don't rely on driver defaults for a production service.
- Transactions: explicit isolation level when it matters (e.g. `SELECT FOR UPDATE` for a real concurrency concern), not assumed.

## Migrations

- Forward-only, numbered files (`migrations/001_init.sql`, `002_add_invoices.sql`), same convention as `python/project-layout.md`.
- Applied via an external migration tool (`golang-migrate`, `atlas`) — never a hand-run script, never generated/applied by the application itself at startup in production.
