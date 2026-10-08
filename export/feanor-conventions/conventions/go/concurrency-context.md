---
type: convention
title: Concurrency & Context
description: Go rules for goroutine lifecycle, channels vs. mutex vs. atomic selection, errgroup structured concurrency, and context propagation.
applies_to: [go]
tags: [go, concurrency, context, goroutines]
---

# Concurrency & Context

Every goroutine is a liability until proven necessary. Structured concurrency: every goroutine has a clear owner, a predictable exit, and error propagation — never fire-and-forget.

## Core Rules

- Every goroutine has a clear exit mechanism — context cancellation, channel close, or explicit signal. No shutdown mechanism means it leaks.
- Share memory by communicating: channels transfer ownership explicitly. Only the sender closes a channel.
- Send copies, not pointers, on channels — a pointer creates invisible shared memory, defeating the point.
- Specify channel direction (`chan<-`, `<-chan`) so the compiler catches misuse.
- Default to unbuffered channels; a larger buffer needs measured justification, not a guess.
- Always include `ctx.Done()` in a `select` — otherwise the goroutine leaks after caller cancellation.
- Track goroutine leaks in tests with `go.uber.org/goleak`.

## Channel vs. Mutex vs. Atomic

| Scenario | Use |
| :--- | :--- |
| Passing data between goroutines | Channel |
| Coordinating goroutine lifecycle | Channel + context |
| Protecting shared struct fields | `sync.Mutex` / `sync.RWMutex` |
| Simple counters/flags | `sync/atomic` (typed: `atomic.Int64`, `atomic.Bool`) |
| Many readers, few writers on a map | `sync.Map` — concurrent map read/write without one is a hard crash |
| Execute once / dedupe concurrent calls | `sync.Once` / `singleflight` |

## WaitGroup vs. errgroup

| Need | Use |
| :--- | :--- |
| Wait for goroutines, no error propagation needed | `sync.WaitGroup` |
| Wait + collect first error | `errgroup.Group` |
| Wait + cancel siblings on first error | `errgroup.WithContext` |
| Wait + bound concurrency | `errgroup.SetLimit(n)` — replaces a hand-rolled worker pool |

## Context

- `context.Context` is the first parameter of any function that does I/O or could block.
- Propagate context through the full call chain — don't create a fresh `context.Background()` partway down just because threading it through is inconvenient.
- Use context for cancellation/deadlines/request-scoped values only — never as a general parameter-passing mechanism.

## Common Mistakes

| Mistake | Fix |
| :--- | :--- |
| Fire-and-forget goroutine | Provide a stop mechanism (context, done channel) |
| Closing a channel from the receiver side | Only the sender closes |
| `time.After` in a hot loop | Reuse `time.NewTimer` + `Reset` |
| Missing `ctx.Done()` in select | Always select on context for cancellation |
| Unbounded goroutine spawning | `errgroup.SetLimit(n)` or a semaphore |
| Mutex held across I/O | Keep critical sections short |
| Forgetting `-race` in CI | Always run `go test -race ./...` |
