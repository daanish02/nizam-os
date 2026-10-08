---
type: convention
title: HTTP Middleware Stack
description: Standard middleware chain every backend service must wire — execution order, request ID, CORS, logging, auth, rate-limiting, timeout, and error handling. Language-specific wiring examples included.
applies_to: [all]
tags: [middleware, api-design, observability, auth, security, backend]
---

# HTTP Middleware Stack

Every backend service wires a consistent middleware chain. Order is not optional — wrong order creates security holes, missing context, or incorrect behaviour. This file defines the canonical stack, what each layer must do, and what it must never do.

---

## Canonical Execution Order

Middleware executes top-to-bottom on the way in, bottom-to-top on the way out (request/response wrapping). This is the required order:

```
1. Panic Recovery          ← outermost — catches everything below
2. Request ID              ← generates/forwards correlation ID before any logging
3. Request Logging         ← logs method, path, IP — request ID already set
4. CORS                    ← preflight handled before auth (unauthenticated OPTIONS)
5. Timeout                 ← request deadline set before any work begins
6. Authentication          ← identity established before rate-limit (rate-limit keys by user)
7. Rate Limiting           ← keyed by authenticated user ID or IP fallback
8. [Route Handlers]        ← business logic
9. Error Handler           ← catches errors from handlers, returns structured JSON
```

**Why this order matters:**
- Panic recovery must be outermost — anything below can panic.
- Request ID before logging — every log line needs the ID.
- CORS before auth — `OPTIONS` preflight is unauthenticated; auth middleware must not block it.
- Timeout before auth — the deadline must wrap the entire request including auth checks.
- Auth before rate-limit — rate-limit keys on user ID when available; IP-only fallback is weaker.
- Error handler innermost (closest to handlers) — catches handler errors, formats them uniformly.

---

## 1. Panic Recovery

Catches any unhandled panic below it, logs the stack trace (server-side only), and returns a `500` with a generic error body. Without this, a panic crashes the goroutine/thread serving the request and may bring down the process.

**Must:**
- Log the full stack trace server-side (for debugging).
- Return `{"error": "internal server error"}` to the client — no stack trace, no panic message, no internal paths.
- Include the request ID in the log so the panic is traceable.

**Must not:**
- Swallow panics silently (no log = invisible crash).
- Expose internal details in the response.

---

## 2. Request ID

Every request gets a unique correlation ID that flows through logs, downstream service calls, and error responses.

**Rules:**
- Check for `X-Request-ID` header from the caller (API gateway, upstream service, load balancer). If present and valid (non-empty, printable, ≤ 128 chars): use it.
- If absent: generate a new UUID v4.
- Store in request context — all downstream code accesses it from context, never from a global.
- Echo back in response header: `X-Request-ID: <id>`.
- Include in every log line (structured logging field `request_id`).
- Include in every error response body: `{"error": "...", "request_id": "<id>"}`.

Never trust the incoming `X-Request-ID` blindly — validate length and character set. A caller can inject an arbitrarily long or malicious string if not validated.

---

## 3. Request Logging

Log one structured entry per request — on the way out (after the response is written), so status code and latency are available.

**Log these fields:**

| Field | Value |
| :--- | :--- |
| `request_id` | From context (set by middleware 2) |
| `method` | `GET`, `POST`, etc. |
| `path` | URL path only — no query string if it may contain tokens |
| `status` | HTTP response status code |
| `latency_ms` | Request duration in milliseconds |
| `ip` | Client IP (from `X-Forwarded-For` if behind a proxy, else `RemoteAddr`) |
| `user_id` | Authenticated user ID if available (set after auth middleware runs) |

**Never log:**
- Request or response bodies — may contain PII, passwords, card numbers.
- `Authorization` header or any credential header.
- Query parameters that may contain tokens or secrets (log the path only, or redact known sensitive param names).
- Full `X-Forwarded-For` chain verbatim — take only the first IP, which is the client.

---

## 4. CORS

Cross-Origin Resource Sharing must be configured explicitly — never use a wildcard `*` origin in production for any endpoint that handles credentials or auth tokens.

**Rules:**
- Allowlist specific origins (`https://app.example.com`, `https://admin.example.com`). Wildcard `*` only for fully public, unauthenticated, read-only APIs.
- Allowed methods: exactly what the API uses (`GET`, `POST`, `PUT`, `PATCH`, `DELETE`, `OPTIONS`). Not `*`.
- Allowed headers: `Content-Type`, `Authorization`, `X-Request-ID` — and any custom headers the API uses. Not `*`.
- `credentials: true` (cookies / `Authorization` header) requires a specific non-wildcard origin — the spec forbids `credentials: true` with `*`.
- `OPTIONS` preflight must return `204` with the correct headers immediately — before auth runs.
- `Max-Age` on preflight: `86400` (24h) — reduces preflight request volume.

Configure once in the middleware layer. Never set CORS headers per-handler — they will be missed on some routes.

---

## 5. Timeout

Every request gets a hard deadline. Without a timeout, a slow DB query or hung downstream call holds a connection and eventually exhausts the pool.

**Default timeout: 30 seconds.** Adjust per service profile:
- Standard API: 30s
- File upload endpoint: 120s (explicit override at route level)
- Webhook receiver: 10s
- Report/export endpoint: 120s (explicit override)

When the timeout fires:
- Return `503 Service Unavailable` with `{"error": "request timeout", "request_id": "<id>"}`.
- Log as a timeout (not as a 503 error — different alert threshold).
- Cancel the request context — DB queries and downstream calls propagated through context will be cancelled automatically.

---

## 6. Authentication

Validate identity once, in one place. Never re-check tokens per handler.

**Rules:**
- Extract token from `Authorization: Bearer <token>` header. Cookies for session-based auth.
- Validate the token (signature, expiry, issuer, audience) — see `cross-stack/auth.md` for full rules.
- On valid token: store the parsed identity (user ID, roles, scopes) in request context.
- On invalid/missing token for a protected route: return `401 Unauthorized` immediately — do not call the handler.
- Public routes (health check, login, public content): skip auth. Use a route group or explicit opt-out — never a global skip.
- Downstream handlers read identity from context only — never re-parse the token.

---

## 7. Rate Limiting

Applied after auth so the limiter can key on user ID (tighter, fairer) rather than IP alone (spoofable, shared NAT).

**Key selection:**
- Authenticated user: key on `user_id` from context.
- Unauthenticated (public endpoints): key on client IP.
- Auth endpoints specifically: key on IP (user has no ID yet) with a tighter limit.

**Response on limit exceeded:**
```http
HTTP/1.1 429 Too Many Requests
Retry-After: 60
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 1718000000

{"error": "rate limit exceeded", "retry_after": 60, "request_id": "<id>"}
```

See `cross-stack/rate-limiting.md` for limit values and algorithm.

---

## 8. Error Handler

The innermost middleware — wraps handlers and catches any error they return or propagate.

**Rules:**
- All handler errors surface through a single error type hierarchy — not raw `500` from unhandled exceptions.
- Map error types to HTTP status codes consistently:

| Error type | Status |
| :--- | :--- |
| Validation error | `400` |
| Unauthenticated | `401` |
| Forbidden | `403` |
| Not found | `404` |
| Conflict (duplicate) | `409` |
| Rate limited | `429` |
| Unhandled / internal | `500` |
| DB / dependency unavailable | `503` |

**Response shape (all errors):**
```json
{
  "error": "human-readable message safe for the client",
  "code": "MACHINE_READABLE_CODE",
  "request_id": "uuid"
}
```

`code` is a stable machine-readable string (e.g. `EMAIL_TAKEN`, `INVALID_TOKEN`, `RESOURCE_NOT_FOUND`) — never changes between releases, safe for clients to switch on. `error` is human-readable and may change.

**Never include in error responses:**
- Stack traces
- Internal file paths
- DB error messages (may leak schema details)
- Library names or versions

---

## Language-Specific Wiring

### Python (FastAPI)

```python
# main.py — wire in order, outermost first
app = FastAPI()

app.add_middleware(PanicRecoveryMiddleware)   # 1
app.add_middleware(RequestIDMiddleware)        # 2
app.add_middleware(RequestLoggingMiddleware)   # 3
app.add_middleware(
    CORSMiddleware,                            # 4
    allow_origins=settings.CORS_ORIGINS,
    allow_methods=["GET","POST","PUT","PATCH","DELETE"],
    allow_headers=["Content-Type","Authorization","X-Request-ID"],
    allow_credentials=True,
    max_age=86400,
)
app.add_middleware(TimeoutMiddleware, timeout=30)  # 5
# Auth (6) and rate-limit (7) as FastAPI dependencies on route groups, not global middleware
# Error handler (8)
app.add_exception_handler(AppError, app_error_handler)
app.add_exception_handler(Exception, unhandled_error_handler)
```

FastAPI note: auth and rate-limit are better as `Depends()` on router groups than as Starlette middleware — they have access to the parsed route and can opt out public routes cleanly.

### Go (net/http / chi)

```go
// main.go
r := chi.NewRouter()

r.Use(middleware.Recoverer)            // 1 — chi built-in
r.Use(RequestIDMiddleware)             // 2
r.Use(RequestLoggingMiddleware)        // 3
r.Use(CORSMiddleware(corsConfig))      // 4
r.Use(TimeoutMiddleware(30*time.Second)) // 5

// Protected routes
r.Group(func(r chi.Router) {
    r.Use(AuthMiddleware)              // 6
    r.Use(RateLimitMiddleware)         // 7
    r.Get("/api/orders", listOrders)
})

// Public routes (no auth/rate-limit)
r.Get("/health", healthHandler)
r.Post("/auth/login", loginHandler)
```

### TypeScript / Next.js

Next.js `middleware.ts` runs at the edge before route handlers — use it for auth, CORS, and rate-limiting. Request logging and error handling are per-route in route handlers or a wrapper utility.

```typescript
// middleware.ts
import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";

export async function middleware(req: NextRequest) {
  const requestId = req.headers.get("x-request-id") ?? crypto.randomUUID();
  const res = NextResponse.next();
  res.headers.set("x-request-id", requestId);

  // CORS (for API routes)
  if (req.method === "OPTIONS") {
    return new NextResponse(null, {
      status: 204,
      headers: {
        "Access-Control-Allow-Origin": process.env.ALLOWED_ORIGIN ?? "",
        "Access-Control-Allow-Methods": "GET,POST,PUT,PATCH,DELETE",
        "Access-Control-Allow-Headers": "Content-Type,Authorization,X-Request-ID",
        "Access-Control-Max-Age": "86400",
      },
    });
  }

  // Auth check for protected routes
  if (req.nextUrl.pathname.startsWith("/api/") &&
      !PUBLIC_ROUTES.includes(req.nextUrl.pathname)) {
    const token = req.headers.get("authorization")?.replace("Bearer ", "");
    if (!token || !isValidToken(token)) {
      return NextResponse.json({ error: "unauthorized" }, { status: 401 });
    }
  }

  return res;
}

export const config = {
  matcher: ["/api/:path*"],
};
```

---

## What Belongs in Middleware vs Handlers

| Concern | Middleware | Handler |
| :--- | :---: | :---: |
| Panic recovery | ✓ | |
| Request ID | ✓ | |
| Request/response logging | ✓ | |
| CORS | ✓ | |
| Request timeout | ✓ | |
| Token validation | ✓ | |
| Permission check (can this user do THIS action) | | ✓ |
| Rate limiting (global/per-user) | ✓ | |
| Rate limiting (per-resource, e.g. per-post) | | ✓ |
| Input validation | | ✓ |
| Business logic | | ✓ |
| Structured error response format | ✓ | |
| Domain-specific error message | | ✓ |

Authentication (who are you) is middleware. Authorization (can you do this specific thing) is in the handler — it has access to the resource being acted on.
