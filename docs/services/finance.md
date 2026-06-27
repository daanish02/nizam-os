# finance-service

Part of [services overview](../services.md). Two sub-schemas: `finance.personal` and `finance.business`. Same service, scoped by caller.

## Personal tools

| Tool | Description |
|---|---|
| `add_transaction(amount, category, note, date?)` | Log income or expense |
| `budget_status(month?)` | Budgets vs actuals. Redis-cached 15 min. |
| `fund_status()` | Emergency fund, travel fund, etc. Redis-cached 15 min. |
| `zakat_status()` | Nisab check, estimated zakat due. Redis-cached 1 hour. |
| `set_budget(category, amount, period)` | Create/update budget |
| `add_to_fund(fund_name, amount)` | Contribute to a named fund |
| `spending_report(period, group_by?)` | Aggregated spend by category/period |
| `net_worth_snapshot()` | Assets minus liabilities |

## Business tools

| Tool | Description |
|---|---|
| `log_revenue(amount, client_id, description, date?)` | Record revenue |
| `log_expense(amount, category, description, date?)` | Record business expense |
| `pl_statement(month?)` | P&L for period |
| `cash_flow_forecast(weeks?)` | Rolling cashflow projection |
| `create_invoice(client_id, line_items)` | Generate invoice record |
| `mark_paid(invoice_id, date?)` | Mark invoice as paid |
| `outstanding_invoices()` | Unpaid invoices with age |
| `business_headlines()` | Revenue, costs, pipeline value. Redis-cached 30 min. |

## Schema (finance)

```
transactions(id, domain, amount, currency, category, description, date, created_at)
budgets(id, domain, category, amount, period, created_at)
funds(id, name, balance, target, created_at)
gold_holdings(id, grams, purchase_price_per_gram, date)
invoices(id, client_id, status, total, issued_at, paid_at)
invoice_items(id, invoice_id, description, qty, unit_price)
```

DB role: `svc_finance` — see [architecture](../architecture.md#per-service-db-users).
