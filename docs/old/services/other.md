# social, analytics, math services

Part of [services overview](../services.md). All three planned (step 7) — not yet implemented.

## social-service

Thin wrapper over social APIs. Operates on behalf of Mira (CMO).

| Tool | Description |
|---|---|
| `draft_post(platform, content, schedule_at?)` | Create a draft |
| `publish_post(draft_id)` | Publish immediately |
| `get_analytics(platform, period)` | Engagement, reach, follower delta |
| `list_drafts()` | Pending drafts |

**Platforms:** LinkedIn (priority), Twitter/X, Instagram (future). API keys per platform in `secrets/nizam.env`.

---

## analytics-service

Read-only cross-schema aggregations. Used by Hala for business summaries and by Bani for system health.

| Tool | Description |
|---|---|
| `llm_usage_summary(period?)` | Token spend, cost, cache savings per profile/model |
| `business_snapshot()` | Revenue, pipeline, active clients, open tasks |
| `personal_snapshot()` | Budget health, habit streaks, goal progress |
| `service_health()` | All systemd services status, Prometheus metrics |
| `audit_log(entity?, limit?)` | Recent writes across all schemas |

---

## math-service

Stateless computational tools. Any profile can call these.

| Tool | Description |
|---|---|
| `compound_growth(principal, rate, years, contributions?)` | Investment/savings projections |
| `loan_schedule(principal, rate, term_months)` | Amortisation table |
| `zakat_calc(assets)` | Nisab check + zakat amount |
| `currency_convert(amount, from, to)` | Live rate via free API |
| `vat_breakdown(amount, rate?)` | Inclusive/exclusive |
