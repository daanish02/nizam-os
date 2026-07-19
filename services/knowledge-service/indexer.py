"""Upsert vault notes into knowledge.vault_index."""

import hashlib
from datetime import date

import psycopg

from nizam_shared.base import ServiceBase


def content_hash(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()


def upsert_note(
    svc: ServiceBase,
    *,
    file_path: str,
    title: str,
    domain: str,
    subdomain: str,
    source: str,
    content: str,
    tags: list[str],
    status: str = "raw",
    confidence: str = "medium",
    source_url: str | None = None,
    source_author: str | None = None,
    date_created: date | None = None,
    date_modified: date | None = None,
) -> int:
    """Upsert a note into vault_index. Conflict key is file_path; all other fields update on conflict."""
    chash = content_hash(content)
    with svc.db() as conn:
        row = conn.execute(
            """
            INSERT INTO knowledge.vault_index
                (file_path, title, domain, subdomain, source, source_url,
                 source_author, tags, status, confidence, content,
                 content_hash, date_created, date_modified)
            VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
            ON CONFLICT (file_path) DO UPDATE SET
                title          = EXCLUDED.title,
                domain         = EXCLUDED.domain,
                subdomain      = EXCLUDED.subdomain,
                source         = EXCLUDED.source,
                source_url     = EXCLUDED.source_url,
                source_author  = EXCLUDED.source_author,
                tags           = EXCLUDED.tags,
                status         = EXCLUDED.status,
                confidence     = EXCLUDED.confidence,
                content        = EXCLUDED.content,
                content_hash   = EXCLUDED.content_hash,
                date_modified  = EXCLUDED.date_modified,
                updated_at     = NOW()
            RETURNING id
            """,
            (
                file_path, title, domain, subdomain, source, source_url,
                source_author, tags, status, confidence, content,
                chash, date_created, date_modified,
            ),
        ).fetchone()
    svc.logger.info(
        "note_indexed",
        extra={"file_path": file_path, "id": row["id"]},
    )
    return row["id"]
