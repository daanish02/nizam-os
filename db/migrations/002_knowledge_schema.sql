-- migrate:up
CREATE EXTENSION IF NOT EXISTS vector;

CREATE SCHEMA IF NOT EXISTS knowledge;

CREATE TABLE IF NOT EXISTS knowledge.vault_index (
    id            BIGSERIAL    PRIMARY KEY,
    file_path     TEXT         NOT NULL UNIQUE,
    title         TEXT         NOT NULL,
    domain        TEXT         NOT NULL,
    source        TEXT         NOT NULL,
    source_url    TEXT,
    source_author TEXT,
    tags          TEXT[]       NOT NULL DEFAULT '{}',
    status        TEXT         NOT NULL DEFAULT 'raw',
    confidence    TEXT         NOT NULL DEFAULT 'medium',
    content       TEXT         NOT NULL,
    content_hash  TEXT         NOT NULL,
    date_created  DATE,
    date_modified DATE,
    fts_vector    tsvector     GENERATED ALWAYS AS (
                      to_tsvector('english', coalesce(title, '') || ' ' || coalesce(content, ''))
                  ) STORED,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS vault_index_domain_idx  ON knowledge.vault_index (domain);
CREATE INDEX IF NOT EXISTS vault_index_status_idx  ON knowledge.vault_index (status);
CREATE INDEX IF NOT EXISTS vault_index_fts_idx     ON knowledge.vault_index USING GIN (fts_vector);

CREATE TABLE IF NOT EXISTS knowledge.vault_embeddings (
    id            BIGSERIAL    PRIMARY KEY,
    note_path     TEXT         NOT NULL UNIQUE,
    content_hash  TEXT         NOT NULL,
    embedding     vector(768)  NOT NULL,
    model         TEXT         NOT NULL,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS vault_embeddings_hnsw_idx
    ON knowledge.vault_embeddings
    USING hnsw (embedding vector_cosine_ops);

-- Role and grants
DO $$ BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'svc_knowledge') THEN
        CREATE ROLE svc_knowledge LOGIN PASSWORD NULL;
    END IF;
END $$;

GRANT USAGE ON SCHEMA knowledge TO svc_knowledge;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA knowledge TO svc_knowledge;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA knowledge TO svc_knowledge;
GRANT USAGE ON SCHEMA audit TO svc_knowledge;
GRANT INSERT ON audit.log TO svc_knowledge;

-- migrate:down
REVOKE ALL ON ALL TABLES IN SCHEMA knowledge FROM svc_knowledge;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA knowledge FROM svc_knowledge;
REVOKE INSERT ON audit.log FROM svc_knowledge;
DROP ROLE IF EXISTS svc_knowledge;
DROP TABLE IF EXISTS knowledge.vault_embeddings;
DROP TABLE IF EXISTS knowledge.vault_index;
DROP SCHEMA IF EXISTS knowledge;
