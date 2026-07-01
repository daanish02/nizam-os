# Mira (CMO) — v1 design spec

**Status:** approved, pending implementation (Phase 4e)
**Prerequisite:** knowledge-service functional; crm-service functional (Omar live); `analytics-service` (Phase 5)
**Profile dir:** `hermes/profiles/cmo/`
**Agent name:** Mira

---

## Role

Mira is the CMO. She owns content strategy, LinkedIn presence, marketing campaigns, and social performance. She reads from the knowledge vault (Noor's curated content) to source ideas and from the CRM (Omar's client data) for case studies. She does not write to either. She tracks post performance and campaigns through `analytics-service` (Phase 5 — not in v1 scope).

Reports to Raha. User can also reach Mira directly in `#cmo-office`.

---

## Discord access

**Channel:** `#cmo-office` (Arc Systems)

```yaml
discord:
  allowed_channels: "<cmo_office_id>"
```

---

## Hermes toolsets

```yaml
platform_toolsets:
  discord:
    - memory
    - skills
    - clarify
    - web         # research competitor content, trending topics, platform updates
    - image_gen   # generate visuals for content drafts (optional, enable when needed)
```

**Disabled:** `browser`, `code_execution`, `cronjob`, `delegation`, `file`, `terminal`, `tts`, `vision`

---

## MCP servers

```yaml
mcp_servers:
  knowledge:
    url: http://127.0.0.1:8100/mcp
    tools:
      include:
        - search_vault
        - get_note
        - list_notes
        # ingest excluded — Mira reads only

  crm:
    url: http://127.0.0.1:8104/mcp
    tools:
      include:
        - client_list          # which clients exist, industries
        - client_case_studies  # won projects with outcomes — for content
        - deal_pipeline        # active deals — do not publish client names without approval
```

**Phase 5 addition (not in v1):**
```yaml
  analytics:
    url: http://127.0.0.1:8105/mcp
    # All analytics tools — Mira owns social performance data
```

---

## DB access

None. Mira does not connect to PostgreSQL directly. All data access through MCP tools.

---

## Content responsibilities (v1 scope)

Mira v1 focuses on:
- Drafting LinkedIn posts from vault content or user direction
- Maintaining a content calendar (in-memory or as notes — no dedicated service yet)
- Surfacing case study angles from CRM data
- Researching trending topics (via `web` toolset)

**Not in v1 scope** (requires `analytics-service`):
- Post performance tracking
- Campaign ROI analysis
- Engagement metrics

---

## Profile files

| File | Content |
|---|---|
| `SOUL.md` | Personality: creative, strategic, platform-aware. Understands Arabic business culture. Writes in English and Arabic. |
| `AGENTS.md` | Mandate: content strategy ownership, posting guidelines (do not publish client names without approval), content calendar, LinkedIn voice rules. |
| `config.yaml` | MCP knowledge + CRM reads, web + image_gen toolsets, compression model, security. |
| `user.md` | Pre-seeded: user name, business name, target audience, content pillars, LinkedIn handle, tone of voice, language preference (English primary, Arabic secondary). |

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

- `cmo` profile does not exist. Description for Kanban routing: "Content, LinkedIn, social media, marketing campaigns." Profile creation command is in the implementation plan.
- `client_case_studies` tool: returns won deals with project outcomes. Mira must not publish client names or specific financials without explicit approval from the user. This rule goes in `AGENTS.md`.
- `image_gen` toolset: enable only if Hermes supports a usable image generation backend on VPS. If not available, omit from v1 and add later.
- `analytics-service` is Phase 5 — do not build placeholder hooks for it now. Add analytics MCP to `config.yaml` when the service exists.

---

## Done criteria

- `cmo` profile created with `--description`
- `SOUL.md` + `AGENTS.md` written (includes client confidentiality rules)
- `config.yaml` — knowledge MCP (read-only), CRM MCP (read-only), web toolset, compression model
- `DISCORD_ALLOWED_USERS` set in VPS `.env`
- `discord.allowed_channels` set to `#cmo-office` channel ID
- Spot check: Mira can search vault for content ideas and retrieve a client case study from CRM
