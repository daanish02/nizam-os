---
title: "Spec 001 — Knowledge"
status: LOCKED
version: 1.0.0
date: 2026-09-26
scope: personal, cycle 1
---

# Spec: Knowledge

> **File:** `docs/specs/001-knowledge.md`
> **Scope:** CP.03 — capture of external sources into the vault, classification,
> durable storage, and retrieval. Owns the `knowledge` schema and the vault.
> **Builds on:**
>
> - `docs/SRS.md` §5 CP.03 — FR.03.1.1 through FR.03.4.2
> - `docs/ARCHITECTURE.md` — the `nizam-mcp` daemon, `/knowledge/mcp`, vault authority, index rebuildability
> - `docs/SCHEMAS.md` — `knowledge` entities and invariants
> - `export/BUGS-AND-GOTCHAS.md` #1 — the transaction-abort bug this spec's search design must not repeat

This document adds implementation detail only: execution order, validation
rules with their reasons, error taxonomy, field semantics, and invariants.

---

## Open Questions

- [x] **Q-K1 — `domain` versus `areas`. RESOLVED 2026-09-26: `areas`, multi-valued, from a controlled vocabulary.** This spec is written against `areas` throughout. There is no `domain` column in the new schema at all — this is a from-scratch rebuild, not a migration.
- [x] **Q-K2 — behaviour when embedding is unavailable. RESOLVED 2026-09-26: ingestion completes without an embedding.** The note is saved and lexically searchable immediately; `embedding_status='pending'` until a background job backfills it (SRS F-01, §4.2). See Invariant K-7.
- [x] **Q-K3 — fetch limits. RESOLVED 2026-09-26: `MAX_FETCH_BYTES = 10MB`,
      `FETCH_TIMEOUT_S = 15`, `MAX_REDIRECTS = 5`.** Confirmed with the owner as
      reasonable defaults for article/page ingestion; large PDFs would exceed
      the byte cap but PDF ingestion is separately deferred (Q-K4) so this
      doesn't lose anything in cycle 1.
- [x] **Q-K4 — document ingestion. RESOLVED 2026-09-26, approach decided, build
      deferred.** FR.03.1.1 names "a web link, a video link, or a document".
      Web and video are specified here; document ingestion is not built in
      cycle 1, but the approach for when it is built (cycle 2) is now fixed:
      **PDF** — local text extraction (`pypdf` or `pdfplumber`, no LLM call
      needed, cheap and works offline from LiteLLM). **Images** — vision-model
      OCR/description via the existing LiteLLM proxy (reuses the same
      inference path every other domain already uses, no new infra). Both
      follow the same MAX_FETCH_BYTES/FETCH_TIMEOUT_S limits as `ingest_url`
      (Q-K3) and the same approve-before-write flow (FR.03.4.1) as every other
      capture path. Not implemented until cycle 2 actually needs it — this
      resolves the *design* question, not the build priority.

---

## Shared Types

```
NoteMetadata                      the frontmatter block of a vault note
  title:          string          1-200 chars, non-empty after trim
  areas:          string[]        1-3 entries, each from AreaVocabulary  [Q-K1]
  source:         SourceType      how the note entered the vault
  source_url:     string?         origin URL, present when source is web|youtube
  source_author:  string?         author or channel, when discoverable
  tags:           string[]        free-form, 0-20 entries, lowercase-kebab
  status:         NoteStatus      lifecycle position
  confidence:     Confidence      how much the owner should trust the content
  date_created:   date            the CONTENT's publication date, not the capture date
  date_modified:  date            when the note was last written

SourceType    enum(web, youtube, manual, research, screening)
              — web:       fetched from a URL
              — youtube:   transcript of a video
              — manual:    written directly by the owner
              — research:  synthesised output from a research capability
                           (cycle 2 — no producer exists in cycle 1)
              — screening: investment screening reasoning
                           (cycle 2 — no producer exists in cycle 1)
              — both values are reserved now so cycle 2 needs no schema change;
                cycle 1 tools accept only web | youtube | manual

NoteStatus    enum(raw, processed, evergreen)
              — raw:       captured, not yet reviewed by the owner
              — processed: read and refined at least once
              — evergreen: durable reference the owner returns to
              — legal transitions: raw->processed, processed->evergreen,
                evergreen->processed. raw->evergreen is NOT legal: a note
                cannot become a durable reference without being read once.

Confidence    enum(low, medium, high)
              — the reliability of the SOURCE, not of the extraction

AreaVocabulary  controlled, closed set  [Q-K1]
                Mind & Behavior · Mathematics & Logic · Physical Sciences ·
                Life Sciences · Earth & Space · Technology & Engineering ·
                Intelligence & Computation · Economics & Finance ·
                Society & Culture · Creative Arts
                — extending it is a schema change, deliberately: an
                  open vocabulary drifts into tags and stops partitioning

ExtractedSource                   the result of pulling content from outside
  title:          string          extracted or derived from the identifier
  text:           string          plain text, markup stripped
  author:         string?
  published:      date?
  retrieved_at:   timestamp       when the fetch happened
  method:         string          which extraction path succeeded  (FR.03.1.3)

NoteDraft                         what the owner approves; never persisted
  metadata:       NoteMetadata
  content:        string
  preview:        string          rendered frontmatter + first 500 chars
```

---

## MCP Tools

Seven tools. Every write is two-pass: draft, then approve *(FR.03.4.1)*.

**Applies to every tool below.**

- **Reads** execute without approval *(FR.06.1.1)*.
- **Writes** follow the two-pass shape and enforcement mechanism in
  `004-agent-runtime.md` *(FR.06.2.1)*:
  - The first call (`approved=false`) validates and returns the draft plus a
    signed `draft_token`. It stores nothing.
  - The second call (`approved=true`) must carry that `draft_token` and the
    exact drafted payload. The Hermes `nizam-approval` plugin holds it for the
    owner's Discord `/approve`, then `nizam-mcp` verifies the token before
    writing.
  - So every write tool below implicitly takes an extra input,
    `draft_token: string` (required when `approved=true`). It also inherits the
    errors `DRAFT_MISMATCH`, `DRAFT_EXPIRED` and `ALREADY_APPLIED`.
- **Ingest tools are read-class — they never write.** `ingest_url` and
  `ingest_youtube` only retrieve and extract, and return an `ExtractedSource`.
  The calling agent then classifies the content (FR.03.2.1) and calls
  `add_note`. `add_note` is the single create path, and its approved call
  writes exactly the content that was drafted. Nothing is re-fetched at
  approval time. **Write-class tools in this spec: `add_note` and
  `update_note`, only.**
- **Every write records an audit row**, with the calling agent as actor and the
  `approval_id` *(FR.06.3.1)*.
- **Every `file_path` argument is containment-checked** before use — see
  Invariant K-1.
- **Vault path convention:** `<VAULT_ROOT>/<primary-area-slug>--<title-slug>.md`,
  flat in the vault root. Example: `physical-sciences--entropy-explained.md`.
  This is the format proven in the prior system. Slugs are lowercase-kebab
  ASCII, with anything else stripped. The primary area is `areas[0]`.

### `search_vault`

**Description (shown to the model):** Find notes in the vault by meaning and by
wording combined. Use when the owner asks about something he may have captured
before, or when you need prior context on a subject.

**When NOT to call:** Do not call to read a note whose path you already have —
use `get_note`. Do not call to enumerate notes by attribute with no search
intent — use `list_notes`.

**Inputs:**

```
query:   string    required   — natural-language description of what is sought
areas:   string[]  optional   — restrict to these areas; each must be in AreaVocabulary  [Q-K1]
status:  string    optional   — restrict to one NoteStatus
limit:   integer   optional  default=10  — 1..50
```

**Logic (execution order):**

1. Validate `query` non-empty after trim → else `INVALID_QUERY`.
2. Validate `limit` in 1..50 → else `INVALID_LIMIT`. Validate each `areas` entry
   against AreaVocabulary → else `UNKNOWN_AREA` naming the invalid value.
3. Embed the query. **On embedding failure, do not fail the search** — set
   `degraded=true` and continue with lexical retrieval only *(FR.03.3.3)*.
4. Run lexical retrieval for `limit * 2` candidates, using Postgres's built-in
   `tsvector`/`ts_rank` (not the ParadeDB `@@@` extension the prior
   implementation used — that extension's failure mode caused a real,
   confirmed bug: a caught query exception led to a fallback query on the same
   poisoned transaction, see `export/BUGS-AND-GOTCHAS.md` #1). If a future
   revision reintroduces ParadeDB or any other fallback-on-error retrieval
   path, it MUST roll back or open a fresh connection before the fallback
   query, and MUST have a test that forces the primary path to fail.
5. If step 3 succeeded, run vector retrieval (pgvector cosine similarity) for
   `limit * 2` candidates.
6. Fuse by Reciprocal Rank Fusion. **Rank-based fusion, not weighted score sum**
   — BM25 scores and cosine similarities are incommensurable scales and
   normalising them introduces an arbitrary constant that silently reweights
   results.
7. Apply `areas` and `status` filters to the fused set, then truncate to `limit`.
8. Return, with `degraded` set.

**Output:**

```
query:     string     — echoed
count:     integer    — results returned
degraded:  boolean    — true when semantic retrieval was unavailable;
                        the model MUST tell the owner when true  (FR.03.3.3)
results:   NoteSummary[]
             file_path, title, areas, source, tags, status,
             confidence, date_created, score
```

**Error cases:**

| Condition | Error returned | Notes |
| :--- | :--- | :--- |
| `query` empty | `INVALID_QUERY`: "Query must not be empty." | Model should ask the owner what to search for |
| `limit` out of range | `INVALID_LIMIT`: "limit must be between 1 and 50." | Model retries with a valid limit |
| Area not in vocabulary | `UNKNOWN_AREA`: "Unknown area '<v>'. Valid: <list>." | Model retries with a listed value |
| Datastore unreachable | `SEARCH_UNAVAILABLE`: "Vault search is unavailable." | **Do not retry.** Report to the owner |

**Idempotent:** yes.

---

### `get_note`

**Description:** Read the full content of one vault note by its path.

**When NOT to call:** Do not call speculatively — call only with a path returned
by `search_vault` or `list_notes`.

**Inputs:**

```
file_path:  string  required  — path from a prior search or list result
```

**Logic:**

1. Resolve `file_path` and assert containment within the vault root
   → else `PATH_REJECTED`. **This is a security control, not a convenience
   check** *(T-16, C-15)*. The path originates in model output and is untrusted.
2. Read and parse the note.
3. Return metadata and body.

**Output:**

```
file_path:  string
metadata:   NoteMetadata
content:    string
```

**Error cases:**

| Condition | Error returned | Notes |
| :--- | :--- | :--- |
| Path escapes the vault root | `PATH_REJECTED`: "Path is outside the vault." | **Never disclose the resolved path.** Do not retry |
| No file at path | `NOTE_NOT_FOUND`: "No note at that path." | Index may be stale; suggest re-searching |
| File unparseable | `NOTE_CORRUPT`: "Note could not be parsed." | Report to the owner. Do not attempt repair |

**Idempotent:** yes.

---

### `list_notes`

**Description:** Enumerate indexed notes filtered by area, tag or status. Use
when the owner wants to see what exists rather than search for meaning.

**When NOT to call:** Do not call when the owner's request has search intent —
use `search_vault`.

**Inputs:**

```
areas:   string[]  optional  — notes matching ANY listed area  [Q-K1]
tags:    string[]  optional  — notes carrying ALL listed tags
status:  string    optional  — one NoteStatus
limit:   integer   optional  default=50  — 1..200
```

**Note the asymmetry:** `areas` is ANY, `tags` is ALL. Areas partition the
vault, so asking for two means "either subject". Tags accumulate, so asking for
two means "narrow to notes carrying both". This is a deliberate difference, not
an inconsistency.

**Logic:**

1. Validate `limit` in 1..200 → else `INVALID_LIMIT`. Validate areas against
   the vocabulary → else `UNKNOWN_AREA`. Validate `status` → else
   `UNKNOWN_STATUS`.
2. Query the index with every filter **bound as a parameter**. No filter is
   composed into the statement text *(C-09, T-13)*.
3. Order by `date_modified` descending, nulls last. Truncate to `limit`.

**Output:**

```
count:  integer
notes:  NoteSummary[]
```

**Error cases:** `INVALID_LIMIT`, `UNKNOWN_AREA`, `UNKNOWN_STATUS`,
`SEARCH_UNAVAILABLE` — as above.

**Idempotent:** yes.

---

### `add_note`

**Description:** Create a vault note. Call first with `approved=false` to
produce a draft for the owner, then with `approved=true` once he confirms.

**When NOT to call:** Do not call with `approved=true` on the first call, ever —
the owner has not seen the draft. Do not call to modify an existing note — use
`update_note`.

**Inputs:**

```
title:          string    required  — 1..200 chars
areas:          string[]  required  — 1..3, each in AreaVocabulary  [Q-K1]
source:         string    required  — a SourceType value
content:        string    required  — the note body, non-empty
tags:           string[]  optional  default=[]  — 0..20, lowercase-kebab
status:         string    optional  default=raw
confidence:     string    optional  default=medium
source_url:     string    optional  — required when source is web|youtube
source_author:  string    optional
approved:       boolean   optional  default=false  — false drafts, true writes
```

**The model supplies the classification.** `title`, `areas` and `tags` are the
model's proposals, never asked of the owner *(FR.03.2.1)*. Asking him to
categorise reintroduces the filing work this capability exists to remove.

**Logic (execution order):**

1. Validate `title` non-empty, ≤200 chars → `INVALID_TITLE`.
2. Validate `areas` non-empty, ≤3, every entry in the vocabulary →
   `UNKNOWN_AREA`. **An unrecognised area is refused, never coerced to a nearest
   match** — a silently reclassified note is unfindable where the owner expects it.
3. Validate `source` is a SourceType → `UNKNOWN_SOURCE_TYPE`. If `web` or
   `youtube` and `source_url` absent → `SOURCE_URL_REQUIRED`: provenance is not
   optional for externally-derived content.
4. Validate `content` non-empty → `EMPTY_CONTENT`.
5. Validate `status` and `confidence` → `UNKNOWN_STATUS`, `UNKNOWN_CONFIDENCE`.
   Reject `status=evergreen` on creation → `ILLEGAL_STATUS_TRANSITION`.
6. Derive the destination path from title and primary area. Assert containment
   → `PATH_REJECTED` *(T-16)*.
7. If a note already exists at that path → `NOTE_EXISTS`, returning the existing
   path. **Do not overwrite** — `add_note` creates; overwriting is `update_note`.
8. **If `approved` is false:** render the draft, issue the signed
   `draft_token` (spec 004), and return both. **Write nothing — touch neither
   the vault nor the index** *(FR.03.4.1)*. Stop here.
8a. **If `approved` is true:** verify the `draft_token` against this exact
    payload (`DRAFT_MISMATCH` / `DRAFT_EXPIRED`). Then, inside the transaction
    opened in step 10, run the replay check (`ALREADY_APPLIED`).
9. Write the vault file. **The file is written before the index** — the file is
   authoritative, and an index row pointing at a file that does not exist is
   worse than a file with no index row, which is merely unsearchable *(NFR.07)*.
10. In **one DB transaction**, do the following:
    - upsert the index row
    - store the embedding if available; otherwise set
      `embedding_status='pending'` (K-7, Q-K2)
    - write the audit row with the calling agent as actor and the
      `approval_id` *(FR.06.3.1)*
11. If step 10 fails: it rolls back. Delete the file written in step 9, as a
    compensating action (spec 004 A-4), and return `INDEX_WRITE_FAILED`. See
    "Two-pass ingestion" step 5 for the case where the delete also fails.
12. Return the created path and id, plus `embedded: boolean`.

**Output — draft (`approved=false`):**

```
status:   "draft"
message:  string      — instructs the model to seek approval
draft:    string      — rendered frontmatter + first 500 chars of body
```

**Output — created (`approved=true`):**

```
status:     "created"
id:         integer
file_path:  string
embedded:   boolean   — false means semantically invisible until backfilled
```

**Error cases:**

| Condition | Error returned | Notes |
| :--- | :--- | :--- |
| Title empty or too long | `INVALID_TITLE` | Model shortens and retries |
| Area unknown | `UNKNOWN_AREA`: "...Valid: <list>." | Model re-picks from the list |
| More than 3 areas | `TOO_MANY_AREAS` | Model narrows to the most relevant |
| Source type unknown | `UNKNOWN_SOURCE_TYPE` | — |
| Web/video without URL | `SOURCE_URL_REQUIRED` | Model supplies the origin |
| Content empty | `EMPTY_CONTENT` | Do not create a placeholder note |
| `evergreen` on create | `ILLEGAL_STATUS_TRANSITION` | Model uses `raw` |
| Path already occupied | `NOTE_EXISTS`: "...at <path>." | Model offers `update_note` |
| Path escapes vault | `PATH_REJECTED` | Do not retry |
| Vault write fails | `VAULT_WRITE_FAILED` | Nothing was written. Report |
| Index write fails after file write | `INDEX_WRITE_FAILED` | **File exists, index does not.** Report as failure; recoverable by reindex *(NFR.08)* |

**Idempotent:** no. A second `approved=true` call with the same title and area
returns `NOTE_EXISTS` rather than duplicating.

---

### `update_note`

**Description:** Modify an existing vault note. Two-pass like `add_note`.

**When NOT to call:** Do not call to create — use `add_note`. Do not call to
change areas as a reclassification without telling the owner what moved.

**Inputs:**

```
file_path:  string    required
title:      string    optional  — omitted leaves it unchanged
content:    string    optional
tags:       string[]  optional  — replaces wholesale; not merged
status:     string    optional
areas:      string[]  optional  [Q-K1]
approved:   boolean   optional  default=false
```

**`tags` replaces rather than merges.** A merge-only interface makes tag removal
impossible; the model must send the full intended set.

**Logic:**

1. Assert path containment → `PATH_REJECTED` *(T-16)*.
2. Read the existing note → `NOTE_NOT_FOUND`.
3. Apply supplied fields over existing metadata. Absent fields are unchanged.
4. Validate every changed field as in `add_note`.
5. If `status` changes, validate the transition against NoteStatus →
   `ILLEGAL_STATUS_TRANSITION`.
6. Set `date_modified` to today. **`date_created` is never modified** — it is
   the content's publication date, not a record timestamp.
7. **If `approved` is false:** return the rendered draft showing the result,
   plus a signed `draft_token`. The token binds the full resulting note
   *and* the content hash of the note as it was read in step 2. Write
   nothing. Stop.
8. **If `approved` is true:**
   1. Verify the `draft_token` (`DRAFT_MISMATCH` / `DRAFT_EXPIRED`).
   2. Re-read the file. If its content hash differs from the one bound in the
      token, return `DRAFT_MISMATCH` — the note changed since the draft
      (spec 004 rule 7).
   3. Keep the prior file bytes in memory, then overwrite the file.
9. In **one DB transaction**, do the following:
   - run the replay check
   - upsert the index row
   - re-embed **only if the content changed** (compare content hashes —
     re-embedding unchanged content is a wasted paid call). If that fails, set
     `embedding_status='pending'`.
   - write the audit row with `operation=UPDATE`, before and after state, and
     `approval_id`
10. If step 9 fails: it rolls back. **Restore the prior file bytes** as a
    compensating action, and return `INDEX_WRITE_FAILED`.
11. Return.

**Output:** as `add_note`, with `status: "updated"` and `embedded` reflecting
whether re-embedding occurred.

**Error cases:** `PATH_REJECTED`, `NOTE_NOT_FOUND`, the validation errors from
`add_note`, `ILLEGAL_STATUS_TRANSITION`, `VAULT_WRITE_FAILED`,
`INDEX_WRITE_FAILED`.

**Idempotent:** yes, when the same field values are supplied — the result
converges. `date_modified` advances.

---

### `ingest_url`

**Class:** read. No approval — it persists nothing.

**Description:** Fetch a web page and extract its readable content. You then
classify it and call `add_note` to draft the note for the owner's approval.

**When NOT to call:** Do not call for a video link — use `ingest_youtube`. Do
not call to re-fetch a URL already in the vault without saying so.

**Inputs:**

```
url:       string   required  — absolute http or https URL
```

**Logic (execution order):**

1. **Validate and filter the URL before any network call** *(T-24, C-16)*:
   - scheme must be `http` or `https` → else `URL_REJECTED`;
   - host must resolve to a public address. Reject loopback, link-local,
     private and unique-local ranges → `URL_REJECTED`;
   - **re-apply this check after every redirect**, up to `MAX_REDIRECTS`
     `[Q-K3]` → `TOO_MANY_REDIRECTS`.

   **Why this is not optional:** the machine runs a model proxy on loopback
   holding the provider credential. An unfiltered fetch of a caller-supplied
   URL reaches it. The URL originates in model output, which may itself have
   come from previously ingested content.
2. Fetch with `FETCH_TIMEOUT_S` timeout and `MAX_FETCH_BYTES` cap `[Q-K3]`.
   Exceeding either → `FETCH_TOO_LARGE` / `FETCH_TIMEOUT`. **Stream and abort at
   the cap; do not buffer the whole body first** — the cap exists to bound
   memory on a co-resident machine *(T-25)*.
3. Reject non-HTML content types → `UNSUPPORTED_CONTENT_TYPE`.
4. Strip navigation, footer, script, style and aside elements. Extract title and
   text.
5. If extracted text is under 200 characters → `EXTRACTION_EMPTY`. A page that
   yields nothing usually means a client-rendered page, not an empty page —
   report rather than storing a stub.
6. Return an ExtractedSource for the model to classify, then proceed through
   `add_note` with `source=web` and `source_url` set to the **final** URL after
   redirects, not the one supplied.

**Output:**

```
extracted:  ExtractedSource   — title, text, author?, published?, retrieved_at,
                                method, char_count
final_url:  string            — after redirects; differs from input when
                                redirected. Pass it as add_note's source_url.
```

**Error cases:**

| Condition | Error returned | Notes |
| :--- | :--- | :--- |
| Non-http(s) scheme | `URL_REJECTED`: "Only http and https are supported." | Do not retry |
| Private or loopback target | `URL_REJECTED`: "That address is not permitted." | **Do not retry, do not report the resolved address** |
| Redirect limit exceeded | `TOO_MANY_REDIRECTS` | Do not retry |
| Timeout | `FETCH_TIMEOUT` | Retry at most once |
| Size cap exceeded | `FETCH_TOO_LARGE` | Do not retry |
| Non-HTML | `UNSUPPORTED_CONTENT_TYPE` | Tell the owner what it was |
| Nothing extractable | `EXTRACTION_EMPTY` | Suggest the owner supply content manually |
| Origin returned an error status | `FETCH_FAILED`: "Origin returned <status>." | Retry once on 5xx only |

**Idempotent:** yes — it persists nothing. The subsequent write is governed by `add_note`.

---

### `ingest_youtube`

**Class:** read. No approval — it persists nothing.

**Description:** Retrieve a video's transcript. You then classify it and call
`add_note` to draft the note for the owner's approval.

**When NOT to call:** Do not call for a non-video URL — use `ingest_url`.

**Inputs:**

```
url:       string   required  — video URL or bare video identifier
```

**Logic:**

1. Extract the video identifier and **validate it against the expected form**
   before use. It is passed to an external tool; an unvalidated identifier is an
   argument-injection vector *(T-26, C-18)* → `INVALID_VIDEO_ID`.
2. Attempt transcript retrieval through the available paths in order. **Try the
   next path on failure before reporting failure** *(FR.03.1.3)*. Record which
   path succeeded in `method`.
3. External tools are invoked with an **argument vector, never through a shell**
   *(C-18)*.
4. If every path fails → `TRANSCRIPT_UNAVAILABLE`, naming what was tried.
5. Return an ExtractedSource, then proceed through `add_note` with
   `source=youtube`.

**Output:** as `ingest_url`, with `method` naming the successful path and
`extracted.author` carrying the channel.

**Error cases:**

| Condition | Error returned | Notes |
| :--- | :--- | :--- |
| Identifier unparseable | `INVALID_VIDEO_ID` | Model asks for a full URL |
| No transcript from any path | `TRANSCRIPT_UNAVAILABLE`: "Tried: <paths>." | Tell the owner; do not fabricate |
| Every path timed out | `FETCH_TIMEOUT` | Retry at most once |

**Idempotent:** the retrieval is.

---

## Schema

### `VaultNote` → `knowledge.vault_index`

```
id:             bigserial     PK, generated server-side, immutable
file_path:      text          not-null, unique
                              — the vault file this row indexes; the join key
                                to embeddings, and the reason unique matters:
                                two rows for one file means one is stale
title:          text          not-null
areas:          text[]        not-null, 1..3 entries          [Q-K1]
                              — controlled vocabulary, enforced at write time
                                by the service, not by a DB constraint, because
                                the vocabulary is a service-level decision
source:         text          not-null  — SourceType
source_url:     text          nullable  — not-null in practice when source is web|youtube
source_author:  text          nullable
tags:           text[]        not-null, default '{}'  — free-form
status:         text          not-null, default 'raw'
                              — legal: raw->processed, processed->evergreen,
                                evergreen->processed
confidence:     text          not-null, default 'medium'
content:        text          not-null
                              — a copy of the file body, held for lexical search
                                only. NOT authoritative; the file is  (NFR.07)
content_hash:   text          not-null
                              — sha256 of content. Detects staleness against the
                                file and gates re-embedding
date_created:   date          nullable
                              — the CONTENT's publication date. Distinct from
                                created_at, which is when this row was written
date_modified:  date          nullable
fts_vector:     tsvector      generated, stored — derived from title and content
created_at:     timestamptz   not-null, default now(), immutable
updated_at:     timestamptz   not-null, updated on every write
```

### `NoteEmbedding` → `knowledge.vault_embeddings`

```
id:            bigserial     PK
note_path:     text          not-null, unique, FK-by-convention -> vault_index.file_path
                             — joined on path rather than id because the file is
                               the identity; a reindex may reassign ids
content_hash:  text          not-null
                             — the hash the vector was computed from. When it
                               differs from the index row's hash, the vector is
                               stale and the note is semantically wrong
embedding:     vector        not-null — dimension must match `model`
model:         text          not-null
                             — stored PER ROW, not assumed globally. Without
                               this, changing the embedding model silently mixes
                               incomparable vectors in one index
created_at:    timestamptz   not-null, default now()
updated_at:    timestamptz   not-null
```

**Relationships:**

- `VaultNote` to `NoteEmbedding`: one-to-zero-or-one, joined on path. A note may
  exist without an embedding (not yet computed, or embedding unavailable). An
  embedding without a note is orphaned and must be pruned on reindex.

**Indexes:**

| Name | Fields | Type | Access pattern |
| :--- | :--- | :--- | :--- |
| `vault_index_path_key` | `file_path` | unique btree | Upsert conflict target; the join from embeddings |
| `vault_index_areas_idx` | `areas` | GIN | `areas && ARRAY[...]` in `list_notes` and search filtering [Q-K1] |
| `vault_index_tags_idx` | `tags` | GIN | `tags @> ARRAY[...]` — the ALL-tags filter in `list_notes` |
| `vault_index_status_idx` | `status` | btree | Status filter; low cardinality but the filter is common |
| `vault_index_fts_idx` | `fts_vector` | GIN | Lexical fallback when BM25 is unavailable |
| `vault_index_modified_idx` | `date_modified DESC` | btree | Default ordering of `list_notes` |
| `vault_embeddings_path_key` | `note_path` | unique btree | Upsert conflict target |
| `vault_embeddings_ann_idx` | `embedding` | HNSW, cosine | Vector retrieval in `search_vault` |

**Invariants** (application-layer unless noted):

- **K-1 — Containment.** Every path derived from any input resolves inside the
  vault root, or the operation is refused. Enforced before any filesystem call.
  *(T-16, C-15)*
- **K-2 — File authority.** The vault file is authoritative. Every column here
  is reconstructible from the files alone. Losing this table loses searchability,
  not knowledge. *(NFR.07, NFR.08)*
- **K-3 — Write order.** File first. Then the index, embedding and audit rows
  go in one transaction. If that transaction fails, the file is deleted. A file
  with no index row is unsearchable but repairable; an index row with no file
  is a dangling reference. So the only possible residue — when the
  compensating delete itself fails — is a file, reported by path.
- **K-4 — No unapproved persistence.** A draft touches neither the vault nor the
  database. A rejected draft leaves no trace anywhere. *(FR.03.4.1)*
- **K-5 — Vocabulary is closed.** An area outside the vocabulary is refused, not
  coerced. *(FR.03.2.2)*
- **K-6 — Hash agreement.** When `vault_embeddings.content_hash` differs from
  the index row's `content_hash`, the vector is stale. Reindex must detect and
  recompute rather than trusting the vector.
- **K-7 — Embedding is optional, absence is visible.** A note may exist with no
  embedding. It is lexically searchable and semantically invisible, and any
  response derived from a degraded search says so. *(FR.03.3.3)* [Q-K2]
- **K-8 — Provenance is mandatory for external content.** A note with
  `source` of `web` or `youtube` and no `source_url` is invalid.
- **K-9 — No hard delete while audited.** A note's index row is not removed
  while audit rows reference it; the audit record must remain interpretable.

---

## Flows

### Two-pass ingestion

The flow behind every capture. It exists because the approval gate is the only
control standing between injected instructions in fetched content and a vault
write *(T-23)*.

**Trigger:** the owner supplies a link, or asks for something to be captured.

**Preconditions:** none. Failure of any step ends the flow without persistence.

**Steps:**

1. **Retrieve** — Actor: `knowledge` — filter the address, fetch under limits,
   extract text.
   - On failure: return the specific error. **Flow ends. Nothing persisted.**
2. **Classify** — Actor: the calling agent — propose title, areas, tags,
   confidence from the extracted content *(FR.03.2.1)*.
   - The owner is never asked for these.
3. **Draft** — Actor: `knowledge` — validate the proposal, render the preview.
   - On validation failure: return the error so the model can re-propose. **Flow
     ends. Nothing persisted.**
4. **Present** — Actor: the calling agent — show the complete draft, including
   destination and classification *(FR.03.4.1)*.
   - Decision: approved → step 5; rejected → flow ends, nothing persisted.
5. **Persist** — Actor: `knowledge`, on `add_note`'s approved call:
   1. Write the file.
   2. In **one DB transaction**, write the index row and the audit row (with
      `approval_id`), and the embedding if one is available.
   - **File write fails:** nothing is written. Report `VAULT_WRITE_FAILED`.
   - **Transaction fails:** it rolls back, so there is no index row and no
     audit row. **Delete the just-written file as a compensating action** —
     an unaudited change is worse than a refused one (spec 004 A-4). Report
     `INDEX_WRITE_FAILED`. If the delete also fails, the file remains with no
     index row. Report `INDEX_WRITE_FAILED` naming the path for manual review;
     reindex (K-2) can adopt it once reviewed.
   - **Embedding unavailable:** commit with `embedding_status='pending'` and
     return `embedded=false`. `nizam-retry-embeddings` backfills it (Q-K2).

**Failure handling:**

| Step | Failure | Immediate action | Recovery |
| :--- | :--- | :--- | :--- |
| 1 | Address rejected | Return `URL_REJECTED` | None. Deliberate refusal |
| 1 | Timeout or size cap | Return the error | Owner may retry once |
| 3 | Validation failed | Return naming the field | Model re-proposes |
| 4 | Owner rejects | End | Nothing to recover — nothing was written |
| 5 | Index/audit transaction failed | Roll back, delete the file, report failure | Owner retries. If the delete failed, review the named file, then reindex *(K-2)* |
| 5 | Embedding unavailable | Commit with `embedding_status='pending'` | `nizam-retry-embeddings` backfills |

**End state — success:** file present, index row present and matching, embedding
present or explicitly absent, audit row written.

**End state — failure:** normally nothing was written, because the file is
removed on a failed transaction. In the rare double failure (transaction *and*
compensating delete), a file exists with no index row and no audit row. It is
reported by path, and is recoverable by review plus reindex. That is why the
file is written first *(K-3)*: the recoverable residue is always a file, never
a phantom index row.

**Idempotency:** the flow is not idempotent. A second approved run for the same
title and area is refused with `NOTE_EXISTS` rather than duplicating.

---

### Reindex

**Trigger:** operator action after index loss, corruption, or a hash mismatch.

**Preconditions:** the vault files exist. Nothing else is required — this is the
flow that makes K-2 true rather than aspirational.

**Steps:**

1. **Enumerate** — walk the vault, parse each note's frontmatter.
2. **Upsert** — for each file, upsert the index row keyed by path.
3. **Reconcile embeddings** — recompute where the hash disagrees; skip where it
   matches *(K-6)*.
4. **Prune** — remove index rows and embeddings whose file no longer exists,
   subject to K-9.

**End state — success:** the index reflects the files exactly. No knowledge was
at risk at any point, because the files were never the thing being rebuilt.

**Idempotency:** yes. Running twice is running once.

---

## Domain Invariants

- Every write is two-pass. No path exists to persist without approval
  *(FR.03.4.1)*.
- Every write records an audit row naming the acting agent *(FR.06.3.1)*.
- Every filter value crosses into a query as a bound parameter. No query text is
  assembled from input *(C-09, T-13)*.
- Every path derived from input is containment-checked before use *(K-1)*.
- Every outbound fetch is address-filtered, size-capped and timed out, with the
  filter reapplied after each redirect *(C-16, C-17)*.
- Fetched content, transcripts, and model output are all untrusted. None may
  become an action except through the approval gate *(T-23)*.
- The vault file is authoritative in every conflict with the database *(K-2)*.
- A degraded retrieval says it is degraded. Silence about degradation is a
  defect, not a simplification *(FR.03.3.3)*.

---

## Acceptance Criteria

Each is directly testable. Adversarial ones are marked — they prove a control
and are the highest-value tests in this domain *(TESTING.md)*.

| # | Criterion | Traces to |
| :--- | :--- | :--- |
| A-01 | A source is fetched, drafted, approved and written; the file, index row and audit row all exist | FR.03.1.1, FR.03.1.2 |
| A-02 | A rejected draft leaves no file, no index row, and no audit row | FR.03.4.1, K-4 |
| A-03 | **Adversarial** — a `file_path` escaping the vault root is refused, and the resolved path is not disclosed | T-16, C-15 |
| A-04 | **Adversarial** — a URL resolving to loopback, private or link-local is refused before any connection | T-24, C-16 |
| A-05 | **Adversarial** — a redirect from a public host to a private address is refused at the redirect | T-24 |
| A-06 | **Adversarial** — a video identifier containing shell metacharacters is refused before tool invocation | T-26, C-18 |
| A-07 | **Adversarial** — a response exceeding the size cap is aborted mid-stream, not buffered | T-25 |
| A-08 | An area outside the vocabulary is refused, never coerced to a near match | FR.03.2.2, K-5 |
| A-09 | With embedding unavailable, search returns lexical results with `degraded=true` | FR.03.3.3 |
| A-10 | A query matching semantically but not lexically returns the note | FR.03.3.1 |
| A-11 | `status` raw→evergreen is refused; raw→processed→evergreen succeeds | NoteStatus |
| A-12 | Re-running `update_note` with unchanged content does not re-embed | efficiency, K-6 |
| A-13 | Reindex from files alone reconstructs the index exactly | NFR.08, K-2 |
| A-14 | An index/audit transaction failing after a file write rolls back, removes the file, and reports failure — never success | K-3, C-14, spec 004 A-4 |
| A-15 | A second approved `add_note` with the same title and area returns `NOTE_EXISTS` | idempotency |
| A-16 | Every successful write produces exactly one audit row naming the actor | FR.06.3.1 |
