# Nizam-OS — Database Schemas

**Last updated:** 2026-07-01

All schemas in one place. For implementation detail, FK constraints, and role grants see the migration files in `db/migrations/`. For design decisions see the linked specs.

Single PostgreSQL instance. Database: `nizam`.

---

## Migration index

| Migration | Schema | Status | Spec |
|---|---|---|---|
| `0001_knowledge_schema.sql` | `knowledge` | **Needs redesign** | `docs/specs/20260701-curator-v1-design.md` |
| `0002_personal_schema.sql` | `personal`, `finance` (personal) | **Specced** | `docs/specs/20260701-assistant-v1-design.md` |
| `0003_audit_schema.sql` | `audit` | **Specced** | `docs/specs/20260701-assistant-v1-design.md` |
| `0004_business_finance_schema.sql` | `business.finance` | **Planned** | `docs/specs/20260701-cfo-v1-design.md` |
| `0005_crm_schema.sql` | `crm` | **Planned** | `docs/specs/20260701-coo-v1-design.md` |
| `0006_analytics_schema.sql` | `analytics` | **Planned** | not yet specced |

Migration order matters: `0003` before `0004` (audit.log must exist). `0004` before `0005` (`crm.clients` FK from invoices). `0005` before Hala profile is enabled.

---

## DB roles

| Role | Service | Access |
|---|---|---|
| `svc_litellm` | LiteLLM proxy | Owns `litellm` schema (Prisma tables) |
| `svc_knowledge` | `knowledge-service` | RW on `knowledge.*`, INSERT on `knowledge.vault_audit` |
| `svc_finance_personal` | `finance-service` | RW on `finance.*` (personal), RO on `personal.*`, INSERT on `audit.log` |
| `svc_personal` | `personal-service` | RW on `personal.*`, INSERT on `audit.log` |
| `svc_finance_business` | `finance-service` | RW on `business.finance.*`, INSERT on `audit.log`. No access to `finance.*` personal. |
| `svc_crm` | `crm-service` | RW on `crm.*`, INSERT on `audit.log`. No direct access to `business.finance.*`. |
| `svc_analytics` | `analytics-service` | TBD (spec not written) |
| `grafana` | Grafana | SELECT-only on `knowledge.*`, `personal.*`, `finance.*`, `business.finance.*`, `crm.*`, `audit.log` |

`svc_finance_personal` and `svc_finance_business` are separate roles. A compromise of one does not expose the other.

---

## `knowledge` schema

**Migration:** `db/migrations/0001_knowledge_schema.sql`
**Status:** Needs redesign (current schema does not match Curator v1 note format)
**Service:** `knowledge-service` (`svc_knowledge`)

```sql
knowledge.vault_index (
    id            BIGSERIAL     PRIMARY KEY,
    file_path     TEXT          NOT NULL UNIQUE,
    title         TEXT          NOT NULL,
    domain        TEXT          NOT NULL,
    subdomain     TEXT          NOT NULL,
    source        TEXT          NOT NULL,     -- article|video|book|paper|course|podcast|post|thought
    source_url    TEXT,
    source_author TEXT,
    tags          TEXT[]        NOT NULL DEFAULT '{}',
    status        TEXT          NOT NULL DEFAULT 'raw',     -- raw|processed|evergreen
    confidence    TEXT          NOT NULL DEFAULT 'medium',  -- low|medium|high
    content       TEXT          NOT NULL,
    content_hash  TEXT          NOT NULL,
    fts_vector    TSVECTOR      GENERATED (to_tsvector of title + content),
    date_created  DATE,
    date_modified DATE,
    indexed_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW()
)

knowledge.vault_embeddings (
    id           BIGSERIAL     PRIMARY KEY,
    note_path    TEXT          NOT NULL UNIQUE → knowledge.vault_index(file_path) CASCADE,
    content_hash TEXT          NOT NULL,
    embedding    vector(768),
    model        TEXT          NOT NULL DEFAULT 'google/gemini-embedding-2',
    updated_at   TIMESTAMPTZ   NOT NULL DEFAULT NOW()
)

knowledge.vault_audit (
    id         BIGSERIAL     PRIMARY KEY,
    profile    TEXT          NOT NULL,
    action     TEXT          NOT NULL,
    file_path  TEXT,
    title      TEXT,
    approved   BOOLEAN       NOT NULL,
    details    JSONB,
    created_at TIMESTAMPTZ   NOT NULL DEFAULT NOW()
)
```

**Indexes:** GIN on `fts_vector`, GIN on `tags`, btree on `(domain, subdomain)`, btree on `status`, BM25 on `(id, title, content)` via ParadeDB, HNSW on `embedding` (cosine ops).

---

## `personal` schema

**Migration:** `db/migrations/0002_personal_schema.sql`
**Status:** Specced
**Service:** `personal-service` (`svc_personal`)

```sql
personal.habits (
    id          BIGSERIAL   PRIMARY KEY,
    name        TEXT        NOT NULL,
    description TEXT,
    frequency   TEXT        NOT NULL,   -- daily|weekly|etc
    active      BOOLEAN     NOT NULL DEFAULT true,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
)

personal.habit_logs (
    id          BIGSERIAL   PRIMARY KEY,
    habit_id    BIGINT      → personal.habits(id),
    logged_date DATE        NOT NULL,
    note        TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
)

personal.goals (
    id          BIGSERIAL   PRIMARY KEY,
    title       TEXT        NOT NULL,
    description TEXT,
    target_date DATE,
    status      TEXT        NOT NULL DEFAULT 'active',  -- active|completed|paused|abandoned
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
)

personal.milestones (
    id           BIGSERIAL   PRIMARY KEY,
    goal_id      BIGINT      → personal.goals(id),
    title        TEXT        NOT NULL,
    due_date     DATE,
    completed_at TIMESTAMPTZ
)

personal.tasks (
    id          BIGSERIAL   PRIMARY KEY,
    title       TEXT        NOT NULL,
    description TEXT,
    due_date    DATE,
    priority    TEXT,                   -- low|medium|high
    status      TEXT        NOT NULL DEFAULT 'open',   -- open|done
    goal_id     BIGINT      → personal.goals(id) NULLABLE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
)

personal.journal (
    id          BIGSERIAL   PRIMARY KEY,
    entry_date  DATE        NOT NULL,
    prompt      TEXT,
    content     TEXT        NOT NULL,
    tags        TEXT[]      NOT NULL DEFAULT '{}',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
)
```

---

## `finance` schema (personal)

**Migration:** `db/migrations/0002_personal_schema.sql` (same migration as `personal`)
**Status:** Specced
**Service:** `finance-service` (`svc_finance_personal`)

```sql
finance.accounts (
    id          BIGSERIAL   PRIMARY KEY,
    name        TEXT        NOT NULL,
    type        TEXT        NOT NULL,   -- cash|bank|savings
    currency    TEXT        NOT NULL,
    is_active   BOOLEAN     NOT NULL DEFAULT true
)

finance.categories (
    id          BIGSERIAL   PRIMARY KEY,
    name        TEXT        NOT NULL,
    parent_id   BIGINT      → finance.categories(id) NULLABLE,   -- null = L1
    domain      TEXT        NOT NULL
)

finance.transactions (
    id                BIGSERIAL   PRIMARY KEY,
    account_id        BIGINT      → finance.accounts(id),
    category_id       BIGINT      → finance.categories(id),
    amount_original   NUMERIC     NOT NULL,
    currency_original TEXT        NOT NULL,
    amount_base       NUMERIC     NOT NULL,   -- USD
    currency_base     TEXT        NOT NULL DEFAULT 'USD',
    fx_rate           NUMERIC     NOT NULL,
    fx_date           DATE        NOT NULL,
    direction         TEXT        NOT NULL,   -- in|out
    counterparty      TEXT,
    description       TEXT,
    transaction_date  DATE        NOT NULL,
    receipt_ref       TEXT,
    is_riba           BOOLEAN     NOT NULL DEFAULT false,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
)

finance.fx_rates (
    date          DATE    NOT NULL,
    from_currency TEXT    NOT NULL,
    to_currency   TEXT    NOT NULL,
    rate          NUMERIC NOT NULL,
    source        TEXT,
    fetched_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (date, from_currency, to_currency)
)

finance.budgets (
    id          BIGSERIAL   PRIMARY KEY,
    category_id BIGINT      → finance.categories(id),
    period      TEXT        NOT NULL,   -- YYYY-MM
    amount      NUMERIC     NOT NULL,
    currency    TEXT        NOT NULL,
    starts_at   DATE        NOT NULL
)

finance.zakat_hawl (
    id                  BIGSERIAL   PRIMARY KEY,
    start_date          DATE        NOT NULL,
    end_date            DATE        NOT NULL,
    nisab_gold_grams    NUMERIC     NOT NULL,
    gold_price_usd      NUMERIC     NOT NULL,
    nisab_usd           NUMERIC     NOT NULL,
    zakatable_base_usd  NUMERIC     NOT NULL,
    obligation_usd      NUMERIC     NOT NULL,
    status              TEXT        NOT NULL,   -- open|calculated|paid
    calculated_at       TIMESTAMPTZ
)

finance.zakat_assets (
    id          BIGSERIAL   PRIMARY KEY,
    hawl_id     BIGINT      → finance.zakat_hawl(id),
    asset_type  TEXT        NOT NULL,
    amount_usd  NUMERIC     NOT NULL,
    description TEXT
)

finance.riba_log (
    id                BIGSERIAL   PRIMARY KEY,
    transaction_id    BIGINT      → finance.transactions(id),
    amount_original   NUMERIC     NOT NULL,
    currency_original TEXT        NOT NULL,
    amount_usd        NUMERIC     NOT NULL,
    riba_type         TEXT        NOT NULL,
    description       TEXT,
    logged_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
)
```

Riba entries never appear in P&L or net worth calculations. Separate ledger, separate reporting.

---

## `audit` schema

**Migration:** `db/migrations/0003_audit_schema.sql`
**Status:** Specced
**Writer:** every service that mutates data (`INSERT` only — no `UPDATE` or `DELETE` granted)

```sql
audit.log (
    id          BIGSERIAL   PRIMARY KEY,
    schema_name TEXT        NOT NULL,
    table_name  TEXT        NOT NULL,
    operation   TEXT        NOT NULL,   -- INSERT|UPDATE|DELETE
    actor       TEXT        NOT NULL,   -- Hermes profile name
    row_id      BIGINT,
    before_state JSONB,
    after_state  JSONB,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
)
```

No `UPDATE` or `DELETE` granted to any service role. Append-only by grant, not trigger.

---

## `business.finance` schema

**Migration:** `db/migrations/0004_business_finance_schema.sql`
**Depends on:** `0003_audit_schema.sql`
**Status:** Planned
**Service:** `finance-service` (`svc_finance_business`)

```sql
business.accounts (
    id          BIGSERIAL   PRIMARY KEY,
    name        TEXT        NOT NULL,
    type        TEXT        NOT NULL,
    currency    TEXT        NOT NULL,
    is_active   BOOLEAN     NOT NULL DEFAULT true
)

business.categories (
    id          BIGSERIAL   PRIMARY KEY,
    name        TEXT        NOT NULL,
    parent_id   BIGINT      → business.categories(id) NULLABLE,
    domain      TEXT        NOT NULL
)

business.transactions (
    id                BIGSERIAL   PRIMARY KEY,
    account_id        BIGINT      → business.accounts(id),
    category_id       BIGINT      → business.categories(id),
    amount_original   NUMERIC     NOT NULL,
    currency_original TEXT        NOT NULL,
    amount_base       NUMERIC     NOT NULL,
    currency_base     TEXT        NOT NULL DEFAULT 'USD',
    fx_rate           NUMERIC     NOT NULL,
    fx_date           DATE        NOT NULL,
    direction         TEXT        NOT NULL,   -- income|expense
    counterparty      TEXT,
    description       TEXT,
    transaction_date  DATE        NOT NULL,
    receipt_ref       TEXT,
    is_riba           BOOLEAN     NOT NULL DEFAULT false,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
)

business.fx_rates (
    date          DATE    NOT NULL,
    from_currency TEXT    NOT NULL,
    to_currency   TEXT    NOT NULL,
    rate          NUMERIC NOT NULL,
    source        TEXT,
    fetched_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (date, from_currency, to_currency)
)

business.budgets (
    id          BIGSERIAL   PRIMARY KEY,
    category_id BIGINT      → business.categories(id),
    period      TEXT        NOT NULL,
    amount      NUMERIC     NOT NULL,
    currency    TEXT        NOT NULL,
    starts_at   DATE        NOT NULL
)

business.invoices (
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

business.invoice_items (
    id           BIGSERIAL   PRIMARY KEY,
    invoice_id   BIGINT      → business.invoices(id),
    description  TEXT        NOT NULL,
    quantity     NUMERIC     NOT NULL,
    unit_price   NUMERIC     NOT NULL,
    currency     TEXT        NOT NULL
)

business.invoice_payments (
    id             BIGSERIAL   PRIMARY KEY,
    invoice_id     BIGINT      → business.invoices(id),
    transaction_id BIGINT      → business.transactions(id),
    amount         NUMERIC     NOT NULL,
    paid_at        TIMESTAMPTZ NOT NULL
)
```

`client_id` FK deferred: `crm.clients` doesn't exist until `0005` runs. Make nullable first, add constraint after `0005`.

---

## `crm` schema

**Migration:** `db/migrations/0005_crm_schema.sql`
**Depends on:** `0004_business_finance_schema.sql`
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
    id         BIGSERIAL   PRIMARY KEY,
    client_id  BIGINT      → crm.clients(id),
    contact_id BIGINT      → crm.contacts(id) NULLABLE,
    type       TEXT        NOT NULL,   -- call|email|meeting|note
    notes      TEXT,
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
