---
type: catalog
title: Scaffold Scripts Index
description: Real, dry-run-verified scaffold scripts called by /scaffold instead of re-derived from prose.
applies_to: [scripts, all]
tags: [scripts, scaffold]
---

# Scaffold Scripts

Each script was actually run end-to-end (not just read/eyeballed) during a Feanor dry run — the flags in each are the ones proven to work non-interactively, including two real bugs the naive/documented-elsewhere flags didn't catch (`uv init` defaulting to a `src/` layout; `shadcn init -y` alone hanging on an unsuppressed prompt).

- [init-branches.sh](./init-branches.sh) - Creates `qa` and cuts `feature/<slug>` from it, per `../../conventions/git/branch-strategy.md`. Idempotent. Must run **first** in `/scaffold`, before anything writes a file — scaffolding commits land on whatever branch is checked out, and a branch cannot be cut retroactively once they are on `main`.
- [python-backend.sh](./python-backend.sh) - `uv init --app --no-package` + domain packages + `conftest.py`, per `../../conventions/python/project-layout.md`.
- [go-backend.sh](./go-backend.sh) - `go mod init` + `cmd/`/`internal/` layout, per `../../conventions/go/project-layout.md`. Syntax-checked only — no Go toolchain was available to run it end-to-end during the dry run that produced this script; verify on first real use.
- [nextjs-frontend.sh](./nextjs-frontend.sh) - `create-next-app` + `shadcn init` (with the non-obvious `-b radix -p nova` flags actually required to run non-interactively) + domain feature dirs, per `../../conventions/nextjs/project-layout.md`.

If one of these needs a new flag/behavior added, re-verify it the same way — run it for real against a scratch directory, don't just edit the script and assume it still works.

## Cross-Stack Boilerplate Scripts

These write verbatim boilerplate sourced from the `conventions/cross-stack/` files. They are not verified end-to-end against a live project — verify on first real use.

- [write-dockerfiles.sh](./write-dockerfiles.sh) — `bash scripts/scaffold/write-dockerfiles.sh [python|go|nextjs] [--dir <path>]`: Writes `Dockerfile` + `.dockerignore` verbatim from `../../conventions/ops/dockerfile-*.md` into one deployable service directory. One per independently deployable unit; no root Dockerfile. Refuses to overwrite an existing Dockerfile.
- [write-check-script.sh](./write-check-script.sh) — `bash scripts/scaffold/write-check-script.sh`: Writes `scripts/check.sh` at the project root — lint, format-check, and tests for every stack present, in one command. Every ticket's `verification_command` calls it, because that field is a single shell-free command and cannot chain lint with tests itself.
- [write-error-types.sh](./write-error-types.sh) — `bash scripts/scaffold/write-error-types.sh [go|python|typescript]`: Writes the typed error hierarchy boilerplate from `cross-stack/error-handling.md` to `backend/internal/domain/errors.go`, `backend/app/core/exceptions.py`, or `frontend/src/lib/errors.ts`.
- [write-logging-setup.sh](./write-logging-setup.sh) — `bash scripts/scaffold/write-logging-setup.sh [go|python|typescript]`: Writes the structured logging setup boilerplate from `cross-stack/observability-logging.md` to `backend/internal/infra/logger.go`, `backend/app/core/logging.py`, or `frontend/src/lib/logger.ts`.
- [write-rate-limiter.sh](./write-rate-limiter.sh) — `bash scripts/scaffold/write-rate-limiter.sh [go|python|typescript]`: Writes the rate limiter middleware boilerplate from `cross-stack/rate-limiting.md` to `backend/internal/middleware/rate_limiter.go` or `backend/app/core/rate_limiter.py`. For `typescript`, prints a redirect to `cross-stack/security.md` and exits — Next.js rate limiting lives in `middleware.ts`, not a standalone file.
