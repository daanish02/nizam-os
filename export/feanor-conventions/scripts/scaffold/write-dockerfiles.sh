#!/usr/bin/env bash
# Writes Dockerfile + .dockerignore for one deployable service, verbatim from
# conventions/ops/dockerfile-{python,go,nextjs}.md.
#
# Those conventions were complete and correct, and nothing generated them — a
# full live run produced a project with no Dockerfile anywhere. Documented
# boilerplate that no script emits is boilerplate an agent retypes from memory,
# which is the drift meta/determinism-standard.md exists to prevent.
#
# One Dockerfile per INDEPENDENTLY DEPLOYABLE unit, in that unit's own
# directory: backend/ and frontend/ each get one; under services/, every
# service gets its own, because that is what makes it a service. There is no
# root Dockerfile.
#
# Usage:
#   write-dockerfiles.sh python  [--dir backend]
#   write-dockerfiles.sh go      [--dir services/worker]
#   write-dockerfiles.sh nextjs  [--dir frontend]
#
# Refuses to overwrite an existing Dockerfile — a service whose image was
# hand-tuned must not be silently reset by a re-run.

set -euo pipefail

STACK="${1:-}"
shift || true

TARGET_DIR=""
if [ "${1:-}" = "--dir" ]; then
  TARGET_DIR="$2"
  shift 2
fi

case "$STACK" in
  python) : "${TARGET_DIR:=backend}" ;;
  go)     : "${TARGET_DIR:=backend}" ;;
  nextjs) : "${TARGET_DIR:=frontend}" ;;
  *)
    echo "usage: write-dockerfiles.sh {python|go|nextjs} [--dir <path>]" >&2
    exit 1
    ;;
esac

if [ ! -d "$TARGET_DIR" ]; then
  echo "write-dockerfiles: $TARGET_DIR does not exist — run the scaffold script first." >&2
  exit 1
fi

if [ -f "$TARGET_DIR/Dockerfile" ]; then
  echo "write-dockerfiles: $TARGET_DIR/Dockerfile already exists — leaving it alone."
  exit 0
fi

case "$STACK" in
python)
cat > "$TARGET_DIR/Dockerfile" <<'EOF'
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
EOF
cat > "$TARGET_DIR/.dockerignore" <<'EOF'
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
EOF
;;

go)
cat > "$TARGET_DIR/Dockerfile" <<'EOF'
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
EOF
cat > "$TARGET_DIR/.dockerignore" <<'EOF'
bin/
*.test
*.out
.git/
.env
.env.*
logs/
.feanor/scratchpad/
EOF
;;

nextjs)
cat > "$TARGET_DIR/Dockerfile" <<'EOF'
# syntax=docker/dockerfile:1

FROM oven/bun:1.3-slim AS deps
WORKDIR /app
COPY package.json bun.lock* ./
RUN bun install --frozen-lockfile

FROM oven/bun:1.3-slim AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
ENV NEXT_TELEMETRY_DISABLED=1
RUN bun run build

FROM oven/bun:1.3-slim AS runtime
WORKDIR /app
RUN groupadd -r nextjs && useradd -r -g nextjs nextjs
ENV NODE_ENV=production \
    NEXT_TELEMETRY_DISABLED=1
COPY --from=builder /app/public ./public
COPY --from=builder --chown=nextjs:nextjs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nextjs /app/.next/static ./.next/static
USER nextjs
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=3s CMD bun -e "fetch('http://localhost:3000/api/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["bun", "server.js"]
EOF
cat > "$TARGET_DIR/.dockerignore" <<'EOF'
node_modules/
.next/
out/
.git/
.env
.env.*
!.env.example
*.log
.feanor/scratchpad/
coverage/
EOF
# next.config must emit a standalone build or the runtime stage copies nothing.
if [ -f "$TARGET_DIR/next.config.ts" ] && ! grep -q "standalone" "$TARGET_DIR/next.config.ts"; then
  echo "NOTE: add  output: \"standalone\"  to $TARGET_DIR/next.config.ts —"
  echo "      the runtime stage copies .next/standalone, which is not built without it."
fi
;;
esac

echo "Wrote $TARGET_DIR/Dockerfile and $TARGET_DIR/.dockerignore ($STACK)"
