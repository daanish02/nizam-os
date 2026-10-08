#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: bash scripts/scaffold/write-rate-limiter.sh [go|python|typescript]"
    exit 1
}

[[ $# -eq 1 ]] || usage

case "$1" in
  go)
    TARGET="backend/internal/middleware/rate_limiter.go"
    mkdir -p "$(dirname "$TARGET")"
    cat > "$TARGET" << 'EOF'
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
// limiter := NewIPRateLimiter(rate.Every(time.Second), 10) // 10 req/s
// mux.Handle("/api/", limiter.Middleware(apiHandler))
EOF
    echo "Written: $TARGET"
    ;;

  python)
    TARGET="backend/app/core/rate_limiter.py"
    mkdir -p "$(dirname "$TARGET")"
    cat > "$TARGET" << 'EOF'
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
EOF
    echo "Written: $TARGET"
    ;;

  typescript)
    echo "Rate limiting for Next.js is implemented in middleware.ts — see cross-stack/security.md"
    exit 0
    ;;

  *)
    echo "Unknown argument: $1"
    usage
    ;;
esac
