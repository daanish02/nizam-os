---
type: convention
title: Code Style & Naming
description: Go naming rules covering MixedCaps, anti-stuttering, constructor patterns, interface naming, doc comments, and control flow conventions.
applies_to: [go]
tags: [go, style, naming, documentation]
---

# Code Style & Naming

## Naming

- **MixedCaps only.** Never `snake_case`, never `ALL_CAPS` for constants — Go's export mechanism relies on capitalization (uppercase = exported), and this is load-bearing, not cosmetic.
- **No stuttering.** A name must not repeat the package name — `http.Client` not `http.HTTPClient`, `user.New()` not `user.NewUser()`.
- **Constructors:** `New()` when a package has one primary type; `NewTypeName()` only when a package has multiple constructible types.
- **Booleans:** `is`/`has`/`can` prefix on fields and methods — `isConnected`, `IsConnected()`. Never a bare adjective.
- **Interfaces:** method name + `-er` suffix — `Reader`, `Closer`, `Stringer`.
- **Errors:** sentinel errors get `Err` prefix (`ErrNotFound`); error types get `Error` suffix (`PathError`). Error strings are fully lowercase, including acronyms, no trailing punctuation — `"invalid message id"` not `"Invalid message ID."` — and prefixed with the package name for sentinels: `"orders: not found"`.
- **Enums (iota):** always an explicit `Unknown`/`Invalid` sentinel at position 0 — a zero-value `Status` must not silently look like a deliberately-chosen state.
- **Acronyms:** all-caps or all-lowercase, never mixed — `HTTPServer`/`xmlParser`, never `HttpServer`.
- **Receivers:** 1-2 letter abbreviation, consistent across all methods of the same type — `func (s *Server)`.
- **No `Get` prefix on getters** — `user.Name()` not `user.GetName()`. Boolean predicates keep `Is`/`Has`/`Can`.
- **Functional options:** `With` + field name — `WithPort()`, `WithLogger()`.


## Control Flow

- Handle errors and edge cases first via early return — avoid deep nesting.
- Eliminate unnecessary `else` after a return in the `if` branch.
- Extract a 3+-operand boolean condition into a named variable.
- `switch` over an `if`/`else` chain when comparing one variable against multiple values.
- Functions: ≤4 parameters; beyond that, use an options struct. `context.Context` is always the first parameter when present.
- Prefer `range` over index-based loops.
- Composite literals use field names (`Point{X: 1, Y: 2}`) so they don't silently break when the struct evolves.
- Slices and maps that are meant to hold values are explicitly initialized, never left as an unintentional `nil`.
- Unexport aggressively — an exported identifier is a permanent commitment to external callers; only export what's actually meant to be used outside the package.
