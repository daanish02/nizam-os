---
type: convention
title: Code Comments & Documentation
description: Cross-stack comment discipline (write WHY not WHAT, self-documenting code first) plus language-specific documentation syntax — godoc for Go, Google-style docstrings for Python, TSDoc for TypeScript.
applies_to: [go, python, typescript]
tags: [comments, documentation, docstrings, godoc, jsdoc]
---

# Code Comments & Documentation

## Cross-Stack Rules

- Self-documenting code first: good names, small functions, clear structure. Reach for a comment only when the logic is non-obvious.
- Write WHY, not WHAT. The code says what. The comment says why it does it this way, what constraint it works around, what invariant it maintains.
- Never restate what the code already says. `// increment counter` above `count++` is noise.
- No commented-out code in commits. Delete it; git has history.
- TODO comments require a linked issue/ticket. `// TODO(#123): remove after migration` is acceptable. `// TODO: fix this` is not.
- A comment that needs updating every time the code changes is a sign the code should be restructured instead.

---

## Go

### Comment syntax

- Every exported identifier (function, type, const, var) gets a doc comment starting with its own name: `// ReadAll reads from r until EOF...`
- Package-level comment (`// Package orders provides...`) on one file per package (use `doc.go` if it doesn't fit naturally elsewhere).
- Unexported identifiers: comment only when non-obvious.
- godoc renders these automatically — format them as plain prose, not markdown.

### Boilerplate

```go
// Package orders provides domain types and service logic for the order lifecycle.
package orders

// ErrNotFound is returned when a requested order does not exist.
var ErrNotFound = errors.New("order not found")

// Create persists a new order and returns it with its assigned ID.
// It returns ErrConflict if an order with the same idempotency key already exists.
func (s *Service) Create(ctx context.Context, req CreateRequest) (Order, error) {
```

---

## Python

### Comment syntax

- Google-style docstrings throughout.
- Mandatory: every module, every class, every public function/method (no leading underscore).
- Private/internal helpers may skip a docstring if the name and signature are self-explanatory.
- Keep docstrings as short as correctness allows. A docstring that restates the function name adds nothing.

### Google-style docstring structure

```python
def create_order(user_id: str, items: list[OrderItem]) -> Order:
    """Create a new order for the given user.

    Args:
        user_id: The authenticated user's ID.
        items: Non-empty list of items to include.

    Returns:
        The persisted Order with its assigned ID.

    Raises:
        ValueError: If items is empty.
        ConflictError: If a duplicate idempotency key is detected.
    """
```

Only include sections that apply — omit `Raises` if no exceptions, omit `Returns` for `None`-returning functions.

---

## TypeScript

### Comment syntax

- TSDoc for exported functions, classes, and types in shared layers (`lib/`, `components/ui/`, public APIs).
- Inline comments for non-obvious logic only — same WHY rule as cross-stack.
- No JSDoc `@param`/`@returns` for internal functions where TypeScript types are self-explanatory.
- React components: one TSDoc comment per exported component describing what it renders and its key props; skip if the component name and prop types are sufficient.

### TSDoc structure

```typescript
/**
 * Calculates the discounted total for an order.
 *
 * @param subtotal - Pre-tax order total in cents.
 * @param discountCode - Optional promotion code; ignored if invalid.
 * @returns Total after discount applied, never negative.
 */
export function calculateTotal(subtotal: number, discountCode?: string): number {
```

Only document params/returns when the types alone don't tell the full story (units, constraints, edge cases).
