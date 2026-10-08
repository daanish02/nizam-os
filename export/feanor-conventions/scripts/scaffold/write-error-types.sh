#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: bash scripts/scaffold/write-error-types.sh [go|python|typescript]"
    exit 1
}

[[ $# -eq 1 ]] || usage

case "$1" in
  go)
    TARGET="backend/internal/domain/errors.go"
    mkdir -p "$(dirname "$TARGET")"
    cat > "$TARGET" << 'EOF'
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
EOF
    echo "Written: $TARGET"
    ;;

  python)
    TARGET="backend/app/core/exceptions.py"
    mkdir -p "$(dirname "$TARGET")"
    cat > "$TARGET" << 'EOF'
# app/exceptions.py
class AppError(Exception):
    """Base for all expected application errors."""
    status_code: int = 500
    default_detail: str = "An unexpected error occurred."

    def __init__(self, detail: str | None = None) -> None:
        self.detail = detail or self.default_detail
        super().__init__(self.detail)


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
EOF
    echo "Written: $TARGET"
    ;;

  typescript)
    TARGET="frontend/src/lib/errors.ts"
    mkdir -p "$(dirname "$TARGET")"
    cat > "$TARGET" << 'EOF'
// lib/errors.ts
export class AppError extends Error {
  constructor(
    message: string,
    public readonly code: string,
    public readonly statusCode: number = 500,
  ) {
    super(message);
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
EOF
    echo "Written: $TARGET"
    ;;

  *)
    echo "Unknown argument: $1"
    usage
    ;;
esac
