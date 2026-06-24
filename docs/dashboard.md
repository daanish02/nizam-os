# Dashboard Guide — Nizam Agents

## Stat tiles (top row)
Six tiles giving a live snapshot. Color = health: green is fine, orange is a warning, red needs attention.

| Tile | What it means |
|---|---|
| Proxy Status | LiteLLM proxy reachable. UP = green, DOWN = red. If DOWN, no agents can make LLM calls. |
| Calls Today | Total LLM requests since midnight. Resets daily. |
| Tokens In Today | Prompt tokens sent today across all models and agents. |
| Tokens Out Today | Completion tokens received today. High ratio vs tokens in = long responses. |
| Spend Today | USD spent today. Orange at $2, red at $5 — adjust thresholds to match your budget. |
| Cache Hit Rate | % of calls served from Redis cache (no API charge). Above 40% = green. Below 20% = red. |

## Cost Rate — by Model
Spend per hour, broken out by model, over a rolling 10-minute window. Each line is one model.

- A flat zero line = no calls to that model in the window. Normal during quiet periods.
- A spike on one model while others are flat = a specific agent is active.
- All models spiking together = a Raha delegation fan-out or a cron job touching multiple agents.

## Token Rate — In / Out / Cache Read
Tokens per minute across all models. Three lines: blue (input), purple (output), teal (cache read).

- Output consistently higher than input = agents are generating verbose responses. Consider tightening system prompts.
- Cache Read climbing = good. Means LiteLLM is serving repeated context from Redis instead of billing for it.
- All three flat = no active calls.

## All-Time bars (row 3)

| Panel | What it means |
|---|---|
| Spend by Model | Cumulative USD per model since the DB was first populated. Longest bar = most expensive model overall. |
| Spend by Provider | Pie split across providers (anthropic, openai, google, etc.). Currently should be 100% openrouter. |
| Spend by Agent | Cumulative USD per Hermes profile. Identifies which agent drives the most cost over time. |

These pull from the `nizam_llm_spend_usd_total` counter which reflects all rows in `LiteLLM_SpendLogs` — they don't reset on Prometheus restart.

## Cache Tokens — Creation vs Read
Tokens per minute: orange (cache creation), teal (cache read).

- Creation tokens appear when a model writes new context into its cache (billed at a small premium).
- Read tokens appear on subsequent calls that hit that cache (billed at a steep discount).
- Read consistently above creation = cache is working well — you're paying to write once and reading many times.
- Creation with no reads = prompts are changing too much for cache to help. Consider stabilising system prompts.

## Avg Response Latency — by Model (1h rolling)
Average end-to-end response time in milliseconds per model, computed from LiteLLM's SpendLogs over the last hour. One line per model.

- Gaps in lines = no calls to that model during the window. Normal.
- One model consistently slower = provider latency or large context size. Not necessarily a problem.
- All models spiking at the same time = network issue or VPS resource pressure. Cross-reference with the system dashboard.

## Bottom stat tiles

| Tile | What it means |
|---|---|
| Spend This Month | Rolling calendar-month total. Green below $60, orange at $60, red at $90. |
| Cache Savings Today | Estimated USD saved via provider prompt cache. Computed from cache read tokens × (prompt price − cache read price) from OpenRouter's pricing API. |
| Total Calls (All Time) | All LLM requests ever recorded in the DB. |
| Total Tokens In (All Time) | Cumulative prompt tokens since the DB was first populated. |
| Total Tokens Out (All Time) | Cumulative completion tokens since the DB was first populated. |
| Total Spend (All Time) | Cumulative USD spend since the DB was first populated. Green below $50, orange at $50, red at $100. |

## Variables (top of dashboard)
- **Model** — filter all panels to one or more models. Default: all.
- **Agent** — filter all panels to one or more Hermes profiles. Default: all.

Combining both narrows to a specific agent using a specific model — useful for cost attribution per agent.
