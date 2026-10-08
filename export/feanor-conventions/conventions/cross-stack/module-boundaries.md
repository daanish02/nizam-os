---
type: convention
title: Module Boundaries & Import Direction
description: Import direction rules, dependency inversion, and cross-domain coupling discipline for Go, Python, and TypeScript.
applies_to: [go, python, typescript]
tags: [boundaries, modules, architecture]
---

# Module Boundaries & Import Direction

## Cross-Stack Rules

- Import direction flows one way: handler → service → repository → domain. Never reverse.
- Domain layer imports nothing from your own codebase — pure types, value objects, errors, and domain logic only.
- Sibling domains never import each other directly. Cross-domain dependencies go through a port/interface defined in the consuming domain.
- No circular imports. A circular import at runtime is a boundary violation — fix the boundary, not the import.
- Shared utilities extract to a shared layer only when a second real domain needs them, never preemptively.

## Go

`internal/` enforces the external boundary at compile time. Import direction within `internal/` is manual discipline.

```
handlers/     →  services/       ✓
services/     →  repositories/   ✓
services/     →  domain/         ✓
repositories/ →  domain/         ✓
handlers/     →  domain/         ✓

services/     →  handlers/       ✗ VIOLATION
repositories/ →  services/       ✗ VIOLATION
domain/       →  anything in own codebase  ✗ VIOLATION
```

**Interface-at-consumer pattern:** interfaces belong to the consumer, not the producer.

```go
// internal/services/orders.go — consumer defines the interface
type InventoryRepository interface {
    IsAvailable(ctx context.Context, sku string, qty int) (bool, error)
}

// internal/repositories/inventory.go — producer implements, no import of services/
type PostgresInventoryRepository struct{ db *sqlx.DB }

func (r *PostgresInventoryRepository) IsAvailable(ctx context.Context, sku string, qty int) (bool, error) {
    // ...
}
```

Keep interfaces small — one to three methods. A five-method interface is usually two interfaces merged.

Two sibling services must not import each other. Cross-service coordination goes through a shared domain event, an orchestrator service, or a `ports` interface in the consuming package.

`pkg/` only when another service in the same monorepo genuinely needs it. Default everything to `internal/`.

## Python

```
app/<domain>/   →  app/core/          ✓
app/<domain>/   →  app/shared/        ✓
app/<domain>/   →  stdlib/third-party ✓
app/<domain_a>/ →  app/<domain_b>/    ✗ VIOLATION
app/core/       →  app/<domain>/      ✗ VIOLATION
```

`app/core/` (or `app/shared/`) must have zero knowledge of any domain.

**`ports.py` pattern** for cross-domain dependencies:

```python
# app/orders/ports.py — domain A owns the interface
from typing import Protocol

class InventoryChecker(Protocol):
    def is_available(self, sku: str, qty: int) -> bool: ...

# app/inventory/adapters.py — domain B implements, no import of orders
from app.orders.ports import InventoryChecker  # only this direction allowed

class PostgresInventoryChecker:
    def is_available(self, sku: str, qty: int) -> bool: ...
```

Wire concrete implementations at startup (DI container, factory function, or FastAPI `Depends`).

No `utils.py` or `helpers.py` at `app/` root — gravity well for unrelated code.

Detecting violations:
```bash
grep -rn "from app\." backend/app --include="*.py"
# flag lines where the importing file's domain ≠ the imported module's domain
```

## TypeScript

Feature folders under `app/(feature)/` are silos. One feature never imports from another feature's internals.

```
app/(orders)/components/OrderCard.tsx  ✗  imported by app/(billing)/
app/(orders)/actions.ts                ✗  imported by app/(inventory)/
lib/formatCurrency.ts                  ✓  imported by anyone
components/ui/Button.tsx               ✓  imported by anyone
```

**Shared layer** (what anyone can import):

| Path | Contents |
| :--- | :--- |
| `lib/` | Pure utility functions, API client, data fetching helpers |
| `components/ui/` | Generic stateless UI primitives |
| `components/layout/` | Shell, nav, page-frame components |
| `hooks/` | Generic hooks with no feature-specific logic |
| `types/` | Shared TypeScript types and Zod schemas |

**Server/Client component direction:**

```
Server Component  →  Server Component   ✓
Server Component  →  Client Component   ✓  (serializable props only)
Client Component  →  Client Component   ✓
Client Component  →  Server Component   ✗  ILLEGAL — build error
```

Push `"use client"` as far down the tree as possible. Never import a Server Component into a Client Component file, even as a type — pass `React.ReactNode` as a prop instead.

TypeScript path aliases (`@/lib/`, `@/components/`, `@/types/`) point at the shared layer only. Never alias into a feature folder from outside that feature.

Detecting violations:
```bash
grep -rn "from '@/app/(orders)" app/\(billing\) app/\(inventory\)
```
