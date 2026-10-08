---
type: reference
title: Feanor Maintenance Audit Log
description: Append-only history of maintenance audits of Feanor itself — date, model, scope, findings by severity, and disposition; makes posture trackable over time instead of rediscovered each run.
applies_to: [maintainer]
tags: [docs, maintainer, audit, history, security]
---

# Maintenance Audit Log

Append-only. **Never edit or delete a past entry** — a superseded finding is corrected by a later entry saying so, not by rewriting history. The value of this file is the trend, and a rewritten history has no trend.

## How To Run One

Roughly weekly, with the most capable model available:

1. Audit `feanor/` excluding `graphify-out/`, against three questions: is it industry-grade, are there security gaps, does it produce simple and maintainable code?
2. **Verify every high-severity finding against the file before recording it.** Reviewers report defects that are not there; unverified findings pollute the trend and waste the next run.
3. Add an entry below using the template. Record what was *fixed* and what was *accepted* — an accepted finding is a decision, and it should not be re-litigated from scratch next week.
4. Update [SECURITY-POSTURE.md](./SECURITY-POSTURE.md) if posture changed, and [OVERVIEW.md](./OVERVIEW.md)'s gaps list.

Carry forward the open findings from the previous entry. An audit that starts from zero each week measures nothing.

## Entry Template

```markdown
## YYYY-MM-DD — <model>

**Scope:** <what was reviewed>
**Method:** <parallel reviewers / single pass / focus area>

| Severity | Count | Fixed | Accepted | Carried |
| :--- | :--- | :--- | :--- | :--- |
| CRITICAL | | | | |
| HIGH | | | | |
| MEDIUM | | | | |

**Fixed:**
- <finding> — <what changed>

**Accepted:**
- <finding> — <why, and revisit-by date>

**False positives:** <claims that did not survive verification — worth recording, they recur>

**Posture change:** <what moved, or "none">
```

---

## 2026-09-10 — Claude Sonnet 5 — Carried-gap remediation

**Trigger:** closing a carried MEDIUM finding from 2026-09-07 ("No accessibility convention for frontends"), raised again directly by the maintainer.

**Scope:** `feanor/conventions/nextjs/` accessibility coverage.
**Method:** targeted addition, not a full audit pass.

| Severity | Count | Fixed | Accepted | Carried |
| :--- | :--- | :--- | :--- | :--- |
| MEDIUM | 1 | 1 | 0 | 0 |

**Fixed:**
- No accessibility convention for frontends — added `conventions/nextjs/accessibility.md` (WCAG 2.1 AA baseline: semantic structure, keyboard/focus, forms, ARIA, motion, and the Biome `a11y` lint group as the mechanical enforcement gate). Trimmed the overlapping "Accessibility Baseline" subsection out of `styling-ui.md` in favor of a cross-reference. Registered in `tags.toml` (`nextjs-accessibility`, priority 3) and `conventions/nextjs/index.md`. Closed the gap in `OVERVIEW.md`'s Known Gaps.

**Accepted:** none this cycle.

**False positives:** none.

**Posture change:** the two remaining 2026-09-07 carried items (no performance-budget convention, no migration/rollback safety convention beyond forward-only numbering) are unaffected and still carried.

---

## 2026-09-08 — Claude Opus 5 — Live end-to-end run remediation

**Trigger:** not a code read. A full greenfield pipeline run (`/reqs` through `/audit`, 25 tickets, real project) produced defects that only running the thing could expose. Every finding below was reproduced against current source before being fixed, and every gate was observed failing before it passed.

**The unifying finding:** the conventions were right and nothing routed agents to them. `git/branch-strategy.md` fully specifies `feature/* -> qa -> main`; `commit-format.md` says "no large commits". Across the entire run neither was followed — the project has only `main` in its history and one commit carrying 74 files / 8647 lines. Tag `git` sits at priority 5 and application tickets are never tagged `git`, so those files were never once loaded. Level-1 prose is silent when skipped.

**Fixed:**

- **`lattice add` installed no git hooks at all** (`.git/hooks/` empty in the live project), while `README.md` promised the installer "verifies the branch-guard hooks… does not silently continue with enforcement missing". True of `install.sh`, false of the path actually used. `install.sh` retired; the CLI now installs hooks a skill declares in `lattice-hooks.json`. See D-013.
- `commit-format.md` added to the resolver's always-load floor — the single change that makes commit discipline reachable at all.
- `check-git.py` gates branch and commit discipline in `/exec`; `init-branches.sh` creates the structure at `/scaffold`, first, before anything writes a file.
- `check-push.py` runs the project's own lint/typecheck/tests before a push. The run's history carries post-push fixups for biome import order and a nonexistent type — both caught locally by this.
- `execution-agent.md` gained a commit step. Its loop ended at `plan.py done` and never mentioned committing, which is why commits accumulated until someone happened to make one.
- `/plan` now requires scaffolded source. It could previously plan `target_files` into directories that did not exist; only agent judgment caught it. Required a new `scaffolded` marker, because `has_source()` cannot tell a greenfield tree Feanor built from brownfield source that predates it.
- PEP 723 scripts refuse bare `python` with the exact `uv run` command, exit 2. In the run an agent hit the raw `ModuleNotFoundError`, ran `pip install`, and abandoned `uv`.
- `audit-mechanical.py` accepted only `bun.lockb`, so every current-Bun project drew a false CRITICAL. Same stale assumption in `dockerfile-nextjs.md` was a live build-breaker (`COPY package.json bun.lockb ./`).
- `/reqs` never asked who builds the system, though the architect agent itself called team fluency the strongest factor in language selection. New checklist section 2.8, wired through the section 5 coverage gate, SRS 3.5, and the architecture criteria table.
- PRD template supplied the FR/NFR tables `product-agent.md` explicitly forbids, and had no home for the budget/timeline it claims to carry.
- `sys.modules` parent-attribute staleness documented in `cross-stack/testing.md` — a real, expensive debugging session in the run.

**Found while fixing, not in the original list:**

- `github-repo-setup.sh` required the `block-feanor-on-main` status check on `main`. With that workflow obsolete, the check would never report and **every PR into `main` would sit permanently pending**. Removed.
- `check-push.py` crashed with `UnicodeEncodeError` on Windows cp1252 from a box-drawing character. Caught by running it, not reading it.

**Accepted / carried:**

- CI actions remain tag-pinned, not SHA-pinned, in the test project — deferred there, and `audit-mechanical.py` still reports it.
- **Cost of D-013, stated plainly:** a gitignored `skills/` gives up D-001's "conventions versioned with the code they governed". Checking out an old commit no longer reproduces the conventions in force then. Accepted because the alternative was enforcement that provably did not run.

**Posture change:** branch and commit discipline moved from documented-and-ignored to gated. Install-time enforcement moved from promised-but-absent to installed-and-reported.

## 2026-09-07 (second pass) — Claude Opus 5 — Determinism push

**Scope:** Feanor's own mechanical steps. Not a defect audit — a deliberate conversion of prose instructions into gates, following `meta/determinism-standard.md` applied to Feanor itself.
**Method:** enumerated every code block in `agents/`, `meta/`, `workflows/`; swept all 54 convention files for mechanically-decidable rules; built gates for the decidable subset.

**What changed — new gates (level 3 on the enforcement ladder):**

- `check-preconditions.py` — replaces the bash comment block in `command-router.md` §2. One call per phase; exits naming the missing artifact and the command that produces it.
- `plan.py` ticket validation — `next` now **refuses** an invalid ticket. Catches a typo'd convention tag (previously silent: the rules were simply absent), a code ticket with no test file, a route-handler ticket missing `access-control`, an unresolvable `spec_ref`, unknown dependencies, and dependency cycles.
- `check-registration.py` — cross-checks manifest ↔ router ↔ `agents/`, catalog completeness, template reachability, and every relative link.
- `audit-mechanical.py` — 11 checks over lockfiles, `.env` hygiene, env-var completeness, image and CI-action pinning, pre-commit config, migrations, and forbidden tokens. `/audit` runs it before judgment work, so convention compliance is repeatable across runs.
- `check-all.sh` — single entry point, wired into the pre-commit hook.
- `_gate.py` — shared block-with-override behaviour; overrides recorded in `.feanor/logs/overrides.log`.

**Defects found and fixed while doing it:**

- `run-tests.sh` ran `npm test` while every convention mandates Bun, had no Go branch, and **silently exited 0 when it found no test suite at all** — a harness that reported success for verifying nothing. Rewritten: multi-service discovery, `go test -race`, `bun test`, and a hard failure when nothing ran.
- `mark-ticket-complete.py` invoked `plan.py` through `sys.executable`, which cannot satisfy its PEP 723 dependencies. Deleted; `plan.py` is the documented path.
- `github-repo-setup.sh` generated CI with `actions/checkout@v4`, a mutable tag, violating the SHA-pinning rule written in the first pass. Pinned.
- `check-preconditions.py` hit MSYS path mangling on Git Bash (`/plan` arriving as `C:/Program Files/Git/plan`) — the same class as the earlier `netstat`/`lsof` portability bug. Fixed in the script.
- `check-registration.py` found six real registration gaps on its first run, including `meta/threat-model.md` (added an hour earlier, never catalogued) and two scripts unlisted for longer.

**Deliberately NOT scripted.** Six candidate rules were rejected as not mechanically decidable: ownership predicates in a WHERE clause, Go name stuttering, cursor-pagination-only, log interpolation, least-privilege DB roles, token lifetimes. Implementing them would produce false positives, and a checker people learn to ignore takes the true findings down with it. Recorded in `DECISIONS.md` D-012 so a later pass does not re-propose them.

**Posture change:** mechanical work moved from level 1 (prose, silent when skipped) to level 3 (gate, refuses). `/audit` convention compliance moved from fully judgment to a stable mechanical base plus judgment on top.

---

## 2026-09-07 — Claude Opus 5

**Scope:** All of `feanor/` except `graphify-out/` — 123 files.
**Method:** Three parallel reviewers (cross-stack conventions, scripts, language conventions) plus direct read of `agents/`, `meta/`, `workflows/`, `templates/`, and the core principle files. Every CRITICAL/HIGH claim re-verified against the source file.

| Severity | Count | Fixed | Accepted | Carried |
| :--- | :--- | :--- | :--- | :--- |
| CRITICAL | 5 | 5 | 0 | 0 |
| HIGH | 14 | 14 | 0 | 0 |
| MEDIUM | 15 | 12 | 0 | 3 |

**Fixed — engine integrity:**

- **The verification gate was non-functional.** `execution-agent.md` ran `eval "$CMD" | tee log` and recorded `$?`, which is `tee`'s status, not the test's. Every ticket passed verification regardless of test outcome. Replaced with `plan.py verify`, which runs the command without a shell and records its real exit code; `plan.py done` now refuses without a passing verify. Proven both directions in a scratch project.
- **Arbitrary code execution via `plan.toml`.** The same `eval` executed a free-text field from a git-tracked data file. Shell removed; shell operators rejected at parse time; `working_dir` added so a leading `cd` is unnecessary.
- **Generated `start.sh` was Windows-only** (`netstat`/`taskkill`) and swallowed failure with `|| true`, so on Linux/macOS the port silently stayed occupied. Now probes `lsof`/`ss`/`netstat` and fails loudly. Verified freeing a real port.
- **`validate-okf.py` crashed** on Windows (`UnicodeEncodeError` on an emoji) and parsed YAML by regex. Rewritten on `yaml.safe_load`; immediately caught two real violations the old version never surfaced. Wired into the pre-commit hook.
- Narrowed a bare `except` in `reindex.py`, fixed a leaked file handle, made `sed -i` portable, quoted an unquoted expansion.

**Fixed — security standards:**

- **OWASP A01 (broken access control) was absent entirely.** Roles were covered; object-level ownership was not. Added `access-control.md`.
- Added `untrusted-input.md` (SSRF, uploads, deserialization, traversal), `secrets-management.md`, `data-protection.md`, `supply-chain.md`.
- `auth.md` promised revocable refresh tokens and implemented none — added token-version and denylist mechanisms to the boilerplate; dropped `python-jose` (unmaintained, CVE-2024-33663/33664) for PyJWT; added claim pinning, lockout, anti-enumeration, MFA.
- Replaced the Next.js in-memory rate limiter, which never evicted entries and was per-instance, with a Redis-backed one.
- Added the full security header set, multi-tenant RLS mandate, idempotency keys, log redaction deny-list, correlation-id propagation.

**Fixed — security as a pipeline gate:**

- Added a mandatory *Security & Data Constraints* elicitation stage with abuse cases (`AC.xx`) traced through the existing zigzag validation.
- Added `meta/threat-model.md` and its template; made `SECURITY.md` and `THREAT-MODEL.md` mandatory on a deterministic condition rather than the architect's judgment.
- Added a literal scanner block to `/audit`; CRITICAL or HIGH now fails the audit.

**Fixed — consistency:**

- `brownfield-standardize.md` referenced a nonexistent `agents/intake-agent.md`; `index.md` named agent files that do not exist; the resolver's tag table was split in two by a stray blank line; `python3` replaced with `uv run`; resolver cap raised from 6 to 10 with security ranked first and an always-load floor for route handlers.
- Python floor unified to 3.12 across four files that disagreed (3.11 / 3.14 / 3.11). Base images pinned to minor tags with digest comments; `ghcr.io/astral-sh/uv:latest` pinned.

**Accepted:** none this cycle.

**Carried (MEDIUM):**

- No accessibility convention for frontends.
- No performance-budget convention or regression gate.
- No migration/rollback safety convention beyond forward-only numbering.

**False positives — did not survive verification, recorded because they will recur:**

- "`Retry-After` calculation is wrong" — it was correct.
- "Go JWT middleware allows algorithm confusion" — it already checked the signing method; strengthened to `WithValidMethods` anyway.
- "Python `jwt.decode` omits `algorithms=`" — it was present.
- "Go `AppError` lacks `Unwrap()`" — it was present. Python and TypeScript did drop cause, and that was fixed.

**Posture change:** OWASP A01 and A10 moved from uncovered to enforced. A04 moved from absent to enforced via threat modeling. Security moved from an optional document to a pipeline gate. The engine's central quality gate moved from broken to verified working.
