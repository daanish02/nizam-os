---
type: convention
title: Error Handling
description: Single-handling rule, fail-fast at boundaries, and typed error hierarchies for Go, Python, and TypeScript — apply when implementing error propagation, logging, or API boundary handling in any layer.
applies_to: [go, python, typescript]
tags: [error-handling, errors]
---

# Error Handling

## Cross-Stack Rules

- **Single-handling rule:** an error is either logged or propagated — never both. Logging at every level it passes through produces duplicate noise for one failure.
- **Fail fast at boundaries:** programmer errors, missing required config, and bad startup state raise immediately at startup — don't limp along with silent `None`/zero defaults.
- **Expected errors are values:** domain-specific failure cases are explicit types (sentinel errors, typed exceptions, typed result objects) — not stringly-typed or swallowed.
- **Never swallow silently:** every error is logged, propagated, or turned into an explicit handled response. An empty `catch {}` or bare `except: pass` is always wrong.
- API boundaries catch unhandled errors, log the full detail, and return a generic error response — never leak internals.

## Go

- Every returned error is checked — never discarded with `_`.
- Wrap with context: `fmt.Errorf("doing X: %w", err)` to preserve the chain for `errors.Is`/`errors.As`.
- Sentinel errors (`ErrNotFound`) for expected comparable conditions; custom error types for conditions that carry data.
- Inspect with `errors.Is` or `errors.As` — never a string comparison on `err.Error()`.
- No panic for expected/recoverable conditions — panic only for programmer errors or truly unrecoverable state, and only at process startup, never mid-request.
- Error strings: lowercase, no trailing punctuation — see `code-style-naming.md`.
- Log via `log/slog` with the error as a structured field, not string-concatenated into the message.

### Boilerplate

```go
// errors/errors.go
package errors

import (
    "errors"
    "fmt"
)

// Sentinel errors for expected domain conditions.
var (
    ErrNotFound   = errors.New("not found")
    ErrConflict   = errors.New("conflict")
    ErrForbidden  = errors.New("forbidden")
    ErrBadRequest = errors.New("bad request")
)

// AppError carries structured context for an error.
type AppError struct {
    Code    string
    Message string
    Cause   error
}

func (e *AppError) Error() string {
    if e.Cause != nil {
        return fmt.Sprintf("%s: %s: %v", e.Code, e.Message, e.Cause)
    }
    return fmt.Sprintf("%s: %s", e.Code, e.Message)
}

func (e *AppError) Unwrap() error { return e.Cause }

func New(code, message string, cause error) *AppError {
    return &AppError{Code: code, Message: message, Cause: cause}
}
```

## Python

- Subclass a project base `AppError` (not bare `Exception`) for expected domain failures, each with a docstring explaining why it exists.
- Never catch bare `except:` or broad `except Exception` except at a defined boundary (the top-level request handler).
- The global exception handler catches anything unhandled, logs the full traceback, and returns a generic 500. Expected domain exceptions are caught explicitly and mapped to the correct HTTP status.
- Fail fast on config/programmer errors: raise at startup, not deep in request handling.

### Boilerplate

```python
# app/exceptions.py
class AppError(Exception):
    """Base for all expected application errors."""
    status_code: int = 500
    default_detail: str = "An unexpected error occurred."

    def __init__(self, detail: str | None = None) -> None:
        self.detail = detail or self.default_detail
        super().__init__(self.detail)

    # Always re-raise with `raise AppError(...) from exc` at a wrap point.
    # A bare `raise` inside an except block drops __cause__, and the traceback
    # then stops at the wrapper instead of showing what actually failed.


class NotFoundError(AppError):
    """The requested resource does not exist."""
    status_code = 404
    default_detail = "Not found."


class ForbiddenError(AppError):
    """The caller is authenticated but not permitted to perform this action."""
    status_code = 403
    default_detail = "Forbidden."


class ConflictError(AppError):
    """The operation conflicts with existing state."""
    status_code = 409
    default_detail = "Conflict."


class BadRequestError(AppError):
    """The request is malformed or violates a domain rule."""
    status_code = 400
    default_detail = "Bad request."
```

## TypeScript

- `error.tsx` at the route level catches render/data errors within that segment — every route with real failure modes (a fetch that can fail, a mutation) gets one, not just the root layout.
- `not-found.tsx` for explicit "doesn't exist" cases — don't let a missing resource render as a generic error.
- Server Actions validate input (Zod) and return a typed result for expected failures — throwing is reserved for truly unexpected errors, not user-facing validation failures.
- Client-side: an error boundary around any section that can fail independently so one broken widget doesn't blank the whole screen.

### Boilerplate

```typescript
// lib/errors.ts
export class AppError extends Error {
  constructor(
    message: string,
    public readonly code: string,
    public readonly statusCode: number = 500,
    options?: { cause?: unknown },
  ) {
    // `cause` preserves the original error so the chain survives re-wrapping.
    // Without it, the stack that explains *why* this failed is discarded here.
    super(message, options);
    this.name = "AppError";
  }
}

export class NotFoundError extends AppError {
  constructor(message = "Not found") {
    super(message, "NOT_FOUND", 404);
    this.name = "NotFoundError";
  }
}

export class ForbiddenError extends AppError {
  constructor(message = "Forbidden") {
    super(message, "FORBIDDEN", 403);
    this.name = "ForbiddenError";
  }
}

export class BadRequestError extends AppError {
  constructor(message = "Bad request") {
    super(message, "BAD_REQUEST", 400);
    this.name = "BadRequestError";
  }
}

// Typed result for Server Actions — avoids throwing for expected failures
export type ActionResult<T> =
  | { success: true; data: T }
  | { success: false; error: string; code?: string };
```
