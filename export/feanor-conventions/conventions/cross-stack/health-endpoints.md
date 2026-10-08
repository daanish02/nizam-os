---
type: convention
title: Health Endpoints
description: Standard /health endpoint contract every backend service must expose — response shape, status codes, what to check, and what not to expose.
applies_to: [all]
tags: [health, api-design, observability, backend]
---

# Health Endpoints

Every backend service exposes a `/health` endpoint. It is the single agreed contract between a service and anything that monitors it — load balancers, uptime monitors, deployment pipelines, and other services that depend on it.

---

## Required Endpoint

```
GET /health
```

No authentication. No API key. Unauthenticated — anything that needs to check health must be able to do so without credentials. The endpoint must never return sensitive data (see Security below).

---

## Response Shape

```json
{
  "status": "ok",
  "version": "1.4.2",
  "checks": {
    "database": "ok",
    "cache": "ok"
  }
}
```

| Field | Required | Description |
| :--- | :--- | :--- |
| `status` | yes | `"ok"` or `"degraded"` or `"error"` — top-level summary |
| `version` | yes | Deployed version. **Major version only (`"3"`) on a publicly reachable endpoint** — an exact build string tells an unauthenticated attacker precisely which CVEs apply. Expose the full version either on an authenticated/internal-only endpoint or via a header the deployment platform strips at the edge. |
| `checks` | yes | Object of named dependency checks. Key = dependency name. Value = `"ok"` or `"error"`. |

Add a dependency to `checks` only if the service cannot function without it. A non-critical dependency that can degrade gracefully does not belong in `checks` — its failure should not flip the top-level status.

---

## Status Codes

| Scenario | HTTP Status | `status` field |
| :--- | :--- | :--- |
| Everything healthy | `200` | `"ok"` |
| Service running but a critical dependency is degraded | `200` | `"degraded"` |
| Service cannot handle requests | `503` | `"error"` |

Return `200` even for `"degraded"` — the service is still running and the caller can decide what to do. Return `503` only when the service itself cannot process requests at all. A `503` tells a load balancer to stop routing traffic to this instance.

---

## What to Check

Check only dependencies whose failure makes the service unable to handle any request:

| Dependency | Check | How |
| :--- | :--- | :--- |
| Primary database | Connection alive | `SELECT 1` (or equivalent ping) |
| Cache (if required for every request) | Connection alive | `PING` |
| Message broker (if required for every request) | Connection alive | lightweight ping command |

**Do not check:**
- Third-party external APIs (Stripe, SendGrid, etc.) — their downtime is not your service's health. Track it in your metrics/alerting instead.
- Read replicas — a failed replica should not mark the service unhealthy if the primary is fine.
- Optional/degraded-gracefully dependencies — if the service handles their absence, don't check them here.

---

## Timeout

The health check itself must complete within **2 seconds**. If any dependency check exceeds 2 seconds, mark that check as `"error"` and return — do not block indefinitely.

The DB ping for `/health` uses a **separate, short-timeout connection** — not a connection borrowed from the main application pool. Borrowing from the pool can deadlock under high load (pool exhausted, health check waiting for a connection, health check itself needed to pass before traffic routes back).

---

## Security

The `/health` endpoint is public and unauthenticated. It must never expose:

- Internal hostnames, IP addresses, or ports
- Database connection strings or usernames
- Dependency versions (library versions, DB engine versions) — version information aids attackers
- Stack traces or error messages with internal paths

`version` exposes the application version only — acceptable and useful for deployment verification. Nothing else identifying internal infrastructure.

---

## Implementation

### Python (FastAPI)

```python
from fastapi import FastAPI, Response
import asyncpg, os

app = FastAPI()

@app.get("/health")
async def health(response: Response):
    checks = {}
    status = "ok"

    try:
        conn = await asyncpg.connect(os.environ["DATABASE_URL"], timeout=2)
        await conn.fetchval("SELECT 1")
        await conn.close()
        checks["database"] = "ok"
    except Exception:
        checks["database"] = "error"
        status = "error"

    if status == "error":
        response.status_code = 503

    return {"status": status, "version": os.getenv("APP_VERSION", "unknown"), "checks": checks}
```

### Go

```go
func healthHandler(db *sql.DB) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        checks := map[string]string{}
        status := "ok"

        ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
        defer cancel()

        if err := db.PingContext(ctx); err != nil {
            checks["database"] = "error"
            status = "error"
        } else {
            checks["database"] = "ok"
        }

        code := http.StatusOK
        if status == "error" {
            code = http.StatusServiceUnavailable
        }

        w.Header().Set("Content-Type", "application/json")
        w.WriteHeader(code)
        json.NewEncoder(w).Encode(map[string]any{
            "status":  status,
            "version": os.Getenv("APP_VERSION"),
            "checks":  checks,
        })
    }
}
```

### TypeScript / Next.js

```typescript
// app/api/health/route.ts
import { NextResponse } from "next/server";
import { db } from "@/lib/db";

export async function GET() {
  const checks: Record<string, string> = {};
  let status = "ok";

  try {
    await db.execute("SELECT 1");
    checks.database = "ok";
  } catch {
    checks.database = "error";
    status = "error";
  }

  return NextResponse.json(
    { status, version: process.env.APP_VERSION ?? "unknown", checks },
    { status: status === "error" ? 503 : 200 }
  );
}
```

---

## Dockerfile HEALTHCHECK Alignment

The `HEALTHCHECK` in `Dockerfile` must hit this endpoint:

```dockerfile
# Python
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1

# Go (distroless — no curl)
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD ["/bin/server", "-healthcheck"]

# Next.js
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD bun -e "fetch('http://localhost:3000/api/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
```

`--start-period` gives the service time to complete startup (including the DB availability check from `db-connection.md`) before the `HEALTHCHECK` starts counting failures.

---

## What `/health` Is Not

- Not a metrics endpoint — use `/metrics` (Prometheus format) for that.
- Not a readiness probe separate from liveness — one `/health` endpoint covers both. Split them only if a deployment system explicitly requires separate routes.
- Not a debugging endpoint — no query params, no verbose mode, no internal state dump.
