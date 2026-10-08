# Hala (CFO) — v1 design spec

**Status:** approved, pending implementation (Phase 4b)
**Prerequisite:** `finance-service` personal schema live (Assistant v1); migration `0004_business_finance_schema.sql` run
**Profile dir:** `hermes/profiles/cfo/`
**Agent name:** Hala

---

## Role

Hala is the CFO. She owns all business financial data: transactions, invoices, P&L, budgets. She does not touch personal finance — that is Ayah's domain. Physically separate DB schemas enforce this boundary at the database level, not just by convention.

Reports to Raha. Does not respond to Discord directly — user interacts with business finance through Raha or by messaging `#cfo-office` directly.

---

## Discord access

**Channel:** `#cfo-office` (Arc Systems)

```yaml
discord:
  allowed_channels: "<cfo_office_id>"
```

Direct access to `#cfo-office` for when user wants to go straight to CFO without routing through Raha.

---

## Hermes toolsets

```yaml
platform_toolsets:
  discord:
    - memory
    - skills
    - clarify
```

**Disabled:** `browser`, `code_execution`, `cronjob`, `delegation`, `file`, `image_gen`, `terminal`, `tts`, `vision`, `web`

---

## MCP servers

```yaml
mcp_servers:
  finance:
    url: http://127.0.0.1:8101/mcp
    tools:
      include:
        - record_business_transaction
        - create_invoice
        - update_invoice_status
        - business_spending_report
        - business_account_balance
        - p_and_l_report
        - invoice_status_report
      # Personal finance tools (record_transaction, spending_report, etc.) are excluded
```

No access to personal-service, knowledge-service, or crm-service.

---

## DB access

Role: `svc_finance_business`

| Schema | Access |
|---|---|
| `business.finance.*` | RW |
| `finance.personal_transactions` | None |
| `personal.*` | None |
| `audit.log` | INSERT only |

`svc_finance_business` and `svc_finance_personal` are separate PostgreSQL roles. A compromise of one does not expose the other. Do not share roles between personal and business finance.

---

## Database schema: `business.finance`

Migration: `db/migrations/0004_business_finance_schema.sql`

```sql
business.accounts       (id, name, type, currency, is_active)
business.categories     (id, name, parent_id, domain)
business.transactions   (
    id, account_id, category_id,
    amount_original, currency_original,
    amount_base, currency_base,
    fx_rate, fx_date,
    direction,          -- 'income' | 'expense'
    counterparty, description,
    transaction_date, receipt_ref,
    is_riba,
    created_at
)
business.fx_rates       (date, from_currency, to_currency, rate, source, fetched_at)
business.budgets        (id, category_id, period, amount, currency, starts_at)

-- Invoices
business.invoices       (
    id, client_id, invoice_number, status,
    issued_date, due_date, paid_date,
    subtotal, currency,
    notes, pdf_path
)
business.invoice_items  (id, invoice_id, description, quantity, unit_price, currency)
business.invoice_payments (id, invoice_id, transaction_id, amount, paid_at)
```

`client_id` references `crm.clients`. Foreign key constraint enforced after `crm-service` and `0005_crm_schema.sql` are created — until then, `client_id` is nullable.

---

## finance-service extension

`finance-service` at port 8101 already serves Ayah's personal finance tools (`svc_finance_personal`). Hala's tools run on the same service binary, connected as `svc_finance_business`.

New MCP tools to add to `finance-service` for Hala:

| Tool | What it does |
|---|---|
| `record_business_transaction` | Insert into `business.transactions`, write to `audit.log` |
| `create_invoice` | Insert into `business.invoices` + `business.invoice_items` |
| `update_invoice_status` | Update invoice status (draft → sent → paid → void), write to audit |
| `business_spending_report` | Aggregate spend by category, date range, account |
| `business_account_balance` | Current balance per account or all accounts |
| `p_and_l_report` | Income minus expenses for a given period, by category |
| `invoice_status_report` | Outstanding invoices, overdue, paid this period |

Tool implementation: see `docs/plans/20260701-cfo-v1.md` (to be written at build time).

---

## Profile files

| File | Content |
|---|---|
| `SOUL.md` | Personality: precise, formal, data-driven. Speaks in numbers. Flags anomalies. |
| `AGENTS.md` | Mandate: business finance ownership, invoice rules, riba-flagging policy, P&L format, audit requirements. |
| `config.yaml` | MCP finance server with business tool includes, compression model, security settings. |
| `user.md` | Pre-seeded: user name, business name, base currency (AED), fiscal year, riba policy. |

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

- `cfo` profile does not exist. Description for Kanban routing: "Business finance, invoicing, P&L, audit-ready records." Profile creation command is in the implementation plan.
- `finance-service` binary is shared with Ayah — new business tools must not break personal tools. Use DB role to gate access at query time, not at MCP layer.
- `svc_finance_business` role must not have any grants on `finance.personal_transactions`. Verify with `\dp finance.personal_transactions` in psql.
- `0004_business_finance_schema.sql` depends on `0003_audit_schema.sql` (audit.log must exist first).
- `client_id` FK to `crm.clients` — defer constraint creation until `0005_crm_schema.sql` is run.

---

## Done criteria

- `cfo` profile created with `--description`
- `SOUL.md` + `AGENTS.md` written
- `config.yaml` — finance MCP with `tools.include`, compression model, no extra toolsets
- `0004_business_finance_schema.sql` written and reviewed
- `svc_finance_business` role created, grants verified
- New business MCP tools added to `finance-service/server.py`
- Ayah's personal tools unaffected (regression test: Ayah can still call `record_transaction`)
- `DISCORD_ALLOWED_USERS` set in VPS `.env`
- `discord.allowed_channels` set to `#cfo-office` channel ID
- Spot check via Raha: Raha can delegate to Hala and receive a P&L summary
