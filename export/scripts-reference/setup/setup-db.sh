#!/usr/bin/env bash
# Idempotent database setup — creates nizam database, svc_litellm role, extensions.
# Called by 001-foundation.sh with POSTGRES_SVC_LITELLM_PASS in environment.
set -euo pipefail

: "${POSTGRES_SVC_LITELLM_PASS:?Set POSTGRES_SVC_LITELLM_PASS before running this script}"

sudo -u postgres psql <<SQL
SELECT 'CREATE DATABASE nizam' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'nizam')\gexec -- \gexec: psql meta-command — executes the query result string as SQL

DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'svc_litellm') THEN
    CREATE USER svc_litellm WITH PASSWORD '${POSTGRES_SVC_LITELLM_PASS}';
  ELSE
    ALTER USER svc_litellm WITH PASSWORD '${POSTGRES_SVC_LITELLM_PASS}';
  END IF;
END
\$\$;

GRANT CONNECT ON DATABASE nizam TO svc_litellm;

\c nizam

CREATE EXTENSION IF NOT EXISTS vector;

-- litellm schema managed by Prisma migrations — kept separate from nizam's dbmate-managed public schema
CREATE SCHEMA IF NOT EXISTS litellm AUTHORIZATION svc_litellm;
GRANT ALL ON SCHEMA litellm TO svc_litellm;
-- applies to future tables created in this schema, not just existing ones
ALTER DEFAULT PRIVILEGES IN SCHEMA litellm GRANT ALL ON TABLES TO svc_litellm;
ALTER DEFAULT PRIVILEGES IN SCHEMA litellm GRANT ALL ON SEQUENCES TO svc_litellm;
SQL

echo "  database setup complete"
