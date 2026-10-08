---
type: convention
title: Python Conventions Index
description: Python-specific layout, async/concurrency, typing, naming, and tooling (Ruff) standards for Python backends; cross-stack topics (auth, caching, error-handling, code-comments, etc.) live in ../cross-stack/.
applies_to: [python]
tags: [python]
---

# Python Conventions

Python is used for **backend services only** in Feanor-managed projects.

Cross-stack topics (auth, caching, error-handling, module-boundaries, observability-logging, rate-limiting, security, testing, dependency-management) moved to [`../cross-stack/`](../cross-stack/). The files below are Python-specific only.

## Python-Specific Files

- [project-layout.md](./project-layout.md) - Domain-based `app/` structure, `.sql`/`.md` colocation, `utils/`, single entry point.
- [async-concurrency.md](./async-concurrency.md) - Async-first FastAPI, structured concurrency, context managers, thread/process offload.
- [code-style.md](./code-style.md) - PEP 8 naming, type hint requirements, Pydantic v2 usage.
- [tooling.md](./tooling.md) - Ruff lint + format baseline, rule rationale, CI/pre-commit commands.

## Cross-Stack (all languages)

See [`../cross-stack/`](../cross-stack/) for: auth, caching, error-handling, module-boundaries, observability-logging, rate-limiting, security, testing, dependency-management.
