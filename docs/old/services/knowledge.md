# knowledge-service

Part of [services overview](../services.md). Hybrid search over PostgreSQL + nizam-vault files. Primary tool for "find relevant context" queries.

## Tools

| Tool | Description |
|---|---|
| `search(query, domain?, limit?)` | Hybrid search (BM25 + pgvector). Returns ranked chunks. |
| `add_note(title, content, tags, domain)` | Write to vault + index for search |
| `get_note(note_id_or_path)` | Retrieve full note |
| `list_notes(domain?, tags?)` | Browse vault |
| `upsert_embedding(note_id)` | Recompute embedding (auto-called on write) |
| `domain_summary(domain)` | High-level overview of what's in a vault domain |

## Vault layout

```
/personal       — private (Ayah access only)
  /finance      — money notes, context behind numbers
  /health       — fitness, nutrition context
  /relationships
/business       — Arc Systems (C-suite access)
  /clients      — meeting prep, notes, context
  /products
  /ops          — SOPs, processes
/commons        — shared learning (read: all, write: Noor w/ approval)
  /books
  /courses
  /reference
```

## Schema (knowledge)

```
knowledge_nodes(id, domain, path, title, content_hash, created_at, updated_at)
knowledge_chunks(id, node_id, chunk_index, content, embedding vector(1536))
```

Embeddings via embedding model configured in `config/litellm.yaml`. Recomputed only on `content_hash` change.

DB role: `svc_knowledge` — see [architecture](../architecture.md#per-service-db-users). Search strategy: [architecture](../architecture.md#search--retrieval).
