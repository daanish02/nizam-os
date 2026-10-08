---
type: convention
title: Metrics & Alerting
description: Prometheus metric types, RED/USE method, label cardinality limits, /metrics exposure, dashboards-as-code, and SLO-based alerting for Go, Python, and TypeScript — opt-in capability, load only when metrics are enabled in the project profile.
applies_to: [go, python, typescript, ops]
tags: [metrics, prometheus, grafana, alerting, slo, observability]
---

# Metrics & Alerting

**Opt-in capability.** Load only when `metrics = true` in `.feanor/profile.toml`. Metrics are an operational commitment — a collector, storage, dashboards, alert routing, and a human who responds — not a coding standard. A system without them can be correct; it just cannot tell you it is unhealthy.

Logging is separate and always on: `observability-logging.md`.

## Cardinality — read this first

**Never put an unbounded value in a label.** This is the failure that takes down a Prometheus install, and it is easy to write by accident because the offending label always looks helpful.

A time series is created for **every distinct combination of label values** and kept in memory. A `user_id` label on a counter means one series per user, forever.

- **Forbidden as labels:** user id, request id, trace id, session id, email, IP address, full URL path with ids in it, error message, SQL query, timestamp, UUID of any kind.
- **Correct labels:** HTTP method, route *template* (`/orders/{id}`, never `/orders/12345`), status code class, service name, queue name, cache result (`hit`/`miss`) — small, closed sets known at write time.
- **Budget:** keep each metric under ~100 series. Multiply your label value counts before adding one — 5 methods × 20 routes × 5 status classes is 500 and already too many for one metric.
- High-cardinality identifiers belong in **logs** (searchable, retained briefly) or **traces** (sampled), never in metrics. That division is the entire reason all three exist.

## What To Measure

Do not instrument everything. Instrument what answers a question someone will actually ask at 3am.

**RED, for every request-handling service:**

- **Rate** — requests per second, by route and method.
- **Errors** — failed requests per second, by route and status class.
- **Duration** — latency histogram, by route.

**USE, for every constrained resource** (connection pool, worker queue, cache):

- **Utilisation** — how busy, as a fraction.
- **Saturation** — queued or waiting work.
- **Errors** — failures on that resource.

**Business metrics** where they answer an operational question: orders placed, signups completed, payments failed. One per genuinely distinct outcome — not one per database write.

## Metric Types

| Type | Use for | Never use for |
| :--- | :--- | :--- |
| Counter | Monotonically increasing totals (requests, errors, bytes) | Anything that can decrease |
| Gauge | Values that go up and down (queue depth, connections, memory) | Rates — derive those from counters |
| Histogram | Latency and size distributions | Anything where you need an exact value |
| Summary | Avoid | — prefer histograms; summaries cannot be aggregated across instances |

- **Histograms, not summaries, for latency.** Summary quantiles are computed per instance and are mathematically meaningless when averaged across replicas.
- **Choose buckets deliberately.** Defaults rarely match a real SLO. If the target is p95 < 200ms, buckets need resolution around 200ms — `[.01, .025, .05, .1, .2, .3, .5, 1, 2.5, 5]` beats the library default for a typical API.
- **Naming:** `<namespace>_<subsystem>_<name>_<unit>`, always base units (seconds, bytes — never milliseconds), counters suffixed `_total`. `http_request_duration_seconds`, `orders_placed_total`.

## Exposure

- Expose `/metrics` in Prometheus text format on the service's own port, or a separate admin port.
- **`/metrics` is not public.** It reveals internal structure, traffic volume, and error patterns. Bind to an internal interface, or require authentication, or restrict at the ingress — never expose it unauthenticated to the internet.
- Health checks are a different endpoint with a different job — see `health-endpoints.md`. A metrics scrape is not a liveness probe.
- The metrics registry is process-global and initialised once at startup. Registering a metric per request leaks memory and eventually panics on duplicate registration.

## Per Language

| Stack | Library | Notes |
| :--- | :--- | :--- |
| Go | `prometheus/client_golang` | Register in `init()` or a constructor; `promhttp.Handler()` for the endpoint |
| Python | `prometheus-client` | Use the multiprocess collector under Gunicorn/Uvicorn workers, or per-worker series will be wrong |
| TypeScript | `prom-client` | Serverless does not hold process state between invocations — push to a gateway or use the platform's own metrics instead |

**Serverless caveat:** in-process metric registries assume a long-lived process. On Vercel/Lambda-style runtimes, counters reset per invocation and gauges are meaningless. Either use the platform's built-in metrics or accept that this capability does not fit that deployment.

## Dashboards

- **Dashboards as code**, committed to the repo (Grafana JSON or Terraform), not hand-built in a UI. A dashboard that exists only in someone's Grafana disappears with the instance and cannot be reviewed.
- One overview dashboard per service showing RED at the top. Detail dashboards below it, not instead of it.
- A panel with no question behind it is noise — it trains people to ignore the dashboard, which is worse than not having one.

## Alerting

- **Alert on symptoms, not causes.** "p95 latency above SLO for 10 minutes" is actionable; "CPU above 80%" is not — high CPU with healthy latency needs no human.
- **Every alert is tied to an SLO or a user-visible failure**, and names the runbook entry that resolves it. See `docs/RUNBOOK.md`.
- **Every alert must be actionable at 3am.** If the response is "watch it," it is a dashboard panel, not an alert.
- Use `for:` durations to suppress transient spikes. An alert that fires and self-resolves in 60 seconds trains responders to ignore the channel — the real cost of a noisy alert is the one that gets ignored later.
- Alert rules live in the repo alongside the dashboards and are reviewed like code.

Related: `observability-logging.md` (baseline logging), `tracing.md` (opt-in tracing), `health-endpoints.md` (liveness/readiness), `data-protection.md` (never put personal data in a label).
