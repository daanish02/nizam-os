---
type: reference
title: Graphify — Knowledge Graph Navigation
description: How to build and query graphify knowledge graphs for both feanor/ docs and project code; two separate scopes, two separate output directories.
applies_to: [all]
tags: [graphify, navigation, knowledge-graph]
---

# Graphify Navigation

Graphify builds a queryable knowledge graph from any folder of files. Feanor uses two independent scopes:

| Scope | What it indexes | Output dir | When to build |
| :--- | :--- | :--- | :--- |
| **feanor-docs** | `feanor/` — all conventions, agents, templates, meta | `feanor/graphify-out/` | When working inside the feanor repo |
| **project-code** | Project codebase (repo root, excludes `feanor/`) | `graphify-out/` | When working on a project that uses feanor |

`feanor/graphify-out/` is gitignored — it is a local navigation artifact, not a committed file. When feanor is loaded into a project repo, `feanor/` stays untouched; only `graphify-out/` at the project root is created.

---

## Install

Install graphify once per machine:

```bash
uv tool install graphifyy
```

Register with Claude Code (writes a hook so `/graphify` is available as a slash command):

```bash
graphify claude install
```

---

## API Key Setup

Graphify uses OpenRouter for semantic doc extraction. Keys live in `feanor/.env` — one file for both scopes. Copy `feanor/.env.example` and fill in your key:

```env
# feanor/.env
OPENAI_BASE_URL=https://openrouter.ai/api/v1
OPENAI_API_KEY=sk-or-...
OPENAI_MODEL=google/gemini-2.0-flash-lite   # swap model here, no other changes needed
```

Load into your shell before running graphify (PowerShell):

```powershell
# from project root — works for both feanor-docs and project-code scope
Get-Content feanor\.env | Where-Object { $_ -match '^[^#]' } | ForEach-Object { $k,$v = $_ -split '=',2; [System.Environment]::SetEnvironmentVariable($k,$v) }
```

`feanor/.env` is gitignored. `feanor/.env.example` is committed (no real keys).

---

## Build

**Feanor docs scope** (run inside the feanor repo):

```bash
/graphify feanor/
# outputs: feanor/graphify-out/
```

**Project code scope** (run at project root):

```bash
/graphify .
# outputs: ./graphify-out/
```

For headless / CI use (no slash command):

```bash
graphify extract feanor/ --backend openai
graphify export wiki --graph feanor/graphify-out/graph.json
```

---

## Query

**Fast path:** if `graph.json` already exists, query directly — do not rebuild unless files have changed significantly.

```bash
# feanor docs
/graphify query "where is the rate limiting convention?"

# project code (from project root)
/graphify query "where is auth middleware defined?"
```

Query returns a ranked list of nodes with file paths — use these paths to read the specific files rather than scanning broadly.

---

## Incremental Update

After files change:

```bash
# feanor docs
/graphify feanor/ --update

# project code
/graphify . --update
```

---

## When to Use

- **Before navigating conventions**: query feanor-docs scope instead of reading `conventions/index.md` and following links manually. The graph returns ranked results for "what convention covers X" faster than breadth-first file reading.
- **Before implementing a ticket**: query project-code scope to locate existing implementations, avoid duplicating utilities, and understand call chains.
- **When context-resolver returns multiple candidate files**: use graphify query to rank them by relevance to the ticket's concern.

Do not rebuild the graph on every query — check if `graphify-out/graph.json` exists first.
