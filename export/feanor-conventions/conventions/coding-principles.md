---
type: convention
title: Coding Principles
description: Language-agnostic coding principles — DRY, KISS, YAGNI, SRP, DI, composition, pure logic, small units, boring architecture — applied to every line of code across all stacks.
applies_to: [all]
tags: [coding-principles, dry, kiss, yagni, srp, solid, architecture, design, abstraction, composition, dependency-inversion, readability]
---

# Coding Principles

> **The objective is not "write clean code." It is: keep the cost of changing the system low as the system grows.**

Maintainable software is software another person can understand, modify, test, and extend without being afraid of breaking something. Optimize for the next programmer, not just the current program.

These principles apply to every stack in every Feanor project. Not a checklist per ticket — the frame inside which all code is written.

---

## DRY — Don't Repeat Yourself

Every piece of knowledge has a single authoritative source. Duplication means two places to change when the logic changes, and two places to get out of sync.

- Extract shared logic when a second real use appears — not before.
- Duplication of code is sometimes the right call when two things are coincidentally similar but represent different concepts. Premature DRY creates a wrong abstraction that resists change. Three lines of similar-looking code is not automatically a violation.
- DRY applies to data schemas, configuration, business rules — not just code.

---

## KISS — Keep It Simple

Prefer the simplest implementation that correctly solves the actual problem.

- Simple code is easier to read, test, debug, and extend. Complexity is a cost; justify it.
- If two solutions work, pick the one a new developer can understand without asking anyone.
- Clever is not a compliment. Boring is.
- Simple architecture wins over clever architecture at scale: `API → Business Logic → Database` is correct for most systems. Microservices, CQRS, event sourcing, distributed caches solve real problems but introduce real failure modes. Use sophisticated patterns when the problem demands them.

---

## YAGNI — You Aren't Gonna Need It

Don't build features, abstractions, or configurability for hypothetical future requirements.

- Abstract at the second real use, never the first. The abstraction you build for a speculative third use case is wrong for the actual third use case half the time.
- Speculative abstraction is future maintenance debt. The code you don't write has no bugs.
- YAGNI applies to abstractions: don't generalize until the generalization is needed and its shape is known from real usage.

---

## SRP — Single Responsibility

Every unit — function, class, module, service — has exactly one reason to change.

- A function that validates input, queries the DB, and sends an email is three functions.
- A class with more than one reason to change should be split.
- Thin layers enforce SRP at the architectural level:

| Layer | Responsibility | Must not |
| :--- | :--- | :--- |
| Handler / Controller / Route | Parse request, validate input, call service, return response | Contain business logic or DB calls |
| Service | Orchestrate business logic, enforce domain rules | Know about HTTP, DB drivers, or UI |
| Repository / Data access | Translate between domain types and the persistence layer | Contain business logic or HTTP concerns |
| Domain / Model | Types, value objects, domain errors, pure domain logic | Import infrastructure or framework code |

---

## DI — Dependency Inversion

High-level modules (business logic) must not depend on low-level details (DB drivers, HTTP clients, external APIs). Both depend on abstractions.

- Define interfaces/protocols at the boundary of each layer. The consumer layer owns the interface; the producer implements it.
- Dependency injection (passing the concrete at construction/startup) is the mechanism. No global singletons or module-level state that hard-codes the implementation.
- This makes layers independently testable: swap the real DB adapter for an in-memory fake without touching business logic.
- Language-specific: see `cross-stack/module-boundaries.md` for Go/Python/TypeScript implementations.

---

## Composition over Inheritance

Prefer small, focused units combined together over deep class hierarchies.

- Inheritance answers "is-a." Composition answers "has-a" and "uses-a." Most problems are the latter.
- Deep inheritance (more than two levels) couples subclass behavior to ancestor implementation details.
- Go enforces this naturally. Python and TypeScript allow inheritance — use it only when the is-a relationship is genuinely true and stable.

---

## Pure Logic at the Core, Side Effects at the Edges

Business logic as pure functions where possible: same inputs → same outputs, no hidden state, no side effects.

- A function that transforms data should not also log, hit the DB, or fire an event. Those go in the caller.
- Pure logic is trivially testable (no mocks needed) and trivially composable.
- Side effects (I/O, DB writes, HTTP calls, timestamps, randomness) belong at the outermost layer — handler or repository — not buried inside a calculation.

---

## Readability over Cleverness

Code is read 10× more than it is written.

- Test: can an unfamiliar developer understand what this code does and why in under five minutes?
- No nested ternaries. No chained side-effecting calls. No one-liners that do three things.
- A name that explains intent is worth more than a comment that explains what the code does.
- Cyclomatic complexity over ~5 (more than a few branches) is a signal to decompose.

---

## No Magic

Avoid framework magic, metaclass tricks, or dynamic attribute injection in application code.

- If behavior is non-obvious from reading the code — if understanding requires knowing a distant decorator, a parent class, or a config file — it will surprise the next developer.
- Explicit is better than implicit.
