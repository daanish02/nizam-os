---
type: convention
title: Backend Database Connection Layer
description: Standards for how backend services connect to relational databases — connection strings, pool sizing, startup validation, retry, graceful shutdown, read/write routing, and secrets injection.
applies_to: [all]
tags: [database, sql, db-connection, backend]
---

# Backend Database Connection Layer

These rules govern how a backend service establishes, maintains, and tears down its connection to a relational database. They apply regardless of language or RDBMS. For query and schema rules see `conventions/cross-stack/database.md`; for engine-specific pool config see `conventions/databases/{engine}.md`.

---

## Connection String

### Format

Use the standard URI format — portable across drivers and tooling:

```
scheme://user:password@host:port/dbname?param=value&param=value
```

Examples:
```
postgresql://app_rw:secret@db.internal:5432/myapp?sslmode=require&connect_timeout=5
mysql://app_rw:secret@db.internal:3306/myapp?tls=true&parseTime=true
sqlserver://app_rw:secret@db.internal:1433?database=myapp&encrypt=true
```

### Required Parameters

Every production connection string must include:

| Parameter | Purpose |
| :--- | :--- |
| `user` | The least-privilege application role (`app_rw` or `app_ro`) — never the schema owner or superuser |
| `password` | From environment variable — never hardcoded |
| `host` | Resolved hostname or VPC-internal IP — never `localhost` in production |
| `port` | Explicit — never rely on driver defaults |
| `dbname` | Explicit — never rely on driver defaults |
| TLS/SSL | `sslmode=require` (PostgreSQL), `tls=true` (MySQL/MariaDB), `encrypt=true` (SQL Server), `ssl=true` (Oracle) |
| `connect_timeout` | Seconds before a connection attempt gives up (recommended: 5–10s) |

### Where It Lives

- **Local / dev**: `DATABASE_URL` environment variable, loaded from `.env`.
- **Staging / production**: injected by the secrets manager (AWS Secrets Manager, Azure Key Vault, HashiCorp Vault, GCP Secret Manager) at runtime — never baked into the image or config file.
- **Never**: hardcoded in source code, committed to the repo, or written to a log.

### Read Replica

If the service uses a read replica, expose it as a separate env var:

```
DATABASE_URL=postgresql://app_rw:...@primary.db.internal:5432/myapp?sslmode=require
DATABASE_RO_URL=postgresql://app_ro:...@replica.db.internal:5432/myapp?sslmode=require
```

The application explicitly routes queries — writes and latency-sensitive reads to `DATABASE_URL`, reporting/analytics/cache-warming reads to `DATABASE_RO_URL`. Never implicit or automatic routing.

---

## Connection Pool

### Sizing

Never use unbounded pools or driver defaults in production. Set explicitly:

```
min_connections = 2
max_connections = (cpu_cores × 2) + effective_spindle_count
```

For most cloud VMs (4 vCPU, SSD): `max = 9`. For high-concurrency services, tune upward under load testing — do not guess.

The database server's `max_connections` is a hard cap shared across all application instances. Account for multiple instances:

```
pool_max_per_instance = floor(db_max_connections / instance_count) - headroom
```

Leave headroom (5–10 connections) for admin tools, migration runner, monitoring.

### Idle Connection Timeout

Set `idle_timeout` / `conn_max_idle_time` (name varies by driver). Connections idle longer than the DB server's `wait_timeout` / `tcp_keepalive` period go stale — the pool must recycle them before the DB closes them:

```
idle_timeout = 10 minutes  (well under typical server idle timeout of 30–60 min)
max_lifetime = 30 minutes  (recycle connections periodically even if active)
```

### Connection Validation

Enable pre-use validation where the driver supports it (ping / `testOnBorrow`). Catches stale connections from:
- DB server restart
- Network timeout
- Load balancer reset

If the driver does not support automatic validation, issue `SELECT 1` before use in critical paths.

---

## Startup: DB Availability Check

The service must not accept traffic until a working DB connection is confirmed. On startup:

1. Attempt `SELECT 1` (or equivalent ping) on the pool.
2. If it fails: wait with exponential backoff (start 1s, double, cap at 30s), retry up to 10 times.
3. If all retries fail: crash with a clear log message (`FATAL: cannot connect to database after 10 attempts: <error>`). Do not start in a degraded state silently.
4. Only after a successful ping: start the HTTP server and begin accepting traffic.

This prevents the common failure mode where a service starts, returns 500s to every request, and the load balancer thinks it is healthy because the process is running.

For Kubernetes: expose this as a `startupProbe` (see `conventions/cross-stack/health-endpoints.md`) — not a `readinessProbe` — so the container restarts if the DB is permanently unreachable on startup, rather than looping indefinitely.

---

## Runtime: Transient Error Retry

Retry on connection-level transient errors only:

| Retry | Do not retry |
| :--- | :--- |
| Connection refused | Query errors (syntax, constraint violation) |
| Connection timeout | Permission denied |
| Network reset / EOF | Duplicate key |
| Deadlock (engine-specific) | Data not found |

Retry policy:
- Max 3 attempts for a single query operation.
- Exponential backoff with jitter between attempts (base 100ms, cap 2s).
- Log every retry with the error, attempt number, and query identifier (never the full query with parameters).
- After max retries: surface the error to the caller — do not swallow it.

Deadlock handling: the database rolls back one transaction automatically on deadlock. The application must catch the deadlock error and retry the entire transaction from the start (not just the failed query) — **under the same 3-attempt cap and backoff as above**. An uncapped deadlock retry turns contention into a self-sustaining load spike, because every retry re-enters the same conflict.

Retries must be safe to repeat. A transaction that also sends an email, charges a card, or publishes an event will do it again on each attempt — move those side effects outside the retried transaction, or make them idempotent (see `api-design.md`).

---

## Graceful Shutdown

On `SIGTERM` (container stop, deployment, scale-in):

1. Stop accepting new requests immediately (close the HTTP listener or set a "draining" flag).
2. Wait for in-flight requests to complete — with a deadline (recommended: 30s).
3. After in-flight requests drain (or deadline passes): close the connection pool cleanly.
4. Exit with code `0`.

Never kill a service mid-transaction. An abrupt shutdown leaves the DB in an unknown state and may hold locks that block other services.

Implement this as a signal handler:

```python
# Python (FastAPI / Starlette)
@asynccontextmanager
async def lifespan(app):
    # startup
    await db_pool.connect()
    yield
    # shutdown — called on SIGTERM before process exits
    await db_pool.disconnect()
```

```go
// Go
quit := make(chan os.Signal, 1)
signal.Notify(quit, syscall.SIGTERM, syscall.SIGINT)
<-quit
ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
defer cancel()
server.Shutdown(ctx)
db.Close()
```

---

## Read / Write Routing

Explicit in code — never ambient or automatic:

```python
# Python — two separate pool references
async with db.primary() as conn:    # writes, latency-sensitive reads
    await conn.execute(INSERT ...)

async with db.replica() as conn:    # reports, analytics, cache-warming
    rows = await conn.fetch(SELECT ...)
```

```go
// Go — two separate *sql.DB
func (r *OrderRepo) Create(ctx context.Context, o Order) error {
    return r.primary.ExecContext(ctx, insertSQL, ...)
}

func (r *OrderRepo) ListForReport(ctx context.Context) ([]Order, error) {
    return queryRows(ctx, r.replica, reportSQL)
}
```

Replica lag is real — never route a read to a replica if the calling code expects to see a write it just made in the same request.

---

## Secret Rotation

When credentials are rotated (scheduled or emergency):

1. The secrets manager injects the new credential at runtime — the application must re-read it without a full restart.
2. The connection pool must support hot credential reload — or implement a pool drain + reconnect on rotation signal (webhook, file watch, or periodic re-read from secrets manager).
3. Old connections using the previous credential must be drained and closed after rotation, not left running indefinitely.

If the driver/pool does not support hot reload: implement a rolling restart strategy — rotate secret, restart instances one at a time, each picks up the new credential on startup.

---

## Language-Specific Notes

### Python

- `asyncpg.create_pool()` / SQLAlchemy `create_async_engine()` — both support `min_size`, `max_size`, `max_inactive_connection_lifetime`.
- Parse `DATABASE_URL` with `urllib.parse.urlparse` or the driver's own URL parser — never split manually.
- `asyncpg` pool exposes `pool.acquire()` as an async context manager — always use it, never hold a raw connection reference across `await` points.

### Go

- `sql.DB` is the pool — call `db.SetMaxOpenConns()`, `db.SetMaxIdleConns()`, `db.SetConnMaxIdleTime()`, `db.SetConnMaxLifetime()` immediately after `sql.Open()`.
- `sql.Open()` does not connect — it just validates the DSN. Call `db.PingContext(ctx)` explicitly to verify the connection on startup.
- Pass `context.Context` to every DB call — enables cancellation and deadline propagation through the pool.

### TypeScript / Next.js

- Server-side DB connections only — never open a DB connection from a Client Component, API route that runs at the edge, or any browser-side code.
- Use a singleton pattern for the pool in Next.js to avoid creating a new pool on every hot-reload in development.
- `DATABASE_URL` must be a server-only env var (no `NEXT_PUBLIC_` prefix — that would expose it to the browser bundle).
