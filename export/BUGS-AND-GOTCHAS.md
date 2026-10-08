# Known bugs and gotchas from the old system

Found during the 2026-09-26 refactor attempt on the old VPS, before the decision to wipe and rebuild. Read this before reusing any code-reference/ file. Don't repeat these.

## 1. Transaction-abort bug (confirmed live, reproduced)

`code-reference/knowledge-service/search.py`, function `_bm25`:

```python
def _bm25(conn, query: str, limit: int) -> list[tuple[int, float]]:
    try:
        rows = conn.execute("... paradedb.boolean(...) ...").fetchall()
        return [...]
    except Exception:
        rows = conn.execute("... plainto_tsquery ...").fetchall()  # BUG: same conn, same transaction
        return [...]
```

Postgres aborts the **entire transaction** on any statement error. The `except` branch runs a different query on the same connection/transaction without a `ROLLBACK` first, so it also fails, with the misleading error `current transaction is aborted, commands ignored until end of transaction block`. Every subsequent query on that same connection fails the same way until the connection is discarded and replaced. This happened live — the ParadeDB `@@@` operator query failed (ParadeDB extension issue, not investigated further), the fallback then also failed, and the agent's knowledge search stayed broken until the whole gateway process was restarted (fresh connection).

**A second, unrelated failure looked similar.** Right after the Postgres password for `svc_knowledge` was rotated, knowledge calls failed with `password authentication failed for user "svc_knowledge"`. The value in the consumer's `.env` did not match the one set with `ALTER ROLE`. The cause was a secret-rotation mismatch, not the transaction bug, but it surfaced as the same kind of connection-level failure. **When this service reports "connection failed" or "transaction aborted", read the exact Postgres error before fixing anything:**

- `current transaction is aborted` means this bug.
- `password authentication failed` means a rotation mismatch — see the procedure in `docs-ready/RUNBOOK.md`.

**Rule for the rebuild:** any exception handler that catches a DB error and then runs another query needs one of:
- `conn.rollback()` before the fallback query, or
- a savepoint (`SAVEPOINT`/`ROLLBACK TO SAVEPOINT`) around the risky query, or
- a fresh connection for the fallback, or
- avoid the retry-fallback pattern entirely — pick one search method and make it reliable instead of catching failures of a second, exotic extension (ParadeDB).

Write an automated test that forces the primary path to fail and asserts the system still returns correct results without needing a process restart.

## 2. Hardcoded LiteLLM URL

`code-reference/knowledge-service/embedder.py:17` (approximate — check current line) hardcodes `http://localhost:4000/embeddings` instead of reading a `LITELLM_BASE_URL` from config. Any port change or host change breaks silently. Read all such values from config, never inline.

## 3. Secrets in an untracked, unignored config file

`config-reference/hermes-curator-config.yaml` originally had a plaintext Postgres DSN (with password), Redis URL (with password), the LiteLLM master key, and a Supadata API key directly in the `mcp_servers.knowledge-service.env` block. The file was **not** covered by `.gitignore`, so it was one `git add .` away from landing in history. It was caught and fixed mid-session (converted to `${VAR}` placeholders resolved from the profile's own `.env`), and the affected Postgres and Redis passwords were rotated. The Supadata key rotation was deferred by the owner and is moot after the VPS wipe.

**Rule for the rebuild:** any file with a real secret must be gitignored *before* it's ever written, not after. Grep your own gitignore against every path pattern you're about to write a secret into, before writing it.

## 4. Live symlink coupling

Systemd units (`/etc/systemd/system/*`) and Hermes profile files (`~/.hermes/profiles/*/{config.yaml,.env,SOUL.md,AGENTS.md,memories,skills,pending}`) were symlinked directly into the git working tree. Editing a file or switching branches immediately changed what was live. This is why the original refactor plan needed an entire phase just to insulate live services before any reorganization could safely begin. **Avoid this from day one in the rebuild** — see `00-START-HERE.md` principle #2 (release-dir deploy) and #4 (Hermes owns its own mutable state, never symlinked from the repo).

## 5. `metrics-llm.timer` had an inline shell comment on a directive line

```
OnCalendar=*:0/1  # every minute; equivalent to OnCalendar=minutely
```

systemd unit files do not support inline comments after a directive value — this put the timer into a permanent `bad-setting` state (it kept running on its last-known-good schedule but `systemctl` flagged it broken). Comments in unit files must be on their own line, starting with `#` as the first non-whitespace character.

## 6. Ambiguous knowledge taxonomy (`domain` vs `areas`)

The DB schema and code (`vault_io.py`, `db/migrations/002_knowledge_schema.sql`) implemented a single `domain` column from a fixed list of 10 values. The newest charter docs (SRS, specs-new/001-knowledge.md) described `areas` — multi-valued, with expected overlap between subjects. These were never reconciled; the code was never updated to match the newer design. Decide this **once**, in the spec, before writing any code — see the rebuild doc, cycle-1 knowledge phase.

## 7. Business-domain remnants scattered across old docs

Ten-agent roster including business agents (Raha/CFO, Hala, Omar, Reem, Mira), `finance_business` schema, CRM/analytics services, `#cfo-office`-style Discord channels — all present in various old docs (`docs/archive-reference/`) despite the project being redirected to personal-only scope. If you read anything in `docs/archive-reference/` for factual details (a port number, a channel-naming pattern, a setup step), **do not** carry over any agent name, schema name, or channel belonging to the business domain.

## 8. Doc sprawl and duplication

At the point of the wipe decision, the docs directory held at minimum three overlapping requirement-tier documents (VISION, PRD, SRS) that repeated the same problem statements and open questions with different levels of detail and some contradictions, plus a `docs/specs/` (old, Discord/infra-focused) and a separate `docs/specs-new/` (newer, domain-focused) with colliding numbering (both had a "001"). Pick **one** doc per tier in the rebuild and don't let a second one accumulate — if you're about to write a doc that restates something already written elsewhere, stop and reference the original instead.

## 9. Grafana dashboard regex didn't match real profile names

A Grafana dashboard filtered on Hermes profile names `ayah|noor|nazim|rashid` (character names) while the actual systemd/Hermes profile identifiers were `admin`, `curator`, `assistant` (role names). Character names belong only in `SOUL.md`/Discord display; every machine-facing identifier (profile name, systemd unit, DB role, dashboard filter) should use the role name consistently.

## 10. `nizam-os.env.enc` was found at 0 bytes

A tracked encrypted secrets file was empty in git — likely an encryption run that failed silently or wrote before the plaintext existed. Whatever encrypts secrets in the rebuild should fail loudly (non-zero exit visible to the operator) rather than produce and commit an empty ciphertext file. This was incidentally fixed when the owner rotated the Redis password and re-ran encryption during this session, but the underlying "why did it go empty" was never root-caused.
