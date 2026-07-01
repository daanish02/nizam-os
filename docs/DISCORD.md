# Nizam-OS — Discord

**Last updated:** 2026-07-01

Discord server structure, bot setup, and infrastructure config. For per-agent channel assignments and toolsets see `docs/AGENTS.md`. For credential storage see `docs/SECRETS.md`.

---

## Server structure

One Discord server. Four categories. Each category groups related agents and channels.

### Chairman's Office

User-only. No agent has access to this category.

| Channel | Agent | Notes |
|---|---|---|
| `#strategy` | None | User's private strategy space |

### System

Nazim's operational channels.

| Channel | Agent | Notes |
|---|---|---|
| `#admin` | Nazim | System admin commands |
| `#alerts` | Nazim | Automated alerts (inventory watcher, metric thresholds) |
| `#warning` | Nazim | Agent warnings and escalations |
| `#sandbox` | Nazim | Testing commands without production impact |

### Personal

| Channel | Agent | Notes |
|---|---|---|
| `#learning` | Noor | Knowledge ingestion — send URLs, PDFs, YouTube links |
| `#chat` | Ayah | General personal assistant |
| `#finances` | Ayah | Transaction recording, spending reports, zakat |
| `#habits` | Ayah | Habit tracking |
| `#goals-tasks` | Ayah | Goals and task management |
| `#journal` | Ayah | Daily journal entries |

Ayah's Personal channels are all `free_response_channels` — no @mention required.

### Arc Systems

| Channel | Agent | Notes |
|---|---|---|
| `#boardroom` | Raha | Weekly C-suite synthesis, strategic decisions |
| `#biz-chat` | Raha | Ad-hoc business queries routed to C-suite |
| `#cfo-office` | Hala | Business finance, invoices, P&L |
| `#coo-office` | Omar | CRM, project delivery, client status |
| `#cto-office` | Reem | Codebase health, PR review, tech debt |
| `#cmo-office` | Mira | Content strategy, marketing campaigns |

---

## Bot setup

One Discord application per agent. Each has its own bot token stored in `hermes/profiles/<name>/.env`.

### Create a bot

1. discord.com/developers → Applications → New Application
2. Name it after the agent (e.g. "Noor", "Raha")
3. Bot tab → Add Bot → copy token
4. Bot tab → enable **Message Content Intent** (required — Hermes cannot read messages without it)
5. Add to server: OAuth2 → URL Generator → scope `bot` → permissions `Send Messages`, `Read Message History`, `View Channels` → copy URL → open in browser → authorise

### Required intents

| Intent | Required | Why |
|---|---|---|
| Message Content Intent | Yes | Hermes reads message text |
| Server Members Intent | No | Not used |
| Presence Intent | No | Not used |

Bots do **not** need admin permissions. Minimum: Send Messages, Read Message History, View Channels.

### Getting channel IDs

Discord channel IDs are snowflake integers. To copy one:

1. Discord → User Settings → Advanced → enable **Developer Mode**
2. Right-click any channel → Copy Channel ID

Use these IDs in `config.yaml` under `discord.allowed_channels` and `discord.free_response_channels`.

---

## DISCORD_ALLOWED_USERS

Whitelist of Discord user IDs that can interact with each agent. Set per profile in `hermes/profiles/<name>/.env`.

```
DISCORD_ALLOWED_USERS=<snowflake_user_id>
```

To get your Discord user ID: Discord → User Settings → Advanced → enable Developer Mode → right-click your username → Copy User ID.

**Phase 2 fix required:** `DISCORD_ALLOWED_USERS` is not set on any current profile — any server member can chat with any active agent. Set this on every profile before adding other Discord users to the server. See `docs/SECURITY.md` known gaps.

---

## Webhooks

Two webhooks used for automated notifications. Both are stored in `secrets/nizam.env`.

| Variable | Channel | Purpose |
|---|---|---|
| `DISCORD_ADMIN_WEBHOOK` | `#alerts` or `#admin` | Inventory changes, system alerts |
| `NIZAM_INVENTORY_WATCHER` | Same or separate channel | Inventory-change notifications from `watch-inventory.sh` |

**Note:** `NIZAM_INVENTORY_WATCHER` is missing from `secrets/nizam.env.example` — add it on rebuild.

### Create a webhook

Discord → channel settings → Integrations → Webhooks → New Webhook → copy URL → add to `nizam.env`.

### Rotate a webhook URL

Regenerate in Discord (same path as creation). Update the var in `nizam.env`. The `watcher-env.service` auto-encrypts on save.

---

## Rate limits

Discord API: 50 requests/second per bot, global. Hermes handles backoff automatically — no manual rate limit management needed.

Bot tokens are per-bot (per-profile), so the 50 req/s limit is independent per agent.

---

## Failure behavior

| Failure | Impact | Recovery |
|---|---|---|
| Discord API down | Gateway fails to connect; Hermes retries | Wait for Discord recovery; restart gateway if needed |
| Bot token invalid | Gateway fails to start | Rotate token (see `docs/RUNBOOK.md` → Rotate a Discord bot token) |
| Agent not responding | Gateway is up but agent may be stuck | `hermes gateway stop <profile> && hermes gateway start <profile>` |
| Webhook URL invalid | Notification silently fails | Regenerate webhook, update `nizam.env` |
