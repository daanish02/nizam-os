"""knowledge-service — MCP stdio server for the nizam-vault commons.

Tools:
  search_vault       hybrid BM25 + vector search
  get_note           read a note by file path
  list_notes         list notes by domain / tags / status
  add_note           approval-gated create
  update_note        approval-gated update
  ingest_url         fetch a URL → approval-gated create
  ingest_youtube     fetch YouTube transcript → approval-gated create
"""

from fastmcp import FastMCP

from nizam_shared.base import ServiceBase
from vault_io import COMMONS_DIR, DOMAINS, read_note
from indexer import upsert_note
from embedder import upsert_embedding
from search import hybrid_search
from ingestion import add_note as _add_note, fetch_url, update_note as _update_note
from transcript import fetch_transcript

svc = ServiceBase("knowledge-service")
mcp = FastMCP("knowledge-service")


# ---------------------------------------------------------------------------
# Search / read
# ---------------------------------------------------------------------------

@mcp.tool()
def search_vault(query: str, domain: str | None = None, limit: int = 10) -> dict:
    """Hybrid BM25 + vector search across vault commons.

    Args:
        query: Natural-language search string.
        domain: Optional MECE domain filter (e.g. "technology").
        limit: Max results to return (default 10).
    """
    results = hybrid_search(svc, query, domain=domain, limit=limit)
    return {"query": query, "count": len(results), "results": results}


@mcp.tool()
def get_note(file_path: str) -> dict:
    """Read the full content of a vault note.

    Args:
        file_path: Absolute path to the note (from search results or list_notes).
    """
    try:
        metadata, body = read_note(file_path)
        return {"file_path": file_path, "metadata": metadata, "content": body}
    except FileNotFoundError:
        return {"error": f"Note not found: {file_path}"}


@mcp.tool()
def list_notes(
    domain: str | None = None,
    tags: list[str] | None = None,
    status: str | None = None,
    limit: int = 50,
) -> dict:
    """List indexed vault notes with optional filters.

    Args:
        domain: Filter by MECE domain.
        tags: Return only notes that have ALL listed tags.
        status: Filter by status ('raw', 'processed', 'evergreen').
        limit: Max notes to return.
    """
    conditions = ["TRUE"]
    params: list = []

    if domain:
        conditions.append("domain = %s")
        params.append(domain)
    if status:
        conditions.append("status = %s")
        params.append(status)
    if tags:
        conditions.append("tags @> %s")
        params.append(tags)

    params.append(limit)
    where = " AND ".join(conditions)

    with svc.db() as conn:
        rows = conn.execute(
            f"""
            SELECT id, file_path, title, domain, subdomain,
                   source, tags, status, confidence, date_created
            FROM knowledge.vault_index
            WHERE {where}
            ORDER BY date_modified DESC NULLS LAST
            LIMIT %s
            """,
            params,
        ).fetchall()

    return {"count": len(rows), "notes": [dict(r) for r in rows]}


# ---------------------------------------------------------------------------
# Write (approval-gated)
# ---------------------------------------------------------------------------

@mcp.tool()
def add_note(
    title: str,
    domain: str,
    subdomain: str,
    source: str,
    content: str,
    tags: list[str],
    approved: bool = False,
    status: str = "raw",
    confidence: str = "medium",
    source_url: str | None = None,
    source_author: str | None = None,
) -> dict:
    """Create a new note in commons. ALWAYS call with approved=False first.

    Step 1: approved=False → returns a draft for the user to review.
    Step 2: approved=True  → writes the note and indexes it.

    Args:
        domain: Must be one of the 10 MECE domains.
        source: 'article' | 'video' | 'book' | 'paper' | 'course' | 'podcast' | 'post' | 'thought'.
        approved: False to preview, True to write.
    """
    return _add_note(
        svc,
        title=title, domain=domain, subdomain=subdomain,
        source=source, content=content, tags=tags,
        approved=approved, status=status, confidence=confidence,
        source_url=source_url, source_author=source_author,
    )


@mcp.tool()
def update_note(
    file_path: str,
    approved: bool = False,
    content: str | None = None,
    title: str | None = None,
    tags: list[str] | None = None,
    status: str | None = None,
) -> dict:
    """Update an existing vault note. ALWAYS call with approved=False first.

    Step 1: approved=False → returns a preview of the changed note.
    Step 2: approved=True  → writes the update and re-indexes.
    """
    return _update_note(
        svc,
        file_path=file_path, content=content,
        title=title, tags=tags, status=status,
        approved=approved,
    )


# ---------------------------------------------------------------------------
# Ingestion
# ---------------------------------------------------------------------------

@mcp.tool()
def ingest_url(
    url: str,
    approved: bool = False,
    domain: str | None = None,
    subdomain: str | None = None,
    tags: list[str] | None = None,
    title: str | None = None,
    confidence: str = "medium",
) -> dict:
    """Fetch a URL and create a vault note from its content.

    Two-pass workflow:
      Pass 1 — omit domain/subdomain: fetches page, returns title + content preview
               so you can read and classify it yourself.
      Pass 2 — supply domain, subdomain, tags, approved=False: returns full draft.
      Pass 3 — approved=True: writes and indexes.

    Args:
        url: The URL to fetch.
        domain: MECE domain. Omit on first call to read content first.
        subdomain: Domain subdivision.
        tags: Free-form tags.
        title: Override the page title (optional).
    """
    try:
        page_title, text = fetch_url(url)
    except Exception as exc:
        return {"error": str(exc)}

    if not domain:
        return {
            "status": "preview",
            "title": page_title,
            "content_preview": text[:2000],
            "word_count": len(text.split()),
            "instruction": "Read the content above. Choose domain, subdomain, tags. Then call ingest_url again with those fields.",
        }

    return _add_note(
        svc,
        title=title or page_title,
        domain=domain, subdomain=subdomain or "general",
        source="article", content=text,
        tags=tags or [], approved=approved,
        confidence=confidence, source_url=url,
    )


@mcp.tool()
def ingest_youtube(
    url: str,
    approved: bool = False,
    domain: str | None = None,
    subdomain: str | None = None,
    tags: list[str] | None = None,
    title: str | None = None,
    confidence: str = "medium",
) -> dict:
    """Fetch a YouTube transcript and create a vault note.

    Two-pass workflow:
      Pass 1 — omit domain/subdomain: fetches transcript, returns preview
               so you can read and classify the content yourself.
      Pass 2 — supply domain, subdomain, tags, approved=False: returns full draft.
      Pass 3 — approved=True: writes and indexes.

    Args:
        url: YouTube URL or video ID.
        domain: MECE domain. Omit on first call to read content first.
    """
    result = fetch_transcript(url)
    if "error" in result:
        return result

    note_title = title or result.get("title") or f"YouTube: {result['video_id']}"
    content = result["full_text"]
    # Downgrade confidence when only metadata (no full transcript) available
    effective_confidence = "low" if result.get("source") == "youtube-api-v3-metadata" else confidence

    if not domain:
        preview: dict = {
            "status": "preview",
            "video_id": result["video_id"],
            "title": note_title,
            "transcript_source": result.get("source"),
            "content_preview": content[:2000],
            "word_count": len(content.split()),
            "instruction": "Read the content above. Choose domain, subdomain, tags. Then call ingest_youtube again with those fields.",
        }
        if result.get("warning"):
            preview["warning"] = result["warning"]
        return preview

    return _add_note(
        svc,
        title=note_title,
        domain=domain, subdomain=subdomain or "general",
        source="video", content=content,
        tags=tags or [], approved=approved,
        confidence=effective_confidence, source_url=url,
    )


if __name__ == "__main__":
    mcp.run()
