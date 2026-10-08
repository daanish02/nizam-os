---
type: convention
title: Authentication & Authorization
description: Token storage, RBAC enforcement, and password rules for Go, Python, and TypeScript — apply whenever implementing auth middleware, route protection, or session handling.
applies_to: [go, python, typescript]
tags: [auth, security]
---

# Authentication & Authorization

## Cross-Stack Rules

- Never store tokens in `localStorage` or `sessionStorage` — always httpOnly, secure, `SameSite` cookies. A token in browser storage is readable by any injected script; a cookie marked httpOnly isn't.
- Access tokens short-lived (~15 min). Refresh tokens longer-lived (~7 days), rotated on use, revocable — see **Revocation** below for the mechanism, which must actually be implemented, not merely intended.
- Signing secret from env, never hardcoded. Support key rotation via key id in token header. See `secrets-management.md`.
- **Validate every claim, not just the signature.** A structurally valid, correctly-signed token issued for a different audience or by a different issuer is still not a token for this API. Check `exp`, `nbf`, `iss`, and `aud` on every request, and pin the accepted algorithm explicitly — never let the token's own header choose it.
- Allow at most ~60 seconds of clock skew on `exp`/`nbf`. More than that materially extends the life of a stolen token.
- Token validation in **one place** — a single middleware/dependency — never re-implemented per handler/route.
- Role and permission checks happen server-side only. Never trust a client-supplied identity claim or a client-side check alone — a hidden button is not access control.
- Roles answer *what kind of user*; they do not answer *may this user touch this record*. Object-level ownership is `access-control.md` and is required in addition to role checks.
- Authorization failures return 403, not 404, unless deliberately hiding resource existence (state that choice explicitly when made).
- Never log a password or token, even at debug level.
- Hash passwords with bcrypt or argon2. Never a custom scheme, never plaintext, never reversible encryption.
- **Regenerate the session identifier on login and on privilege change**, and invalidate it on logout. Reusing a pre-login identifier is session fixation.

## Revocation

A JWT is self-contained: once issued, it is valid until it expires, and nothing about the token alone can withdraw that. "Revocable" therefore requires server-side state — implement one of these, do not assume it:

- **Token version per user** (simplest, recommended default). Store `token_version` on the user row; put it in the token as a claim; the auth middleware rejects any token whose version is behind the stored one. Logout-everywhere, password change, and role change all become one increment.
- **Denylist by `jti`** when individual sessions must be killed independently. Store the token id until its natural expiry, checked on every request. Needs a cache with TTL, and the lookup is on the hot path.
- **Opaque refresh tokens.** The refresh token is a random id looked up in the database; only access tokens are JWTs. Revocation is a row delete.

Rules that apply whichever is chosen:

- **Refresh rotation is single-use.** Issuing a new refresh token invalidates the old one. If an already-used refresh token is presented, treat it as theft: revoke the whole family and force re-authentication.
- Password change, email change, role change, and logout all revoke existing sessions.
- Access-token lifetime is the window in which revocation is not effective. That is the reason it is ~15 minutes, not hours.

## Login Protection

- **Throttle authentication endpoints** by IP *and* by account — per-IP alone is defeated by a distributed attempt, per-account alone lets one IP spray many accounts. See `rate-limiting.md`.
- **Lock or exponentially back off** after repeated failures for one account, and alert on the pattern. Prefer backoff over hard lockout: a hard lock is itself a denial-of-service against the real user.
- **Do not leak whether an account exists.** Login, registration, password reset, and resend-verification return the same response and take the same time whether or not the address is registered. "No account with that email" is an account-enumeration oracle.
- **Password reset tokens** are single-use, high-entropy, short-lived (~15–60 min), stored hashed, invalidated on use and on password change, and never included in a redirect that a third party can log.
- Enforce a password policy by length and by a breached-password check, not by composition rules. Long passphrases beat mandatory punctuation.
- **MFA (TOTP or WebAuthn) for administrative and high-privilege accounts** at minimum; offer it to all users. Verify the second factor server-side and rate-limit it — a 6-digit code with unlimited attempts is not a second factor. Recovery codes are single-use and stored hashed.

## Go

- Use `golang.org/x/crypto/bcrypt` or `argon2` for password hashing.
- Validate JWT in a single HTTP middleware using `github.com/golang-jwt/jwt/v5`.
- Propagate the authenticated principal via `context.Context` — handlers read from context, never from raw headers.
- Refresh tokens stored in httpOnly cookies; access tokens kept short-lived enough that XSS exposure window is small.

### Boilerplate

```go
// middleware/auth.go
package middleware

import (
    "context"
    "net/http"
    "strings"

    "github.com/golang-jwt/jwt/v5"
)

type contextKey string

const ClaimsKey contextKey = "claims"

func Auth(secret []byte) func(http.Handler) http.Handler {
    return func(next http.Handler) http.Handler {
        return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
            raw := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
            if raw == "" {
                http.Error(w, "unauthorized", http.StatusUnauthorized)
                return
            }
            // WithValidMethods pins the algorithm from the outside: the token's
            // own header never gets to choose how it is verified.
            token, err := jwt.Parse(raw, func(t *jwt.Token) (any, error) { return secret, nil },
                jwt.WithValidMethods([]string{"HS256"}),
                jwt.WithIssuer(expectedIssuer),
                jwt.WithAudience(expectedAudience),
                jwt.WithLeeway(60*time.Second), // exp/nbf are checked by default
            )
            if err != nil || !token.Valid {
                http.Error(w, "unauthorized", http.StatusUnauthorized)
                return
            }

            // Revocation: the signature only proves the token was issued, not
            // that it is still good. Compare its version against the user's.
            claims, ok := token.Claims.(jwt.MapClaims)
            if !ok || !versions.IsCurrent(r.Context(), claims) {
                http.Error(w, "unauthorized", http.StatusUnauthorized)
                return
            }

            ctx := context.WithValue(r.Context(), ClaimsKey, token.Claims)
            next.ServeHTTP(w, r.WithContext(ctx))
        })
    }
}
```

## Python

- Use `argon2-cffi` or `bcrypt` for password hashing.
- Validate JWT in a single FastAPI dependency using **`PyJWT`**. Not `python-jose`: it is effectively unmaintained and carries known algorithm-confusion advisories (CVE-2024-33663, CVE-2024-33664).
- Inject the authenticated principal as a typed dependency — routes receive it, never re-parse raw headers.

### Boilerplate

```python
# app/dependencies/auth.py
import jwt                              # PyJWT
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

from app.config import settings

bearer = HTTPBearer()

UNAUTHORIZED = HTTPException(
    status_code=status.HTTP_401_UNAUTHORIZED,
    detail="Invalid or expired token",     # never says which — that is an oracle
)

async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(bearer),
) -> dict:
    try:
        payload = jwt.decode(
            credentials.credentials,
            settings.jwt_secret,
            algorithms=[settings.jwt_algorithm],   # pinned: header never chooses
            issuer=settings.jwt_issuer,
            audience=settings.jwt_audience,
            leeway=60,
            options={"require": ["exp", "iss", "aud", "sub"]},
        )
    except jwt.PyJWTError:
        raise UNAUTHORIZED

    # Revocation — a valid signature does not mean the session is still live.
    if payload.get("ver") != await current_token_version(payload["sub"]):
        raise UNAUTHORIZED
    return payload

def require_role(role: str):
    def _check(user: dict = Depends(get_current_user)) -> dict:
        if role not in user.get("roles", []):
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Forbidden")
        return user
    return _check
```

## TypeScript

- Auth state checked in `middleware.ts` for route protection — not ad-hoc per-page checks scattered across the app.
- Refresh handled server-side (Server Component or Server Action) — never expose the refresh token to client JS.
- Role and permission checks in Server Components or Server Actions, never in client components.

### Boilerplate

```typescript
// middleware.ts
import { NextRequest, NextResponse } from "next/server";
import { jwtVerify } from "jose";

const secret = new TextEncoder().encode(process.env.JWT_SECRET!);

const PUBLIC_PATHS = ["/login", "/api/auth"];

export async function middleware(req: NextRequest) {
  if (PUBLIC_PATHS.some((p) => req.nextUrl.pathname.startsWith(p))) {
    return NextResponse.next();
  }

  const token = req.cookies.get("access_token")?.value;
  if (!token) {
    return NextResponse.redirect(new URL("/login", req.url));
  }

  try {
    await jwtVerify(token, secret, {
      algorithms: ["HS256"],        // pinned — the token header never chooses
      issuer: process.env.JWT_ISSUER!,
      audience: process.env.JWT_AUDIENCE!,
      clockTolerance: 60,
    });
    return NextResponse.next();
  } catch {
    return NextResponse.redirect(new URL("/login", req.url));
  }
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"],
};
```

- `PUBLIC_PATHS` is an explicit allowlist — everything not listed requires a session. Never invert this into a list of protected paths; a route someone forgets to add would then ship unauthenticated.
- Middleware proves *a valid session exists*. It cannot see which record a request will touch, so it is not the authorization layer — revocation checks and ownership checks belong where the data is loaded. See `access-control.md`.

Related: `access-control.md` (object ownership), `secrets-management.md` (signing keys), `rate-limiting.md` (login throttling), `security.md` (cookies and headers).
