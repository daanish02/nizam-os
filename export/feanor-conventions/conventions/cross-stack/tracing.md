---
type: convention
title: Distributed Tracing
description: OpenTelemetry span rules, W3C context propagation, sampling strategy, what to instrument, and trace/log correlation for Go, Python, and TypeScript — opt-in capability, load only when tracing is enabled in the project profile.
applies_to: [go, python, typescript]
tags: [tracing, opentelemetry, otel, spans, sampling, observability]
---

# Distributed Tracing

**Opt-in capability.** Load only when `tracing = true` in `.feanor/profile.toml`.

Tracing answers one question the other two cannot: *where did this one specific request spend its time, across every service it touched.* Metrics tell you the p99 got worse; traces tell you which call caused it.

**It earns its cost only with multiple services or heavy external calls.** For a single service talking to one database, a latency histogram plus a correlation id in the logs gives most of the answer for none of the operational overhead. Do not enable this by default.

## OpenTelemetry, Not a Vendor SDK

- Instrument with **OpenTelemetry** and export to whatever backend is chosen (Jaeger, Tempo, Honeycomb, Datadog). Vendor SDKs in application code make the backend a rewrite instead of a configuration change.
- Backend choice is an ADR — see `meta/adrs.md`.
- Use auto-instrumentation for HTTP servers, HTTP clients, and database drivers first. It covers most of the value with almost no code, and hand-written spans around a library call usually duplicate what auto-instrumentation already produces.

## Context Propagation

- **W3C Trace Context** (`traceparent`/`tracestate`) is the wire format. Not a custom header.
- **Propagate on every outbound call.** A trace that stops at a service boundary is a single-service trace with extra steps — the whole point is the join.
- **Context is passed explicitly, never through a global.** Go: `context.Context` as the first parameter, all the way down. Python: `contextvars`, which async frameworks propagate correctly. TypeScript: the OTel context manager.
- The **same correlation id appears in logs and traces.** Inject `trace_id` and `span_id` into every log line — that is what lets someone move from a log entry to the full trace and back. This is the seam where `observability-logging.md` and this file meet, and it is the highest-value part of enabling tracing at all.

## Spans

- **Span names are low-cardinality**, like metric labels: the route template (`GET /orders/{id}`), never the concrete path. High-cardinality names break grouping and aggregation in every backend.
- **Attributes carry the high-cardinality detail** — `user.id`, `order.id`, `http.route`, `db.statement`. Attributes are the right place for it; names are not.
- Follow **OTel semantic conventions** for attribute names (`http.request.method`, `db.system`, `server.address`). Custom names lose every backend's built-in dashboards and queries.
- **Never put secrets or personal data in attributes.** Traces go to a third-party backend and are retained there. The redaction deny-list in `observability-logging.md` applies identically — see `data-protection.md`.
- **Record errors on the span** (`RecordError`, status `ERROR`), and do it once at the boundary that handles the error, matching the no-double-logging rule.
- **Do not create a span per function.** A span per meaningful unit of work — an HTTP handler, a database query, an external call, an expensive computation. A trace with 400 spans is unreadable, expensive, and slower than the code it measures.
- Close every span. Use `defer span.End()` / a context manager / `try…finally`; a leaked span leaks memory and never exports.

## Sampling

Tracing every request at production volume is prohibitively expensive in ingest cost and storage.

- **Head sampling** — decide at the root, propagate the decision. Simple, cheap, and biased: it drops the rare slow request you actually wanted.
- **Tail sampling** — buffer the trace, decide after it completes. Keeps every error and every slow trace plus a small percentage of normal ones. More infrastructure (a collector holding state), and worth it in production.
- **Always sample errors and traces exceeding the latency SLO.** A sampling strategy that discards the interesting traces has bought nothing.
- Typical starting point: 100% in development, 1–10% of successful requests plus 100% of errors and slow requests in production.
- **The sampling decision propagates.** A service that re-decides mid-trace produces broken partial traces that are worse than none.

## Per Language

| Stack | Package | Notes |
| :--- | :--- | :--- |
| Go | `go.opentelemetry.io/otel` | `otelhttp`/`otelsql` wrappers; `context.Context` must reach every layer |
| Python | `opentelemetry-sdk` + instrumentation packages | `opentelemetry-instrument` auto-instruments FastAPI, SQLAlchemy, httpx |
| TypeScript | `@opentelemetry/sdk-node` | Node runtime only — the edge runtime has no equivalent; serverless needs a per-invocation flush or spans are lost on freeze |

## Cost

Tracing is the most expensive of the three signals per unit of insight: instrumentation effort, ingest cost, storage cost, and a measurable latency overhead on every request. It also creates a **new place personal data can leak** to a third party.

Enable it when a real question demanded it — a cross-service latency problem nobody could diagnose — not preemptively. That is the same YAGNI judgment as any other abstraction; see `coding-principles.md`.

Related: `observability-logging.md` (baseline, trace/log correlation), `metrics.md` (opt-in), `data-protection.md` (what must never reach a trace backend).
