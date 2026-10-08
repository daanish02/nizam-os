---
type: convention
title: Rate Limiting
description: Rate limiting rules at the API boundary for Go and Python; TypeScript rate limiting is covered in security.md.
applies_to: [go, python, typescript]
tags: [rate-limiting, security]
---

# Rate Limiting

## Cross-Stack Rules

- Rate limiting lives at the API boundary — not deep in services.
- Every publicly reachable endpoint has a rate limit. No endpoint is exempt by default.
- Key by authenticated user/API key id when available; fall back to IP when not.
- Auth endpoints (login, signup, password reset) get stricter limits than general traffic — these are brute-force targets.
- Expensive endpoints (LLM calls, heavy DB aggregations, exports) get their own tighter limit independent of the general API limit.
- Return `429` with a `Retry-After` header on rate-limited responses — never a silent drop or generic 500.
- Exempt internal service-to-service calls with a shared secret header; don't rate-limit your own infrastructure.
- Limits defined centrally (config/env), never as magic numbers scattered per-handler.

## Go

Use `golang.org/x/time/rate` (token bucket). Wire as HTTP middleware.

Set `http.Server.ReadTimeout`/`WriteTimeout` explicitly — an unbounded connection is its own resource-exhaustion vector, separate from per-endpoint rate limiting.

### Boilerplate

```go
import (
    "net/http"
    "sync"
    "time"

    "golang.org/x/time/rate"
)

type IPRateLimiter struct {
    limiters sync.Map
    r        rate.Limit
    b        int
}

func NewIPRateLimiter(r rate.Limit, b int) *IPRateLimiter {
    return &IPRateLimiter{r: r, b: b}
}

func (l *IPRateLimiter) limiter(key string) *rate.Limiter {
    v, _ := l.limiters.LoadOrStore(key, rate.NewLimiter(l.r, l.b))
    return v.(*rate.Limiter)
}

func (l *IPRateLimiter) Middleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        key := r.RemoteAddr // replace with user id when authenticated
        if !l.limiter(key).Allow() {
            w.Header().Set("Retry-After", "1")
            http.Error(w, "rate limit exceeded", http.StatusTooManyRequests)
            return
        }
        next.ServeHTTP(w, r)
    })
}

// Usage
limiter := NewIPRateLimiter(rate.Every(time.Second), 10) // 10 req/s
mux.Handle("/api/", limiter.Middleware(apiHandler))
```

For auth endpoints, use a tighter limiter instance (e.g. 5 req/min) applied to those routes specifically.

## Python

Use `slowapi` (a `limits`-backed middleware for FastAPI/Starlette).

### Boilerplate

```python
from fastapi import FastAPI, Request
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address

# config.py — limits defined centrally
RATE_LIMIT_DEFAULT = "60/minute"
RATE_LIMIT_AUTH = "5/minute"
RATE_LIMIT_EXPENSIVE = "10/minute"

# main.py
limiter = Limiter(key_func=get_remote_address)  # swap for user id when authed
app = FastAPI()
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# router
from slowapi.decorator import limits

@app.post("/auth/login")
@limiter.limit(RATE_LIMIT_AUTH)
async def login(request: Request, ...):
    ...

@app.get("/api/export")
@limiter.limit(RATE_LIMIT_EXPENSIVE)
async def export(request: Request, ...):
    ...
```

`slowapi`'s `_rate_limit_exceeded_handler` returns `429` with a `Retry-After` header automatically.

## TypeScript

Rate limiting for Next.js API routes and Server Actions is handled in `middleware.ts` — see `cross-stack/security.md` for the Next.js approach. The surface is typically thinner than a backend service's, so it's covered there rather than as a separate file.
