# Raha (Chief of Staff) — v1 design spec

**Status:** approved, pending implementation (Phase 4a)
**Prerequisite:** personal agents (Noor, Nazim, Ayah) fully functional and stable
**Profile dir:** `hermes/profiles/cos/`
**Agent name:** Raha

---

## Role

Raha is the Chief of Staff. She is the only agent with access to the full business layer at once. She coordinates the four C-suite agents (Hala, Omar, Reem, Mira), synthesises their outputs, and reports to the Chairman (user). She has no direct data access — she reads through delegated child agents only.

You = Chairman & CEO. Raha = CoS. All C-suite report to Raha. Raha reports to you.

---

## Discord access

**Channels:** `#strategy` (Chairman's Office), `#boardroom`, `#biz-chat` (Arc Systems)

```yaml
discord:
  allowed_channels: "<strategy_id>,<boardroom_id>,<biz_chat_id>"
```

`#strategy` — user-driven, high-level decisions and briefings.
`#boardroom` — cross-functional business decisions, weekly reviews.
`#biz-chat` — general business queries and ad-hoc delegation.

---

## Hermes toolsets

```yaml
platform_toolsets:
  discord:
    - delegation    # spawns child agents (Hala, Omar, Reem, Mira)
    - kanban        # task tracking across C-suite
    - memory        # persistent context between sessions
    - skills        # custom skills via agentskills.io
    - clarify       # ask user for missing context before acting
    - cronjob       # weekly review cron (Monday 09:00)
```

**Disabled:** `browser`, `code_execution`, `file`, `image_gen`, `terminal`, `tts`, `vision`, `web`

> `kanban` is NOT included in the Hermes `all` toolsets wildcard. It must be explicitly listed under `platform_toolsets.discord`. Do not add it to other agent profiles.

---

## MCP servers

None. Raha has no direct DB or service access.

```yaml
mcp_servers: {}
```

All data access is delegated. When Raha needs financial data, she spawns Hala with a goal. When she needs ops status, she spawns Omar. She serialises all relevant context into each `delegate_task` call — child agents start with zero context beyond what is passed.

---

## Delegation pattern

Uses Hermes `delegate_task` tool. Raha spawns child agents, gathers results, synthesises before responding. Sub-agents never respond directly to Discord — Raha owns the channel response.

```python
# Example delegation call (conceptual — Hermes handles the API)
delegate_task(
    profile="cfo",
    goal="Provide a P&L summary for the current month.",
    context={
        "user_request": "Monthly business review",
        "date_range": "2026-07-01 to 2026-07-31",
        "output_format": "bullet points, AED, max 10 lines"
    }
)
```

Delegation mode:
- **Sync** — Raha blocks until the child responds (use for: data needed before synthesising)
- **Async** — Raha fires and moves on (use for: independent tasks that can run in parallel)

Hermes Kanban worker profiles for routing: each business agent must be created with `--description` so the Kanban orchestrator knows what each is good at. The `--description` strings are defined in each agent's spec. Creation commands are in each agent's implementation plan.

---

## Weekly review cron

Runs every Monday at 09:00 (VPS timezone = user timezone). Raha:
1. Delegates to Hala: last week spend vs budget
2. Delegates to Omar: active projects + client status
3. Delegates to Reem: open PRs, tech issues
4. Delegates to Mira: content performance, upcoming posts
5. Synthesises into a weekly brief and posts in `#boardroom`

**Model must be pinned at cron creation time.** A model swap on the primary profile will silently change cron behaviour — pin with `--model` at `hermes cron create` time.

---

## Profile files

| File | Content |
|---|---|
| `SOUL.md` | Personality: strategic, composed, precise. Speaks in summaries, not details. No jargon. Asks one clarifying question at a time. |
| `AGENTS.md` | Mandate: CoS role, delegation rules, synthesis format, escalation rules, channel context, cron schedule. |
| `config.yaml` | Toolsets, MCP (empty), model, compression model, security settings. |
| `user.md` | Pre-seeded context: user name, timezone, business name, C-suite roster, delegation preferences. |

---

## Security config

```yaml
security:
  allow_lazy_installs: false
  redact_secrets: true

approvals:
  mode: manual
  cron_mode: deny

auxiliary:
  compression:
    provider: custom:litellm
    model: deepseek/deepseek-v3-0324
```

---

## Implementation notes

- `cos` profile already exists — SOUL.md is a default placeholder. Rewrite completely.
- Old SOUL.md references "Hala" as the CoS name. Correct name is Raha.
- Hermes `delegate_task` documentation: read before implementing. Confirm whether async delegation is available in the installed version.
- Do not give Raha any MCP access "just in case". If she needs data, she delegates.
- Weekly review cron: test by manually triggering before setting the schedule.

---

## Grafana: business dashboard

File: `grafana/business-dashboard.json`
Built in: CoS v1 plan — Task N (defined when Phase 4 plan is written)
**Prerequisite:** migrations `0004_business_finance_schema.sql` + `0005_crm_schema.sql` run; Hala and Omar live and actively logging data

**Datasource:** PostgreSQL direct. `grafana` role with `SELECT` on `business.finance.*`, `crm.*`. Role grants extended in migration `0004`.

**Panels:**

| Section | Panel | Type | Query target |
|---|---|---|---|
| Finance | Revenue this month | stat (AED) | `business.transactions WHERE direction = 'income' AND month = current` |
| Finance | Expenses this month | stat (AED) | `business.transactions WHERE direction = 'expense' AND month = current` |
| Finance | Net income this month | stat (AED, green/red) | revenue minus expenses |
| Finance | Outstanding invoices — total | stat (AED) | `business.invoices WHERE status = 'sent'` |
| Finance | Overdue invoices | stat (red if > 0) | `business.invoices WHERE due_date < today AND status != 'paid'` |
| Finance | Revenue vs expenses — 6 months | timeseries | monthly aggregates, last 6 months |
| Finance | Spend by category | bargauge | `business.transactions` this month grouped by category |
| CRM | Active clients | stat | `crm.clients WHERE status = 'active'` |
| CRM | Active projects | stat | `crm.projects WHERE status = 'active'` |
| CRM | Open deals | stat | `crm.deals WHERE stage NOT IN ('won', 'lost')` |
| CRM | Pipeline value | stat (AED) | `SUM(value) WHERE stage NOT IN ('won', 'lost')` |
| CRM | Deals by stage | bargauge | `crm.deals` grouped by stage |
| CRM | Interactions this week | stat | `crm.interactions WHERE occurred_at >= start_of_week` |
| CRM | Projects by status | bargauge | `crm.projects` grouped by status |

**Rebuild:** Same PostgreSQL datasource role as personal dashboard (extend grants). Import `grafana/business-dashboard.json`.

---

## Done criteria

- `SOUL.md` rewritten — personality, no mandate content
- `AGENTS.md` written — delegation mandate, escalation rules, synthesis format
- `config.yaml` — kanban + delegation in toolsets, no MCP servers, compression model pinned
- `user.md` — pre-seeded with user name, business name, C-suite roster
- `DISCORD_ALLOWED_USERS` set in VPS `.env`
- `discord.allowed_channels` set to `#strategy`, `#boardroom`, `#biz-chat` channel IDs
- Weekly review cron created and tested with manual trigger
- Spot check: Raha responds in `#boardroom`, silent in all personal channels
