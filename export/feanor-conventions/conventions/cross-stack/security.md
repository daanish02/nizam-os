---
type: convention
title: Security
description: Injection prevention, cryptography, security response headers, and least-privilege rules for Go, Python, and TypeScript — the entry point to the security convention set.
applies_to: [go, python, typescript]
tags: [security]
---

# Security

This is the entry point. Four adjacent files carry the rest, and a ticket tagged `security` should pull whichever apply:

| File | Covers |
| :--- | :--- |
| `access-control.md` | Object ownership, IDOR, tenant scoping, mass assignment |
| `untrusted-input.md` | SSRF, file upload, deserialization, path traversal |
| `secrets-management.md` | Secret storage, rotation, scanning |
| `data-protection.md` | Classification, PII, encryption, retention |
| `supply-chain.md` | Lockfiles, pinning, SBOM, dependency vetting |

## Cross-Stack Rules

- Validate all external input at the boundary — never trust client data. Upstream validation does not excuse a downstream layer from validating independently (defense in depth, not defense in one place).
- Parameterised queries only — no SQL built by string concatenation.
- No secrets in code or logs — no hardcoded credentials, no logging of tokens/passwords/PII. Use environment variables or a dedicated secrets manager; see `secrets-management.md`.
- Placeholder convention: `{{EXAMPLE_SECRET}}` in any doc or example, never a real value.
- Least-privilege: request only the permissions and DB grants a component actually needs.
- Dependency vulnerability scanning in CI — not a manual-only step. See `supply-chain.md`.
- Fail closed. When an authorization, validation, or verification step errors, deny — never fall through to the permissive branch.
- Error responses carry a code and a safe message, never a stack trace, SQL fragment, internal path, or dependency version. See `error-handling.md`.

## Security Response Headers

Set at the edge (reverse proxy, `middleware.ts`, or framework middleware) for every HTML response. All of them, not just CSP:

| Header | Value | Why |
| :--- | :--- | :--- |
| `Content-Security-Policy` | Explicit source allowlist; no `unsafe-inline` for scripts | Limits injection impact |
| `Strict-Transport-Security` | `max-age=63072000; includeSubDomains; preload` | Stops downgrade and cookie interception |
| `X-Content-Type-Options` | `nosniff` | Stops MIME confusion on uploads and downloads |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | Keeps paths and query strings out of third-party logs |
| `Permissions-Policy` | Deny unused features (`camera=(), microphone=(), geolocation=()`) | Shrinks the attack surface of injected script |
| `frame-ancestors` (in CSP) | `'none'`, or an explicit allowlist | Clickjacking; supersedes `X-Frame-Options` |
| `X-Robots-Tag` | `noindex, nofollow` on every authenticated or otherwise non-public response | Search engines cache and serve pages independently of `robots.txt` — this is the header that actually keeps a page out of results |

- Build CSP from a nonce or hash, not `unsafe-inline`. A CSP with `unsafe-inline` on scripts stops approximately nothing.
- Cookies: `HttpOnly`, `Secure`, `SameSite=Lax` (or `Strict`), scoped `Path`, and no wildcard `Domain`. See `auth.md`.
- **`robots.txt` is not access control.** It is a public, unauthenticated file read by anyone, and a `disallow` entry advertises the path to every reader — including the crawlers ignoring it. Never list an admin route, an internal tool, or anything sensitive in it. Keeping a page out of a *crawl* (`robots.txt`) and keeping it out of search *results* (`X-Robots-Tag: noindex`) and keeping it out of *unauthorized hands* (`access-control.md`) are three different controls — don't substitute one for another. See `nextjs/project-layout.md` for generating `robots.txt`/`sitemap.xml` on a public-facing app.

## Go

**Injection:**
- SQL: parameterized queries — see `database.md`.
- Shell: pass arguments to `exec.Command` separately, never build a command string via concatenation.
- HTML: `html/template` for auto-escaping, never `text/template` for anything user-facing.
- File access: scope to allowed roots explicitly (`os.Root` on Go 1.24+) — never trust a path built from user input. See `untrusted-input.md`.
- Deserialization: decode JSON into a typed struct with a body size cap, never into `map[string]any` that is then reflected over.

**Cryptography:**
- Vetted algorithms only, never a custom scheme: `crypto/aes`, `crypto/rand` for randomness, `golang.org/x/crypto/argon2` (or `bcrypt`) for password hashing.
- Tokens and secrets use `crypto/rand`, never `math/rand`.

**Verification tools:**
- `govulncheck ./...` — dependency vulnerabilities; run before merge.
- `gosec` — security-focused static analysis.
- `go test -race ./...` — data race detection; always on in CI.

Rate limiting: `cross-stack/rate-limiting.md`. Auth/session strategy: `cross-stack/auth.md`.

## Python

**Injection:**
- SQL: ORM parameterisation (SQLAlchemy) or explicit `%s`/`:name` placeholders — never f-strings or concatenation in queries.
- Subprocess: pass argument lists to `subprocess.run`, never `shell=True` with user-controlled input.
- Deserialization: `yaml.safe_load` only, and never `pickle` on anything that crossed a trust boundary — both are code execution, not parsing. Full rules in `untrusted-input.md`.

**Validation:**
- Pydantic v2 at every API boundary — reject unknown fields (`model_config = ConfigDict(extra="forbid")`).

**Secrets:**
- `python-dotenv` or a secrets manager; never `os.environ["SECRET"] = "literal"` in source.

**Scanning:**
- `bandit` for static security analysis (`uv run bandit -r app/`).
- `uv run pip-audit` or `govulncheck` equivalent — `uv` surfaces known vulnerabilities; wire into CI.

Rate limiting: `cross-stack/rate-limiting.md`.

## TypeScript / Next.js

**Env vars:**
- Only variables explicitly prefixed `NEXT_PUBLIC_` reach the browser. Before adding one, confirm it is actually meant to be public — this is an easy, permanent leak if done by habit.
- API keys, DB URLs, and secrets stay server-only.

**XSS:**
- React auto-escapes by default. `dangerouslySetInnerHTML` is the one place XSS happens — never pass unsanitized user input to it. If HTML rendering is genuinely required, sanitize with a vetted library (e.g. DOMPurify) first.

**CSRF:**
- Server Actions have built-in CSRF protection (origin-checking) — do not bypass it.
- Any hand-rolled `app/api/` route accepting mutations that is cookie-authenticated needs its own CSRF token.

**CSP:**
- Set a `Content-Security-Policy` header in production — restricts script/style sources and limits injection impact.

**Rate limiting (API routes / Server Actions):**
- Any `app/api/` route or Server Action that is a real attack surface (auth, mutations, expensive operations) gets rate-limited in `middleware.ts`. Same policy as the backend: `429` with `Retry-After`, keyed by user id or IP, stricter limits on auth endpoints.
- **Use a shared store, not process memory.** Serverless and load-balanced deployments run many instances; a per-process counter divides the effective limit by the instance count and resets on every cold start, so an attacker simply gets more attempts. A per-process `Map` also grows without bound — one entry per distinct IP, never evicted, is a memory leak an attacker controls.

```typescript
// middleware.ts — Redis-backed, correct under multiple instances.
import { NextRequest, NextResponse } from "next/server";
import { Ratelimit } from "@upstash/ratelimit";
import { Redis } from "@upstash/redis";

const redis = Redis.fromEnv();

const limiters = {
  auth:    new Ratelimit({ redis, limiter: Ratelimit.slidingWindow(5, "60 s"), prefix: "rl:auth" }),
  default: new Ratelimit({ redis, limiter: Ratelimit.slidingWindow(60, "60 s"), prefix: "rl:api" }),
};

export async function middleware(request: NextRequest) {
  const ip = request.headers.get("x-forwarded-for")?.split(",")[0].trim() ?? "unknown";
  const limiter = request.nextUrl.pathname.startsWith("/api/auth") ? limiters.auth : limiters.default;

  const { success, reset } = await limiter.limit(ip);
  if (!success) {
    return new NextResponse("Too Many Requests", {
      status: 429,
      headers: { "Retry-After": String(Math.max(1, Math.ceil((reset - Date.now()) / 1000))) },
    });
  }
  return NextResponse.next();
}

export const config = { matcher: ["/api/:path*"] };
```

- `x-forwarded-for` is caller-supplied unless a trusted proxy sets it. Take the client IP from the hosting platform's trusted header, and never trust the leftmost value on an untrusted path — otherwise the key is attacker-chosen and the limit is meaningless.
- Rate limiting is a control against volume, not a substitute for authorization. Both apply. See `rate-limiting.md` for policy per endpoint class and the backend implementations.
