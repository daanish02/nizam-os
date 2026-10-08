---
type: convention
title: Dockerfile - Go
description: Multi-stage Dockerfile and .dockerignore for a Go backend, building a static binary and deploying it into a minimal distroless/scratch runtime image.
applies_to: [go, ops]
tags: [ops, docker, go]
---

# Dockerfile — Go

`backend/Dockerfile` when this is the project's only backend service. **With multiple backend services** (per `go/project-layout.md`'s `services/<role>/` rule), this exact Dockerfile — unchanged content — is placed at `services/<role>/Dockerfile` for each Go service instead; it's the same convention applied per directory, not a different one. Builder → minimal static runtime. Go's static-binary compilation makes distroless/scratch viable — much smaller and lower attack-surface than Python's runtime image can be.

```dockerfile
# syntax=docker/dockerfile:1

FROM golang:1.25-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o /bin/server ./cmd/server

FROM gcr.io/distroless/static-debian12:nonroot AS runtime
COPY --from=builder /bin/server /bin/server
USER nonroot:nonroot
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s CMD ["/bin/server", "-healthcheck"]
ENTRYPOINT ["/bin/server"]
```

## Rules

- **Pin the base image.** Minor version tag, never `:latest` and never a bare major. Record the digest in a comment above each `FROM` so the exact image is auditable and refreshable:

  ```dockerfile
  # golang:1.25-alpine  digest as of {{PIN_DATE}}: sha256:{{DIGEST}}
  FROM golang:1.25-alpine AS runtime
  ```

  Refresh the tag and digest when picking up security updates — that is a reviewable commit, which a floating tag never is. Same rule for every image the build copies from. See `cross-stack/supply-chain.md`.
- `go.mod`/`go.sum` copied and `go mod download` run **before** `COPY . .` — same dependency-layer-caching rationale as the Python file.
- `CGO_ENABLED=0` — produces a fully static binary with no libc dependency, which is what makes `distroless/static` (not even `-alpine`) usable as the runtime base. If a dependency genuinely needs cgo, fall back to `distroless/base` or `alpine`, not further down to `scratch`.
- `-ldflags="-w -s"` strips debug symbols — smaller binary, no functional loss for a production image.
- `distroless/static-debian12:nonroot` — no shell, no package manager, no root user, nothing beyond the binary and CA certs. Distroless works cleanly for Go specifically because the binary has no runtime dependencies to satisfy, unlike Python.
- `HEALTHCHECK` runs the binary's own `-healthcheck` flag rather than `curl`/`wget`, since distroless has neither — the binary needs to support this flag itself (a lightweight self-check, not a full HTTP round-trip through the network stack).
- No build secrets baked into `ARG`/`ENV` layers — `--mount=type=secret` if a private module proxy needs credentials.

## `backend/.dockerignore` (or `services/<role>/.dockerignore` per service, multi-service case)

```text
bin/
*.test
*.out
.git/
.env
.env.*
logs/
.feanor/scratchpad/
```
