# Nizam-OS — Business Services (Future)

**Last updated:** 2026-07-02

Business MCP services (Phases 6b+). Personal services: `docs/SERVICES.md`.

---

## Port map

| Port | Service | Status |
|---|---|---|
| 8103 | `math-service` | Planned |
| 8104 | `crm-service` | Planned |
| 8105 | `analytics-service` | Planned |

Personal service ports (4000, 8100–8102): `docs/SERVICES.md`.

All services run on `127.0.0.1` only. Hermes connects via `url: http://127.0.0.1:PORT/mcp`.

---

## finance-service

**Port:** 8101
**Transport:** streamable-HTTP
**Status:** Specced
**Spec:** `docs/specs/20260701-assistant-v1-design.md` (personal tools), `docs/specs/20260701-cfo-v1-design.md` (business tools)
**Systemd unit:** `systemd/finance-service.service`

One service binary, two DB roles. Personal tools in `docs/SERVICES.md`. Business tools below.

### Consumers and tool access

| Agent | DB role used | Tools included |
|---|---|---|
| Hala (`cfo`) | `svc_finance_business` | All business tools |
| Omar (`coo`) | `svc_finance_business` (RO subset) | `business_account_balance`, `invoice_status_report` |

### DB roles

| Role | Access |
|---|---|
| `svc_finance_business` | RW on `finance_business.*`, INSERT on `audit.log`. No access to `finance_personal.*`. |

### Tools — business (Hala, Omar read-subset)

| Tool | Consumers | What it does |
|---|---|---|
| `record_business_transaction` | Hala | Insert into `business.transactions`, write audit |
| `create_invoice` | Hala | Insert into `business.invoices` + `business.invoice_items` |
| `update_invoice_status` | Hala | Advance status: draft → sent → paid → void |
| `business_spending_report` | Hala | Aggregate spend by category, date range, account |
| `business_account_balance` | Hala, Omar | Current balance per account or all accounts |
| `p_and_l_report` | Hala | Income minus expenses for a period, by category |
| `invoice_status_report` | Hala, Omar | Outstanding, overdue, paid invoices for a period |

### Dependencies

`pymupdf` (statement PDF extraction), `httpx` (FX API, gold price API), `hijridate` (Hijri hawl boundary dates).

Env vars: `FX_API_KEY` (exchangerate-api.com), `GOLD_API_KEY` (metals-api.com or goldpricez.com).

### Tunables

| Parameter | Value | Notes |
|---|---|---|
| Default currency | SAR (configurable) | All amounts stored in `amount_base` converted to `default_currency`. Change via `DEFAULT_CURRENCY` env var in `nizam.env`. |

---

## math-service

**Port:** 8103
**Transport:** streamable-HTTP
**Status:** Planned
**Spec:** to be written at Phase build time

---

## crm-service

**Port:** 8104
**Transport:** streamable-HTTP
**Status:** Planned — built in Phase 6c (Omar/COO)
**Spec:** `docs/specs/20260701-coo-v1-design.md`
**DB role:** `svc_crm` (RW on `crm.*`, INSERT on `audit.log`. No direct access to `business.finance.*` — Omar reads finance data via finance-service MCP tool includes.)
**Migration:** `db/migrations/0005_crm_schema.sql` (depends on `0004_business_finance_schema.sql`)
**Systemd unit:** `systemd/crm-service.service` (to be written at build time)

### Consumers and tool access

| Agent | Tools included |
|---|---|
| Omar (`coo`) | All tools (no filter) |
| Mira (`cmo`) | `client_list`, `deal_pipeline`, `client_case_studies` |
| Raha (`cos`) | `deal_pipeline` |

### Tools

| Tool | Consumers | What it does |
|---|---|---|
| `add_client` | Omar | Insert into `crm.clients` |
| `update_client` | Omar | Update client status or details |
| `add_contact` | Omar | Insert into `crm.contacts` |
| `add_deal` | Omar | Insert into `crm.deals` |
| `update_deal_stage` | Omar | Advance deal: prospect → proposal → negotiation → won / lost |
| `add_project` | Omar | Insert into `crm.projects` |
| `update_project_status` | Omar | Update project status: active → on_hold → delivered → cancelled |
| `log_interaction` | Omar | Insert into `crm.interactions` (call / email / meeting / note) |
| `client_list` | Omar, Mira | List clients, filterable by status and industry |
| `deal_pipeline` | Omar, Raha | All open deals with stage and value |
| `client_case_studies` | Mira | Won deals with outcomes — for content. Never publish client names without approval. |

---

## analytics-service

**Port:** 8105
**Transport:** streamable-HTTP
**Status:** Planned — Phase 7 (after Mira/CMO is live)
**Spec:** not yet written
**DB role:** `svc_analytics` (to be defined when spec is written)
**Migration:** `db/migrations/0006_analytics_schema.sql`

### Consumers (planned)

| Agent | Notes |
|---|---|
| Mira (`cmo`) | Owns analytics — all tools |
| Raha (`cos`) | Read-only summary views |
| Nazim (`admin`) | System-level performance views |

Tools are not specced yet. Write spec at Phase 7 start.

---

## External MCP server — GitHub

**Transport:** stdio subprocess via `npx -y @modelcontextprotocol/server-github`
**Status:** Specced (Reem / CTO, Phase 6d)
**Spec:** `docs/specs/20260701-cto-v1-design.md`

Not a nizam-os service — pulled from npm at runtime. Requires Node.js on VPS. `GITHUB_PAT` env var (read + PR review scopes only — never admin scope).

### Consumers

| Agent | Tools included |
|---|---|
| Reem (`cto`) | `list_issues`, `get_issue`, `list_pull_requests`, `get_pull_request`, `create_pull_request_review`, `list_commits`, `get_commit` |

Excluded tools: `delete_*`, `create_repository`, `manage_webhooks`, `add_collaborator`, and any other write/admin tools.

---

## External MCP server — Gmail

**Transport:** stdio subprocess via `npx -y @modelcontextprotocol/server-gmail` (or equivalent)
**Status:** Planned (Omar / COO Phase 6c, Mira / CMO Phase 6e)
**Spec:** per-agent specs

Not a nizam-os service — pulled from npm at runtime. Requires OAuth2 credentials (`GMAIL_CLIENT_ID`, `GMAIL_CLIENT_SECRET`, `GMAIL_REFRESH_TOKEN` in `nizam.env`).

### Consumers

| Agent | Tools included |
|---|---|
| Omar (`coo`) | Read email, send email, search — client communication and project updates |
| Mira (`cmo`) | Read email, send email — outreach and campaign communication |

Gmail MCP is read+send only. No delete, no label management, no settings changes. Exact tool include list defined at build time per agent spec.
