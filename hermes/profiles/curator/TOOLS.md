# Noor — Tools reference

All vault operations go through the `knowledge` MCP toolset. Read this before any vault call.

---

## Search and read

### `search_vault`

Hybrid BM25 + vector search across all indexed commons notes.

```
search_vault(query, domain=None, limit=10)
```

Use this first — before creating anything. Report results to the user before proceeding.

### `get_note`

Read the full content and frontmatter of a specific note.

```
get_note(file_path)
```

`file_path` comes from `search_vault` or `list_notes` results.

### `list_notes`

List indexed notes with optional filters.

```
list_notes(domain=None, tags=None, status=None, limit=50)
```

---

## Write (approval-gated)

### `add_note`

Create a new note. **Always call with `approved=False` first.**

```
add_note(
    title, domain, subdomain, source, content, tags,
    approved=False,                  # ← always start here
    status="raw",
    confidence="medium",
    source_url=None,
    source_author=None,
)
```

`source` values: `article` | `video` | `book` | `paper` | `course` | `podcast` | `post` | `thought`

`status` values: `raw` (just captured) | `processed` (clean, tagged) | `evergreen` (fundamental, revisited)

`confidence` values: `low` | `medium` | `high`

### `update_note`

Update an existing note. **Always call with `approved=False` first.**

```
update_note(
    file_path,
    approved=False,
    content=None,
    title=None,
    tags=None,
    status=None,
)
```

---

## Ingestion

### `ingest_url`

Fetch a URL, extract its text, create a vault note.

```
ingest_url(url)                                          # pass 1: read content
ingest_url(url, domain, subdomain, tags, approved=False) # pass 2: draft
ingest_url(url, domain, subdomain, tags, approved=True)  # pass 3: write
```

### `ingest_youtube`

Fetch a YouTube transcript (no audio download), create a vault note.

```
ingest_youtube(url)                                          # pass 1: read transcript
ingest_youtube(url, domain, subdomain, tags, approved=False) # pass 2: draft
ingest_youtube(url, domain, subdomain, tags, approved=True)  # pass 3: write
```

---

## Workflow pattern

```
User: "Save this video/article: <url>"

1. search_vault(query=<topic or url>)          ← check duplicates first
2. Report any existing notes
3. ingest_youtube(url=...)                     ← pass 1: fetch, get content preview
4. Read preview → infer domain, subdomain, tags from content
5. ingest_youtube(url=..., domain=..., subdomain=..., tags=[...], approved=False)
6. Present draft to user, ask for confirmation
7. ingest_youtube(url=..., domain=..., ..., approved=True)
8. Confirm: "Saved as <file_path>"
```

Never ask the user to supply domain/subdomain/tags. Infer from content.

---

## Audit

Every approved write is logged to `knowledge.vault_audit`:

| Column | Value |
|---|---|
| `profile` | `curator` |
| `action` | `note_create` / `note_update` |
| `file_path` | path written |
| `approved` | `true` |
| `details` | note id, domain |

Unapproved drafts are also logged (`approved=false`) so there is always a trail.
