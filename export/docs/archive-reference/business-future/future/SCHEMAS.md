# Nizam-OS — Business Schemas (Future)

**Last updated:** 2026-07-02

Business schemas (Phases 6b+). Not yet run. Personal schemas: `docs/SCHEMAS.md`.

Single PostgreSQL instance. Database: `nizam`. Database owner: `vazir` (PostgreSQL superuser). Service roles are granted minimum permissions by `vazir`.

---

## Migration index

| Migration | Schema | Status | Spec |
|---|---|---|---|
| `0004_finance_business_schema.sql` | `finance_business` | **Planned** | `docs/specs/20260701-cfo-v1-design.md` |
| `0005_crm_schema.sql` | `crm` | **Planned** | `docs/specs/20260701-coo-v1-design.md` |
| `0006_analytics_schema.sql` | `analytics` | **Planned** | not yet specced |

Migration order matters: `0003` before `0004` (audit.log must exist). `0004` before `0005` (`crm.clients` FK from invoices). `0005` before Hala profile is enabled.

---

## DB roles

Full role list including personal service roles: `docs/SCHEMAS.md`.

| Role | Service | Access |
|---|---|---|
| `svc_finance_business` | `finance-service` | RW on `finance_business.*`, INSERT on `audit.log`. No access to `finance_personal.*`. |
| `svc_crm` | `crm-service` | RW on `crm.*`, INSERT on `audit.log`. No direct access to `finance_business.*`. |
| `svc_analytics` | `analytics-service` | TBD (spec not written) |

---

## `finance_business` schema

**Migration:** `db/migrations/0004_finance_business_schema.sql`
**Depends on:** `0003_audit_schema.sql`
**Status:** Planned
**Service:** `finance-service` (`svc_finance_business`)

Renamed from `business.finance` to `finance_business`. (PostgreSQL schema names cannot contain dots.)

```sql
finance_business.accounts (
    id          BIGSERIAL   PRIMARY KEY,
    name        TEXT        NOT NULL,
    type        TEXT        NOT NULL,
    currency    TEXT        NOT NULL,
    is_active   BOOLEAN     NOT NULL DEFAULT true
)

finance_business.categories (
    id          BIGSERIAL   PRIMARY KEY,
    name        TEXT        NOT NULL,
    parent_id   BIGINT      → finance_business.categories(id) NULLABLE,
    domain      TEXT        NOT NULL
)

finance_business.transactions (
    id                BIGSERIAL   PRIMARY KEY,
    account_id        BIGINT      → finance_business.accounts(id),
    category_id       BIGINT      → finance_business.categories(id),
    amount_original   NUMERIC     NOT NULL,
    currency_original TEXT        NOT NULL,
    amount_base       NUMERIC     NOT NULL,
    currency_base     TEXT        NOT NULL,
    fx_rate           NUMERIC     NOT NULL,
    fx_date           DATE        NOT NULL,
    direction         TEXT        NOT NULL,   -- income|expense
    counterparty      TEXT,
    description       TEXT,
    transaction_date  DATE        NOT NULL,
    receipt_ref       TEXT,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
)

finance_business.transfers (
    id                BIGSERIAL   PRIMARY KEY,
    from_account_id   BIGINT      → finance_business.accounts(id),
    to_account_id     BIGINT      → finance_business.accounts(id),
    amount_original   NUMERIC     NOT NULL,
    currency_original TEXT        NOT NULL,
    amount_received   NUMERIC     NOT NULL,
    currency_received TEXT        NOT NULL,
    fx_rate           NUMERIC,
    transfer_date     DATE        NOT NULL,
    fee               NUMERIC,
    fee_currency      TEXT,
    description       TEXT,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
)

finance_business.fx_rates (
    date          DATE    NOT NULL,
    from_currency TEXT    NOT NULL,
    to_currency   TEXT    NOT NULL,
    rate          NUMERIC NOT NULL,
    source        TEXT,
    fetched_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (date, from_currency, to_currency)
)

finance_business.budgets (
    id          BIGSERIAL   PRIMARY KEY,
    category_id BIGINT      → finance_business.categories(id),
    period      TEXT        NOT NULL,
    amount      NUMERIC     NOT NULL,
    currency    TEXT        NOT NULL,
    starts_at   DATE        NOT NULL
)

finance_business.invoices (
    id             BIGSERIAL   PRIMARY KEY,
    client_id      BIGINT      → crm.clients(id) NULLABLE until 0005 runs,
    invoice_number TEXT        NOT NULL UNIQUE,
    status         TEXT        NOT NULL DEFAULT 'draft',  -- draft|sent|paid|void
    issued_date    DATE        NOT NULL,
    due_date       DATE        NOT NULL,
    paid_date      DATE,
    subtotal       NUMERIC     NOT NULL,
    currency       TEXT        NOT NULL,
    notes          TEXT,
    pdf_path       TEXT
)

finance_business.invoice_items (
    id           BIGSERIAL   PRIMARY KEY,
    invoice_id   BIGINT      → finance_business.invoices(id),
    description  TEXT        NOT NULL,
    quantity     NUMERIC     NOT NULL,
    unit_price   NUMERIC     NOT NULL,
    currency     TEXT        NOT NULL
)

finance_business.invoice_payments (
    id             BIGSERIAL   PRIMARY KEY,
    invoice_id     BIGINT      → finance_business.invoices(id),
    transaction_id BIGINT      → finance_business.transactions(id),
    amount         NUMERIC     NOT NULL,
    paid_at        TIMESTAMPTZ NOT NULL
)
```

`client_id` FK deferred: `crm.clients` doesn't exist until `0005` runs. Make nullable first, add constraint after `0005`.

---

## `crm` schema

**Migration:** `db/migrations/0005_crm_schema.sql`
**Depends on:** `0004_finance_business_schema.sql`
**Status:** Planned
**Service:** `crm-service` (`svc_crm`)

```sql
crm.clients (
    id         BIGSERIAL   PRIMARY KEY,
    name       TEXT        NOT NULL,
    industry   TEXT,
    status     TEXT        NOT NULL DEFAULT 'prospect',  -- prospect|active|inactive
    country    TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
)

crm.contacts (
    id              BIGSERIAL   PRIMARY KEY,
    client_id       BIGINT      → crm.clients(id),
    name            TEXT        NOT NULL,
    role            TEXT,
    email           TEXT,
    phone           TEXT,
    primary_contact BOOLEAN     NOT NULL DEFAULT false
)

crm.deals (
    id             BIGSERIAL   PRIMARY KEY,
    client_id      BIGINT      → crm.clients(id),
    title          TEXT        NOT NULL,
    stage          TEXT        NOT NULL DEFAULT 'prospect',
    value          NUMERIC,
    currency       TEXT,
    expected_close DATE,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
)

crm.projects (
    id         BIGSERIAL   PRIMARY KEY,
    client_id  BIGINT      → crm.clients(id),
    deal_id    BIGINT      → crm.deals(id) NULLABLE,
    title      TEXT        NOT NULL,
    status     TEXT        NOT NULL DEFAULT 'active',
    start_date DATE,
    end_date   DATE
)

crm.interactions (
    id          BIGSERIAL   PRIMARY KEY,
    client_id   BIGINT      → crm.clients(id),
    contact_id  BIGINT      → crm.contacts(id) NULLABLE,
    type        TEXT        NOT NULL,   -- call|email|meeting|note
    notes       TEXT,
    occurred_at TIMESTAMPTZ NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
)
```

`deal.stage` values: `prospect → proposal → negotiation → won → lost`
`project.status` values: `active → on_hold → delivered → cancelled`

---

## `analytics` schema

**Migration:** `db/migrations/0006_analytics_schema.sql`
**Status:** Planned — spec not yet written. Build when Mira (Phase 6e) starts.

Stores post and campaign performance metrics. Populated by `analytics-service` pulling from social platform APIs or manual input.
