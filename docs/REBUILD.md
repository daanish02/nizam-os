# Nizam OS — Ground-Up Rebuild

**Audience:** a fresh Claude Code session on a freshly reinstalled VPS. You have no memory of the old system. Read this whole doc before touching anything. It is self-contained — do not go looking at any old repo, old `~/.hermes`, or old database. Everything you need is here or in `docs/specs/` (written fresh alongside this doc, read those too before Phase 4).

**Audience for the human:** Danish. You reinstall the OS, then hand this doc to Claude Code.

## Why this doc exists

The old nizam-os grew organically: business agents got bolted on then ripped out, docs got rewritten twice and disagreed with each other and with the code, secrets leaked into a config file, the DB schema drifted from the code, and a live symlink farm meant every edit touched running agents. Untangling it in place was slower and riskier than starting clean. This doc is the target architecture only — no history, no bug carried forward, no "why does this exist" archaeology.

**Principle for the rebuild: build correct the first time, small vertical slices, verify each slice end-to-end before starting the next.** Never leave a slice half-done between sessions.

## What Nizam OS is

A personal AI operating system for one person (Danish), running on one VPS. A small set of named AI agents (Hermes profiles) live in a private Discord server and are the only interface — no web UI, no mobile app. Each agent has a role, a memory, and a scoped set of tools reaching into shared backend services over MCP. LLM calls route through a local LiteLLM proxy to OpenRouter (DeepSeek models). Data lives in Postgres; long-form knowledge lives as Markdown files in a separate vault repo (`~/nizam-vault`).

**Scope: personal only.** No business agents, no CRM, no client work, no "Arc Systems". If you find any reference to business domains, agents named Raha/Hala/Omar/Reem/Mira, or channels like `#cfo-office`, that reference is a leftover from the old system's docs — ignore it, do not build it.

**Cycle 1 domains** (build these): knowledge (capture/search a personal vault) and personal finance + exact arithmetic. **Cycle 2, deferred:** tasks/habits/journal, investment review. Do not build cycle 2 unless told to.

## Infra facts (fixed, don't relitigate)

- VPS: Hostinger, 2 vCPU, 7.8 GB RAM, no swap, ~96 GB disk. Budget accordingly — this is not a scale-out system, it's one small box.
- OS: Ubuntu 24.04 LTS.
- Owner's local timezone: UTC+4.
- LLM models: DeepSeek via OpenRouter (`deepseek/deepseek-v4-flash` or newer DeepSeek model available at build time — check OpenRouter's catalog, don't hardcode an outdated one). **Keep DeepSeek models specifically** — this is a deliberate, standing preference, not a placeholder.
- Discord is the only interface. No Telegram, no voice/STT, no web UI.
- Repos, three, kept separate:
  - `~/nizam-dotfiles` — the machine: shell config, security hardening (ufw, fail2ban, Tailscale), host-level metrics, secrets for host-level things. Not covered by this doc in detail; assume it's set up separately or set up minimal host security first (see Phase 1).
  - `~/nizam-os` — this repo. The application: agents, services, configs, migrations, dashboards.
  - `~/nizam-vault` — the knowledge: Markdown notes with frontmatter, its own git repo with a private remote.

## Non-negotiable design decisions (carry these into every phase)

1. **One Python package, one daemon.** All domain logic lives in a single `nizam` package. One long-running process (`nizam-mcp`) serves every domain's MCP tools over HTTP on `127.0.0.1:8100`, one path per domain (`/knowledge/mcp`, `/finance/mcp`, ...). Per-agent bearer tokens map to which domains that agent may call. Not one process per domain, not stdio-per-session.
2. **Release-dir deploy, never edit live.** Live services run from `~/.local/share/nizam/current`, a symlink to a release directory under `~/.local/share/nizam/releases/<sha>`. A `scripts/deploy.sh` script builds a release and flips the symlink atomically. You develop in the git working tree; nothing live changes until you run `deploy.sh`. This means from the very first phase, get this pattern in place before anything is "live" — it costs nothing to do it right from day one on a fresh box, unlike last time where it was bolted on after the fact.
3. **Secrets never touch tracked files.** Real values live in `~/.config/nizam/*.env` (mode 600, outside the repo, outside Hermes's own dirs) or in age/sops-encrypted `secrets/*.env.enc` in the repo. Config files (`agents/*/config.yaml`, systemd units) reference `${VAR}` placeholders only. Verify a secrets manager pattern works (Hermes resolves `${VAR}` in its `mcp_servers.*.env` block from the profile's own `.env` — confirm this still holds in the Hermes version you install, don't assume) before wiring real credentials through it.
4. **Hermes owns agent-mutable state.** Memories, skills, and pending-approval files for each profile live as real files under `~/.hermes/profiles/<name>/`, never symlinked from the repo. The repo holds only what a human authors: `SOUL.md`, `AGENTS.md`, `config.yaml` templates. A nightly job backs up memories/skills; nothing more.
5. **Migrations are the only source of truth for schema.** No committed `pg_dump` schema file. `migrations/NNN_description.sql`, forward-only, applied with `dbmate` (or an equivalent simple migration tool — pick one and stick with it).
6. **Errors are typed, never silently caught-and-retried on a poisoned connection.** A specific bug in the old system: a search function caught a query exception and retried a *different* query on the *same* Postgres connection/transaction — but Postgres aborts the whole transaction on any statement error, so every later statement failed with "current transaction is aborted" until the connection was replaced. Rule for this rebuild: **any exception handler that catches a DB error and does something else on the same connection must roll back first**, or better, use `psycopg`'s autocommit mode for read-only queries, or open a fresh connection/savepoint per fallback attempt. Write a test that exercises exactly this fallback path (a search where the primary query intentionally errors) before trusting any retry-on-same-connection code.
7. **Docs before code, one doc set, no duplicates.** Doc tiers, in order, each depending only on the one above: `VISION.md` → `SRS.md` → `ARCHITECTURE.md` (+ `SCHEMAS.md`, `SECURITY.md`, `SCAFFOLD.md`, `RUNBOOK.md`, `TESTING.md`, `ROADMAP.md` as needed) → ADRs for individual decisions → `docs/specs/NNN-<domain>.md` per domain → `docs/plan.toml` tickets → code. Never write two docs that say the same thing — if ARCHITECTURE and a spec would both describe the same interface, the spec owns it and ARCHITECTURE references it. This is a deliberately lighter version of the Feanor methodology (`skills/feanor/` if present in your environment — read `skills/feanor/docs/OVERVIEW.md` for the philosophy, but skip qa-branch/PR-review/Docker/ADR-blocks-everything ceremony; this is a one-person project).
8. **Never commit for the user.** After each phase, stop and tell the human what changed and that it's ready to commit. They commit manually, every time, no exceptions.
9. **LLM outage degrades, never crashes a write.** If LiteLLM is unreachable, a tool that needs embeddings/classification should still save the deterministic part of the write (e.g. the note text) and mark the derived part (embedding, classification) as pending, retried by a background job. A tool should never lose user input because an LLM call failed.
10. **The admin agent's autonomy is bounded and written down explicitly.** It may restart a short explicit allowlist of Nizam's own systemd units (never Postgres, Redis, or anything host-level), at most one retry, then it must escalate to the human via Discord. Write this in its `AGENTS.md` and enforce it via a narrow sudoers file, not by the LLM's judgment alone.

## Target repo layout

```
nizam-os/
├── README.md
├── CLAUDE.md               # rules for coding agents working in this repo
├── pyproject.toml          # single package `nizam`, uv-managed
├── uv.lock
├── nizam/
│   ├── __init__.py
│   ├── __main__.py         # `python -m nizam serve` / `python -m nizam jobs <name>`
│   ├── config.py           # every env var read once at import; missing required var -> fail fast at startup
│   ├── core/                # domain-agnostic — imports no domain package
│   │   ├── db.py            # async Postgres connection pool
│   │   ├── log.py           # one get_logger() factory, JSON to stderr
│   │   ├── errors.py        # AppError base + typed subclasses
│   │   ├── audit.py         # append-only audit log writer
│   │   ├── llm.py           # LiteLLM HTTP client (chat + embeddings); raises a typed UpstreamError
│   │   ├── auth.py          # bearer token -> agent name -> allowed domains
│   │   ├── sql.py           # loads .sql files from a domain's queries/ dir
│   │   └── http.py          # the single daemon's ASGI app: mounts each domain + GET /health
│   ├── knowledge/           # cycle 1
│   │   ├── tools.py          # MCP tool definitions (thin)
│   │   ├── service.py        # business logic
│   │   ├── repo.py           # DB access
│   │   ├── vault.py          # reads/writes Markdown files in the vault repo
│   │   ├── embed.py          # calls core.llm for embeddings, degrades on failure
│   │   ├── areas.py          # controlled vocabulary for classification
│   │   ├── sources/           # web.py, youtube.py — ingestion adapters
│   │   └── queries/*.sql
│   ├── finance/              # cycle 1
│   │   ├── tools.py service.py repo.py queries/*.sql
│   ├── calc/                 # cycle 1 — pure exact arithmetic, no I/O, spec-driven
│   └── jobs/                 # retry_embeddings.py, backup_db.py — invoked by systemd timers
├── tests/                    # mirrors nizam/, pytest, DB tests marked `slow`
├── migrations/               # 001_..sql, 002_..sql, forward-only
├── agents/
│   ├── admin/{SOUL.md,AGENTS.md,config.yaml}      # Nazim
│   ├── curator/{SOUL.md,AGENTS.md,config.yaml}    # Noor
│   └── assistant/{SOUL.md,AGENTS.md,config.yaml}  # Ayah (finance) — cycle 1, added once knowledge is stable
├── ops/                       # what systemd runs
│   ├── metrics/               # small textfile-exporter scripts for Prometheus
│   └── skillgate/             # the pending-skill-approval watcher, if you keep this Hermes feature
├── deploy/                    # what deploy.sh installs onto the host
│   ├── manifest.txt            # "kind src dst" lines — see deploy.sh below
│   ├── systemd/system/*.service|*.timer
│   ├── systemd/user/*.service
│   ├── litellm.yaml  promtail.yaml  logrotate.nizam  redis.conf
│   ├── sudoers/admin-nizam
│   └── grafana/*.json
├── scripts/
│   ├── check.sh               # ruff check + ruff format --check + pytest -m "not slow"
│   ├── deploy.sh               # build a release, flip `current`, apply manifest, restart changed units
│   ├── secrets.sh              # encrypt|decrypt|check, wraps sops+age
│   ├── db.sh                   # migration tool wrapper
│   └── bootstrap.sh            # fresh-host install, idempotent
├── secrets/                    # *.env.enc + *.env.example tracked; plaintext .env gitignored, never committed
└── docs/
    ├── VISION.md  SRS.md  ARCHITECTURE.md  SCAFFOLD.md  SCHEMAS.md
    ├── SECURITY.md  RUNBOOK.md  TESTING.md  ROADMAP.md
    ├── adrs/{index.md, ADR-NNN-slug.md}
    └── specs/{index.md, 001-knowledge.md, 002-finance.md, 003-calc.md, 004-agent-runtime.md}
```

Runtime paths outside the repo, created by `deploy.sh` / bootstrap:
- `~/.local/share/nizam/{releases/<sha>/, current -> releases/<sha>}`
- `~/.config/nizam/*.env` (mode 700 dir, 600 files)
- `~/.local/state/nizam/{logs/, backups/}`

## Phases

Each phase ends with: tests passing, a short verification against the real running system, and a stop for the human to commit. Do not start the next phase until the human has confirmed the commit.

### Phase 1 — Host bootstrap

Goal: a bare Ubuntu 24.04 box with the pieces this system needs, and basic security, nothing Nizam-specific installed as "live" yet.

1. Base packages: `git`, `curl`, `build-essential`, `age`, `sops`, `postgresql-16` (+ `pgvector` extension; skip ParadeDB/`pg_search` unless you specifically re-decide to use BM25 hybrid search — the old system's ParadeDB integration was the direct cause of the transaction-abort bug in principle #6, so if you do use it, write the fallback-path test in principle #6 before trusting it), `redis-server`, `prometheus`, `prometheus-node-exporter`, `loki` + `promtail`, `grafana`.
2. Install `uv` (Python package/venv manager) for the `vazir` user.
3. Basic host security (or confirm `nizam-dotfiles` handles this): `ufw` (allow only SSH + Tailscale), `fail2ban`, Tailscale for private access to Grafana. Bind everything Nizam-specific to `127.0.0.1` only — nothing but SSH/Tailscale should be reachable from the public internet.
4. Create the age keypair for secrets (`age-keygen`), store the private key at `secrets/nizam-age-key.txt` outside git (gitignored), never commit it.
5. Clone this repo to `~/nizam-os`. Create `~/nizam-vault` as a fresh git repo with a private remote (GitHub or similar) that Danish sets up.
6. Verify: `psql`, `redis-cli`, `prometheus`, `grafana-server` all reachable locally. Nothing Nizam-specific is running yet. **Stop, human commits nothing yet** (this phase has no repo changes beyond maybe a bootstrap script) — but do commit `scripts/bootstrap.sh` documenting what you just did by hand, so it's reproducible.

### Phase 2 — Database

1. Design `migrations/001_init.sql`: `audit` schema with an append-only `audit.log` table (actor, action, target, payload, timestamp). No LiteLLM tables committed here — LiteLLM manages its own schema, let it create its own tables in its own `litellm` schema on first run, don't hand-write them.
2. Set up one Postgres role per domain service (`svc_knowledge`, `svc_finance`, ...), least-privilege grants on their own schema only. Generate passwords with `openssl rand -hex 24`, store immediately in the right `secrets/*.env`, never paste a generated secret into a chat/log/commit.
3. `scripts/db.sh`: wraps your chosen migration tool (`dbmate` is a fine default — simple, forward-only, one binary). `db.sh migrate`, `db.sh status`, `db.sh new <name>`.
4. Verify: `scripts/db.sh status` shows `001_init` applied. Both a raw `psql` connection as each service role and a connection as your admin role work.
5. **Stop, human commits.**

### Phase 3 — LiteLLM + secrets pipeline

1. `deploy/litellm.yaml`: proxy config pointing at OpenRouter, current DeepSeek model(s), Redis for caching, Postgres (LiteLLM's own schema) for spend tracking. Master key and OpenRouter key come from `~/.config/nizam/nizam-os.env` via `EnvironmentFile=` in its systemd unit — never inline in the yaml.
2. `deploy/systemd/system/litellm-proxy.service`, bound to `127.0.0.1:4000`.
3. `scripts/secrets.sh`: `encrypt`/`decrypt`/`check` wrapping sops+age. `check` fails if any `secrets/*.env` is newer than its `.enc` counterpart (i.e., un-encrypted changes pending) — wire this as a pre-commit hook later, but write the script now.
4. Verify: `curl 127.0.0.1:4000/health/liveliness` returns healthy, and a manual chat completion through the proxy with a virtual key succeeds.
5. **Stop, human commits.**

### Phase 4 — `nizam` package skeleton + knowledge domain

Read `docs/specs/001-knowledge.md` first — write it before this phase if it doesn't exist yet, following principle #7. It should specify: tool names and parameters, the vault file format (frontmatter fields, filename convention), the classification taxonomy (a fixed list of "areas", multi-valued per note — this replaced a broken single-`domain` model in the old system, keep it multi-valued from the start), search algorithm and its error/fallback behavior (respecting principle #6), and what happens when the LLM is unreachable during ingest (principle #9).

1. `nizam/core/*` per the layout above. `config.py` reads `LITELLM_BASE_URL`, `LITELLM_API_KEY`, `EMBED_MODEL`, `KNOWLEDGE_DSN`, `REDIS_URL`, `VAULT_ROOT` — fail fast on missing required ones.
2. `nizam/knowledge/*`: vault read/write, embedding via `core.llm` (wrapped so an outage returns a typed error, not a crash), Postgres-backed index + search. Prefer a **simpler search than BM25+ParadeDB hybrid fusion** unless you have a specific reason to want it — pgvector cosine similarity alone, or pgvector + Postgres's built-in `tsvector`/`ts_rank` (not ParadeDB's `@@@` operator), is enough for a personal vault and avoids the exact bug class in principle #6. If you do want hybrid search, implement it with two separate connections (or two separate transactions) for the two query types, never one connection retried across a caught exception.
3. Tools via FastMCP (or the current equivalent — check what's current), served through `core/http.py` at `/knowledge/mcp`.
4. Tests: vault round-trip, area-classification validation, the LLM-outage-degrades-to-pending path, and — required — a test that deliberately makes the primary search query fail and asserts the fallback still returns correct results rather than an aborted-transaction error.
5. `scripts/check.sh` passes.
6. **Do not wire this into Hermes yet.** Verify it standalone first: run the daemon locally, hit `/knowledge/mcp` with a raw MCP client or `curl`, confirm search/add/ingest work and the outage test passes against a real (temporarily stopped) LiteLLM.
7. **Stop, human commits.**

### Phase 5 — Hermes + Discord + the admin and curator agents

1. Install Hermes fresh. Create the Discord server, bot applications, and channels you actually want (personal-only categories — no business channels). Keep names simple: e.g. one "Personal" category with channels per domain (`#knowledge`, `#finance`, `#alerts`, `#logs`).
2. Create two profiles: `admin` (Nazim) and `curator` (Noor). Write `agents/admin/{SOUL.md,AGENTS.md,config.yaml}` and `agents/curator/{...}` from scratch — describe each agent's actual role, its tool scope, and (for admin) the exact restart allowlist and escalation rule from principle #10. Don't copy old SOUL/AGENTS text; the old ones had accumulated contradictions (e.g., claiming an unattended-restart authority that a security doc explicitly forbade).
3. Wire the curator's `config.yaml` to the `nizam-mcp` daemon over HTTP (`url: http://127.0.0.1:8100/knowledge/mcp`, bearer token from its `.env`) — not stdio, not a spawned subprocess. This is the deploy target from day one, skipping the stdio-then-migrate step the old system took.
4. `scripts/deploy.sh`: builds `~/.local/share/nizam/releases/<sha>` from a git archive, `uv sync`, flips `current`, applies `deploy/manifest.txt` (symlinks units into `/etc/systemd/system` and `~/.config/systemd/user`, links agent `config.yaml`/`SOUL.md`/`AGENTS.md` into `~/.hermes/profiles/<name>/`, copies anything needing root like promtail/logrotate/sudoers configs), reloads daemons, restarts only units whose content changed. Support `--dry-run` and `--rollback`.
5. Verify end to end over real Discord: ask Noor to search, add a note, ingest a URL. Ask Nazim for a status report. Stop LiteLLM, confirm a knowledge write degrades to pending instead of erroring, restart LiteLLM, confirm a background job clears the pending state.
6. **Stop, human commits.**

### Phase 6 — Observability + backups

1. `ops/metrics/*`: small scripts writing Prometheus textfile-collector metrics for service health, LLM spend, tool-call counts — whatever you actually want to see on a dashboard. Keep it minimal; don't rebuild the old system's full metrics surface unless asked.
2. Promtail ships `nizam-mcp` and Hermes gateway logs to Loki; a couple of Grafana dashboards (services up/down, LLM spend, recent errors) imported from `deploy/grafana/*.json`.
3. Backups: a nightly systemd timer running `nizam/jobs/backup_db.py` (pg_dump, rotate 14 daily/8 weekly, `~/.local/state/nizam/backups/`) and a vault auto-commit+push job. Test a restore into a scratch database before trusting it.
4. **Stop, human commits.**

### Phase 7 — Finance + calc + the assistant agent (Ayah)

Before this phase, get explicit answers from Danish (do not guess): whether zakat correctness is treated as strict/obligation-grade or best-effort, which currencies and accounts exist, the FX rate source if multi-currency, the rounding rule for money math, and whether bank CSV import is wanted now.

1. Write `docs/specs/002-finance.md` and `docs/specs/003-calc.md` first.
2. `nizam/calc/`: pure, exactly-specified arithmetic (integer minor units or `Decimal`, one documented rounding rule), exhaustively unit tested — no I/O in this package at all.
3. `migrations/00N_finance.sql`: accounts, transactions, categories, budgets. Balances are **derived from the transaction ledger** (sum of transactions, reconciled against periodic statement entries), never a separately-maintained mutable balance field that can drift from its own history.
4. `nizam/finance/`: tools per the spec. Mutating tools go through whatever approval gate principle #10-style design you set for agent actions in general (write this once in `docs/specs/004-agent-runtime.md`, reference it from every domain spec rather than repeating it).
5. New Hermes profile `assistant` (Ayah), scoped to `finance` + `calc` + read-only `knowledge`, its own Discord bot and channels, its own LiteLLM virtual key.
6. Verify over Discord: record a transaction, ask for a position report, confirm it matches hand-computed arithmetic.
7. **Stop, human commits.**

## Verification checklist (re-run after every phase from 4 onward)

- `bash scripts/check.sh` exits 0.
- `scripts/db.sh status` shows every migration applied.
- `scripts/deploy.sh --dry-run` shows no drift.
- `systemctl --failed` and `systemctl --user --failed` are both empty.
- `curl 127.0.0.1:8100/health` returns 200; a request with no/wrong bearer token is rejected; a token scoped to one domain can't call another domain's tools.
- The actual Discord agents respond correctly to a real message, not just a unit test.
- `git ls-files | grep -E '\.env$|cookies'` returns nothing, ever.

## What NOT to do

- Don't symlink anything mutable (memories, skills, pending approvals, or the live systemd units) directly into the git working tree. That was the single biggest source of live breakage last time.
- Don't put a real secret value in a config file, a commit, a log line, or this doc.
- Don't build business-domain anything.
- Don't build cycle-2 domains (tasks/habits/journal, investment) before cycle 1 is verified stable in daily use.
- Don't run `git commit` yourself — always stop and let Danish commit.
- Don't catch a database exception and issue another query on the same connection without a rollback first.
- Don't invent facts about integrations, ports, or model names — if unsure, ask Danish rather than guessing, especially for anything security- or money-related.
