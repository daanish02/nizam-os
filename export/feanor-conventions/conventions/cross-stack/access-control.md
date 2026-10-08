---
type: convention
title: Access Control & Object Ownership
description: Object-level ownership checks, deny-by-default routing, tenant scoping, and mass-assignment prevention for Go, Python, and TypeScript — load for any ticket that reads or writes a resource belonging to a user or tenant.
applies_to: [go, python, typescript]
tags: [access-control, authorization, idor, multi-tenancy, mass-assignment, owasp-a01]
---

# Access Control & Object Ownership

Authentication answers *who is this*. Access control answers *may this caller touch this specific record*. `auth.md` covers the first. This file covers the second — the most exploited class of web vulnerability, and the one that unit tests almost never catch because the happy path passes either way.

## Cross-Stack Rules

- **Every fetch of a resource by id is an authorization decision.** A valid token proves identity, not entitlement. `GET /orders/{id}` with a valid token for user A must not return user B's order.
- **Scope the query, do not filter after.** Put the ownership predicate in the `WHERE` clause, not in an `if` after the row is loaded. A post-load check that someone later removes leaves no trace; a query that never selects the row cannot leak it.
- **Deny by default.** A new route is unauthenticated only when a rule explicitly says so. Maintain an explicit public-route allowlist; anything not on it requires auth. Never the reverse — an opt-in-to-protection scheme leaks every route somebody forgets.
- **Never accept the actor's identity from the request.** The user id, tenant id, role, and permissions come from the validated token or session, never from a body field, query parameter, or header the caller controls.
- **Bind updates to an explicit field allowlist.** Deserialising a whole request body onto a domain object lets a caller set `role`, `is_admin`, `tenant_id`, `balance`, or `id`. Name the fields a caller may write, per endpoint.
- **Check on write as well as read.** `DELETE` and `PATCH` need the same ownership predicate as `GET`. Mutations are where a missing check is most costly.
- **Authorization lives in the service layer, not the handler.** A rule enforced only in an HTTP handler is bypassed by every background job, admin script, and second entry point. Handlers carry the identity in; the service decides.
- **Never use a sequential integer as the only protection for a private resource.** Sequential ids are enumerable by design. Use them if you like, but the ownership check — not the id's shape — is what protects the row.
- **Return 404, not 403, when the existence of the resource is itself sensitive** (another tenant's record). Use 403 when the caller may legitimately know the resource exists but lacks the right to act on it. Pick one per resource and state it in the spec — see `api-design.md`.

## Multi-Tenancy

- A tenant-scoped table gets `tenant_id NOT NULL` and every query against it is scoped by it. See `database.md` for the schema rules and PostgreSQL Row-Level Security setup.
- **Do not rely on application code alone.** One repository function missing its `WHERE tenant_id` clause is a cross-tenant breach with no error and no log line. Enforce underneath the application too: RLS on PostgreSQL, or a single tenant-scoped repository/session that is the only path to the table.
- The tenant id comes from the token. A `tenant_id` in a request body or query string is an attacker-supplied value — reject it, do not honour it.
- Test isolation explicitly: seed two tenants, authenticate as one, assert the other's rows are invisible through every listed endpoint. This test is the only thing that proves the property.

## Go

```go
// repo/orders.go — ownership is part of the query, not a check after it.
func (r *OrderRepo) GetForUser(ctx context.Context, orderID, userID string) (*Order, error) {
    var o Order
    err := r.db.QueryRowContext(ctx,
        `SELECT id, user_id, total FROM orders WHERE id = $1 AND user_id = $2`,
        orderID, userID,
    ).Scan(&o.ID, &o.UserID, &o.Total)
    if errors.Is(err, sql.ErrNoRows) {
        return nil, ErrNotFound // caller maps to 404 — does not reveal existence
    }
    return &o, err
}
```

- Take the principal from `context.Context` (populated by the auth middleware in `auth.md`), never from a request field.
- Give the repository method the caller's id as a parameter. A method signature that cannot express ownership is one an agent will call unsafely.

## Python

```python
# app/orders/repository.py
async def get_for_user(session: AsyncSession, order_id: UUID, user_id: UUID) -> Order | None:
    result = await session.execute(
        select(Order).where(Order.id == order_id, Order.user_id == user_id)
    )
    return result.scalar_one_or_none()
```

```python
# app/orders/schemas.py — mass assignment prevention.
class OrderUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")   # unknown fields rejected, not ignored
    note: str | None = None
    quantity: int | None = None
    # id, user_id, tenant_id, status deliberately absent — not caller-writable
```

- One Pydantic model per direction. Reusing the ORM model or the response model as the request body is how `is_admin` becomes settable.
- Put the current user in a FastAPI dependency (`Depends(get_current_user)`) and pass it explicitly into the service. Do not read it from a global or middleware-set attribute.

## TypeScript / Next.js

- **Server Actions and Route Handlers are public HTTP endpoints.** Rendering a component conditionally, or hiding a button, protects nothing — the action is directly invocable. Every Server Action re-checks auth and ownership itself, first thing, before touching data.
- `middleware.ts` is a coarse gate, not the authorization layer. It cannot see the record being requested. Ownership is checked where the data is loaded.
- Never pass a `userId` or `tenantId` from client to server as an argument to trust. Read the session server-side inside the action.

```typescript
// app/orders/actions.ts
"use server";

export async function updateOrder(orderId: string, input: unknown) {
  const session = await getSession();              // server-side, not a parameter
  if (!session) throw new UnauthorizedError();

  const parsed = OrderUpdateSchema.parse(input);   // Zod allowlist — see below

  const order = await db.order.findFirst({
    where: { id: orderId, userId: session.userId }, // ownership in the query
  });
  if (!order) throw new NotFoundError();

  return db.order.update({ where: { id: order.id }, data: parsed });
}
```

```typescript
// Zod schema is the field allowlist. .strict() rejects unknown keys instead of
// dropping them silently, so an over-posting attempt is a visible 400.
const OrderUpdateSchema = z.object({
  note: z.string().max(500).optional(),
  quantity: z.number().int().positive().optional(),
}).strict();
```

## Testing

Every endpoint returning or mutating a user- or tenant-owned resource needs a test that authenticates as the **wrong** user and asserts the resource is not returned or changed. A suite that only ever tests the owner proves nothing about access control — it passes identically against a completely unprotected endpoint.

- Cover: owner succeeds, non-owner is denied, unauthenticated is denied, and cross-tenant is denied.
- Bug fixes here start with a reproducer that performs the unauthorized access and fails — see `tdd.md`.

Related: `auth.md` (identity and roles), `database.md` (RLS, tenant columns), `untrusted-input.md` (validation), `api-design.md` (status code taxonomy).
