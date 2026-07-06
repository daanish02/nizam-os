# Services

All MCP services run on `127.0.0.1` only. Agents connect via `url: http://127.0.0.1:PORT/mcp`. One service can serve multiple agents; each agent sees only the tool subset specified in its `config.yaml` `tools.include` list.

Services are independent of agents. Adding capability means building a new service or updating existing service, not modifying an existing agent.

---

## Port map

| Port | Service | Domain |
|------|---------|--------|
| 3000 | Grafana | Observability |
| 3001 | Langfuse | Observability |
| 3100 | Loki | Observability |
| 4000 | LiteLLM proxy | Shared |
| 8100 | `knowledge-service` | Personal |
| 8101 | `math-service` | Shared |
| 8102 | `finance-service` | Personal + Business |
| 8103 | `personal-service` | Personal |
| 8104 | `investment-service` | Personal |
| 8105 | `crm-service` | Business |
| 8106 | `analytics-service` | Business |

---

## knowledge-service

**Port:** 8100  
**DB role:** `svc_knowledge`  
**Consumers:** curator and researcher (all tools), investor (read and write), cto and cmo (read-only subset)

**Responsibility:** Manages the knowledge vault (`~/nizam-vault/`). Handles ingestion from URLs, YouTube, PDFs, and images. Enforces the approval workflow before any vault write. Maintains the vault index and embeddings in PostgreSQL. Exposes search over the vault (keyword, semantic, hybrid).

**Contract:** No vault write without owner approval. Agent suggests classification (areas, tags, title) — owner never supplies these manually. Every ingest is a two-pass operation: draft → approval → write.

**Key capability boundaries:**
- curator can read and write.
- researcher can read and write — research findings are stored to vault as permanent output.
- cto and cmo can search and read notes only — no writes.
- investor can read and write — Shariah screening results and due diligence notes stored as structured vault entries.
- No other agent has access.

> Concrete tool definitions, tunables, and embedding model choices: [SPECS](docs/specs/).

---

## math-service

**Port:** 8101  
**Consumers:** assistant, cfo and investor (all tools)

**Responsibility:** Arbitrary-precision arithmetic as an agent-callable MCP service. Covers financial rounding, currency conversion with sub-unit handling, compound interest, amortization, and zakat arithmetic. Exists so agents never do financial math inline.

**Contract:** Stateless — no DB access, no writes. finance-service also uses internal precision helpers for sub-unit conversion; math-service is for calculations that require explicit agent invocation or cross-service reuse. investor uses math-service for arithmetic calculations.

---

## finance-service

**Port:** 8102  
**DB role (personal):** `svc_finance_personal`  
**DB role (business):** `svc_finance_business`  
**Consumers (personal):** assistant (all personal tools)  
**Consumers (business):** cfo (all business tools), coo (2 read-only tools)

**Responsibility:** Personal finance — transaction logging, balance reporting, monthly reconciliation, multicurrency support, zakat calculation. Business finance — revenue tracking, expense categorization, financial reporting.

**Contract:** Personal and business tools are isolated in the same service but behind separate DB roles. assistant cannot call business finance tools. cfo cannot call personal finance tools. This isolation is enforced at the `tools.include` list level and at the DB role level.

**Key capability boundary:** `finance-service` contains internal precision helpers for sub-unit currency handling. Calculations that agents need to invoke explicitly (amortization, zakat arithmetic, compound interest) are exposed through `math-service`.

> Concrete tool definitions, tunables: [SPECS](docs/specs/).

---

## personal-service

**Port:** 8103  
**DB role:** `svc_personal`  
**Consumers:** assistant (all tools)

**Responsibility:** Habits (definitions and daily logs), goals, tasks, and journal entries for the personal domain. assistant is the sole writer. No other agent accesses this service.

**Contract:** Journal entries are written to both the vault (`~/nizam-vault/personal/journal/`) and the DB. The DB copy exists for search; the vault copy is the source of truth.

> Concrete tool definitions: [SPECS](docs/specs/).

---

## investment-service

**Port:** 8104  
**DB role:** none — read-only IBKR API wrapper, no persistent state  
**Consumers:** investor (all tools)

**Responsibility:** Wraps the Interactive Brokers (IBKR) Client Portal API. Exposes read-only tools for investor: current positions, watchlist, price data, and financial statement data. No writes to IBKR in current scope — investor advises, owner executes.

**Screening results:** Not stored in PostgreSQL. investor writes structured screening notes to vault via `knowledge-service`. IBKR is the source of truth for portfolio and watchlist data.

**Future scope:** Order placement (with approval gate), portfolio rebalancing suggestions, portfolio manager expansion. Not in current scope.

**Contract:** Stateless from the DB perspective. investment-service is a thin API proxy — it authenticates to IBKR, translates responses to clean MCP tool output, and returns data to investor. No vault writes from this service.

> Concrete tool definitions and IBKR API scope: [SPECS](docs/specs/).

---

## crm-service

**Port:** 8105  
**DB role:** `svc_crm`  
**Consumers:** coo (all tools), cos (read-only summary tools)

**Responsibility:** Contact management, pipeline tracking, interaction history for the business domain. 

> Concrete tool definitions: [SPECS](docs/specs/).

---

## analytics-service

**Port:** 8106  
**DB role:** `svc_analytics`  
**Consumers:** cmo (all tools), cos (read-only)

**Responsibility:** Campaign performance, content metrics, audience data for the business domain. 

> Concrete tool definitions: [SPECS](docs/specs/).

---

## Agent toolset contracts

### Common config (all agents)

Every profile has:
- `allow_lazy_installs: false`
- `redact_secrets: true`
- `approvals.mode: manual`
- `DISCORD_ALLOWED_USERS` set to owner's Discord user ID only
- `discord.allowed_channels` scoped to the agent's own channels

### Nazim (system admin)

- Terminal: enabled, scoped via `command_allowlist` + `/etc/sudoers.d/admin-nizam`
- Cron: `cron_mode: manual`
- MCP: none
- Sudo: scoped to select commands only — not full sudo

### Noor (knowledge curator)

- Terminal: disabled
- Cron: `cron_mode: deny`
- MCP: `knowledge-service` — all tools

### Ayah (personal assistant)

- Terminal: disabled
- Cron: `cron_mode: deny`
- MCP: `finance-service` (personal tools only), `personal-service` (all tools), `knowledge-service` (read-only), `math-service` (all tools)

### Hakim (researcher)

- Terminal: disabled
- Cron: `cron_mode: deny`
- MCP: `knowledge-service` (read + write)
- File toolset: enabled — research output written to temp files, not held in context. Prevents context window exhaustion on deep multi-source research tasks.
- Delegation: `max_spawn_depth: 1`, `subagent_auto_approve: false`, `max_concurrent_children: 5`
- Receives research requests from business agents via cos (kanban) and from owner directly.

### Rashid (investor)

- Terminal: disabled
- Cron: `cron_mode: deny`
- MCP: `investment-service` (all tools), `knowledge-service` (read + write), `math-service` (all tools)
- Delegation: `max_spawn_depth: 1`, `subagent_auto_approve: false`, `max_concurrent_children: 3`
- Research delegated to researcher — investor does not do raw research itself.

### Raha (chief of staff)

- Terminal: disabled
- Cron: `cron_mode: manual`
- MCP: none — coordinates via kanban delegation to C-suite agents
- No direct data access: cannot read or write any database directly

### Hala (CFO)

- Terminal: disabled
- Cron: `cron_mode: deny`
- MCP: `finance-service` (business tools only), `math-service` (all tools)

### Omar (COO)

- Terminal: disabled
- Cron: `cron_mode: deny`
- MCP: `crm-service` (all tools), `finance-service` (2 read-only tools)

### Reem (CTO)

- Terminal: enabled, `command_allowlist` for read-only diagnostics only — no restarts, no installs
- Cron: `cron_mode: deny`
- MCP: `knowledge-service` (read-only), `crm-service` (read-only), GitHub MCP (read + write)
- Delegation: `max_spawn_depth: 2`, `subagent_auto_approve: false`, `max_concurrent_children: 2`
- Technical research stays with cto via sandbox delegation. Non-technical research delegated to researcher via cos.

### Mira (CMO)

- Terminal: disabled
- Cron: `cron_mode: deny`
- MCP: `analytics-service` (all tools), `knowledge-service` (read-only), `crm-service` (read-only)
- Research: delegated to researcher via cos — cmo carries no web search tools
