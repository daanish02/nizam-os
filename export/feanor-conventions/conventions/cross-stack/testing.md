---
type: convention
title: Testing
description: Test boundaries, mocking discipline, and TDD loop for Go, Python, and TypeScript.
applies_to: [go, python, typescript]
tags: [testing, tests]
---

# Testing

## Cross-Stack Rules

- Test at the public API boundary — not internals. Tests are executable specifications of observable behaviour, not a coverage target.
- Independent expected values — never re-compute expected results the same way as production code. Hard-code expected values or derive them from a different path.
- Mock only at system boundaries: external HTTP, third-party services, DB, time, randomness. Never mock your own domain logic or internal collaborators. If you need to mock an internal, the design is missing a seam.
- Tests are independent — no execution-order dependencies. Each test runs standalone.
- Fast default suite — slow/live tests (real DB, external APIs) are gated and excluded from the default run. Goal: fast feedback on every commit; slow tests run deliberately.
- TDD loop (see `../tdd.md`): write the failing test first, implement minimally to pass, refactor separately. Every bug fix starts with a reproducer test that fails before the fix.

## Go

- Table-driven tests with named subtests: every case has a `name` field passed to `t.Run(tt.name, ...)`.
- Test file named after source file: `foo.go` → `foo_test.go`. Functions ordered to match source order.
- `t.Parallel()` where the test allows it.
- Integration tests (real DB/external deps) gated behind `//go:build integration`.
- `goleak.VerifyTestMain(m)` to catch goroutine leaks.
- `go test -race ./...` in CI, always.
- `testify` (`assert`/`require`) as a helper on top of stdlib. Never create a testify instance in the parent test and reuse inside `t.Run` closures — failures get misattributed to the parent.

**Mocking:** use Go's interface-at-consumer pattern (from `module-boundaries.md`) — define a narrow interface in the consuming package, pass the real or test implementation at construction. No monkey-patching.

```go
func TestOrderService_Place(t *testing.T) {
    tests := []struct {
        name    string
        sku     string
        qty     int
        want    bool
        wantErr bool
    }{
        {name: "available", sku: "ABC", qty: 1, want: true},
        {name: "unavailable", sku: "ABC", qty: 100, want: false},
    }
    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            t.Parallel()
            svc := NewOrderService(&fakeInventory{available: tt.want})
            got, err := svc.Place(context.Background(), tt.sku, tt.qty)
            if tt.wantErr {
                require.Error(t, err)
                return
            }
            require.NoError(t, err)
            assert.Equal(t, tt.want, got)
        })
    }
}
```

## Python

- pytest. `tests/` mirrors `app/` package structure.
- Test files: `test_<module>.py`. Plain `def test_*()` functions — no test classes.
- `tests/conftest.py` inserts the backend root onto `sys.path`.
- Default run excludes slow/live tests (`-m 'not slow'`). `RUN_LIVE_TESTS=1` env gate opts in real DB/LLM tests.

**Mocking:** pass dependencies via constructor/function parameter (dependency injection). `unittest.mock.patch` on internal classes is a code smell — if you need it, add a seam.

```python
# conftest.py
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

# test_orders.py
import pytest

@pytest.mark.parametrize("sku,qty,expected", [
    ("ABC", 1, True),
    ("ABC", 100, False),
])
def test_order_service_place(sku, qty, expected, fake_inventory):
    svc = OrderService(inventory=fake_inventory(available=expected))
    result = svc.place(sku, qty)
    assert result == expected
```

**Re-importing a module to pick up new env/config:** `sys.modules.pop("app.config")` does **not** invalidate `config` as an *attribute of the `app` package*. The parent package keeps its own reference, so a later `from app import config` hands back the stale module and the test silently asserts against the old environment — passing for the wrong reason, which is worse than failing. Either:

- `importlib.import_module("app.config")` after the pop — it re-executes the module and rebinds the parent's attribute; or
- evict the parent too: `sys.modules.pop("app", None)` alongside the submodule.

Better than both: don't need them. A module that reads env at import time has no seam. Read config inside a function or a `Settings` object the test constructs directly, and there is nothing to re-import.

## TypeScript

- **Vitest** for unit/component tests (fast, Bun-compatible). **Playwright** for end-to-end.
- Component tests colocated with source: `OrderCard.test.tsx` next to `OrderCard.tsx`.
- Assert on rendered text and roles via Testing Library queries — not internal component state.
- E2E tests are the slow tier — excluded from the default fast run, run separately.
- Mock at the network boundary with MSW for component tests that need data. Never mock React internals, internal hooks, own Server Actions, `lib/` utilities, or domain logic.
- Pass external service clients (API wrappers, SDK instances) into components/hooks via props or context — makes them swappable in tests without module-level patching.

```typescript
// OrderCard.test.tsx
import { render, screen } from "@testing-library/react";
import { describe, it, expect } from "vitest";
import { OrderCard } from "./OrderCard";

describe("OrderCard", () => {
  it("displays order id and status", () => {
    render(<OrderCard orderId="ORD-123" status="confirmed" />);
    expect(screen.getByText("ORD-123")).toBeInTheDocument();
    expect(screen.getByRole("status")).toHaveTextContent("confirmed");
  });
});
```

TDD loop: write the failing test (Vitest for unit/component, Playwright for E2E) first, implement minimally, refactor separately. Bug fixes start with a Vitest or Playwright reproducer that fails before the fix.
