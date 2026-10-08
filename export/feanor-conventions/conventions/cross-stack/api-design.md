---
type: convention
title: API Design
description: REST API design rules covering response envelope, pagination (cursor-based), error shape, and versioning — apply whenever implementing or reviewing HTTP API endpoints in Go, Python, or TypeScript backends.
applies_to: [all]
tags: [cross-stack, api, rest, pagination]
---

# API Design

## Response Envelope

All list and single-resource endpoints return a consistent top-level shape — no naked arrays, no inconsistent wrappers.

**Single resource:**
```json
{
  "data": { ...resource fields }
}
```

**List:**
```json
{
  "items": [ ...resources ],
  "next_cursor": "opaque-string-or-null"
}
```

- `items` always present (empty array, never `null`).
- `next_cursor` is `null` when no further pages exist.
- Do **not** include `total` unless the count is cheap (cached or indexed). Counting unbounded tables for every list request is a performance trap — if you need it, document it as a separate `HEAD` or `count` endpoint.

## Pagination

Use **cursor-based pagination only**. Offset pagination (`?page=2&per_page=20`) is forbidden for any dataset that can grow beyond a few hundred rows — page drift (inserts/deletes shifting rows between page fetches) produces duplicates and gaps that are invisible to the client.

**Query params:**

| Param | Type | Default | Notes |
| :--- | :--- | :--- | :--- |
| `limit` | integer | 20 | Max items per page. Cap at 100 server-side; reject >100 with 400. |
| `cursor` | string | omit for first page | Opaque server-issued token. Never parse client-side. |

**Rules:**
- Cursor encodes position, not an ID — use a stable, indexed field (e.g. `(created_at, id)` composite) so the query is O(index), not O(table scan).
- Cursors are opaque to clients: base64-encode the internal state, never expose raw DB values.
- Cursors are short-lived: no guarantee they remain valid across schema changes or deployments. A stale cursor returns 400, not 500.
- Default sort is deterministic (e.g. `created_at DESC, id DESC`). Document it — clients cannot paginate consistently without knowing sort order.
- Never allow the client to change sort direction mid-pagination via cursor (enforce on the server).

**Example response:**
```json
{
  "items": [
    { "id": "abc", "name": "Foo" },
    { "id": "def", "name": "Bar" }
  ],
  "next_cursor": "eyJpZCI6ImRlZiIsImNyZWF0ZWRfYXQiOiIyMDI0LTAxLTAxIn0="
}
```

## Error Shape

All error responses use a consistent body regardless of status code:

```json
{
  "error": {
    "code": "VALIDATION_FAILED",
    "message": "Human-readable summary.",
    "details": [ { "field": "email", "issue": "invalid format" } ]
  }
}
```

- `code`: machine-readable constant in `SCREAMING_SNAKE_CASE`. Used for programmatic handling — never change an existing code value.
- `message`: human-readable, safe to display. No stack traces, no internal paths.
- `details`: optional array for field-level validation errors. Omit (not `null`) when not applicable.

## Idempotency

Networks retry. A client that times out cannot tell a lost request from a lost response, so it retries — and an unguarded `POST /payments` charges twice.

- **Any non-idempotent mutation whose repetition would cause real harm** (payments, orders, transfers, sending messages, provisioning) **accepts an `Idempotency-Key` header** — a client-generated UUID per logical operation, reused on every retry of that operation.
- Server behaviour: on first use, process and store the key with the response and a hash of the request body. On a repeat of the same key, return the **stored response** without re-executing. On the same key with a *different* body, return `422` — that is a client bug, not a retry.
- Store keys with a TTL (24h is typical) scoped per user or per tenant, so one caller's key cannot collide with another's.
- Record the key and the outcome **in the same transaction as the effect**. Written separately, a crash between the two leaves a completed charge with no recorded key — and the next retry charges again.
- `PUT` and `DELETE` are idempotent by definition — make them genuinely so. `DELETE` on an already-deleted resource returns `204`, not `404`; a second `PUT` of the same body is a no-op, not an error.
- `GET` and `HEAD` never mutate state. A "GET that also increments a counter" breaks caches, prefetchers, and retries alike.
- Webhooks you *receive* are also retried by their sender: dedupe on the provider's event id, and verify the signature before acting. Webhooks you *send* are retried with backoff and carry a stable event id so the receiver can dedupe.

## Versioning

- Version in the URL path: `/v1/`, `/v2/`. No header-based versioning — headers are invisible in logs, browser history, and copy-pasted URLs.
- Never mutate a versioned contract. Breaking changes (removed fields, changed types, renamed routes) require a new version.
- Deprecation: respond with `Deprecation: true` header and `Sunset: <RFC 7231 date>` header on deprecated routes. Log a warning server-side on every hit.

## Language-Specific Notes

### Go

- Use a shared `response` package with typed `WriteJSON(w, status, body)` and `WriteError(w, status, code, message, details)` helpers — no ad-hoc `json.NewEncoder` at handler level.
- Cursor encoding/decoding lives in a shared `pagination` package.

### Python (FastAPI)

- Define a generic `Page[T]` Pydantic model: `items: list[T]`, `next_cursor: str | None`.
- Use a `CursorParams` dependency for `limit` and `cursor` query params — validates and enforces the 100-item cap in one place.
- Return `Page[YourSchema]` from list endpoints; FastAPI generates correct OpenAPI output automatically.

### TypeScript (API routes / backend)

- Apply the same envelope shape for any Next.js API routes or separate Node backends.
- Use a typed `paginate<T>` helper that accepts an array and returns `{ items: T[], next_cursor: string | null }`.
