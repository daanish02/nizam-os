---
title: Testing — nizam-os (Cycle 1)
status: LOCKED
version: 2.0.0
date: 2026-09-26
---

# Testing

Testing here is not an afterthought. Every code ticket in `docs/plan.toml`
names its tests before any code exists. Those names are the definition of
"done".

## The TDD loop (every ticket, no exceptions)

1. **Pick up the ticket.** Run `plan.py next`, then read the ticket's
   `acceptance_criteria` and its `spec_ref`.
2. **Write the named tests.** Each `tests/...::test_name` in the ticket gets
   written first, with an assertion that encodes the criterion. **Run the tests
   and watch them fail for the right reason** — an assertion failure, not an
   `ImportError`. A test that has never failed has never proven anything.
3. **Write the least code that makes them pass.** Then refactor while they stay
   green.
4. **Verify.** `plan.py verify <id>` runs the ticket's `verification_command`
   and records the real exit code. `plan.py done <id>` refuses unless that
   passed.
5. **Add tests beyond the list when needed.** The named tests are the
   **minimum**. Add more for any branch the named ones don't reach — the
   coverage gate will find the ones you missed.

## Commands

| Command | Runs | When |
| :--- | :--- | :--- |
| `bash scripts/check.sh` | `ruff check`, `ruff format --check`, `pytest -m "not slow"` (unit + property) | Every ticket; the pre-commit habit. Target under 60 s. |
| `bash scripts/check.sh --all` | The above, plus `[slow]` integration tests against Postgres, plus the **coverage gate** | Every ticket that touches the DB (their `verification_command` says `--all`), and before every phase ends |
| `pytest -m slow` | Integration tests only | Debugging |
| `HYPOTHESIS_PROFILE=thorough pytest -m property` | Property tests at 2,000 examples each | Before a phase ends, and after touching `calc/`, `finance/reports.py`, `core/approval.py` or `jobs/backup.py` |

## Test tiers

| Marker in the plan | pytest marker | What it is | Touches |
| :--- | :--- | :--- | :--- |
| *(none)* | — | **Unit test.** One function or module, at its public boundary. | Nothing outside the process. HTTP is mocked with `respx`; subprocess and filesystem use `tmp_path`. |
| `[property]` | `property` | **Hypothesis property test.** An invariant must hold for generated inputs, not just hand-picked ones. | Nothing outside the process. |
| `[slow]` | `slow` | **Integration test** against a real, throwaway Postgres database, built from the real migrations. | The `pg` fixture's database only. **Never** the live `nizam` database. |
| "Live: …" | — | **A manual check** against running services, done by the agent with Danish at the end of a phase. It is recorded in the phase summary. | Live services |

### Mocking rules
- **Mock only at the true I/O boundary:** `respx` for HTTP (LiteLLM, fetch
  targets, FX/metal APIs), a fake clock, and `tmp_path` for the vault.
- **Never** use `mock.patch` on a class from this codebase to make a test pass.
  If a unit is hard to test without that, its dependencies need injecting —
  fix the design, not the test.
- **The DB is never mocked in a `[slow]` test.** In unit tests, services take a
  repository object, and tests pass a small in-memory fake that implements the
  same protocol.

## Fixtures (`tests/conftest.py`)

| Fixture | Scope | Provides |
| :--- | :--- | :--- |
| `pg` | session | Creates `nizam_test_<random>`, runs `dbmate up` from `migrations/` (with `DBMATE_NO_DUMP_SCHEMA=true`), and yields an admin DSN plus per-role DSNs (`svc_knowledge`, `svc_finance`). Drops the database at teardown. Roles are cluster-global, so migrations create them idempotently. |
| `pg_conn` | function | A connection inside a transaction that is **rolled back** after the test, giving isolation without re-migrating. Tests that need committed data (replay, concurrency) use `pg` directly and clean up. |
| `vault` | function | A `tmp_path` configured as `VAULT_ROOT`. |
| `fake_clock` | function | An injectable clock used by `core/approval.py`, the hawl logic and backup rotation. |
| `approval_key` | function | A random `NIZAM_APPROVAL_KEY` per test. |
| `llm` | function | A `respx` router for LiteLLM `/embeddings`, with helpers `.up(dims)`, `.down()` and `.malformed()`. |
| `rates` | function | A `respx` router for the FX and silver-price providers, with `.stale()` and `.down()`. |
| `mcp_client` | function | FastMCP's in-memory `Client` bound to a domain's tools, used for tool-level tests. |
| `app_client` | function | A Starlette `TestClient` for `core/http.py`, with helpers to attach each agent's token. |

## Property-based testing (hypothesis)

Profiles are registered in `tests/conftest.py`:
- `default`: 100 examples
- `thorough`: 2,000 examples
- selected with `HYPOTHESIS_PROFILE`

Property tests are required wherever correctness must hold for all inputs:

| Area | Properties |
| :--- | :--- |
| `calc/money` | Addition is commutative, associative, and equal to the integer sum. Conversion matches a `Decimal` half-even reference, and rounds once even over multiple steps. Output is deterministic, byte for byte. |
| `calc/ops`, `calc/zakat` | Amortisation reconstructs the total exactly. Share basis points stay in bounds and partition-sum to 10,000. `compound` rounds once. Zakat = ceil(total / 40), never below the exact 2.5%. |
| `finance/reports` | Category totals plus `unrecorded` equal the total, for any ledger. Transfers never change spending. |
| `finance/zakat` | The hawl never completes if any balance point falls below nisab. |
| `core/approval` | Any payload mutation is rejected. Arbitrary payloads round-trip. |
| `knowledge/vault`, `knowledge/areas`, `knowledge/sources/youtube` | A slugged path is always inside the vault. Metadata round-trips. Every valid subset of areas passes. Only valid video IDs reach a subprocess. |
| `core/log` | A redacted value never appears in the output. |
| `jobs/backup` | Rotation keeps the newest backup, bounds the count, and is idempotent. |
| agent plugin | `rule_key` is deterministic and distinct for distinct arguments. |

**Expected values in money and zakat tests come from an independent
computation** written inside the test (Python `Decimal` with an explicit
rounding mode), or are hand-computed and commented. Never run the code and
paste its output back in as the expected value — that tests nothing.

## Coverage gate

`check.sh --all` writes `coverage.json`, then `scripts/coverage_gate.py`
enforces these line-coverage thresholds:

| Scope | Threshold | Why |
| :--- | :--- | :--- |
| `nizam/core/` | **≥ 90%** | Approval, auth, audit and transactions — the control surface |
| `nizam/calc/` | **≥ 90%** | Money correctness |
| `nizam/finance/` | **≥ 90%** | Money correctness, zakat |
| `nizam/` overall | **≥ 80%** | Everything else |

- A package with no source files yet is skipped, not failed.
- Coverage is measured only in `--all` mode. Fast mode would under-count paths
  that only `[slow]` tests reach.
- The gate is a floor, not a target. A line covered by a test that asserts
  nothing still counts, so reviewers must check that assertions are meaningful.

## Traceability: spec acceptance IDs → tests

Every acceptance ID in the specs maps to a named test or live check in
`docs/plan.toml`, and the ID appears in that test's criterion:

- A-xx — knowledge
- B-xx — finance
- C-xx — calc
- E-xx — agent runtime

The one exception is **E-18 to E-23** (delegation and external agents), which
are deferred to cycle 2. **When you add or change a spec acceptance
criterion, add or change the ticket's named test in the same commit.**

A quick audit that nothing is unmapped:

```bash
uv run python - <<'PY'
import re, tomllib
t = " ".join(" ".join(x["acceptance_criteria"]) + x["description"]
             for x in tomllib.load(open("docs/plan.toml", "rb"))["tickets"])
for pre, f in {"A": "001-knowledge", "B": "002-finance", "C": "003-calc", "E": "004-agent-runtime"}.items():
    ids = set(re.findall(rf"^\| ({pre}-\d+[a-z]?) \|", open(f"docs/specs/{f}.md").read(), re.M))
    print(pre, sorted(i for i in ids if not re.search(re.escape(i) + r"\b", t)))
PY
```

Expected output: every list empty except E, which lists E-18 to E-23.

## Planned test volume (cycle 1)

| Phase | Tickets | Named tests | of which `[slow]` | of which `[property]` |
| :--- | ---: | ---: | ---: | ---: |
| 1 — tooling, secrets | 6 | 12 | 0 | 0 |
| 2 — database | 2 | 6 | 6 | 0 |
| 3 — deploy, LiteLLM | 3 | 17 | 0 | 0 |
| 4 — core + knowledge | 20 | 135 | 40 | 8 |
| 5 — Hermes + plugin | 4 | 21 | 0 | 1 |
| 6 — observability, backups | 3 | 15 | 2 | 2 |
| 7 — calc, finance, Ayah | 13 | 86 | 21 | 14 |
| **Total** | **51** | **292** | **69** | **25** |

These are minimums. Parametrised tests expand the count: the scope matrix
alone is every agent × every domain, and the error-code mapping tests cover
every row of the specs' error tables.

## Must-have tests, by risk

These are the tests that would have caught the old system's real failures, or
that guard what matters most. Each is a named test in the plan.

- **The transaction-abort regression** (`export/BUGS-AND-GOTCHAS.md` #1):
  TICK-403 `test_connection_usable_after_failed_statement_in_transaction`, and
  TICK-412 `test_forced_lexical_failure_then_same_connection_query_succeeds`.
- **Approval enforcement** (spec 004, E-25 to E-30): TICK-406, TICK-416,
  TICK-502 and TICK-712.
- **Adversarial input** (SECURITY T-16, T-24, T-26): TICK-409 (path escape),
  TICK-413 (SSRF, redirects, stream cap), TICK-414 (shell metacharacters).
- **LLM outage degrades** (ADR-006): TICK-411, TICK-415, TICK-418.
- **Unaudited writes are impossible** (spec 004 A-4, spec 001 K-3): TICK-405
  and TICK-415.
- **Money exactness and zakat**: TICK-701 to TICK-703, TICK-708, TICK-709.
- **Scope isolation**: TICK-407 and TICK-712 (the HTTP scope matrix), plus the
  `[slow]` grant tests in TICK-201, TICK-408 and TICK-705.
- **Secrets hygiene** (BUGS #3, #10): TICK-103 (`secrets.sh check`),
  TICK-302 (no secret literals in `deploy/`), TICK-501 (no secret literals in
  agent configs).
- **Units can't regress into old bugs** (BUGS #5, #9): TICK-302's unit linter
  and TICK-603's dashboard test.

## What not to test
- Tests that only re-assert what a mock returns.
- Framework internals (FastMCP routing, Starlette). Test your use of them.
- Coverage for its own sake. Test behaviour that a spec criterion or an
  invariant demands.

## Layout

`tests/` mirrors `nizam/`, plus `tests/scripts/` (shell scripts driven by
pytest), `tests/migrations/`, `tests/deploy/` (unit, sudoers, manifest,
dashboard and config linters), `tests/agents/` (Hermes configs and plugin) and
`tests/ops/`. Test names are the plan's names — `plan.py` and reviewers rely on
them matching.
