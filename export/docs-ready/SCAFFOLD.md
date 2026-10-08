---
title: Scaffold — nizam-os (Cycle 1)
status: LOCKED
version: 1.0.0
date: 2026-09-26
---

# Scaffold

This is the repo layout and the runtime paths. It is the authoritative copy;
`export/00-START-HERE.md` reproduces it for orientation. Anything not listed
here doesn't belong in the repo.

## Repo layout

```
nizam-os/
├── README.md                 # what it is, the layout, how to deploy (short)
├── CLAUDE.md                 # rules for coding agents working in this repo
├── pyproject.toml            # single package `nizam`; uv; requires-python >=3.12,<3.13
├── uv.lock                   # committed
├── .sops.yaml                # age public key; sops encrypts secrets/*.env to it
├── .gitignore                # secrets/*.env, *.key, .venv/, caches, .run/, *cookies*
├── .pre-commit-config.yaml   # ruff, gitleaks, `scripts/secrets.sh check`
├── nizam/
│   ├── __init__.py
│   ├── __main__.py           # `python -m nizam serve` | `python -m nizam jobs <name>`
│   ├── config.py             # every env var read once; missing required → fail at startup
│   ├── core/                 # domain-agnostic; imports no domain package
│   │   ├── errors.py         # AppError + typed subclasses with stable codes
│   │   ├── log.py            # get_logger(): JSON to stderr, redaction
│   │   ├── db.py             # async pools per DSN; transaction() rolls back on any error
│   │   ├── sql.py            # load_query(domain, name) from <domain>/queries/*.sql
│   │   ├── llm.py            # LiteLLM embeddings client; raises UpstreamError
│   │   ├── audit.py          # audit rows inside the caller's transaction; replay check
│   │   ├── approval.py       # signed draft tokens (spec 004 Layer 2)
│   │   ├── auth.py           # bearer token → agent → allowed domains
│   │   └── http.py           # Starlette app: mounts each domain's MCP app + GET /health
│   ├── knowledge/            # spec 001
│   │   ├── tools.py  service.py  repo.py  vault.py  embed.py  areas.py
│   │   ├── sources/{web.py,youtube.py}
│   │   └── queries/*.sql
│   ├── finance/              # spec 002 (Phase 7)
│   │   ├── tools.py  service.py  repo.py
│   │   └── queries/*.sql
│   ├── calc/                 # spec 003 (Phase 7): pure library + read-class MCP tools
│   └── jobs/                 # retry_embeddings.py, reindex.py, backup.py
├── tests/                    # mirrors nizam/ + scripts/ migrations/ deploy/ agents/ ops/; see docs/TESTING.md
├── migrations/               # dbmate, forward-only: 001_audit.sql, 002_knowledge.sql, 003_finance.sql
├── agents/
│   ├── admin/{SOUL.md,AGENTS.md,config.yaml}       # Nazim
│   ├── curator/{SOUL.md,AGENTS.md,config.yaml}     # Noor
│   ├── assistant/{SOUL.md,AGENTS.md,config.yaml}   # Ayah (Phase 7)
│   └── plugins/nizam-approval/                     # Hermes pre_tool_call approval hook
├── ops/
│   └── metrics/              # textfile-metric scripts, run by nizam-metrics-* timers
├── deploy/                   # everything deploy.sh installs onto the host
│   ├── manifest.txt          # "kind src dst" lines: unit-system | link | copy-root
│   ├── systemd/system/       # litellm-proxy.service, nizam-*.service|timer
│   ├── litellm.yaml
│   ├── promtail-nizam.yaml
│   ├── logrotate.nizam
│   ├── sudoers/admin-nizam
│   └── grafana/*.json
├── scripts/                  # things humans run
│   ├── check.sh              # fast: ruff + pytest -m 'not slow'; --all: + [slow] Postgres tests + coverage gate
│   ├── coverage_gate.py      # core/calc/finance >= 90%, overall >= 80%
│   ├── deploy.sh             # release → flip `current` → manifest → restart changed; --dry-run --rollback --sync-secrets
│   ├── secrets.sh            # encrypt | decrypt | install | check
│   ├── db.sh                 # dbmate wrapper: migrate | status | new (DBMATE_NO_DUMP_SCHEMA=true)
│   └── bootstrap.sh          # app-level host deps, idempotent (host hardening is nizam-dotfiles)
├── secrets/                  # *.env.enc + *.env.example ONLY
├── docs/                     # VISION SRS ARCHITECTURE SCAFFOLD SCHEMAS SECURITY RUNBOOK TESTING ROADMAP, adrs/, specs/, plan.toml
└── export/                   # rebuild handoff bundle — read-only reference; delete after cycle 1
```

## Runtime paths (outside the repo)

| Path | Contents | Created by |
| :--- | :--- | :--- |
| `~/.local/share/nizam/releases/<sha>/` | a built release, including `.venv` | `deploy.sh` |
| `~/.local/share/nizam/current` | symlink to the live release | `deploy.sh` |
| `~/.config/nizam/*.env` | live secrets: `nizam-os.env`, `nizam-mcp.env`, `hermes-<profile>.env`. Directory mode 700, files mode 600. | `secrets.sh install` |
| `~/.config/sops/age/keys.txt` | age private key, mode 600. **Keep an offline copy.** | Phase 1, by hand |
| `~/.local/state/nizam/backups/` | `pg_dump` files and Hermes memories tarballs | `nizam-backup.timer` |
| `~/.local/state/nizam/deploy-links.txt` | the links the last deploy created, so stale ones get removed | `deploy.sh` |
| `~/.hermes/profiles/<p>/` | Hermes-owned: memories, skills, sessions. Links to `config.yaml`, `SOUL.md`, `AGENTS.md`, `.env` and the plugin. | Hermes + `deploy.sh` |
| `~/nizam-vault/` | knowledge notes (its own git repo) | Phase 1 |

## Deliberate deviations from Feanor conventions

Feanor (`export/feanor-conventions/`) assumes a team building a web backend.
This is one person running a personal system on one VPS. Each deviation is
listed with its reason, so nobody "fixes" it back.

| Feanor says | nizam-os does | Why |
| :--- | :--- | :--- |
| Flat `app/` package, `main.py` entry point | `nizam/` package, `__main__.py` entry point | The package name is the product name; `python -m nizam` is the entry point. Same shape, different name. |
| Migrations inside each service | One root `migrations/` | One database, one daemon — there is no per-service boundary to put them in. |
| Docker, digest-pinned images, HEALTHCHECK | systemd units and a release directory (ADR-002) | Hermes, LiteLLM and the host stack are already systemd. Docker would add overhead on a 2 vCPU box with no isolation gain for this threat model. |
| `feature/* → qa → main`, PR review, branch protection | The owner commits directly, manually | One person. There is no reviewer to require, and no qa environment. |
| Ruff line length 79 | 100 | Readability of long SQL-adjacent and typed signatures. The old codebase used 100. |
| `.env` per service | `~/.config/nizam/*.env`, decrypted from sops/age | Secrets stay outside the working tree and the release directory entirely. |
| HTTP `/health` per service, behind a load balancer | One `/health` on the daemon, used by Nazim and the metrics timer | There is no load balancer, and only one daemon. |
| Full `/reqs` interrogation, PRD, CP/CN traceability ceremony | The SRS keeps CP/CN/FR traceability; no PRD | The PRD only restated the SRS. The traceability is kept because it is cheap and useful. |
| ADRs start PROPOSED and block `/plan` | ADRs are written ACCEPTED, recording decisions the owner already made | The decisions were made in conversation first; the ADR records them. |
