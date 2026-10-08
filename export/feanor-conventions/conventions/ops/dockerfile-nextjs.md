---
type: convention
title: Dockerfile - Next.js
description: Multi-stage Dockerfile and .dockerignore for a Bun-managed Next.js frontend using Next.js standalone output to minimise the runtime image.
applies_to: [nextjs, ops]
tags: [ops, docker, nextjs, bun]
---

# Dockerfile — Next.js

`frontend/Dockerfile`, three stages: deps → build → runtime. Uses Next.js's `standalone` output mode (`next.config.ts`: `output: "standalone"`) so the runtime image only needs the traced production dependencies, not the full `node_modules`.

```dockerfile
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
```

## Rules

- **Pin the base image.** Minor version tag, never `:latest` and never a bare major. Record the digest in a comment above each `FROM` so the exact image is auditable and refreshable:

  ```dockerfile
  # oven/bun:1.3-slim  digest as of {{PIN_DATE}}: sha256:{{DIGEST}}
  FROM oven/bun:1.3-slim AS runtime
  ```

  Refresh the tag and digest when picking up security updates — that is a reviewable commit, which a floating tag never is. Same rule for every image the build copies from. See `cross-stack/supply-chain.md`.
- `package.json`/`bun.lock*` copied and installed **before** `COPY . .`, same dependency-layer-caching rationale as the backend files. The glob matches whichever lockfile the project has — Bun writes the text `bun.lock` by default and the binary `bun.lockb` only on older versions, so naming one exactly breaks the build on the other.
- `--frozen-lockfile` — never resolve/update inside the build, matching `nextjs/dependency-management.md`.
- `output: "standalone"` in `next.config.ts` is required for this Dockerfile shape — it produces a `server.js` plus only the dependencies actually traced as used, instead of copying all of `node_modules` (often 10x+ larger) into the runtime image.
- Runtime stage never runs `bun install` — it only copies already-built artifacts, so build tooling and full `node_modules` never enter the final image.
- Non-root `nextjs` user, same as every other runtime stage in this project.
- `NEXT_TELEMETRY_DISABLED=1` — no external telemetry calls from a production build.
- A route like `/api/health` (or a lightweight custom one) is required for the `HEALTHCHECK` to have something real to hit — add one if the project doesn't already have it.

## `frontend/.dockerignore`

```text
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
```
