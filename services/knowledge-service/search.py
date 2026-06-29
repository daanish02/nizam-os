"""Hybrid BM25 + vector search via Reciprocal Rank Fusion."""

from nizam_shared.base import ServiceBase
from embedder import embed_query


def _rrf(rank: int, k: int = 60) -> float:
    return 1.0 / (k + rank)


def _bm25(conn, query: str, limit: int) -> list[tuple[int, float]]:
    """BM25 search via ParadeDB @@@. Falls back to tsvector on error."""
    try:
        rows = conn.execute(
            """
            SELECT id, paradedb.score(id) AS score
            FROM knowledge.vault_index
            WHERE id @@@ paradedb.boolean(
                should => ARRAY[
                    paradedb.parse('title', %s),
                    paradedb.parse('content', %s)
                ]
            )
            ORDER BY score DESC
            LIMIT %s
            """,
            (query, query, limit),
        ).fetchall()
        return [(r["id"], r["score"]) for r in rows]
    except Exception:
        rows = conn.execute(
            """
            SELECT id, ts_rank(fts_vector, plainto_tsquery('english', %s)) AS score
            FROM knowledge.vault_index
            WHERE fts_vector @@ plainto_tsquery('english', %s)
            ORDER BY score DESC
            LIMIT %s
            """,
            (query, query, limit),
        ).fetchall()
        return [(r["id"], r["score"]) for r in rows]


def _vector(conn, embedding: list[float], limit: int) -> list[tuple[int, float]]:
    """Cosine-similarity search via pgvector halfvec."""
    vec = "[" + ",".join(f"{v:.8f}" for v in embedding) + "]"
    rows = conn.execute(
        """
        SELECT v.id, 1 - (e.embedding <=> %s::vector) AS score
        FROM knowledge.vault_embeddings e
        JOIN knowledge.vault_index v ON e.note_path = v.file_path
        ORDER BY e.embedding <=> %s::vector
        LIMIT %s
        """,
        (vec, vec, limit),
    ).fetchall()
    return [(r["id"], r["score"]) for r in rows]


def hybrid_search(
    svc: ServiceBase,
    query: str,
    *,
    domain: str | None = None,
    limit: int = 10,
) -> list[dict]:
    """Combine BM25 and vector results via RRF. Returns top-limit notes."""
    embedding = embed_query(query)

    with svc.db() as conn:
        bm25_hits = _bm25(conn, query, limit * 2)
        vec_hits = _vector(conn, embedding, limit * 2)

        bm25_rank = {doc_id: i + 1 for i, (doc_id, _) in enumerate(bm25_hits)}
        vec_rank = {doc_id: i + 1 for i, (doc_id, _) in enumerate(vec_hits)}
        all_ids = set(bm25_rank) | set(vec_rank)

        scored = []
        for doc_id in all_ids:
            score = 0.0
            if doc_id in bm25_rank:
                score += _rrf(bm25_rank[doc_id])
            if doc_id in vec_rank:
                score += _rrf(vec_rank[doc_id])
            scored.append((doc_id, score))
        scored.sort(key=lambda x: x[1], reverse=True)

        top_ids = [doc_id for doc_id, _ in scored[:limit]]
        if not top_ids:
            return []

        domain_filter = "AND domain = %s" if domain else ""
        params: list = [top_ids]
        if domain:
            params.append(domain)

        rows = conn.execute(
            f"""
            SELECT id, file_path, title, domain, subdomain,
                   source, tags, status, confidence, date_created
            FROM knowledge.vault_index
            WHERE id = ANY(%s) {domain_filter}
            """,
            params,
        ).fetchall()

    by_id = {r["id"]: dict(r) for r in rows}
    return [by_id[doc_id] for doc_id, _ in scored if doc_id in by_id]
