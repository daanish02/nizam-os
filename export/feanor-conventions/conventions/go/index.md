---
type: convention
title: Go Conventions Index
description: Go-specific layout, style/naming, concurrency, and database standards for Go backends; cross-stack topics (auth, caching, error-handling, etc.) live in ../cross-stack/.
applies_to: [go]
tags: [go]
---

# Go Conventions

Go is used for **backend services only** in Feanor-managed projects.

Cross-stack topics (auth, caching, error-handling, module-boundaries, observability-logging, rate-limiting, security, testing, dependency-management) moved to [`../cross-stack/`](../cross-stack/). The files below are Go-specific only.

## Go-Specific Files

- [code-style-naming.md](./code-style-naming.md) - MixedCaps, anti-stuttering, constructors, interfaces, doc comments, control flow.
- [concurrency-context.md](./concurrency-context.md) - Goroutine lifecycle, channels vs. mutex vs. atomic, errgroup, context propagation.
- [database.md](./database.md) - sqlx/pgx, parameterized queries, connection pooling, migrations.
- [project-layout.md](./project-layout.md) - `cmd/`/`internal/`/`pkg/` structure, module naming, 12-factor.

## Cross-Stack (all languages)

See [`../cross-stack/`](../cross-stack/) for: auth, caching, error-handling, module-boundaries, observability-logging, rate-limiting, security, testing, dependency-management.

## Optional (generate only if the project actually needs it — YAGNI)

| Topic | Generate when... |
| :--- | :--- |
| Dependency injection (wire/dig/fx) | The project actually adopts a DI framework — most services don't need one. |
| `grpc.md` | The backend exposes a gRPC API. |
| `graphql.md` | The backend exposes a GraphQL API. |

Functional-options pattern is already covered in `code-style-naming.md`; graceful shutdown is already covered in `concurrency-context.md` — no standalone "design patterns" file.

## Explicitly not used

`samber`'s personal library ecosystem (`lo`, `mo`, `do`, `hot`, `ro`, `oops`) is deliberately not adopted as a default — stdlib (`log/slog`, `sync`, `context`) and widely-adopted community libraries (`sqlx`/`pgx`, `golang.org/x/time/rate`, `errgroup`, `testify`) are used instead, matching the same "modern, actively-maintained, industry-standard" bar set in `../cross-stack/dependency-management.md`.

`golangci-lint` config lives in [../git/pre-commit-hooks.md](../git/pre-commit-hooks.md) alongside the Python hooks, not here.
