-- migrate:up
CREATE SCHEMA IF NOT EXISTS audit;

CREATE TABLE IF NOT EXISTS audit.log (
    id           BIGSERIAL PRIMARY KEY,
    schema_name  TEXT        NOT NULL,
    table_name   TEXT        NOT NULL,
    operation    TEXT        NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
    actor        TEXT        NOT NULL,  -- application-supplied caller identifier; not auto-populated
    row_id       BIGINT,               -- nullable: not all audit events map to a single table row
    before_state JSONB,
    after_state  JSONB,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Prevent accidental updates or deletes at the schema level.
REVOKE UPDATE, DELETE ON audit.log FROM PUBLIC;

-- migrate:down
DROP TABLE IF EXISTS audit.log;
DROP SCHEMA IF EXISTS audit;
