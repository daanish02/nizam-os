-- migrate:up

CREATE SCHEMA IF NOT EXISTS knowledge;

CREATE TABLE IF NOT EXISTS knowledge.vault_index (
    id            BIGSERIAL    PRIMARY KEY,
    file_path     TEXT         NOT NULL UNIQUE,
    title         TEXT         NOT NULL,
    domain        TEXT         NOT NULL,
    subdomain     TEXT         NOT NULL,
    source        TEXT         NOT NULL,
    source_url    TEXT,
    source_author TEXT,
    tags          TEXT[]       NOT NULL DEFAULT '{}',
    status        TEXT         NOT NULL DEFAULT 'raw',
    confidence    TEXT         NOT NULL DEFAULT 'medium',
    content       TEXT         NOT NULL,
    content_hash  TEXT         NOT NULL,
    fts_vector    TSVECTOR     GENERATED ALWAYS AS (
                      to_tsvector('english',
                          coalesce(title, '') || ' ' || coalesce(content, ''))
                  ) STORED,
    date_created  DATE,
    date_modified DATE,
    indexed_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS vault_fts    ON knowledge.vault_index USING GIN(fts_vector);
CREATE INDEX IF NOT EXISTS vault_domain ON knowledge.vault_index(domain, subdomain);
CREATE INDEX IF NOT EXISTS vault_tags   ON knowledge.vault_index USING GIN(tags);
CREATE INDEX IF NOT EXISTS vault_status ON knowledge.vault_index(status);

CREATE INDEX IF NOT EXISTS vault_bm25 ON knowledge.vault_index
    USING bm25 (id, title, content)
    WITH (key_field='id');

CREATE TABLE IF NOT EXISTS knowledge.vault_embeddings (
    id           BIGSERIAL    PRIMARY KEY,
    note_path    TEXT         NOT NULL UNIQUE
                              REFERENCES knowledge.vault_index(file_path) ON DELETE CASCADE,
    content_hash TEXT         NOT NULL,
    embedding    vector(768),
    model        TEXT         NOT NULL DEFAULT 'google/gemini-embedding-2',
    updated_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS vault_embed_hnsw ON knowledge.vault_embeddings
    USING hnsw (embedding vector_cosine_ops);

CREATE TABLE IF NOT EXISTS knowledge.vault_audit (
    id         BIGSERIAL    PRIMARY KEY,
    profile    TEXT         NOT NULL,
    action     TEXT         NOT NULL,
    file_path  TEXT,
    title      TEXT,
    approved   BOOLEAN      NOT NULL,
    details    JSONB,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS vault_audit_time    ON knowledge.vault_audit(created_at DESC);
CREATE INDEX IF NOT EXISTS vault_audit_profile ON knowledge.vault_audit(profile, created_at DESC);

GRANT USAGE ON SCHEMA knowledge                               TO svc_knowledge;
GRANT SELECT, INSERT, UPDATE ON knowledge.vault_index         TO svc_knowledge;
GRANT SELECT, INSERT, UPDATE ON knowledge.vault_embeddings    TO svc_knowledge;
GRANT SELECT, INSERT         ON knowledge.vault_audit         TO svc_knowledge;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA knowledge      TO svc_knowledge;

-- migrate:down

DROP TABLE IF EXISTS knowledge.vault_audit;
DROP TABLE IF EXISTS knowledge.vault_embeddings;
DROP TABLE IF EXISTS knowledge.vault_index;
DROP SCHEMA IF EXISTS knowledge;
