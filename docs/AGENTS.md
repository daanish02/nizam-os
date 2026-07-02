# Nizam-OS — Agent Roster

**Last updated:** 2026-07-02

Personal agents (Phases 3–5). For business agents (Phases 6a–6e): `docs/future/AGENTS.md`.

---

## Quick reference

| Agent | Profile | Persona | Spec |
|---|---|---|---|
| Nazim | `admin` | System admin | `docs/specs/20260701-admin-v1-design.md` |
| Noor | `curator` | Knowledge curator | `docs/specs/20260701-curator-v1-design.md` |
| Ayah | `assistant` | Personal assistant | `docs/specs/20260701-assistant-v1-design.md` |

Phase and build status: `docs/ROADMAP.md`. Model: all profiles use `deepseek/deepseek-v4-flash` via `custom:litellm`. Compression: `deepseek/deepseek-v3-0324` (pinned per profile).

---

## Nazim — System Admin

**Profile:** `hermes/profiles/admin/`
**Channels:** `#admin`, `#alerts`, `#warning`, `#sandbox` (System category — full category access)

**Mandate:** Infrastructure health, incident response, service restarts, Hermes guide. Has `terminal` + `file` for diagnostic commands. Sudo scoped to service restarts only via `/etc/sudoers.d/nazim-hermes`. All scheduled health checks created via Hermes `cronjob` toolset — not native system cron.

**Hermes toolsets:** `terminal`, `file`, `memory`, `skills`, `clarify`, `cronjob`, `web`

**MCP servers:** None. Diagnostics come from terminal and journalctl — vault access not needed.

**`#alerts` channel:** Receives both Nazim-posted alerts and webhook-posted notifications (inventory watcher, metrics scripts via `DISCORD_ADMIN_WEBHOOK`). Dual source — no conflict. Nazim does not need to read webhook messages.

**Key constraints:**
- Sudo restricted to specific `systemctl restart` commands only
- Does not write to knowledge vault
- Scheduled jobs via Hermes `cronjob` only — never `crontab -e`

---

## Noor — Knowledge Curator

**Profile:** `hermes/profiles/curator/`
**Channel:** `#learning` (Personal category)

**Mandate:** Ingest content into `~/nizam-vault/commons/`. All writes approval-gated (2-pass). Workflow: `docs/SERVICES.md` → knowledge-service → Approval workflow. Never skips approval. Vault walks via Hermes `cronjob` (periodic re-indexing or status updates).

**Hermes toolsets:** `memory`, `skills`, `clarify`, `cronjob`

**Discord config:** `allow_any_attachment: true`, `max_attachment_bytes: 33554432` — accepts PDF and image file uploads from Discord

**MCP servers:**

| Server | Access |
|---|---|
| `knowledge-service` :8100 | All tools (owns all vault writes) |

**Area vocabulary:** Controlled, enforced by knowledge-service — `docs/SCHEMAS.md` → knowledge schema → areas taxonomy. Noor suggests areas; user corrects at approval step.
---

## Ayah — Personal Assistant

**Profile:** `hermes/profiles/assistant/`
**Channels:** `#chat`, `#finances`, `#planner`, `#briefing` (Personal category — all four are free_response_channels, no @mention needed)

`#planner` — habits, goals, tasks (merged). `#briefing` — morning/evening briefings posted by Ayah; journal entries added as threads inside `#briefing`.

**Mandate:** Personal finance (multicurrency, zakat, riba), habits, goals, tasks, journal. All finance writes require user confirmation before committing. Never commits with `approved=False`.

**Hermes toolsets:** `memory`, `skills`, `clarify`

**Discord config:** `allow_any_attachment: true` — accepts bank statement PDFs and CSVs

**MCP servers:**

| Server | Access |
|---|---|
| `finance-service` :8101 | Personal tools only: `record_transaction`, `spending_report`, `budget_status`, `account_balance`, `reconcile_statement`, `add_category`, `zakat_status`, `calculate_zakat`, `log_riba`, `riba_report` |
| `personal-service` :8102 | All tools (no filter) |

**Key constraints:**
- Never touches `finance_business.*` schema
- Riba lines routed to `log_riba`, never to `record_transaction`
- FX rate always shown before approval

---

## Common config applied to all profiles

```yaml
security:
  allow_lazy_installs: false
  redact_secrets: true

approvals:
  mode: manual
  cron_mode: deny           # except Raha, Nazim, and Noor (vault walks) where cronjob is enabled

auxiliary:
  compression:
    provider: custom:litellm
    model: deepseek/deepseek-v3-0324
```

Per-profile `.env` (VPS only, gitignored): `DISCORD_TOKEN`, `DISCORD_GUILD_ID`, `LITELLM_MASTER_KEY` (virtual key).

Disabled by default on all profiles unless explicitly listed above: `browser`, `code_execution`, `image_gen`, `tts`, `vision`, and all toolsets not enumerated per agent.
