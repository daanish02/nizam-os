---
type: workflow
title: Repository Self-Maintenance Protocol
description: Mandatory operating constraints for any AI agent modifying files inside lattice/feanor/ — covers frontmatter schema, file placement, and change verification rules.
applies_to: [maintenance]
tags: [workflow, maintenance, okf, governance, agent-protocol]
---

# Repository Self-Maintenance Protocol

This document defines the strict protocol that any external AI agent (e.g., Claude Code, Gemini CLI, Cursor, Windsurf) **MUST** follow when adding, modifying, or refactoring files within the `lattice/feanor/` vault.

---

## 1. Core Operating Principles

### Rule A: Progressive Navigation (Never Dump Context)

- **DO NOT** load the entire repository or whole subdirectories into your context window.
- Always navigate from root to leaf using catalog files (`index.md`):
  1. Read `lattice/feanor/index.md` to identify the target domain.
  2. Read the domain-specific catalog (e.g., `conventions/python/index.md`).
  3. Load _only_ the specific target Markdown file requiring modification.

### Rule B: Atomic File Granularity

- Every rule, architectural decision, or convention **MUST** reside in its own isolated `.md` file.
- **DO NOT** create giant monolithic files combining multiple tech stacks or concepts.
- Keep individual rule files short, concise, and focused on a single topic (e.g., separate `dependency-management.md` from `async-concurrency.md`).

### Rule C: Relative Paths & Subdirectory Isolation

- All internal Markdown links **MUST** use relative paths (`./` or `../`).
- **DO NOT** write absolute system paths (e.g., `/home/user/lattice/...` or `/conventions/...`), ensuring `feanor/` remains fully portable within `lattice/` or when sparse-checked.

---

## 2. Mandatory File Structure & Frontmatter Schema

Every new `.md` file created in `lattice/feanor/` **MUST** include standard OKF v0.2 YAML frontmatter at the top of the file:

```yaml
---
type: convention # Options: catalog, workflow, convention, template, meta, agent, engine, skill
title: Human Readable Title
description: One LLM-facing sentence stating what rules live here, which languages they apply to, and when to load this file.
applies_to: [python, conventions] # Scope tags (tech stack, domain area, etc.)
tags: [keyword1, keyword2]
---
```

All five fields are mandatory and enforced by `scripts/validate-okf.py`. There is deliberately **no `status` field**: every file in the corpus is live and normative, so a status on all of them carries no signal — a convention that no longer holds is deleted, not flagged, because an agent loading it JIT would follow it either way. `description` is held to a minimum length because it is what the Context Resolver reads when deciding whether to load the file; see `meta/determinism-standard.md`'s description mandate.

---

## 3. Workflow for Adding a New Micro-Standard

When adding a new engineering convention (e.g., adding Rust standards under `conventions/rust/`):

1. **Locate Target Directory:** Check if `conventions/<category>/` exists. If not, create the directory.
2. **Create Atomic Standard:** Write the rule file (e.g., `conventions/rust/cargo-workspaces.md`) using strict RFC 2119 keywords (`MUST`, `MUST NOT`, `SHOULD`). Include valid YAML frontmatter.
3. **Register it in `conventions/tags.toml`** — **without this the file is unreachable.** The Context Resolver finds conventions through this map; an unregistered file is never loaded, and nothing errors:

```toml
[tags.cargo-workspaces]
files = ["conventions/rust/cargo-workspaces.md"]
aliases = ["cargo", "rust-workspaces"]
priority = 3   # 1 security · 2 principles · 3 language · 4 domain · 5 devops
```

4. **Add a catalog line to `conventions/index.md`.** `reindex.py` never rewrites an existing `index.md` — it only creates missing ones — so this hand-curated catalog must be edited directly. The Planner reads it in full.
5. **Execute Catalog Reindexing:**

```bash
uv run feanor/scripts/reindex.py
```

6. **Validate metadata and the tag map:**

```bash
uv run feanor/scripts/validate-okf.py
uv run feanor/scripts/resolve-context.py --validate
```

7. **Confirm it actually resolves** — the check that proves the registration worked:

```bash
uv run feanor/scripts/resolve-context.py --tags cargo-workspaces --files backend/src/main.rs --explain
```

8. **Verify Commit Hygiene:** Format the git commit using conventional commit syntax:

```bash
git commit -m "feat(conventions): add Rust cargo workspace standard"
```

Adding anything other than a convention — a script, template, agent, workflow, or maintainer doc — has its own registration points. See `docs/EXTENDING.md`.

---

## 4. Maintenance Script Execution Commands

| Task                   | Execution Command                 | Mandatory Outcome                                                      |
| ---------------------- | --------------------------------- | ---------------------------------------------------------------------- |
| **Catalog Reindexing** | `uv run feanor/scripts/reindex.py`      | Automatically updates all `index.md` files with new relative links.    |
| **OKF Linting**        | `uv run feanor/scripts/validate-okf.py` | Must return `Exit Code 0` with zero frontmatter or link syntax errors. |
| **Skill Update**       | `lattice update feanor`                  | Pulls the latest `feanor/` from the Lattice remote and reinstalls its declared git hooks. |

---

## 5. Defensive Formatting Rules

- **Code Blocks:** Wrap code examples in appropriate syntax-highlighted blocks (`py`, `bash`, `json`, `yaml`).
- **No Direct Prompt Pollution:** Do not mix state-machine execution code into `conventions/`. `conventions/` is strictly for JIT standards, while `agents/` is strictly for system execution prompts.
