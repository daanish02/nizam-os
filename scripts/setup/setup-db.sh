#!/usr/bin/env bash
# Step 1 database setup — creates the nizam database and svc_litellm user.
# Run once: bash scripts/setup-db.sh
# Requires: LITELLM_DB_PASSWORD set in environment.
set -euo pipefail

: "${LITELLM_DB_PASSWORD:?Set LITELLM_DB_PASSWORD before running this script}"

sudo -u postgres psql <<SQL
-- Main project database (all services will use schemas within this db)
CREATE DATABASE nizam;

-- LiteLLM service user — only gets its own schema
CREATE USER svc_litellm WITH PASSWORD '${LITELLM_DB_PASSWORD}';
GRANT CONNECT ON DATABASE nizam TO svc_litellm;

\c nizam

-- LiteLLM tables live in their own schema, isolated from future service schemas
CREATE SCHEMA IF NOT EXISTS litellm AUTHORIZATION svc_litellm;
GRANT ALL ON SCHEMA litellm TO svc_litellm;
-- Pre-grant on tables/sequences Prisma will create on first LiteLLM boot
ALTER DEFAULT PRIVILEGES IN SCHEMA litellm GRANT ALL ON TABLES TO svc_litellm;
ALTER DEFAULT PRIVILEGES IN SCHEMA litellm GRANT ALL ON SEQUENCES TO svc_litellm;
SQL

echo "Database setup complete."
echo ""
echo "Add to nizam.env:"
echo "  LITELLM_DB_URL=postgresql://svc_litellm:${LITELLM_DB_PASSWORD}@localhost:5432/nizam?schema=litellm"
echo "  REDIS_URL=redis://localhost:6379/0"
