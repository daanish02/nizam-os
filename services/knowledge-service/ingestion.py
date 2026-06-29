"""Approval-gated note creation and update pipeline."""

from datetime import date

import httpx
from bs4 import BeautifulSoup

from nizam_shared.base import ServiceBase
from vault_io import DOMAINS, note_path, read_note, render_draft, write_note
from indexer import upsert_note
from embedder import upsert_embedding

_PROFILE = "curator"


def _validate_domain(domain: str) -> None:
    if domain not in DOMAINS:
        raise ValueError(f"Invalid domain '{domain}'. Valid: {sorted(DOMAINS)}")


def add_note(
    svc: ServiceBase,
    *,
    title: str,
    domain: str,
    subdomain: str,
    source: str,
    content: str,
    tags: list[str],
    approved: bool,
    status: str = "raw",
    confidence: str = "medium",
    source_url: str | None = None,
    source_author: str | None = None,
) -> dict:
    """Two-step note creation. Call with approved=False to preview, True to write."""
    _validate_domain(domain)
    today = date.today()
    metadata = {
        "title": title,
        "domain": domain,
        "subdomain": subdomain,
        "source": source,
        "tags": tags,
        "status": status,
        "confidence": confidence,
        "date_created": str(today),
        "date_modified": str(today),
    }
    if source_url:
        metadata["source_url"] = source_url
    if source_author:
        metadata["source_author"] = source_author

    if not approved:
        svc.audit.log(
            profile=_PROFILE, action="note_draft",
            title=title, approved=False,
            details={"domain": domain, "subdomain": subdomain},
        )
        return {
            "status": "draft",
            "message": "Review the draft. Call add_note with approved=True to write.",
            "draft": render_draft(metadata, content),
        }

    path = note_path(title, domain, subdomain)
    write_note(path, metadata, content)

    note_id = upsert_note(
        svc,
        file_path=path,
        title=title, domain=domain, subdomain=subdomain,
        source=source, content=content, tags=tags,
        status=status, confidence=confidence,
        source_url=source_url, source_author=source_author,
        date_created=today, date_modified=today,
    )
    upsert_embedding(svc, note_path=path, content=content)

    svc.audit.log(
        profile=_PROFILE, action="note_create",
        file_path=path, title=title, approved=True,
        details={"id": note_id, "domain": domain},
    )
    return {"status": "created", "id": note_id, "file_path": path}


def update_note(
    svc: ServiceBase,
    *,
    file_path: str,
    content: str | None = None,
    title: str | None = None,
    tags: list[str] | None = None,
    status: str | None = None,
    approved: bool,
) -> dict:
    """Two-step note update. approved=False shows what will change."""
    metadata, body = read_note(file_path)

    if title:
        metadata["title"] = title
    if tags is not None:
        metadata["tags"] = tags
    if status:
        metadata["status"] = status
    if content:
        body = content
    metadata["date_modified"] = str(date.today())

    if not approved:
        svc.audit.log(
            profile=_PROFILE, action="note_update_draft",
            file_path=file_path, approved=False,
        )
        return {
            "status": "draft",
            "message": "Review changes. Call update_note with approved=True to save.",
            "draft": render_draft(metadata, body),
        }

    write_note(file_path, metadata, body)
    note_id = upsert_note(
        svc,
        file_path=file_path,
        title=metadata["title"],
        domain=metadata["domain"],
        subdomain=metadata["subdomain"],
        source=metadata.get("source", ""),
        content=body,
        tags=metadata.get("tags", []),
        status=metadata.get("status", "raw"),
        confidence=metadata.get("confidence", "medium"),
    )
    upsert_embedding(svc, note_path=file_path, content=body)

    svc.audit.log(
        profile=_PROFILE, action="note_update",
        file_path=file_path, title=metadata["title"], approved=True,
        details={"id": note_id},
    )
    return {"status": "updated", "id": note_id, "file_path": file_path}


def fetch_url(url: str) -> tuple[str, str]:
    """Fetch a URL and return (title, plain_text). Strips nav/footer/scripts."""
    resp = httpx.get(url, timeout=20, follow_redirects=True)
    resp.raise_for_status()
    soup = BeautifulSoup(resp.text, "html.parser")
    for tag in soup(["nav", "footer", "script", "style", "aside"]):
        tag.decompose()
    title = soup.title.string.strip() if soup.title else url
    text = " ".join(soup.get_text(" ", strip=True).split())
    return title, text
