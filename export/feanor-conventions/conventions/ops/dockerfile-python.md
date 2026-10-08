---
type: convention
title: Dockerfile - Python
description: Multi-stage Dockerfile and .dockerignore for a uv-managed Python backend, layering dependencies before source to maximise cache reuse.
applies_to: [python, ops]
tags: [ops, docker, python]
---

# Dockerfile — Python

`backend/Dockerfile` when this is the project's only backend service. **With multiple backend services** (per `python/project-layout.md`'s `services/<role>/` rule), this exact Dockerfile — unchanged content — is placed at `services/<role>/Dockerfile` for each Python service instead; it's the same convention applied per directory, not a different one. Builder → runtime, dependencies layered before source so code changes don't invalidate the dependency-install cache.

```dockerfile
# syntax=docker/dockerfile:1

FROM python:3.12-slim AS builder
WORKDIR /app
COPY --from=ghcr.io/astral-sh/uv:0.12.0 /uv /uvx /bin/
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-install-project --no-dev
COPY . .
RUN uv sync --frozen --no-dev

FROM python:3.12-slim AS runtime
WORKDIR /app
RUN groupadd -r app && useradd -r -g app app
COPY --from=builder /app /app
ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1
USER app
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=3s CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1
CMD ["uv", "run", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

## Rules

- **Pin the base image.** Minor version tag, never `:latest` and never a bare major. Record the digest in a comment above each `FROM` so the exact image is auditable and refreshable:

  ```dockerfile
  # python:3.12-slim  digest as of {{PIN_DATE}}: sha256:{{DIGEST}}
  FROM python:3.12-slim AS runtime
  ```

  Refresh the tag and digest when picking up security updates — that is a reviewable commit, which a floating tag never is. Same rule for every image the build copies from. See `cross-stack/supply-chain.md`.
- Dependencies installed (`uv sync --no-install-project`) **before** `COPY . .` — the dependency layer only invalidates when `pyproject.toml`/`uv.lock` change, not on every code edit.
- `--frozen` — never resolve/update the lockfile inside the build; the lockfile is the source of truth, matching `python/dependency-management.md`.
- `--no-dev` in the final `uv sync` — dev-group tooling (pytest, ruff) never ships in the runtime image.
- Non-root `app` user in the runtime stage — never run as root.
- `python:3.12-slim` for both stages, not `-alpine` — Python's C-extension wheels frequently lack alpine/musl wheels, causing slow from-source builds; slim (Debian-based) is the better size/compatibility trade-off for Python specifically.
- `HEALTHCHECK` matches whatever health endpoint the service actually exposes — every service exposes one.
- A build secret (private package index credentials, etc.) uses `--mount=type=secret`, never an `ARG`/`ENV` baked into a layer — those persist in image history even after removal.

## `backend/.dockerignore` (or `services/<role>/.dockerignore` per service, multi-service case)

```text
.venv/
__pycache__/
*.pyc
.pytest_cache/
.ruff_cache/
.git/
.env
.env.*
logs/
.feanor/scratchpad/
tests/
```
