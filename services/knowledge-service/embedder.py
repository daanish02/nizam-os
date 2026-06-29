"""Compute and store embeddings via LiteLLM proxy, skipping unchanged content."""

import hashlib
import os

import httpx

from nizam_shared.base import ServiceBase

_MODEL = "google/gemini-embedding-2"
_MAX_CHARS = 8000  # truncate before sending


def _embed(text: str, api_key: str) -> list[float]:
    """Call LiteLLM proxy /embeddings. Returns a 768-dim float list."""
    resp = httpx.post(
        "http://localhost:4000/embeddings",
        headers={"Authorization": f"Bearer {api_key}"},
        json={"model": _MODEL, "input": text[:_MAX_CHARS]},
        timeout=30,
    )
    resp.raise_for_status()
    return resp.json()["data"][0]["embedding"]


def _vec_str(embedding: list[float]) -> str:
    return "[" + ",".join(f"{v:.8f}" for v in embedding) + "]"


def upsert_embedding(svc: ServiceBase, *, note_path: str, content: str) -> bool:
    """Embed note content if the content_hash changed. Returns True if embedded.

    Uses sha256 of content to skip re-embedding unchanged notes.
    """
    new_hash = hashlib.sha256(content.encode()).hexdigest()
    api_key = os.environ["LITELLM_MASTER_KEY"]

    with svc.db() as conn:
        existing = conn.execute(
            "SELECT content_hash FROM knowledge.vault_embeddings WHERE note_path = %s",
            (note_path,),
        ).fetchone()

        if existing and existing["content_hash"] == new_hash:
            svc.logger.info("embedding_skip", extra={"note_path": note_path})
            return False

        embedding = _embed(content, api_key)

        conn.execute(
            """
            INSERT INTO knowledge.vault_embeddings
                (note_path, content_hash, embedding, model)
            VALUES (%s, %s, %s::vector, %s)
            ON CONFLICT (note_path) DO UPDATE SET
                content_hash = EXCLUDED.content_hash,
                embedding    = EXCLUDED.embedding,
                model        = EXCLUDED.model,
                updated_at   = NOW()
            """,
            (note_path, new_hash, _vec_str(embedding), _MODEL),
        )

    svc.logger.info("embedding_upserted", extra={"note_path": note_path})
    return True


def embed_query(text: str) -> list[float]:
    """Embed a search query string. No caching."""
    api_key = os.environ["LITELLM_MASTER_KEY"]
    return _embed(text, api_key)
