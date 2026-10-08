---
type: convention
title: Project Layout
description: Go project directory structure covering cmd/internal/pkg layout, module naming conventions, and 12-factor compliance rules.
applies_to: [go]
tags: [go, layout, architecture]
---

# Project Layout

## Structure

```text
backend/
├── cmd/
│   └── server/
│       └── main.go          # single entry point per binary
├── internal/                 # private code, not importable by other modules
│   ├── config/
│   ├── orders/                # domain package — router/handler, models, queries
│   │   ├── handler.go
│   │   ├── models.go
│   │   └── queries.go
│   └── billing/
├── pkg/                       # ONLY if something here is meant to be imported by other projects
├── migrations/
│   ├── 001_init.sql
│   └── 002_add_invoices.sql
├── go.mod                    # go 1.24  (exact minor — Go modules don't support ranges)
└── go.sum
```

- `cmd/<binary-name>/main.go` — one entry point per binary, thin (wiring only, no business logic).
- `internal/` — everything not meant to be imported outside this module. Default here; most code belongs in `internal/`.
- `pkg/` — only for code deliberately meant as a public, importable library. Don't default to `pkg/` just because a Go tutorial used it — an empty or near-empty `pkg/` is a sign it shouldn't exist.
- Domain packages under `internal/` follow the same domain-based grouping as `python/project-layout.md` — group by business capability (`orders/`, `billing/`), not by generic technical layer (`handlers/`, `models/`, `services/` as shared dumping grounds).
- Migrations: forward-only, numbered, same convention as `python/project-layout.md` — applied via an external migration tool (`golang-migrate`, `atlas`), never hand-run.
- **Tunables split into two tiers, same as `python/project-layout.md`:** cross-cutting config (used by 2+ packages, or environment-dependent) lives in `internal/config/` as exported constants/a config struct. A constant only one file uses is declared `MixedCaps` (unexported if package-local) at the top of that file, not promoted to `internal/config/` — promote only once a second file actually needs it (YAGNI), not speculatively.
- **Directory name:** `backend/` when this is the project's only backend service, same rule as `python/project-layout.md`. With **more than one backend service** (this + a Python service, or two Go services split by responsibility), this stops being `backend/` and becomes its own `services/<role>/` directory, named for what it does, not its language. See `agents/architect-agent.md`'s `/scaffold` directive for how the target directory gets decided.

## Go Version

Pin the Go version as an exact minor in `go.mod`: `go 1.24`, matching [`../versions.toml`](../versions.toml). Go toolchain does not support version ranges — the `go` directive locks the minimum; set it to exactly the version you develop and deploy against so `go.sum` doesn't drift across environments. Update intentionally (one minor at a time, verify `go vet ./...` and `go test ./...` pass after).

## 12-Factor Compliance

- Config via environment variables, never hardcoded or config-file-only.
- Logs to stdout (structured, see `observability-logging.md`) — the process doesn't manage its own log files; the runtime environment does.
- Stateless process — no in-memory session/state that would break horizontal scaling; externalize to the database/cache.

## Right-Sizing

A small CLI tool or single-file utility doesn't need `cmd/`/`internal/`/`pkg/` layering or dependency injection — this structure is for backend services with real growth surface. Don't impose it on something that doesn't need it.
