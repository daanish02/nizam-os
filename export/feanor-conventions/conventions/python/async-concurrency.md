---
type: convention
title: Async & Concurrency
description: Python async rules covering async-first FastAPI routes, structured concurrency with anyio/asyncio, context managers, and when to offload to threads or processes.
applies_to: [python]
tags: [python, async, concurrency, fastapi]
---

# Async & Concurrency

Python's reputation for being "slow" is mostly about unused concurrency — use the language's tools rather than writing code that's accidentally serial.

## Rules

- FastAPI routes are `async def` by default. Only stay sync if a route does zero I/O.
- DB access goes through an async driver (async SQLAlchemy, `asyncpg`, or equivalent) — no blocking sync calls inside an async route; a blocking call there stalls the whole event loop, not just that request.
- Use `asyncio` primitives properly:
  - `asyncio.TaskGroup` for structured concurrent work (replaces manual `asyncio.gather` bookkeeping, propagates errors correctly).
  - `asyncio.Semaphore` to bound concurrency (e.g. concurrent LLM calls, concurrent DB queries) — never fire an unbounded number of concurrent tasks against an external service.
- Use async context managers (`async with`) for connections/sessions/clients. Never manually open/close a resource without one — a context manager guarantees cleanup even on exception.
- CPU-bound work (not I/O) still goes to a thread/process pool (`asyncio.to_thread` / `ProcessPoolExecutor`) — it doesn't belong on the event loop regardless of `async def`.
