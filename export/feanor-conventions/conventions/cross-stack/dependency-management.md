---
type: convention
title: Dependency Management
description: Lockfile pinning, stdlib-first bias, one package manager per stack, and vulnerability scanning for Go, Python, and TypeScript.
applies_to: [go, python, typescript]
tags: [dependencies, packages]
---

# Dependency Management

## Cross-Stack Rules

- Pin exact versions via lockfiles — `go.sum`, `uv.lock`, `bun.lock` are committed and are the source of truth for reproducible installs.
- Standard library first — before adding a dependency, check whether the stdlib or framework already covers it. Every external dependency is a maintenance burden and an attack-surface increase.
- One package manager per stack — no mixing (no npm/yarn/pnpm alongside bun, no pip alongside uv).
- Vulnerability scanning in CI — not a manual-only step.
- Don't default to a library out of habit — confirm it's the actively-maintained choice for the job.

## Go

- `go.mod` and `go.sum` committed. No vendoring unless there's a specific offline-build requirement.
- Module path matches the repository URL, lowercase, hyphens not underscores.
- Version conflicts resolved with `replace`/`exclude` directives, documented with a comment explaining why.
- `go mod tidy` keeps `go.mod` honest — run it before merge.
- Standard library covers a lot: `net/http`, `context`, `sync`, `log/slog`, `crypto/*` — reach for these before adding a dependency.

**Vulnerability scanning:**
```bash
govulncheck ./...   # run before merge; wire into CI or pre-commit
```

## Python

- `uv` is the package/environment manager. No pip/poetry/pipenv.
- `uv.lock` committed and is the source of truth.
- All commands via `uv`: `uv run pytest`, `uv run ruff check`, `uv sync --frozen` in CI/Docker.
- `uv run some_script.py` — no redundant `uv run python some_script.py`.
- One-off scripts with their own dependencies: use PEP 723 inline script metadata (`# /// script` block) rather than polluting `pyproject.toml`.
- Project init: `uv init --app --no-package` — produces the flat `app/` layout (`main.py` at root, no `src/`).

**`pyproject.toml` shape:**
```toml
[project]
requires-python = ">=3.12,<3.13"
# runtime deps: >= floors only, no upper bounds — uv.lock handles exact reproducibility
dependencies = ["fastapi>=0.115", "pydantic>=2.0"]

[dependency-groups]
# dev tooling never ships to production
dev = ["pytest", "ruff", "bandit"]
```

**Library defaults:**
- FastAPI over Flask/Django for new APIs.
- Pydantic v2 for validation/schemas.
- `httpx` over `requests` for HTTP clients (async-capable).

## TypeScript

- `bun install`, `bun add`, `bun run` — no npm/yarn/pnpm mixed in.
- `bun.lock` committed (current Bun writes this text format; older versions wrote the binary `bun.lockb` — either is valid, whichever your Bun version produces).
- All commands via `bun`, never bare `node`/`npx`.
- `bunx` for one-off tool execution instead of a global install.

**Framework-first bias:**
- Before adding a dependency, check whether Next.js/React already covers it: built-in image optimization, font loading, `fetch` caching, middleware.
- `package.json` version ranges follow the same philosophy as Python — no unnecessary upper-bound pinning; the lockfile handles exact reproducibility.
- Prefer actively-maintained, widely-adopted libraries (Zod, React Hook Form, TanStack Query only if actually needed) over single-author or unmaintained packages.

**Vulnerability scanning:**
```bash
bunx audit   # or: bun pm audit — run in CI
```
