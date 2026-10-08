---
type: catalog
title: Ops Conventions Index
description: Dockerfile and .dockerignore standards for each stack (Python, Go, Next.js), stored in backend/ or frontend/.
applies_to: [ops]
tags: [ops, docker, dockerfile]
---

# Ops Conventions

Multi-stage Docker builds, one convention file per stack (build/runtime steps differ enough per language to warrant separate files, same reasoning as keeping `auth.md` per-language rather than one merged doc).

- [dockerfile-python.md](./dockerfile-python.md) - `backend/Dockerfile` + `.dockerignore` for a `uv`-managed Python service.
- [dockerfile-go.md](./dockerfile-go.md) - `backend/Dockerfile` + `.dockerignore` for a Go service.
- [dockerfile-nextjs.md](./dockerfile-nextjs.md) - `frontend/Dockerfile` + `.dockerignore` for a Bun-managed Next.js app.
- [root-layout.md](./root-layout.md) - Canonical repo-root structure on `main`, per-service env vars, `.github/` vs. `.pre-commit-config.yaml`, and the `feanor/`/`.feanor/`/`CLAUDE.md` pre-`main` boundary.

A project uses whichever backend file matches its actual language (Python or Go — see `python/index.md`/`go/index.md`, both backend-only) plus the frontend file if it has a Next.js frontend. With more than one backend service (see `python/project-layout.md`/`go/project-layout.md`'s `services/<role>/` rule), the matching Dockerfile is placed once per service at `services/<role>/Dockerfile` — same content, applied per directory.
