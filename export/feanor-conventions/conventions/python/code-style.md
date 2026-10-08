---
type: convention
title: Code Style & Naming
description: Python PEP 8 naming rules for modules, functions, classes, constants, and booleans; type hint requirements; and Pydantic v2 for structured validation.
applies_to: [python]
tags: [python, naming, style, typing, pydantic]
---

# Code Style & Naming

## Naming Quick Reference

| Element | Convention | Example |
| :--- | :--- | :--- |
| Module/package | lowercase, short, no underscores unless it aids readability | `orders`, `db`, `query_guard` |
| Function/variable | `snake_case` | `parse_token`, `user_count` |
| Class | `PascalCase` | `OrderService`, `RequestError` |
| Constant | `UPPER_SNAKE_CASE` | `MAX_RETRIES`, `DEFAULT_TIMEOUT` |
| Private (module-internal) | leading underscore | `_parse_internal`, `_Cache` |
| Name-mangled (class-internal) | leading double underscore | `__buffer` (rare — usually a single underscore is enough) |
| Boolean variable/field | `is_`/`has_`/`can_` prefix | `is_ready`, `has_permission` |
| Boolean function | `is_`/`has_`/`can_` prefix | `is_valid()`, `has_access()` |
| Exception class | `Error`/`Exception` suffix | `ValidationError`, `NotFoundError` |
| Type variable (generics) | short `PascalCase`, often single letter | `T`, `KT`, `VT` |
| Test function | `test_` + description | `test_rejects_invalid_email` |
| Pytest fixture | `snake_case`, noun describing what it provides | `db_session`, `authenticated_client` |

## Naming Rules

- **`snake_case` everywhere** for functions, variables, and module names — never `camelCase` or `PascalCase` outside of class names. This is PEP 8, not a house preference, and every linter assumes it.
- **No stuttering**, same principle as the Go conventions: a name shouldn't repeat its containing module/class. In `orders/service.py`, the class is `Service` or `OrderService` if disambiguation across modules is genuinely needed — not `OrdersOrderService`.
- **Booleans always read as a question**: `is_active`, not a bare `active`. Applies to variables, function names, and Pydantic model fields alike.
- **Private means private**: a single leading underscore (`_helper`) signals "not part of this module/class's public contract" — respect it as a real boundary, not decoration. Name-mangled double-underscore (`__x`) is rarely needed; reach for it only when subclass attribute collision is a real risk.
- **Exceptions** end in `Error` (for actual error conditions) or occasionally `Exception` for a broader base class — never a bare noun (`Invalid`, `Missing`).
- **Avoid single-letter names** outside of short comprehensions/lambdas or well-known conventions (`i`/`j` in a short loop, `T` for a generic type var). A name's length should match its scope, same rule as the Go conventions.
- **No `get_` prefix on simple accessors** — Python doesn't need Java-style getters; a plain attribute or a `@property` is idiomatic. Reserve a verb prefix (`fetch_`, `load_`) for something that actually does work (I/O, computation), so the name signals cost.
- **Acronyms stay uppercase in `PascalCase` contexts, lowercase in `snake_case` contexts** — `HTTPClient` (class), `http_client` (variable) — never `HttpClient`/`Http_Client`.
- **No `utils.py`/`helpers.py` as a flat module** — same reasoning as Go's `util`/`helper` package anti-pattern: the name says nothing about content, so it becomes a gravity well for unrelated code. Name the module after what it actually does.
  A `utils/` **package** is different and is allowed: `utils/db.py`, `utils/dates.py` each say what they hold, and the package groups genuinely cross-domain code used by 2+ domains. See [project-layout.md](./project-layout.md) for the rule on what qualifies. The anti-pattern is the unnamed catch-all, not the directory.

## Typing

- Type hints are mandatory on all public function/method signatures.
- Use modern syntax: `str | None` not `Optional[str]`, `list[int]` not `List[int]` — no imports from `typing` where the builtin generic works.
- Use Pydantic v2 `BaseModel` for request/response bodies and any structured data where validation matters — not raw dicts, not dataclasses.
