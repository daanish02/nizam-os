# Omar (COO) — v1 design spec

**Status:** approved, pending implementation (Phase 4c)
**Prerequisite:** `crm-service` built; migration `0005_crm_schema.sql` run; Hala live (for quoting context)
**Profile dir:** `hermes/profiles/coo/`
**Agent name:** Omar

---

## Role

Omar is the COO. He owns client relationships, project delivery, and operations. He tracks deals through the pipeline, manages client contacts, logs interactions, and monitors project status. He has read access to business finance for quoting context only — he cannot record transactions or create invoices.

Reports to Raha. User can also reach Omar directly in `#coo-office`.

---

## Discord access

**Channel:** `#coo-office` (Arc Systems)

```yaml
discord:
  allowed_channels: "<coo_office_id>"
```

---

## Hermes toolsets

```yaml
platform_toolsets:
  discord:
    - memory
    - skills
    - clarify
    - web         # external client research, company lookups
```

**Disabled:** `browser`, `code_execution`, `cronjob`, `delegation`, `file`, `image_gen`, `terminal`, `tts`, `vision`

---

## MCP servers

```yaml
mcp_servers:
  crm:
    url: http://127.0.0.1:8104/mcp
    # No filter — Omar owns all CRM tools
  finance:
    url: http://127.0.0.1:8101/mcp
    tools:
      include:
        - business_account_balance   # quoting context: know available budget
        - invoice_status_report      # project billing: track what's been invoiced
```

No access to personal-service, knowledge-service, or personal finance tools.

---

## DB access

Role: `svc_crm`

| Schema | Access |
|---|---|
| `crm.*` | RW |
| `business.finance.*` | RO (via included MCP tools only) |
| `personal.*` | None |
| `finance.personal_transactions` | None |
| `audit.log` | INSERT only |

---

## Database schema: `crm`

Migration: `db/migrations/0005_crm_schema.sql`

```sql
crm.clients     (id, name, industry, status, country, created_at)
crm.contacts    (id, client_id, name, role, email, phone, primary_contact)
crm.deals       (id, client_id, title, stage, value, currency, expected_close, created_at)
crm.projects    (id, client_id, deal_id nullable, title, status, start_date, end_date)
crm.interactions (id, client_id, contact_id nullable, type, notes, occurred_at, created_at)
```

`deal.stage` values: `prospect` → `proposal` → `negotiation` → `won` → `lost`
`project.status` values: `active` → `on_hold` → `delivered` → `cancelled`
`interaction.type` values: `call` | `email` | `meeting` | `note`

---

## crm-service MCP tools

New service at `services/crm-service/`. Port 8104.

| Tool | Consumer | What it does |
|---|---|---|
| `add_client` | Omar | Insert into `crm.clients` |
| `update_client` | Omar | Update client status/details |
| `add_contact` | Omar | Insert into `crm.contacts` |
| `add_deal` | Omar | Insert into `crm.deals` |
| `update_deal_stage` | Omar | Progress deal through pipeline stages |
| `add_project` | Omar | Insert into `crm.projects` |
| `update_project_status` | Omar | Update project status |
| `log_interaction` | Omar | Insert into `crm.interactions` |
| `client_list` | Omar, Mira | List clients, filterable by status/industry |
| `deal_pipeline` | Omar, Raha | All open deals with stage and value |
| `client_case_studies` | Mira | Won deals with project outcomes for content use |

Service writes to `audit.log` on every mutation. Detailed tool spec in `docs/plans/20260701-coo-v1.md` (written at build time).

---

## Profile files

| File | Content |
|---|---|
| `SOUL.md` | Personality: practical, client-focused, detail-oriented. Tracks every commitment. |
| `AGENTS.md` | Mandate: CRM ownership, project status rules, deal stage definitions, interaction logging policy. |
| `config.yaml` | MCP crm + filtered finance, `web` toolset enabled, compression model, security. |
| `user.md` | Pre-seeded: user name, business name, primary industries, current active clients (at setup time). |

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

- `coo` profile does not exist. Description for Kanban routing: "Operations, client onboarding, project delivery, CRM." Profile creation command is in the implementation plan.
- `crm-service` is a new service — build its spec (`docs/plans/20260701-coo-v1.md`) at Phase 4c start.
- `0005_crm_schema.sql` depends on `0004_business_finance_schema.sql` being run first (FK from invoices to clients is set up in `0004`).
- `svc_crm` gets RO on `business.finance` only through the MCP tool include list — not a direct DB grant. The MCP tools `business_account_balance` and `invoice_status_report` connect as `svc_finance_business`. Omar does not have a direct DB connection to `business.finance`.

---

## Done criteria

- `coo` profile created with `--description`
- `SOUL.md` + `AGENTS.md` written
- `config.yaml` — crm MCP (no filter), finance MCP with include list, web toolset, compression model
- `crm-service` built at port 8104 with all tools above
- `0005_crm_schema.sql` written and reviewed
- `svc_crm` role created, grants verified
- `DISCORD_ALLOWED_USERS` set in VPS `.env`
- `discord.allowed_channels` set to `#coo-office` channel ID
- Spot check: Omar can add a client, log an interaction, and update a deal stage
