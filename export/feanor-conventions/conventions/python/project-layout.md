---
type: convention
title: Project Layout
description: Python project directory structure covering domain-based app/ layout, SQL/migration colocation, utils/ rules, single entry point, and multi-service services/ shape.
applies_to: [python]
tags: [python, layout, architecture]
---

# Project Layout

## Structure

Flat `app/` package (no `src/` layer), organized by **domain/feature**, not by generic technical layer. Don't create top-level `models/`, `services/`, `schemas/`, `routers/` dumping grounds shared across unrelated features — group each feature's router, schema, service, and models together under its own domain package.

Example shape (domain names are illustrative — always use the project's own domain vocabulary, never copy another project's package names verbatim):

```text
backend/
├── main.py                  # single entry point
├── app/
│   ├── config.py
│   ├── utils/               # genuinely cross-domain code only
│   ├── orders/
│   │   ├── router.py
│   │   ├── models.py
│   │   ├── queries/*.sql
│   │   └── prompts/*.md     # only if this domain drives an LLM
│   └── billing/
│       └── ...
├── tests/
│   ├── orders/
│   └── billing/
├── migrations/
│   ├── 001_init.sql
│   └── 002_add_invoices.sql
├── pyproject.toml           # requires-python = ">=3.12,<3.13"
├── uv.lock
├── Dockerfile
├── .venv/
├── logs/
└── .env
```

## Rules

- Any domain package that touches the DB gets its own `queries/*.sql` files — SQL lives in `.sql` files, never inlined as Python strings.
- Any domain package driving an LLM gets its own `prompts/*.md` files — prompts live in `.md` files, never inlined as Python strings.
- Migrations are forward-only, numbered (`migrations/001_x.sql`, `002_y.sql`, ...), tracked via a `schema_migrations` table.
- `tests/` mirrors `app/`'s package structure exactly.
- **Tunables split into two tiers:**
  - **Major** — config that's cross-cutting (used by 2+ modules, or genuinely environment-dependent: timeouts, pool sizes, feature flags read from env vars) lives in `app/config.py` as flat, explicit `UPPER_SNAKE_CASE` constants.
  - **Minor** — a constant that only one file/module actually uses (a magic number, a local threshold, a per-script setting) is declared as `UPPER_SNAKE_CASE` at the top of that file, above the code that uses it, not promoted to `config.py`. Keeps `config.py` from becoming a dumping ground, and keeps a tunable's blast radius (and the place you'd go to change it) exactly as wide as its actual usage.
  - Promote a minor tunable to `config.py` the moment a second file needs the same value — don't promote speculatively "in case something else needs it later" (YAGNI).
- **Every package `__init__.py` carries a one-line docstring** saying what the package owns. It is the only file that states a package's purpose, and an empty one documents nothing — a live run produced 19 empty `__init__.py` files across a whole backend.
  Add `__all__` once the package has a settled public surface, naming what callers may import so the rest stays internal. Do not write an empty `__all__` on a fresh package: it exports nothing and silently breaks `from app.x import *`. What belongs in it is a design decision about the package boundary, not a mechanical list of everything defined inside.
  `tests/` packages are the exception — keep those `__init__.py` files empty. A docstring there is noise.
- `utils/` holds only genuinely cross-domain code (used by 2+ domain packages — e.g. shared logging setup, date helpers, generic retry/pagination helpers). Anything used by a single domain stays inside that domain's package. `utils/` is not a catch-all.
- **Python version:** pin `requires-python = ">=3.12,<3.13"` in `pyproject.toml`. Lock the minor version; patch updates are allowed, minor bumps are not — prevents silent breakage when the runtime environment has a different minor installed. Use `uv python pin 3.12` to write `.python-version` so uv uses the same version locally.
- **uv version:** pin in CI and tooling docs, per [`../versions.toml`](../versions.toml) (currently `>=0.12.0,<0.13.0`). uv's minor releases sometimes change resolver behavior; patch-flexible is safe, minor-locked is not over-constrained.
- Single entry point: `main.py` at the service's root creates the app instance and wires routers/middleware/exception handlers. No other application code lives there — only `main.py`, `app/`, `tests/`, and project plumbing (`pyproject.toml`, `uv.lock`, `Dockerfile`, `.venv/`, `logs/`, `.env`, config files).
- **Directory name:** `backend/` when this is the project's only backend service. The moment a project has **more than one backend service** (this + a Go service, or two Python services split by responsibility), neither is called `backend/` anymore — each gets its own `services/<role>/` directory, named for what it does (`services/api/`, `services/ingest/`), not for its language. See `agents/architect-agent.md`'s `/scaffold` directive and `go/project-layout.md` for the same rule applied on the Go side.
