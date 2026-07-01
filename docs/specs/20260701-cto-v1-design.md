# Reem (CTO) — v1 design spec

**Status:** approved, pending implementation (Phase 4d)
**Prerequisite:** knowledge-service functional; GitHub PAT available
**Profile dir:** `hermes/profiles/cto/`
**Agent name:** Reem

---

## Role

Reem is the CTO. She monitors codebase health, reviews pull requests, tracks open issues, surfaces technical debt, and flags architecture concerns. She reads from knowledge-service (vault) for context but does not write to it. She reads from GitHub but does not admin repositories or manage webhooks.

Reports to Raha. User can also reach Reem directly in `#cto-office`.

---

## Discord access

**Channel:** `#cto-office` (Arc Systems)

```yaml
discord:
  allowed_channels: "<cto_office_id>"
```

---

## Hermes toolsets

```yaml
platform_toolsets:
  discord:
    - terminal    # run test suites, linters, checks on VPS codebase
    - file        # read source files for review context
    - memory
    - skills
    - clarify
    - web         # research RFCs, library docs, CVEs
```

**Disabled:** `browser`, `code_execution`, `cronjob`, `delegation`, `image_gen`, `tts`, `vision`

Note: `terminal` is enabled but scoped. Reem's `command_allowlist` in `config.yaml` permits read-only diagnostics only — no deployments, no restarts, no package installs.

---

## MCP servers

```yaml
mcp_servers:
  knowledge:
    url: http://127.0.0.1:8100/mcp
    tools:
      include:
        - search_vault
        - get_note
        - list_notes
        # ingest is excluded — Noor owns all vault writes

  github:
    command: npx
    args: ["-y", "@modelcontextprotocol/server-github"]
    env:
      GITHUB_PERSONAL_ACCESS_TOKEN: ${GITHUB_PAT}
    tools:
      include:
        - list_issues
        - get_issue
        - list_pull_requests
        - get_pull_request
        - create_pull_request_review
        - list_commits
        - get_commit
        # Excluded: delete_*, create_repository, manage_webhooks, add_collaborator, etc.
```

`GITHUB_PAT` — read + PR review scopes only. Never admin scope. Set in VPS `.env`.

---

## DB access

None. Reem does not connect to PostgreSQL directly. All data access is through MCP tools.

---

## command_allowlist

```yaml
command_allowlist:
  - pytest
  - uv run pytest
  - mypy
  - ruff check
  - ruff format --check
  - git log
  - git diff
  - git status
  - journalctl -u
  - systemctl is-active
```

Patterns not in this list require manual Discord approval before execution.

---

## Profile files

| File | Content |
|---|---|
| `SOUL.md` | Personality: thorough, direct, architecture-minded. Flags risk before writing code. Asks about constraints. |
| `AGENTS.md` | Mandate: codebase health ownership, PR review guidelines, tech debt criteria, escalation to Raha for resourcing. |
| `config.yaml` | MCP knowledge + GitHub, terminal + file + web toolsets, command_allowlist, compression model, security. |
| `user.md` | Pre-seeded: user name, repo name (nizam-os), primary language (Python 3.12), testing framework (pytest + uv), key architectural rules (no .hermes/ modification, etc.). |

---

## Security config

```yaml
security:
  allow_lazy_installs: false
  redact_secrets: true

approvals:
  mode: manual
  cron_mode: deny

auxiliary:
  compression:
    provider: custom:litellm
    model: deepseek/deepseek-v3-0324
```

---

## Implementation notes

- `cto` profile does not exist. Description for Kanban routing: "Architecture, code review, tech delivery, GitHub." Profile creation command is in the implementation plan.
- GitHub MCP server uses `npx` — ensure Node.js is installed on VPS: `node --version`. If not: install via `nvm` or apt.
- `GITHUB_PAT`: generate at github.com → Settings → Developer settings → Fine-grained tokens. Scopes: `Contents: Read`, `Pull requests: Read and write`, `Issues: Read`, `Metadata: Read`. Store in VPS `.env` only.
- Do not give Reem write access to knowledge-service. Noor owns vault writes. Reem reads only.
- `terminal` toolset: Reem can read code and run tests but must not restart services or install packages. The `command_allowlist` is the enforcement mechanism.

---

## Done criteria

- `cto` profile created with `--description`
- `SOUL.md` + `AGENTS.md` written
- `config.yaml` — knowledge MCP (read-only includes), GitHub MCP, terminal + file + web toolsets, `command_allowlist` set, compression model
- `GITHUB_PAT` in VPS `.env` with correct scopes
- `DISCORD_ALLOWED_USERS` set in VPS `.env`
- `discord.allowed_channels` set to `#cto-office` channel ID
- Spot check: Reem can list open PRs from GitHub and search vault for an architecture note
