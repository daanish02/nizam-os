# Nizam-OS — Business Agents (Future)

**Last updated:** 2026-07-02

Business agents (Phases 6a–6e). Not yet built. Personal agents: `docs/AGENTS.md`.

---

## Quick reference

| Agent | Profile | Persona | Spec |
|---|---|---|---|
| Raha | `cos` | Chief of Staff | `docs/specs/20260701-cos-v1-design.md` |
| Hala | `cfo` | CFO | `docs/specs/20260701-cfo-v1-design.md` |
| Omar | `coo` | COO | `docs/specs/20260701-coo-v1-design.md` |
| Reem | `cto` | CTO | `docs/specs/20260701-cto-v1-design.md` |
| Mira | `cmo` | CMO | `docs/specs/20260701-cmo-v1-design.md` |

Phase and build status: `docs/ROADMAP.md`. Model: all profiles use `deepseek/deepseek-v4-flash` via `custom:litellm`. Compression: `deepseek/deepseek-v3-0324` (pinned per profile).

---

## Raha — Chief of Staff

**Profile:** `hermes/profiles/cos/`
**Channels:** `#boardroom`, `#biz-chat` (Arc Systems)

**Mandate:** Coordinate C-suite agents, synthesise outputs, report to Chairman. No direct data access — all information comes via kanban task responses. Owns the weekly Monday review cron.

**Hermes toolsets:** `kanban`, `memory`, `skills`, `clarify`, `cronjob`

> `kanban` must be listed explicitly — it is NOT included in Hermes `all` toolsets wildcard.

**MCP servers:** None. `mcp_servers: {}`. Raha creates kanban tasks; C-suite agents read and respond independently.

**C-suite coordination model:** Raha does NOT spawn C-suite agents as child agents. She creates kanban board tasks with instructions and context. Each C-suite agent (Hala, Omar, Reem, Mira) operates independently, picks up their assigned tasks from the kanban board, completes the work, and posts results as task comments. Raha reads the completed comments, synthesises, and posts in `#boardroom` or `#biz-chat`.

**Weekly review cron:** Monday 09:00 VPS time. Creates kanban tasks for each C-suite agent, waits for results, synthesises, posts in `#boardroom`.

---

## Hala — CFO

**Profile:** `hermes/profiles/cfo/`
**Channel:** `#cfo-office` (Arc Systems)
**Mandate:** Business financial records — transactions, invoices, P&L, budgets. Does not touch personal finance. Reports to Raha; user can also reach Hala directly in `#cfo-office`.

**Hermes toolsets:** `memory`, `skills`, `clarify`

**MCP servers:**

| Server | Access |
|---|---|
| `finance-service` :8101 | Business tools only: `record_business_transaction`, `create_invoice`, `update_invoice_status`, `business_spending_report`, `business_account_balance`, `p_and_l_report`, `invoice_status_report` |

**Key constraints:**
- `svc_finance_business` role — zero access to `finance_personal.*` tables
- All writes go to `audit.log`

---

## Omar — COO

**Profile:** `hermes/profiles/coo/`
**Channel:** `#coo-office` (Arc Systems)
**Mandate:** Client relationships, project delivery, CRM. Read-only access to business finance for quoting context only — cannot create transactions or invoices.

**Hermes toolsets:** `memory`, `skills`, `clarify`, `web`

**MCP servers:**

| Server | Access |
|---|---|
| `crm-service` :8104 | All tools (owns CRM) |
| `finance-service` :8101 | `business_account_balance`, `invoice_status_report` only |
| Gmail (npx) | Read email, send email, search — client communication and project updates |

**Key constraints:**
- No direct DB access to `finance_business.*` — finance access is via tool include list only (tools connect as `svc_finance_business`)
- No access to personal-service or knowledge-service

---

## Reem — CTO

**Profile:** `hermes/profiles/cto/`
**Channel:** `#cto-office` (Arc Systems)
**Mandate:** Codebase health, PR review, tech debt, architecture concerns. Read-only diagnostics on VPS. Cannot deploy, restart services, or install packages.

**Hermes toolsets:** `terminal` (scoped), `file`, `memory`, `skills`, `clarify`, `web`, `delegation`

**MCP servers:**

| Server | Access |
|---|---|
| `knowledge-service` :8100 | `search_vault`, `get_note`, `list_notes` (read-only) |
| GitHub (npx) | `list_issues`, `get_issue`, `list_pull_requests`, `get_pull_request`, `create_pull_request_review`, `list_commits`, `get_commit` |

**Sandbox delegation:** Reem uses `delegation` to spawn short-lived sandbox agents for risky dev work (code execution, test runs, experimental patches). Sandbox agents operate in a sandboxed terminal environment, report results back to Reem. Reem synthesises and posts to `#cto-office`. Sandbox agents never respond to Discord directly.

**command_allowlist** (Reem's own terminal — read-only diagnostics):
```
pytest, uv run pytest, mypy, ruff check, ruff format --check,
git log, git diff, git status, git show, git blame,
journalctl -u, systemctl is-active, systemctl status,
cat, ls, find, grep, ps aux, df -h, free -h
```

Anything outside this list requires manual Discord approval before execution. Sandbox child agents have their own terminal scope defined at spawn time.

**GitHub PAT scopes:** Contents: Read, Pull requests: Read+Write, Issues: Read, Metadata: Read. Never admin scope.

---

## Mira — CMO

**Profile:** `hermes/profiles/cmo/`
**Channel:** `#cmo-office` (Arc Systems)
**Mandate:** Content strategy, LinkedIn presence, marketing campaigns. Reads vault for ideas, reads CRM for case studies. Does not write to either. Post performance tracking is Phase 7 (requires `analytics-service`).

**Hermes toolsets:** `memory`, `skills`, `clarify`, `web`, `image_gen` (enable only if vision backend available on VPS)

**MCP servers:**

| Server | Access |
|---|---|
| `knowledge-service` :8100 | `search_vault`, `get_note`, `list_notes` (read-only) |
| `crm-service` :8104 | `client_list`, `deal_pipeline`, `client_case_studies` (read-only) |
| `analytics-service` :8105 | All tools — Phase 7 only, not in v1 |
| Gmail (npx) | Read email, send email, search — outreach and campaign communication |

**Key constraints:**
- Never publish client names or specific financials without explicit user approval
- `client_case_studies` data must not go into content without approval — rule in AGENTS.md
- `image_gen` toolset: enable only after confirming image generation backend works on VPS

---

Common config applied to all profiles (personal and business): `docs/AGENTS.md` → Common config.
