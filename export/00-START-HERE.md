# Nizam OS — Ground-Up Rebuild

**Audience:** a fresh Claude Code session on a freshly reinstalled VPS. You
have no memory of the old system. Read this whole doc before touching
anything. It is self-contained. Do not go looking for any old repo, old
`~/.hermes` or old database — they no longer exist.

**Audience for the human:** Danish. You reinstall the OS, run the
`nizam-dotfiles` machine setup, then hand this doc to Claude Code.

## Where things live

- **This export folder is committed at the root of the new `nizam-os` repo as
  `export/`**, which puts this file at `~/nizam-os/export/00-START-HERE.md`.
  The `nizam-dotfiles` guide links to exactly that path. `export/` is
  read-only reference material. Once cycle 1 is live, it can be deleted in one
  commit; git history keeps it.
- **The finished doc set is in `export/docs-ready/`.** Do not re-derive or
  rewrite these documents. They already resolve every open question from the
  owner interrogation, and re-litigating them wastes the owner's time. Extend
  them instead: new ADRs, new specs for cycle 2. The set contains:
  - VISION, SRS, ARCHITECTURE, SCAFFOLD, SCHEMAS, SECURITY, RUNBOOK, TESTING,
    ROADMAP
  - four cycle-1 specs
  - seven ADRs
  - a `CLAUDE.md` for the new repo root
  - a Feanor `plan.toml` with every ticket for Phases 1–7 (51 tickets,
    292 named tests)
- **Your first action, before Phase 1:**
  - copy `export/docs-ready/*` into `docs/` — this includes `plan.toml`,
    which lands at `docs/plan.toml`
  - move `docs/CLAUDE.md` to the repo root
  - read `docs/SRS.md`, `docs/ARCHITECTURE.md` and `docs/specs/004-agent-runtime.md`

## Why this doc exists

The old nizam-os grew organically:

- Business agents were bolted on, then ripped out.
- The docs were rewritten twice and disagreed with each other and with the
  code.
- Secrets leaked into a config file.
- The DB schema drifted from the code.
- A live symlink farm meant every edit touched running agents.

Untangling that in place was slower and riskier than starting clean.
`export/BUGS-AND-GOTCHAS.md` lists the ten concrete mistakes. Read it.

**Principle: build correct the first time, in small vertical slices, and verify
each slice end-to-end before starting the next.** Never leave a slice half-done
between sessions.

## What Nizam OS is

A personal AI operating system for one person (Danish), running on one VPS.

- A small set of named AI agents (Hermes profiles) live in a private Discord
  server. That server is the only interface.
- Each agent has a role, a memory, and scoped tools that reach backend services
  over MCP.
- LLM calls route through a local LiteLLM proxy to OpenRouter, using DeepSeek
  models.
- Structured data lives in Postgres. Long-form knowledge lives as Markdown in a
  separate vault repo (`~/nizam-vault`).

**Scope: personal only.** If you see business agents
(Raha/Hala/Omar/Reem/Mira), CRM, "Arc Systems" or `#cfo-office`-style channels
in any reference material, they are leftovers. Ignore them.

**Cycle 1 domains:**
- **Knowledge** — Noor.
- **Personal finance + exact arithmetic** — Ayah.
- **Nazim** is the admin agent: bounded restarts and status reports.

**Cycle 2, deferred — do not build:** tasks/habits/goals/journal,
self-maintenance beyond Nazim's restart allowlist, and investment review.

## Infra facts (fixed — don't relitigate)

- **Box.** Hostinger VPS: 2 vCPU, 7.8 GB RAM, no swap, ~96 GB disk. One small
  box — budget accordingly.
- **OS.** Ubuntu 24.04 LTS. The owner is in UTC+4; store everything in UTC.
- **Models.** DeepSeek via OpenRouter (`deepseek/deepseek-v4-flash`, or the
  newest DeepSeek in OpenRouter's catalog at build time). **Keep DeepSeek** —
  a standing owner preference.
- **Interface.** Discord only. No Telegram, no voice, no web UI.
- **Three repos:**

  | Repo | Owns |
  | :--- | :--- |
  | `~/nizam-dotfiles` | The machine: SSH hardening, UFW, fail2ban, unattended-upgrades, Tailscale, zsh, and the Prometheus/node-exporter/Grafana/Loki/Promtail install with host metrics (`metrics-*` units). **Already exists and is reused.** Its `docs/RUNBOOK.md` → Machine setup runs before this doc, and ends by pointing here. |
  | `~/nizam-os` | This repo. The application. |
  | `~/nizam-vault` | Knowledge notes. A fresh, empty git repo with a private remote. |

## Non-negotiable design decisions

The why behind each is in `docs/adrs/`.

1. **One Python package, one daemon (ADR-001).**
   - The `nizam` package's `nizam-mcp` process serves every domain over
     streamable HTTP on `127.0.0.1:8100`, at `/knowledge/mcp`, `/finance/mcp`
     and `/calc/mcp`.
   - Per-agent bearer tokens map to allowed domains.
   - Not one process per domain, and not stdio.
2. **Release-directory deploy — never edit live (ADR-002).**
   - Live services run from `~/.local/share/nizam/current`.
   - `scripts/deploy.sh` builds a release from a committed git ref and flips
     `current` atomically.
   - It is written in **Phase 3, before the first live unit exists**, and every
     later phase deploys through it.
3. **Secrets never touch tracked files.**
   - Real values live in `~/.config/nizam/*.env` (directory mode 700, files
     mode 600). Encrypted copies live in `secrets/*.env.enc`.
   - The age private key is at `~/.config/sops/age/keys.txt` — sops's default
     path, never inside the repo. The public key goes in `.sops.yaml`.
   - **The owner keeps an offline copy of the age key.**
   - Config files use `${VAR}` only.
   - Before wiring real secrets through Hermes, confirm the installed version
     still resolves `${VAR}` in `mcp_servers.*.headers` from the profile
     `.env`. Check `tools/mcp_tool.py` `_interpolate_env_vars`; don't assume.
4. **Hermes owns agent-mutable state.**
   - Memories, skills and sessions are real files under
     `~/.hermes/profiles/<name>/`, never symlinked from the repo.
   - The repo holds only authored files: `SOUL.md`, `AGENTS.md`, `config.yaml`,
     and the `nizam-approval` plugin.
   - Memories and skills are backed up nightly.
5. **Migrations are the only schema truth.**
   - `migrations/NNN_*.sql`, forward-only, applied with dbmate.
   - `DBMATE_NO_DUMP_SCHEMA=true` — no committed schema dump.
6. **Never retry a query on a poisoned connection.** Any DB error handler that
   then queries again must roll back first, use a savepoint, or use a fresh
   connection. Test the fallback path explicitly (`export/BUGS-AND-GOTCHAS.md`
   #1).
7. **Docs before code, one doc set, no duplicates.**
   - Tiers: VISION → SRS → ARCHITECTURE (+ SCAFFOLD, SCHEMAS, SECURITY,
     RUNBOOK, TESTING, ROADMAP) → ADRs → specs → `plan.toml` → code.
   - If two docs would say the same thing, the lower tier owns it and the
     higher one references it.
   - This is Feanor-lite: its conventions are in `export/feanor-conventions/`.
     Skip the qa branch, PR review, Docker and ADR-blocks-everything ceremony —
     this is a one-person project.
8. **Never commit for the user.** After each phase, stop, summarise what
   changed, and say it's ready to commit. Danish commits manually, every time.
9. **An LLM outage degrades; it never loses a write (ADR-006).**
   - Deterministic parts save.
   - Embedding and classification go `pending` and are retried by a timer.
   - A purely-reasoning request fails explicitly.
10. **Nazim's autonomy is bounded and enforced below the LLM.** Allowed: one
    restart of `litellm-proxy`, `nizam-mcp`, `hermes-gateway-curator` or
    `hermes-gateway-assistant`, then escalate. System units are enforced by
    `deploy/sudoers/admin-nizam`; user units (which need no sudo) by the Hermes
    `command_allowlist`. See `docs/SECURITY.md` — both are required.
11. **Approval is enforced below the LLM (ADR-007).**
    - Every write is two-pass: a draft returns a signed `draft_token`, and the
      approved call must present it together with the exact payload.
    - The Hermes `nizam-approval` plugin holds every approved write for the
      owner's Discord `/approve`.
    - The draft is valid 24h; the Discord prompt waits 30 minutes.
    - Spec: `docs/specs/004-agent-runtime.md` "Enforcement mechanism".

## Target repo layout

The authoritative copy is `docs/SCAFFOLD.md`, reproduced here for orientation:

```
nizam-os/
├── README.md  CLAUDE.md  pyproject.toml  uv.lock  .sops.yaml  .gitignore  .pre-commit-config.yaml
├── nizam/
│   ├── __main__.py         # python -m nizam serve | jobs <name>
│   ├── config.py           # all env read once; missing required -> fail at startup
│   ├── core/               # db, log, errors, audit, llm, auth, approval, sql, http — imports no domain
│   ├── knowledge/          # tools, service, repo, vault, embed, areas, sources/{web,youtube}, queries/
│   ├── finance/            # tools, service, repo, queries/            (Phase 7)
│   ├── calc/               # pure arithmetic library + read-only MCP tools (Phase 7)
│   └── jobs/               # retry_embeddings, backup
├── tests/                  # mirrors nizam/
├── migrations/             # 001_audit.sql, 002_knowledge.sql, 003_finance.sql, ...
├── agents/
│   ├── admin/ curator/ assistant/     # SOUL.md, AGENTS.md, config.yaml each
│   └── plugins/nizam-approval/        # Hermes pre_tool_call approval hook
├── ops/metrics/            # app textfile-metric scripts (run by nizam-metrics-* timers)
├── deploy/
│   ├── manifest.txt
│   ├── systemd/system/     # litellm-proxy.service, nizam-*.service|timer
│   ├── litellm.yaml  promtail-nizam.yaml  logrotate.nizam
│   ├── sudoers/admin-nizam
│   └── grafana/*.json
├── scripts/                # check.sh deploy.sh secrets.sh db.sh bootstrap.sh
├── secrets/                # *.env.enc + *.env.example only
├── docs/                   # from export/docs-ready/
└── export/                 # this folder — read-only reference
```

**Runtime paths outside the repo:**
- `~/.local/share/nizam/{releases/<sha>/, current}`
- `~/.config/nizam/*.env`
- `~/.config/sops/age/keys.txt`
- `~/.local/state/nizam/{logs,backups}/`

## Phases

**The tickets in `docs/plan.toml` are authoritative.** Phase N is exactly
tickets `TICK-N01` onward. The prose below gives context and live checks, but
work item by item from the plan:

```
plan.py next → write the named tests (they fail) → write code → plan.py verify → plan.py done
```

Run `plan.py` as
`uv run --with tomlkit --with rich python export/feanor-conventions/scripts/plan.py`.
Testing conventions, fixtures and the coverage gate are in `docs/TESTING.md`.

Each phase ends with:
- `bash scripts/check.sh` green (once it exists)
- a real check against the running system
- a stop for Danish to commit

Don't start the next phase until he confirms.

### Phase 0 — Host layer (`nizam-dotfiles`, done by the human first)

Danish follows `~/nizam-dotfiles/docs/RUNBOOK.md` → Machine setup on the fresh
box. That covers:
- root bootstrap and the `vazir` user
- SSH hardening, UFW, fail2ban, unattended-upgrades
- the Prometheus/Grafana/Loki/Promtail install, host metrics, and `tailscale up`
- deleting public SSH once Tailscale works

**Check** before starting Phase 1:
- `systemctl is-active prometheus grafana-server loki promtail fail2ban` shows
  all active
- `tailscale status` shows online

If anything is missing, stop and tell Danish — don't reinstall host-layer
pieces from this repo.

### Phase 1 — Secrets pipeline + app dependencies

Tickets TICK-101 to TICK-106. Order matters: nothing secret may exist before
it is ignored and encryptable.

0. TICK-101: the Python project skeleton, `scripts/check.sh` (fast and
   `--all` modes) and `scripts/coverage_gate.py`. This comes first so every
   later ticket, including the shell-script ones, is TDD from day one.
1. Write `.gitignore` first. At minimum it covers: `secrets/*.env` (keeping
   `!secrets/*.env.example`), `*.key`, `.venv/`, `__pycache__/`, the
   ruff/pytest caches, `.run/`, and `*cookies*`.
2. Generate the age key into `~/.config/sops/age/keys.txt` (mode 600) and write
   `.sops.yaml` with its public key. **Tell Danish to store an offline copy of
   the private key now.**
3. Write `scripts/secrets.sh`:
   - `encrypt <name>` and `decrypt <name>`
   - `install`: decrypt every `secrets/*.env.enc` into `~/.config/nizam/`
     (directory 700, files 600). `deploy.sh --sync-secrets` calls this later.
   - `check`: fails if any `.env` is newer than its `.enc`, or if any `.enc` is
     zero bytes

   Wire `check` and gitleaks into `.pre-commit-config.yaml`.
4. Create `secrets/nizam-os.env` with a generated `REDIS_PASSWORD`
   (`openssl rand -hex 24`). Placeholders for the LiteLLM master key and the
   OpenRouter key can be filled in during Phase 3 — Danish pastes the
   OpenRouter key himself. Then `scripts/secrets.sh encrypt nizam-os` and
   `scripts/secrets.sh install`.
5. `scripts/bootstrap.sh` — idempotent, re-runnable:
   - installs `postgresql-16`, `postgresql-16-pgvector` (**not** ParadeDB),
     `redis-server`, `age`, `sops`, `dbmate`, and `uv` for `vazir`
   - sets Redis `requirepass` from `~/.config/nizam/nizam-os.env`
   - binds Postgres and Redis to `127.0.0.1`
6. Initialise `~/nizam-vault` as an empty git repo. Danish adds the private
   remote.
7. **Check:**
   - `psql -h /var/run/postgresql -c 'select 1'` works
   - `redis-cli` with the password answers `PING`
   - `ss -tlnp` shows Postgres and Redis on `127.0.0.1` only
   - `scripts/secrets.sh check` passes
   - `git status` shows no plaintext `.env`
8. **Stop — Danish commits** (`.gitignore`, `.sops.yaml`, `secrets.sh`,
   pre-commit config, `secrets/nizam-os.env.enc` + `.example`, bootstrap,
   `docs/`, `CLAUDE.md`).

### Phase 2 — Database

1. Write `migrations/001_audit.sql`:
   - the `audit` schema and `audit.log` (row shape in spec 004)
   - a non-unique index on `approval_id`
   - roles `svc_knowledge` and `svc_finance`, each granted only `INSERT` and
     `SELECT` on `audit.log` — never `UPDATE` or `DELETE`
   - `svc_finance` is created now, with its schema grants added in Phase 7
2. Generate role passwords with `openssl rand -hex 24`. Write them straight into
   `secrets/nizam-mcp.env` as `KNOWLEDGE_DSN` and `FINANCE_DSN`. Then run
   `secrets.sh encrypt nizam-mcp` and `secrets.sh install`, and apply them with
   `ALTER ROLE`. Never echo a secret into chat or a log.
3. Write `scripts/db.sh`: a dbmate wrapper providing `migrate`, `status` and
   `new`, run with `DBMATE_MIGRATIONS_DIR=migrations DBMATE_NO_DUMP_SCHEMA=true`.
4. **Check:**
   - `scripts/db.sh status` shows 001 applied
   - connecting as `svc_knowledge` and trying `UPDATE audit.log` fails
5. **Stop — Danish commits.**

### Phase 3 — LiteLLM and `deploy.sh`

1. Fill in the LiteLLM master key (generate it) and the OpenRouter key (Danish
   pastes it) in `secrets/nizam-os.env`. Then `secrets.sh encrypt nizam-os` and
   `secrets.sh install`.
2. Write `scripts/deploy.sh`, per `docs/ARCHITECTURE.md` "Deploy model":
   - `git archive` → release directory → `uv sync --frozen --no-dev` → atomic
     flip of `current`
   - apply `deploy/manifest.txt`, then `daemon-reload` and restart only changed
     units
   - support `--dry-run`, `--rollback` and `--sync-secrets`

   It builds only from **committed** refs.
3. Write `deploy/litellm.yaml`:
   - OpenRouter with the current DeepSeek model, plus a DeepSeek-compatible
     embedding model
   - Redis cache
   - Postgres `litellm` schema for spend tracking
   - keys come from `EnvironmentFile=/home/vazir/.config/nizam/nizam-os.env`

   Also write `deploy/systemd/system/litellm-proxy.service`, bound to
   `127.0.0.1:4000`. **No inline `#` comments on directive lines**
   (`export/BUGS-AND-GOTCHAS.md` #5).
4. Create LiteLLM virtual keys, one each for: `nizam-mcp`, `admin`, `curator`
   and, later, `assistant`. The master key never leaves `nizam-os.env`.
5. **Check:**
   - after Danish commits the Phase 3 files: `scripts/deploy.sh --dry-run`,
     then `scripts/deploy.sh`
   - `curl 127.0.0.1:4000/health/liveliness`
   - a chat completion made with a virtual key succeeds
   - `scripts/deploy.sh --rollback`, then deploy again, both work
6. **Stop — Danish commits.**

### Phase 4 — `nizam` package + knowledge domain (standalone)

Execute the tickets in `docs/plan.toml`, using the Feanor `plan.py` (in
`export/feanor-conventions/scripts/`) with `next`, `verify` and `done`. Don't
invent parallel tickets. Specs to read first: `docs/specs/001-knowledge.md`
and `004-agent-runtime.md`.

The tickets (TICK-401 to TICK-420) cover:
- `config.py`
- `core/*`, including `approval.py`, `auth.py` and `http.py`
- `002_knowledge.sql`
- vault, areas, embed, repo, sources, service, tools
- the `python -m nizam serve` daemon
- the retry-embeddings and reindex jobs
- an end-to-end check

The project skeleton, `check.sh` and the coverage gate already exist from
TICK-101.

Rules the tickets encode — don't deviate:
- **Search** is Postgres `tsvector`/`ts_rank` plus pgvector cosine similarity,
  fused by Reciprocal Rank Fusion (spec 001). **No ParadeDB.** A failed query is
  never retried on the same transaction.
- **Writes** are two-pass with a signed `draft_token` (spec 004). A draft
  touches nothing.
- **Config** is exactly as listed in `docs/ARCHITECTURE.md`. `nizam-mcp` uses
  its own LiteLLM virtual key and does **not** use Redis.

**Check** — standalone, not yet wired into Hermes:
- run `python -m nizam serve` against real Postgres and LiteLLM
- use a raw MCP client with a test bearer token to draft, then approve, an
  `ingest_url` call
- confirm the note lands in the vault and the index
- stop LiteLLM → the next ingest saves with `embedding_status='pending'`
- start LiteLLM, run `python -m nizam jobs retry-embeddings` → the note becomes
  `done`

**Stop — Danish commits.**

### Phase 5 — Hermes, Discord, Nazim + Noor, go live

1. Discord (Danish does these by hand):
   - one server, category "Personal"
   - channels `#admin`, `#alerts`, `#logs`, `#knowledge`, `#finance`
   - bot applications for Nazim and Noor (Ayah comes in Phase 7)
2. Install Hermes fresh. Create profiles `admin` and `curator` with
   `hermes profile create`, and install their gateways with Hermes's own
   installer (they become user units).
3. Write `agents/admin/*` and `agents/curator/*` from scratch. Old SOUL and
   AGENTS text is tone reference only (`export/hermes-profiles-reference/`) —
   it contradicted the security docs.
   - Every `config.yaml` sets `approvals: {mode: manual, gateway_timeout: 1800,
     cron_mode: deny}`.
   - Admin additionally sets the `command_allowlist` from `docs/SECURITY.md`.
   - Curator gets `mcp_servers.knowledge` with
     `url: http://127.0.0.1:8100/knowledge/mcp` and
     `headers: {Authorization: "Bearer ${NIZAM_MCP_TOKEN}"}`.
4. Write `agents/plugins/nizam-approval/`: the Hermes `pre_tool_call` plugin
   (spec 004 Layer 1). Test it against a write tool with a fake approval
   callback, and add test E-30 (the plugin's write-tool list equals the tools
   `nizam-mcp` declares as write-class).
5. Add to `deploy/`:
   - `systemd/system/nizam-mcp.service` (`User=vazir`,
     `ExecStart=/home/vazir/.local/share/nizam/current/.venv/bin/python -m nizam serve`,
     `EnvironmentFile=/home/vazir/.config/nizam/nizam-mcp.env`,
     `Restart=on-failure`, `MemoryMax=512M`)
   - `nizam-retry-embeddings.{service,timer}` (every 10 minutes)
   - `sudoers/admin-nizam`
   - manifest lines for all of these, plus the Hermes profile links and the
     plugin
6. Deploy after Danish commits.
7. **Check over real Discord:**
   - Noor: search; add a note (see the `/approve` prompt, approve it); ingest a
     URL; deny one draft and confirm nothing was written.
   - Nazim: status report. Ask it to restart Postgres — **it must refuse**.
   - Wrong-token and cross-scope calls to `nizam-mcp` return 401 and 403.
8. **Stop — Danish commits.**

### Phase 6 — Observability + backups

1. `ops/metrics/*` plus `nizam-metrics-*` timers writing textfile metrics for:
   - service up/down for `litellm-proxy`, `nizam-mcp` and the gateways
   - LLM spend per virtual key
   - tool calls per agent
   - pending embeddings
   - `nizam_backup_last_success_timestamp`

   Keep it minimal.
2. `deploy/promtail-nizam.yaml`: ship `nizam-mcp` and gateway journald logs to
   Loki. Import `deploy/grafana/*.json` dashboards for services, spend and
   errors, using the profile names `admin|curator|assistant`, not character
   names (`export/BUGS-AND-GOTCHAS.md` #9).
3. `nizam/jobs/backup.py` plus `nizam-backup.{service,timer}` at 03:30. It:
   - runs `pg_dump -Fc nizam --exclude-schema=litellm`
   - tars `~/.hermes/profiles/*/{memories,skills}`
   - commits and pushes `~/nizam-vault`
   - rotates to 14 daily and 8 weekly copies in `~/.local/state/nizam/backups/`
4. **Check:**
   - restore the latest dump into a scratch DB and count rows
   - Grafana shows the new panels
5. **Stop — Danish commits.**

### Phase 7 — Finance + calc + Ayah

Everything is decided (spec 002):
- AED/USD/INR, reporting in AED
- a free FX API and a metal-price API — choose providers, record them in spec
  002 Q-F3
- half-even rounding
- manual entry only
- savings is just an account type
- zakat: silver nisab, cash and bank accounts only, lunar-year hawl from the
  first crossing, rounded up

No open questions remain.

1. Read `docs/specs/002-finance.md` and `003-calc.md` in full. Then execute
   tickets TICK-701 to TICK-713 (already in `docs/plan.toml`).
2. `nizam/calc/` — a pure library, and read-class MCP tools at `/calc/mcp`.
   Unit tests use independently derived expected values.
3. `migrations/003_finance.sql`:
   - the `finance_personal` schema: accounts, transactions, categories,
     budgets, recurring items, and a single-row `zakat_state`
   - `svc_finance` grants on that schema only
   - no stored balance column (ADR-005)
4. `nizam/finance/` — tools per spec. Writes use `core/approval.py`. Add the
   new write tools to the plugin list.
5. Ayah:
   - `hermes profile create assistant`
   - write `agents/assistant/*`, scoped to `finance` and `calc` **only** (no
     knowledge)
   - its own virtual key, Discord bot and `#finance`
6. **Check over Discord:**
   - record a transaction (approve it)
   - report position — it matches a hand calculation, with the FX rate and
     as-of time shown
   - with the FX API blocked, the total is withheld with a reason, not
     estimated
7. **Stop — Danish commits.**

## Verification checklist (after every phase from 4 on)

- `bash scripts/check.sh` exits 0, and `plan.py status` shows the phase's
  tickets `done`.
- `scripts/db.sh status` shows every migration applied.
- `scripts/deploy.sh --dry-run` shows no drift.
- `systemctl --failed` and `systemctl --user --failed` are both empty.
- `ss -tlnp` shows nothing new on non-loopback addresses.
- `curl 127.0.0.1:8100/health` returns 200. No or wrong token → 401.
  Cross-scope → 403.
- Real Discord round-trip works, including one `/approve`.
- `git ls-files | grep -E '\.env$|cookies|keys\.txt'` → empty.
- `gitleaks detect` → clean.

## What NOT to do

- Don't symlink mutable state (memories, skills, sessions) into the repo, and
  don't point live units at the working tree.
- Don't put a secret in a tracked file, a log line, a commit, a chat or this
  doc.
- Don't build business anything, or cycle-2 domains.
- Don't `git commit`.
- Don't retry a query on the same transaction after an error.
- Don't let any write happen without both approval layers.
- Don't reinstall host-layer pieces owned by `nizam-dotfiles`.
- Don't invent integrations, ports, model names or religious rules. Ask Danish.
