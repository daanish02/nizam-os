---
type: convention
title: Test-Driven Development
description: TDD loop discipline, seams, vertical slicing, tautological test anti-pattern, and mocking rules — applied across all stacks.
applies_to: [all]
tags: [tdd, testing, red-green-refactor, seams, mocking]
---

# Test-Driven Development

TDD is not a testing convention — it's a development discipline that produces better interfaces and catches design problems before they calcify into code. It applies on every ticket that produces new behavior.

---

## The loop

```
RED  → write a failing test for one behavior
GREEN → write the minimal code that makes it pass
then stop, commit, and repeat for the next behavior
```

Three hard rules:

1. **Red before green.** Write the failing test first. Don't write code in anticipation of future tests — only enough to pass the current one.
2. **One slice at a time.** One test, one minimal implementation, per cycle. Not all tests then all code.
3. **Refactoring is not part of the loop.** It is a separate stage after tests are green. Never refactor during the red→green phase; it conflates two different kinds of thinking.

---

## Seams

A **seam** is the public boundary you test at: the interface where you observe behavior without reaching inside. Tests live at seams, never against internals.

Before writing any test: identify the seam. What is the public interface? What behavior should it exhibit from the caller's perspective? Write the test against that. If you can't describe the seam in one sentence, the interface isn't clear yet — clarify the design before writing the test.

Do not test through a side channel (querying the database directly instead of using the application's own retrieval function, checking internal state instead of observable output). If behavior is observable only through the interface, the test must go through the interface too.

---

## Vertical slicing

Write one test → implement minimally → verify it passes → write the next test. Do not write all tests first.

Writing all tests before any implementation is **horizontal slicing**. It produces tests that verify the *imagined* shape of the code, not behavior discovered through the implementation. Those tests are brittle, insensitive to real changes, and commit you to structure before you understand the problem.

Each test in a vertical slice is a tracer bullet: it teaches you something about the real interface, and the next test is informed by that knowledge.

---

## What a good test is

A test should read like a specification. "User can checkout with a valid cart" tells you exactly what capability exists and survives any refactor because it doesn't care about internal structure.

- Test what users/callers observe through the public interface, not how the code achieves it.
- Name the behavior, not the implementation: `test_returns_empty_list_for_unknown_user`, not `test_query_builder_left_join`.
- Expected values come from an **independent, known source of truth** — a worked example, a literal from the spec, a manually verified number. Never recomputed the same way the code would compute them (see Tautological anti-pattern below).
- One logical assertion per test. If a test asserts five things, it's testing five behaviors — split it.

---

## Anti-patterns

### Implementation-coupled

Mocking internal collaborators, testing private methods, or asserting on call counts/order. The tell: the test breaks when you refactor but the externally observable behavior hasn't changed.

```python
# BAD: asserts on an internal call, not on behavior
mock_repo.save.assert_called_once_with(user)

# GOOD: asserts on what the caller can observe
retrieved = user_service.get(user.id)
assert retrieved.email == "alice@example.com"
```

### Tautological

The expected value is recomputed the same way the implementation would compute it, so the test passes by construction and can never catch a bug in the logic.

```python
# BAD: expected is derived the same way the function does it
expected = sum(item.price for item in items)
assert calculate_total(items) == expected

# GOOD: expected is an independent literal from a worked example
assert calculate_total([Item(price=10), Item(price=5)]) == 15
```

This is the most common subtle failure mode in test suites. If the formula in the test mirrors the formula in the code, you're asserting that the code agrees with itself — not that it's correct.

### Horizontal slicing

Writing all tests upfront, then all implementation. Produces tests that verify imagined behavior, commits you to structure prematurely, and hides what each test actually taught you about the interface. Work in vertical slices instead.

---

## Mocking rules

Mock at **system boundaries** only:

- External APIs (payment providers, email services, third-party HTTP)
- The database — preferably use a real test database; mock only when a live DB is unavailable in the test tier
- Time, randomness, file system
- Environment / configuration

Do **not** mock:

- Your own domain classes, services, or repositories
- Internal collaborators — things you wrote and control
- Anything within your own codebase boundary

Mocking internal collaborators is the mechanism by which implementation-coupled tests are written. It also means the test can pass while the actual wiring between components is broken. Test the real composition; mock only what you can't control.

### Dependency injection for testability

Boundaries are only mockable if the concrete dependency is injected rather than constructed internally. Design functions and classes to receive external dependencies as parameters — this is the same dependency inversion rule from `coding-principles.md`, and testability is the second payoff (the first is architectural cleanliness).

```python
# Hard to test — concrete is constructed inside
class OrderService:
    def __init__(self):
        self.payment = StripeClient(settings.STRIPE_KEY)  # can't swap in tests

# Easy to test — dependency is injected
class OrderService:
    def __init__(self, payment: PaymentGateway):  # Protocol/interface type
        self.payment = payment
```

Design external-facing adapters with specific, narrow interfaces rather than a generic fetch/call function. Each specific function is independently mockable; a generic function requires conditional logic inside the mock.

---

## When TDD applies

Every ticket that produces new externally observable behavior. This includes:

- New features
- Bug fixes (write a test that reproduces the bug first — it becomes your RED; fixing the bug is your GREEN)
- New API endpoints
- New components with observable state or output

It does not apply to:

- Pure configuration changes (no behavior, nothing to assert)
- Documentation-only changes
- Scaffolding without logic

---

## Language-specific reference

- All stacks: `cross-stack/testing.md` — tool choices, mock boundaries, public-API testing rules per language (Go table-driven, Python pytest, TypeScript Vitest + Playwright + MSW)
