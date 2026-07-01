# Curator v1 — design spec

**Status:** approved, pending implementation
**Date:** 2026-07-01
**Scope:** Make the curator profile (Noor) fully functional for its core mandate — ingesting YouTube, web pages, PDFs, and images into the vault.

---

## Problem

The curator profile exists and is configured, but cannot be used. Two blockers:

1. `~/nizam-vault/` does not exist on the VPS — every write fails silently at the filesystem level.
2. PDF and image ingestion are not implemented — the two most common media types beyond URLs and YouTube.

**Vault structure:**
```
~/nizam-vault/
├── personal/
│   ├── journal/          # dated journal entries
│   ├── fleeting/         # quick captures, random thoughts, unprocessed ideas
│   └── notes/            # personal notes (not in commons taxonomy)
├── common/               # flat structure — all knowledge base notes, MECE taxonomy
└── business/             # business-related notes and documents
```

Noor writes to `common/` (knowledge ingestion). Ayah writes to `personal/journal/` (journal entries) and `personal/fleeting/` (quick notes). Business content goes to `business/`.

---

## What this spec covers

| Area | Change |
|---|---|
| Vault | Create `~/nizam-vault/`, git-init, create `commons/` |
| knowledge-service | Add `ingest_pdf` tool (pymupdf) |
| knowledge-service | Add `ingest_image` tool (LiteLLM vision) |
| knowledge-service deps | Add `pymupdf` |
| knowledge-service env | Add `VISION_MODEL` to env example |
| knowledge-service transport | Switch from stdio subprocess to HTTP (streamable-http on port 8100) |
| `systemd/knowledge-service.service` | New systemd unit for knowledge-service |
| Curator config | Enable Discord attachments; switch MCP to `url:` transport |
| Curator SOUL.md | Personality and tone only (per Hermes docs) |
| Curator AGENTS.md | Mandate, vault path, MECE taxonomy, approval workflow, failure rules |
| Docs | Populate `docs/VISION.md` and `docs/ARCHITECTURE.md` (currently empty stubs) |

> **TOOLS.md dropped.** Hermes auto-discovers MCP tools via `list_tools()` at startup — a manual doc file adds prompt weight for information the agent already has at runtime.

## Out of scope (future specs)

- OCR for scanned PDFs
- Audio and podcast ingestion
- Local video processing
- Vault sync to local Obsidian (Syncthing)
- Vault walker AI

---

## Vault initialisation

One-time setup. Run once on the VPS before starting the curator gateway.

```bash
mkdir -p ~/nizam-vault/commons
git -C ~/nizam-vault init
echo "*.env\n.DS_Store" > ~/nizam-vault/.gitignore
git -C ~/nizam-vault add .gitignore
git -C ~/nizam-vault commit -m "init: vault"
```

`vault_io.py` already defaults `VAULT_ROOT` to `~/nizam-vault`. No code change needed. The `VAULT_ROOT` env var in `secrets/nizam.env.example` exists as an override if the vault moves later.

---

## `ingest_pdf` — design

### New file: `services/knowledge-service/pdf_reader.py`

```python
"""PDF text extraction using pymupdf."""

import base64
import tempfile
from pathlib import Path

import fitz  # pymupdf
import httpx

WORD_LIMIT = 15_000
TIMEOUT = 10


def extract_pdf(source: str) -> dict:
    """Extract text from a PDF given a URL or local file path.

    Returns:
        {"title": str, "text": str, "word_count": int, "truncated": bool}
        or {"error": str}
    """
    if source.startswith("http://") or source.startswith("https://"):
        try:
            resp = httpx.get(source, timeout=TIMEOUT, follow_redirects=True)
            resp.raise_for_status()
        except httpx.TimeoutException:
            return {"error": "Request timed out (10s)."}
        except httpx.HTTPStatusError as e:
            return {"error": f"HTTP {e.response.status_code} fetching PDF."}

        content_type = resp.headers.get("content-type", "")
        if "pdf" not in content_type:
            return {"error": f"URL did not return a PDF (Content-Type: {content_type})."}

        pdf_bytes = resp.content
    else:
        path = Path(source)
        if not path.exists():
            return {"error": f"File not found: {source}"}
        pdf_bytes = path.read_bytes()

    try:
        doc = fitz.open(stream=pdf_bytes, filetype="pdf")
    except Exception as e:
        return {"error": f"Could not open PDF: {e}"}

    if doc.needs_pass:
        return {"error": "PDF is encrypted — cannot extract text."}

    pages = []
    for page in doc:
        pages.append(page.get_text())

    text = "\n\n".join(pages).strip()
    if not text:
        return {"error": "No text extracted — PDF may be scanned. OCR not supported in v1."}

    words = text.split()
    truncated = len(words) > WORD_LIMIT
    if truncated:
        text = " ".join(words[:WORD_LIMIT])

    title = doc.metadata.get("title") or Path(source).stem or "Untitled PDF"

    return {
        "title": title,
        "text": text,
        "word_count": min(len(words), WORD_LIMIT),
        "truncated": truncated,
    }
```

### New MCP tool: `ingest_pdf` in `server.py`

Same 3-pass workflow as `ingest_url` and `ingest_youtube`.

```
Pass 1 — omit domain/subdomain: fetch + extract, return title + content preview
Pass 2 — supply domain, subdomain, tags, approved=False: return full draft
Pass 3 — approved=True: write and index
```

Source values: `"paper"` | `"book"` | `"article"` (caller picks based on content).

---

## `ingest_image` — design

### New file: `services/knowledge-service/vision.py`

```python
"""Image description via LiteLLM vision proxy."""

import base64
import mimetypes
import os
from pathlib import Path

import httpx

SUPPORTED_TYPES = {"image/jpeg", "image/png", "image/gif", "image/webp"}
MAX_BYTES = 20 * 1024 * 1024  # 20MB
TIMEOUT = 30
VISION_MODEL = os.environ.get("VISION_MODEL", "google/gemini-2.0-flash")
LITELLM_BASE_URL = "http://localhost:4000"


def describe_image(source: str) -> dict:
    """Fetch an image and return a description and extracted text via vision model.

    Returns:
        {"description": str, "extracted_text": str | None}
        or {"error": str}
    """
    if source.startswith("http://") or source.startswith("https://"):
        try:
            resp = httpx.get(source, timeout=TIMEOUT, follow_redirects=True)
            resp.raise_for_status()
        except httpx.TimeoutException:
            return {"error": "Request timed out (30s)."}
        except httpx.HTTPStatusError as e:
            return {"error": f"HTTP {e.response.status_code} fetching image."}

        image_bytes = resp.content
        content_type = resp.headers.get("content-type", "image/jpeg").split(";")[0].strip()
    else:
        path = Path(source)
        if not path.exists():
            return {"error": f"File not found: {source}"}
        image_bytes = path.read_bytes()
        content_type = mimetypes.guess_type(str(path))[0] or "image/jpeg"

    if len(image_bytes) > MAX_BYTES:
        return {"error": f"Image too large ({len(image_bytes) // 1024 // 1024}MB). Limit is 20MB."}

    if content_type not in SUPPORTED_TYPES:
        return {"error": f"Unsupported image type: {content_type}. Supported: jpeg, png, gif, webp."}

    b64 = base64.b64encode(image_bytes).decode()
    data_url = f"data:{content_type};base64,{b64}"

    api_key = os.environ.get("LITELLM_MASTER_KEY", "")
    try:
        resp = httpx.post(
            f"{LITELLM_BASE_URL}/chat/completions",
            headers={"Authorization": f"Bearer {api_key}"},
            json={
                "model": VISION_MODEL,
                "messages": [{
                    "role": "user",
                    "content": [
                        {
                            "type": "text",
                            "text": (
                                "Describe this image in detail. "
                                "If it contains text, extract all readable text exactly. "
                                "Structure your response as:\n"
                                "DESCRIPTION: <what the image shows>\n"
                                "EXTRACTED TEXT: <verbatim text from the image, or 'none'>"
                            ),
                        },
                        {"type": "image_url", "image_url": {"url": data_url}},
                    ],
                }],
            },
            timeout=TIMEOUT,
        )
        resp.raise_for_status()
    except httpx.HTTPStatusError as e:
        return {"error": f"Vision model error: HTTP {e.response.status_code} — {e.response.text[:200]}"}
    except Exception as e:
        return {"error": f"Vision model call failed: {e}"}

    content = resp.json()["choices"][0]["message"]["content"]

    description, extracted_text = content, None
    if "EXTRACTED TEXT:" in content:
        parts = content.split("EXTRACTED TEXT:", 1)
        description = parts[0].replace("DESCRIPTION:", "").strip()
        raw_et = parts[1].strip()
        extracted_text = None if raw_et.lower() == "none" else raw_et

    return {"description": description, "extracted_text": extracted_text}
```

### New MCP tool: `ingest_image` in `server.py`

Vault note body assembled as:

```
{description}

---

Extracted text:
{extracted_text}
```

If `extracted_text` is `None`, the separator and extracted text block are omitted. Source value: `"post"` for screenshots, `"article"` for infographics, `"paper"` for scanned figures. Same 3-pass approval workflow.

---

## Dependency change

`services/knowledge-service/pyproject.toml`:

```toml
dependencies = [
    ...
    "pymupdf>=1.24",
]
```

---

## Environment change

`secrets/nizam.env.example` — add:

```
VISION_MODEL=google/gemini-2.0-flash
```

Actual `nizam.env` needs this value set (or leave unset to use the default).

---

## knowledge-service HTTP transport

Switch from Hermes-managed stdio subprocess to a standalone HTTP service. This decouples the service lifecycle from Hermes sessions and lets multiple profiles share the same instance.

**`services/knowledge-service/server.py` — add HTTP entrypoint:**

```python
if __name__ == "__main__":
    mcp.run(transport="streamable-http", host="127.0.0.1", port=8100)
```

**`systemd/knowledge-service.service`:**

```ini
[Unit]
Description=Nizam-OS knowledge-service (MCP HTTP)
After=network.target postgresql.service

[Service]
Type=simple
User=vazir
EnvironmentFile=/home/vazir/nizam-os/secrets/nizam.env
ExecStart=/home/vazir/.local/bin/uv run \
    --directory /home/vazir/nizam-os/services/knowledge-service \
    --env-file /home/vazir/nizam-os/secrets/nizam.env \
    python server.py
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

Install: symlink to `/etc/systemd/system/`, `daemon-reload`, `enable`, `start`.

**Port allocation:** `8100` — knowledge-service.

---

## Curator config change

`hermes/profiles/curator/config.yaml` — update MCP section and Discord section:

```yaml
mcp_servers:
  knowledge:
    url: http://127.0.0.1:8100/mcp
    tools:
      prompts: false
      resources: false

discord:
  allow_any_attachment: true
  max_attachment_bytes: 33554432   # 32MB — already default, make explicit
```

Remove the old `command:`/`args:` stdio block entirely.

---

## SOUL.md — Noor profile

**What goes here:** personality, tone, communication style ONLY. Per Hermes docs: no file paths, no tool instructions, no mandates.

```markdown
You are Noor, a knowledge curator.

You are precise, methodical, and terse. You never improvise taxonomy or skip
approval steps. When something cannot be ingested, you report the exact reason
and stop — no workarounds.

You do not use emojis. You format responses for Discord (code blocks for
structured output, plain prose otherwise). You confirm each vault write
explicitly: domain, subdomain, title, tags.
```

---

## AGENTS.md — Noor profile

`hermes/profiles/curator/AGENTS.md` — technical mandate and rules. Auto-injected as project context at session start.

```markdown
# Noor — Knowledge Curator

## Vault
- Location: ~/nizam-vault/commons/
- All writes go to this directory. Never write outside it.
- Git is managed manually by the user — do not run git commands.

## Ingestion tools
- ingest_url: web pages
- ingest_youtube: YouTube (transcript)
- ingest_pdf: PDFs (URL or Discord CDN attachment)
- ingest_image: images (URL or Discord CDN attachment)

All tools follow a 3-pass approval workflow:
- Pass 1: no args beyond source → extract and preview
- Pass 2: domain, subdomain, tags, approved=False → show full draft
- Pass 3: approved=True → write to vault

Never skip passes. Never write without approved=True.

## MECE taxonomy (10 domains)
Deen, Knowledge, Finance, Health, Craft, World, People, Projects, Systems, Vault.
All notes must be classified into exactly one domain and one subdomain.

## Failure rules
- ingest_pdf encrypted → report "PDF is encrypted — cannot extract text." Stop.
- ingest_pdf scanned → report "No text extracted — PDF may be scanned. OCR not supported." Stop.
- ingest_image >20MB or unsupported format → report exact error. Stop.
- Vision model error → report HTTP status and truncated error. Stop.
- Discord attachments arrive as CDN URLs. Pass directly as source. Do not ask user to re-upload.
```

---

## Docs fix

`docs/VISION.md` and `docs/ARCHITECTURE.md` are empty stubs. These must be populated with accurate current-state content as part of this spec's implementation. Content should reflect actual live state, not aspirational state. Use `docs/old/vision.md` and `docs/old/architecture.md` as reference — they are accurate but need trimming to current reality and the doc convention format.

This is a documentation correctness fix, not a separate spec.

---

## Note format — `common/` vault notes

Every note Noor writes to `~/nizam-vault/common/` follows this structure exactly.

### Frontmatter

```yaml
---
title: "Attention Is All You Need — Paper Notes"
source: paper                # book | article | video | course | paper | podcast | post | conversation | thought
source_url: ""               # optional
source_author: ""            # optional
date_created: 2026-06-15
date_modified: 2026-06-16
areas:                       # required, multi-value, overlapping OK
  - machine-learning
  - natural-language-processing
tags:                        # required, multi-value, fine-grained
  - transformers
  - attention-mechanism
  - self-attention
status: raw                  # required: raw | processed | evergreen
confidence: high             # required: low | medium | high
related:                     # optional, Obsidian [[wikilinks]]
  - "[[transformer-architecture]]"
---
```

**Required fields:** `title`, `source`, `date_created`, `areas`, `tags`, `status`, `confidence`
**Optional fields:** `source_url`, `source_author`, `date_modified`, `related`

**Status stages:**

| Status | Meaning |
|---|---|
| `raw` | Just captured. May be messy or incomplete. Not ready to reference. |
| `processed` | Clean, tagged, complete. Ready to reference and link. |
| `evergreen` | Fundamental knowledge that stays relevant. Revisited periodically. |

All ingested notes start as `raw`. Upgrading to `processed` or `evergreen` is a manual decision.

### Body structure

```markdown
---
(frontmatter)
---

Brief summary — what this is about and why it matters. 1–3 sentences.

## Key Takeaways

- Takeaway 1
- Takeaway 2
- Takeaway 3

## Notes

Free-form. Your own words. What you learned, what stood out.
Use [[wikilinks]] inline wherever you reference related concepts:

The [[Transformer]] architecture replaced [[recurrence]] with
[[self-attention]], creating a fully connected computational graph
similar to how [[graph neural networks]] operate.

Training uses [[teacher forcing]] while inference uses [[autoregressive
decoding]], creating a [[train-test mismatch]] that [[scheduled sampling]]
tried to address.

## Questions / Open Threads

Things to explore further. Optional.
```

**Wikilinks philosophy (Karpathy-inspired):** Links go inline in the text, right where the connection happens — not in a references section at the bottom. They ARE the connections. Link to existing notes. Link to notes that don't exist yet (ghost links in Obsidian, filled later). Over time the vault becomes a graph: clusters, bridges, hubs, and orphans all visible in Obsidian's graph view.

### Noor's responsibility

Noor fills `title`, `source`, `source_url`, `source_author`, `date_created`, `areas`, `tags`, `confidence`, and the note body during ingestion. `status` starts as `raw`. `related` starts empty — wikilinks are added manually or in a future enrichment pass. `date_modified` is updated on every edit.

---

## Single ingest tool (design decision)

**Decision: one `ingest` tool, not four.**

Currently the spec describes four tools: `ingest_url`, `ingest_youtube`, `ingest_pdf`, `ingest_image`. When Hermes starts a session it loads all tool descriptions into the system prompt. Four ingestion tool descriptions = extra tokens every session.

Replace with one `ingest` tool that auto-detects source type:

```
ingest(source, approved, domain, subdomain, tags, media_type=None)
```

Auto-detection logic (in Python, transparent to the agent):
- `youtu.be` or `youtube.com` in URL → YouTube transcript
- Content-Type `application/pdf` or `.pdf` extension → PDF extraction
- Content-Type `image/*` or image extension (jpg/png/gif/webp) → vision model
- Everything else → URL/web scrape

`media_type` parameter is an optional override for ambiguous cases (`"pdf"` | `"youtube"` | `"image"` | `"web"`).

Agent sees one tool with one description. All routing happens in code.

**Impact on plan:** Curator v1 plan (`docs/plans/20260701-curator-v1.md`) needs updating — Tasks 2, 3, and 4 change from separate tool functions to a unified `ingest` function with internal routing. Plan not yet updated.

---

## Implementation order

1. Vault init (unblocks any testing)
2. `pymupdf` dep + `pdf_reader.py` + `ingest_pdf` tool
3. `vision.py` + `ingest_image` tool
4. Add HTTP entrypoint to `server.py` (port 8100)
5. Write `systemd/knowledge-service.service`; install + start
6. Update curator `config.yaml` (MCP `url:`, `allow_any_attachment`)
7. Write curator `SOUL.md` (personality only) and `AGENTS.md` (mandate + rules)
8. `docs/VISION.md` + `docs/ARCHITECTURE.md`
9. Smoke test: ingest one PDF URL, one image URL, one Discord attachment of each

---

## Grafana: knowledge analytics

Appended as a section in `grafana/personal-dashboard.json` (not a separate file — all personal tracking in one dashboard).
Built in: Curator v1 plan — Task 10 (after knowledge schema is set up and first notes exist)

**Datasource:** PostgreSQL direct. `grafana` role with `SELECT` on `knowledge.*`. Same role defined in `0001_knowledge_schema.sql`.

**Panels:**

| Panel | Type | Query target |
|---|---|---|
| Total notes in vault | stat | `COUNT(*) FROM knowledge.notes` |
| Notes added today | stat | `WHERE DATE(created_at) = CURRENT_DATE` |
| Notes added this week | stat | `WHERE created_at >= start_of_week` |
| Notes by domain | bargauge | `knowledge.notes` grouped by `domain` |
| Notes by source type | bargauge | grouped by `source` (video/paper/article/post/etc.) |
| Notes by status | bargauge | grouped by `status` (raw/processed/evergreen) |
| Vault growth — cumulative | timeseries | `COUNT(*)` by day, last 90 days |
| Average confidence | stat | weighted avg (low=1, medium=2, high=3) |

**Rebuild:** Same PostgreSQL datasource as personal dashboard. After importing `grafana/personal-dashboard.json`, knowledge panels populate once `knowledge.notes` table has rows.

---

## What "done" looks like

- `~/nizam-vault/` exists and is a git repo with `personal/`, `common/`, `business/` subdirs
- Noor can ingest a YouTube URL, web URL, PDF URL, and image URL end-to-end with approval gating
- Noor can process a Discord file attachment (PDF or image) via CDN URL
- Notes appear as `.md` files in `~/nizam-vault/common/` with correct frontmatter
- Personal dashboard knowledge panels show note counts and domain breakdown
- `docs/VISION.md` and `docs/ARCHITECTURE.md` are accurate and non-empty