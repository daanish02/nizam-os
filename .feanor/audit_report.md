# Feanor Audit Report — nizam-os

---

## Run: 2026-09-03 — `/standardize` (Brownfield Compliance Audit)

- **Status:** FAIL
- **Total Convention Domains Checked:** 5 (project-layout, error-handling, logging, typing, testing)
- **Violations Found:** 9

### Scope

Audit target: `services/knowledge-service/` (sole Python service).
Conventions applied: `3-conventions/python/` (project-layout, error-handling, logging, typing, testing, module-boundaries).
Git conventions deferred to post-standardize pass (no active branch strategy violations found).

---

### Convention Violations

| Severity | File | Rule Violated | Remediation Required |
| :------- | :--- | :------------ | :------------------- |
| HIGH | `services/knowledge-service/` | `python/project-layout.md` — flat modules at service root, no `app/` package | Restructure into `app/<domain>/` layout; create `main.py` entry point |
| HIGH | `services/knowledge-service/server.py` | `python/project-layout.md` — SQL inlined as Python string (lines 90–99) | Extract to `app/queries/list_notes.sql` |
| HIGH | `services/knowledge-service/indexer.py` | `python/project-layout.md` — SQL inlined as Python string | Extract to `app/queries/*.sql` |
| HIGH | `services/knowledge-service/search.py` | `python/project-layout.md` — SQL inlined as Python string | Extract to `app/queries/*.sql` |
| HIGH | `services/knowledge-service/` | `python/testing.md` — zero test files exist | Create `tests/conftest.py` + `tests/test_*.py` mirroring service modules |
| HIGH | `services/knowledge-service/embedder.py:16` | `python/error-handling.md` — `httpx.post().raise_for_status()` uncaught; propagates as unhandled exception to MCP caller | Wrap in try/except; raise typed `AppError` |
| HIGH | `services/knowledge-service/embedder.py` | `python/error-handling.md` — no `AppError` base exception hierarchy | Create `app/exceptions.py` with `AppError` and subtypes |
| MEDIUM | `services/knowledge-service/server.py:74` | `python/typing.md` — `params: list` missing element type | Change to `params: list[Any]` or typed union |
| MEDIUM | `services/knowledge-service/embedder.py:17` | `python/project-layout.md` — `"http://localhost:4000/embeddings"` hardcoded; not from `app/config.py` | Move to `config.py` as `LITELLM_BASE_URL` |

### Spec Conformance

N/A — no `docs/specs/` exist yet. `/document` must be run after `/standardize` to produce specs and `docs/PRD.md`.

### Notes

- `nizam_shared.base.ServiceBase` provides the logger factory (`svc.logger`) and DB connection pool (`svc.db()`). Logging format and rotation assumed handled there — not audited (external package). If `ServiceBase` does not implement `CompressingTimedRotatingFileHandler` per `python/logging.md`, that is a separate violation in the `shared` package.
- DB migrations are at repo root (`db/schema.sql`, `db/migrations/`). Per `python/project-layout.md`, migrations belong inside the service. This is a **deliberate architectural choice** (shared DB across services) — flag for human review, not auto-fixed.
- `services/knowledge-service/server.py:list_notes()` DB query is not wrapped in try/except. Included in TICK-004 remediation scope.
