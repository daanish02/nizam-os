# Services

All MCP services run on `127.0.0.1` only. Agents connect via `url: http://127.0.0.1:PORT/mcp`. One service can serve multiple agents; each agent sees only the tool subset specified in its `config.yaml` `tools.include` list.

Services are independent of agents. Adding capability means building a new service, not modifying an existing agent.

---

## Port map

| Port | Service | Domain |
|------|---------|--------|
| 3000 | Grafana | Observability |
| 3001 | Langfuse (self-hosted, on-demand) | Observability |
| 3100 | Loki (log aggregation) | Observability |
| 4000 | LiteLLM proxy (not MCP — model routing) | Shared |
| 8100 | `knowledge-service` | Personal |
| 8101 | `finance-service` | Personal + Business |
| 8102 | `personal-service` | Personal |
| 8103 | `math-service` | Shared utility |
| 8104 | `crm-service` | Business |
| 8105 | `analytics-service` | Business |

---

## knowledge-service

**Port:** 8100  
**DB role:** `svc_knowledge`  
**Consumers:** Noor (all tools), Reem (read-only subset)

**Responsibility:** Manages the knowledge vault (`~/nizam-vault/`). Handles ingestion from URLs, YouTube, PDFs, and images. Enforces the approval workflow before any vault write. Maintains the vault index and embeddings in PostgreSQL. Exposes search over the vault (keyword, semantic, hybrid).

**Contract:** No vault write without owner approval. Agent suggests classification (areas, tags, title) — owner never supplies these manually. Every ingest is a two-pass operation: draft → approval → write.

**Key capability boundaries:**
- Noor can read and write.
- Reem can search and read notes only — no writes.
- No other agent has access.

> Concrete tool definitions, tunables, and embedding model choices: [SPECS](docs/specs/).

---

## finance-service

**Port:** 8101  
**DB role (personal):** `svc_finance_personal`  
**DB role (business):** `svc_finance_business`  
**Consumers (personal):** Ayah (all personal tools)  
**Consumers (business):** Hala (all business tools), Omar (2 read-only tools)

**Responsibility:** Personal finance — transaction logging, balance reporting, monthly reconciliation, multicurrency support, zakat calculation. Business finance — revenue tracking, expense categorization, financial reporting.

**Contract:** Personal and business tools are isolated in the same service but behind separate DB roles. Ayah cannot call business finance tools. Hala cannot call personal finance tools. This isolation is enforced at the `tools.include` list level and at the DB role level.

**Key capability boundary:** `finance-service` contains internal precision helpers for sub-unit currency handling. Calculations that agents need to invoke explicitly (amortization, zakat arithmetic, compound interest) are exposed through `math-service`.

> Concrete tool definitions, tunables: [SPECS](docs/specs/).

---

## personal-service

**Port:** 8102  
**DB role:** `svc_personal`  
**Consumers:** Ayah (all tools)

**Responsibility:** Habits (definitions and daily logs), goals, projects, tasks, and journal entries for the personal domain. Ayah is the sole writer. No other agent accesses this service.

**Contract:** Journal entries are written to both the vault (`~/nizam-vault/personal/journal/`) and the DB. The DB copy exists for search; the vault copy is the source of truth.

> Concrete tool definitions: [SPECS](docs/specs/).

---

## math-service

**Port:** 8103  
**Consumers:** Hala (CFO — financial calculations), Ayah (personal finance calculations)

**Responsibility:** Arbitrary-precision arithmetic as an agent-callable MCP service. Covers financial rounding, currency conversion with sub-unit handling, compound interest, amortization, and zakat arithmetic. Exists so agents never do financial math inline.

**Contract:** Stateless — no DB access, no writes. finance-service also uses internal precision helpers for sub-unit conversion; math-service is for calculations that require explicit agent invocation or cross-service reuse.

---

## crm-service

**Port:** 8104  
**DB role:** `svc_crm`  
**Consumers:** Omar (all tools), Raha (read-only summary tools)

**Responsibility:** Contact management, pipeline tracking, interaction history for the business domain.

> Concrete tool definitions: [SPECS](docs/specs/).

---

## analytics-service

**Port:** 8105  
**DB role:** `svc_analytics`  
**Consumers:** Mira (all tools), Raha (read-only)

**Responsibility:** Campaign performance, content metrics, audience data for the business domain. Phase 6e.

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

- Terminal: enabled, scoped via `command_allowlist` + `/etc/sudoers.d/nazim-nizam`
- Cron: `cron_mode: manual`
- MCP: none
- Sudo: scoped to service restart commands only — not full sudo

### Noor (knowledge curator)

- Terminal: disabled
- Cron: `cron_mode: deny`
- MCP: `knowledge-service` — all tools

### Ayah (personal assistant)

- Terminal: disabled
- Cron: `cron_mode: deny`
- MCP: `finance-service` (personal tools only), `personal-service` (all tools), `knowledge-service` (read-only), `math-service` (all tools)

### Raha (chief of staff)

- Terminal: disabled
- Cron: `cron_mode: manual`
- MCP: none — coordinates via kanban delegation to C-suite agents
- No direct data access: cannot read or write any database directly

### Hala (CFO)

- Terminal: disabled
- Cron: `cron_mode: deny`
- MCP: `finance-service` (business tools only), `math-service` (all tools)

### Omar (CRO)

- Terminal: disabled
- Cron: `cron_mode: deny`
- MCP: `crm-service` (all tools), `finance-service` (2 read-only tools)

### Reem (CTO)

- Terminal: enabled, `command_allowlist` for read-only diagnostics only — no restarts, no installs
- Cron: `cron_mode: deny`
- MCP: `knowledge-service` (read-only), GitHub MCP (read + PR write)
- Delegation: `max_spawn_depth: 2`, `subagent_auto_approve: false`, `max_concurrent_children: 3`

### Mira (CMO)

- Terminal: disabled
- Cron: `cron_mode: deny`
- MCP: `analytics-service` (all tools), `knowledge-service` (read-only)
