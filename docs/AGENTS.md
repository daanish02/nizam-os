# Nizam-OS — Agent Roster

**Last updated:** 2026-07-01

High-level reference for all eight agents. For full design decisions, behavioral rules, SOUL/AGENTS.md content, and implementation detail see each agent's spec.

---

## Quick reference

| Agent | Profile | Persona | Phase | Status | Spec |
|---|---|---|---|---|---|
| Nazim | `admin` | System admin | 4 | In repo — rename Bani→Nazim pending | `docs/specs/20260701-admin-v1-design.md` |
| Noor | `curator` | Knowledge curator | 3 | In repo — tools non-functional (DB schema not run) | `docs/specs/20260701-curator-v1-design.md` |
| Ayah | `assistant` | Personal assistant | 5 | In repo — stub profile | `docs/specs/20260701-assistant-v1-design.md` |
| Raha | `cos` | Chief of Staff | 6a | In repo — stub profile | `docs/specs/20260701-cos-v1-design.md` |
| Hala | `cfo` | CFO | 6b | Not built | `docs/specs/20260701-cfo-v1-design.md` |
| Omar | `coo` | COO | 6c | Not built | `docs/specs/20260701-coo-v1-design.md` |
| Reem | `cto` | CTO | 6d | Not built | `docs/specs/20260701-cto-v1-design.md` |
| Mira | `cmo` | CMO | 6e | Not built | `docs/specs/20260701-cmo-v1-design.md` |

Model: all profiles use `deepseek/deepseek-v4-flash` via `custom:litellm`. Compression: `deepseek/deepseek-v3-0324` (pinned per profile).

---

## Nazim — System Admin

**Profile:** `hermes/profiles/admin/`
**Channels:** `#admin`, `#alerts`, `#warning`, `#sandbox` (System category — full category access)
**Gateway:** Active (rename Bani→Nazim pending)

**Mandate:** Infrastructure health, incident response, service restarts, Hermes guide. Has `terminal` + `file` for diagnostic commands. Sudo scoped to service restarts only via `/etc/sudoers.d/nazim-hermes`.

**Hermes toolsets:** `terminal`, `file`, `memory`, `skills`, `clarify`, `cronjob`, `web`

**MCP servers:**

| Server | Access |
|---|---|
| `knowledge-service` :8100 | `search_vault`, `get_note`, `list_notes` (read-only) |

**Hermes native tools Nazim can use:** `terminal` (full system access, scoped by sudoers), `file` (read VPS config files), `cronjob` (health check schedule)

**Key constraints:**
- Sudo restricted to specific `systemctl restart` commands only
- Does not write to knowledge vault

---

## Noor — Knowledge Curator

**Profile:** `hermes/profiles/curator/`
**Channel:** `#learning` (Personal category)
**Gateway:** Active — tools non-functional until knowledge schema runs

**Mandate:** Ingest content into `~/nizam-vault/commons/`. All writes approval-gated (3-pass: preview → draft → write). MECE taxonomy enforced. Never skips approval.

**Hermes toolsets:** `memory`, `skills`, `clarify`

**Discord config:** `allow_any_attachment: true`, `max_attachment_bytes: 33554432` — accepts PDF and image file uploads from Discord

**MCP servers:**

| Server | Access |
|---|---|
| `knowledge-service` :8100 | All tools (owns all vault writes) |

**10 MECE domains:** technology, science, business, finance-economics, philosophy-ethics, health-wellness, arts-culture, history-society, language-communication, personal-development

---

## Ayah — Personal Assistant

**Profile:** `hermes/profiles/assistant/`
**Channels:** `#chat`, `#finances`, `#habits`, `#goals-tasks`, `#journal` (Personal category — all five are free_response_channels, no @mention needed)
**Gateway:** Not active (stub profile)

**Mandate:** Personal finance (multicurrency, zakat, riba), habits, goals, tasks, journal. All finance writes require user confirmation before committing. Never commits with `approved=False`.

**Hermes toolsets:** `memory`, `skills`, `clarify`

**Discord config:** `allow_any_attachment: true` — accepts bank statement PDFs and CSVs

**MCP servers:**

| Server | Access |
|---|---|
| `finance-service` :8101 | Personal tools only: `record_transaction`, `spending_report`, `budget_status`, `account_balance`, `reconcile_statement`, `add_category`, `zakat_status`, `calculate_zakat`, `log_riba`, `riba_report` |
| `personal-service` :8102 | All tools (no filter) |

**Key constraints:**
- Never touches `business.finance.*` schema
- Riba lines routed to `log_riba`, never to `record_transaction`
- FX rate always shown before approval

---

## Raha — Chief of Staff

**Profile:** `hermes/profiles/cos/`
**Channels:** `#strategy` (Chairman's Office), `#boardroom`, `#biz-chat` (Arc Systems)
**Gateway:** Not active (stub profile)

**Mandate:** Coordinate C-suite agents, synthesise outputs, report to Chairman. No direct data access — all information comes through delegation. Owns the weekly Monday review cron.

**Hermes toolsets:** `delegation`, `kanban`, `memory`, `skills`, `clarify`, `cronjob`

> `kanban` must be listed explicitly — it is NOT included in Hermes `all` toolsets wildcard.

**MCP servers:** None. `mcp_servers: {}`. Raha delegates; she never queries services directly.

**Delegation targets:**

| Child agent | When Raha delegates |
|---|---|
| Hala (`cfo`) | Business finance, P&L, invoices |
| Omar (`coo`) | Client status, project delivery, CRM |
| Reem (`cto`) | Codebase health, open PRs, tech issues |
| Mira (`cmo`) | Content performance, upcoming posts |

Delegation modes: **sync** (Raha blocks until child responds) or **async** (Raha fires and moves on). Child agents never respond to Discord directly — Raha owns the channel reply.

**Weekly review cron:** Monday 09:00 VPS time. Delegates to all four C-suite in order, synthesises, posts in `#boardroom`.

---

## Hala — CFO

**Profile:** `hermes/profiles/cfo/`
**Channel:** `#cfo-office` (Arc Systems)
**Gateway:** Not built

**Mandate:** Business financial records — transactions, invoices, P&L, budgets. Does not touch personal finance. Reports to Raha; user can also reach Hala directly in `#cfo-office`.

**Hermes toolsets:** `memory`, `skills`, `clarify`

**MCP servers:**

| Server | Access |
|---|---|
| `finance-service` :8101 | Business tools only: `record_business_transaction`, `create_invoice`, `update_invoice_status`, `business_spending_report`, `business_account_balance`, `p_and_l_report`, `invoice_status_report` |

**Key constraints:**
- `svc_finance_business` role — zero access to `finance.personal_transactions`
- All writes go to `audit.log`

---

## Omar — COO

**Profile:** `hermes/profiles/coo/`
**Channel:** `#coo-office` (Arc Systems)
**Gateway:** Not built

**Mandate:** Client relationships, project delivery, CRM. Read-only access to business finance for quoting context only — cannot create transactions or invoices.

**Hermes toolsets:** `memory`, `skills`, `clarify`, `web`

**MCP servers:**

| Server | Access |
|---|---|
| `crm-service` :8104 | All tools (owns CRM) |
| `finance-service` :8101 | `business_account_balance`, `invoice_status_report` only |

**Key constraints:**
- No direct DB access to `business.finance.*` — finance access is via tool include list only (tools connect as `svc_finance_business`)
- No access to personal-service or knowledge-service

---

## Reem — CTO

**Profile:** `hermes/profiles/cto/`
**Channel:** `#cto-office` (Arc Systems)
**Gateway:** Not built

**Mandate:** Codebase health, PR review, tech debt, architecture concerns. Read-only diagnostics on VPS. Cannot deploy, restart services, or install packages.

**Hermes toolsets:** `terminal` (scoped), `file`, `memory`, `skills`, `clarify`, `web`

**MCP servers:**

| Server | Access |
|---|---|
| `knowledge-service` :8100 | `search_vault`, `get_note`, `list_notes` (read-only) |
| GitHub (npx) | `list_issues`, `get_issue`, `list_pull_requests`, `get_pull_request`, `create_pull_request_review`, `list_commits`, `get_commit` |

**command_allowlist** (terminal restricted to):
```
pytest, uv run pytest, mypy, ruff check, ruff format --check,
git log, git diff, git status, journalctl -u, systemctl is-active
```

Anything outside this list requires manual Discord approval before execution.

**GitHub PAT scopes:** Contents: Read, Pull requests: Read+Write, Issues: Read, Metadata: Read. Never admin scope.

---

## Mira — CMO

**Profile:** `hermes/profiles/cmo/`
**Channel:** `#cmo-office` (Arc Systems)
**Gateway:** Not built

**Mandate:** Content strategy, LinkedIn presence, marketing campaigns. Reads vault for ideas, reads CRM for case studies. Does not write to either. Post performance tracking is Phase 7 (requires `analytics-service`).

**Hermes toolsets:** `memory`, `skills`, `clarify`, `web`, `image_gen` (enable only if vision backend available on VPS)

**MCP servers:**

| Server | Access |
|---|---|
| `knowledge-service` :8100 | `search_vault`, `get_note`, `list_notes` (read-only) |
| `crm-service` :8104 | `client_list`, `deal_pipeline`, `client_case_studies` (read-only) |
| `analytics-service` :8105 | All tools — Phase 7 only, not in v1 |

**Key constraints:**
- Never publish client names or specific financials without explicit user approval
- `client_case_studies` data must not go into content without approval — rule in AGENTS.md
- `image_gen` toolset: enable only after confirming image generation backend works on VPS

---

## Common config applied to all profiles

```yaml
security:
  allow_lazy_installs: false
  redact_secrets: true

approvals:
  mode: manual
  cron_mode: deny           # except Raha and Nazim where cronjob is enabled

auxiliary:
  compression:
    provider: custom:litellm
    model: deepseek/deepseek-v3-0324
```

Per-profile `.env` (VPS only, gitignored): `DISCORD_TOKEN`, `DISCORD_GUILD_ID`, `LITELLM_MASTER_KEY` (virtual key).

Disabled by default on all profiles unless explicitly listed above: `browser`, `code_execution`, `image_gen`, `tts`, `vision`, and all toolsets not enumerated per agent.
