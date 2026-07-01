# Nizam-OS — Glossary

**Last updated:** 2026-07-01

Domain-specific terms, Hermes terms, and nizam-os patterns. Alphabetical. For configuration detail follow the linked docs.

---

**age** — Encryption backend used with sops. Generates a keypair; the private key (`secrets/nizam-age-key.txt`) decrypts all `.enc` files in the repo. Back up before VPS wipe.

**AGENTS.md** — Per-profile mandate file. Injected by Hermes as project context at every session start (same mechanism as CLAUDE.md in Claude Code). Contains rules, domain knowledge, failure behaviours. No personality content — that goes in SOUL.md.

**approval gate** — Two-step confirmation pattern for all agent writes. Step 1: call tool with `approved=False` → returns a preview. Step 2: call with `approved=True` → commits. Agents must never skip to `approved=True` without the user seeing the preview.

**Arc Systems** — The business entity. Business agents (Hala, Omar, Reem, Mira) operate under Arc Systems. Distinct from the Chairman's personal domain.

**AuditLogger** — Module in `nizam-shared`. Writes an audit record on every agent-initiated mutation. Opens its own autocommit connection so the audit entry persists even if the caller's transaction rolls back.

**BM25** — Probabilistic text ranking algorithm. In nizam-os: implemented via ParadeDB's `@@@` operator on `knowledge.vault_index`. Returns ranked results by keyword relevance. Combined with vector search via RRF.

**Chairman** — The user (Danish Ahmed). All agents report to the Chairman, either directly or via Raha.

**commons** — The shared MECE knowledge base directory: `~/nizam-vault/commons/`. All notes Noor ingests go here. Flat structure — no subdirectories. Noor owns all writes; other agents read only.

**compression** — Hermes mechanism for summarising long session context to fit within the model's context window. Triggered at 50% context usage (`compression.threshold`). Compression model must be pinned per profile to `deepseek/deepseek-v3-0324` — leaving it as `provider: auto` uses the primary model and costs significantly more.

**confidence** — Metadata field on vault notes: `low` / `medium` / `high`. Set by Noor at ingest time. YouTube metadata-only fallback (Tier 3) downgrades to `low` automatically.

**CoS** — Chief of Staff. Raha's role. Coordinates the four C-suite agents, synthesises their outputs, reports to the Chairman.

**delegation** — Hermes mechanism allowing one agent (Raha) to spawn child agents with a goal and context. Child agents execute the task and return a result; they never post to Discord directly. `max_spawn_depth: 1` — children cannot spawn further children.

**evergreen** — Vault note status. Fundamental knowledge that stays relevant over time. Manually promoted from `processed`. See also: `raw`, `processed`.

**FastMCP** — Python library for building MCP servers. Used by all nizam-os services. Decorating a function with `@mcp.tool()` registers it as an MCP tool.

**FX rate** — Foreign exchange rate. finance-service fetches at transaction time, caches by date in `finance.fx_rates`. Same-day rate reused across transactions — no duplicate API calls within a day.

**gateway** — The Hermes Discord bot process for a profile. Started with `hermes gateway start <profile>`. One gateway per active agent. The gateway connects to Discord, receives messages, runs the agent, posts replies.

**hawl** — Islamic lunar year. The minimum period over which nisab-level wealth must be held before zakat becomes obligatory. Tracked in `finance.zakat_hawl`.

**Hermes** — The agent framework. `~/.hermes/` is the runtime — read-only. Agent behaviour is configured via `hermes/profiles/<name>/` files in this repo.

**HNSW** — Hierarchical Navigable Small World. Vector index type in pgvector. Used on `knowledge.vault_embeddings.embedding` for approximate nearest-neighbour search. Index type: `vector_cosine_ops` (cosine distance).

**hybrid search** — Search strategy combining BM25 (keyword relevance) and pgvector (semantic similarity). Results from both are fused via RRF. Handles both exact-term queries (BM25 wins) and semantic/paraphrase queries (vector wins).

**kanban** — Hermes task dispatch system. Raha uses it to track and route delegated tasks across C-suite agents. Must be listed explicitly in `platform_toolsets.discord` — not included in Hermes's default discord toolset wildcard.

**LiteLLM** — Local model proxy on `localhost:4000`. All agent LLM calls route through it to OpenRouter. Provides: spend tracking, per-profile virtual keys, Redis caching, token counting, retry logic.

**MECE** — Mutually Exclusive, Collectively Exhaustive. Taxonomy principle for vault notes. Every note belongs to exactly one domain and one subdomain. The 10 domains: technology, science, business, finance-economics, philosophy-ethics, health-wellness, arts-culture, history-society, language-communication, personal-development.

**MCP** — Model Context Protocol. Anthropic standard for tool servers. Hermes connects to MCP servers and exposes their tools to agents. nizam-os services implement MCP via FastMCP.

**nizam-shared** — Shared Python library at `services/shared/`. Three modules: `ServiceBase` (DB connection + Redis + AuditLogger), `AuditLogger` (writes audit records), `get_logger` (JSON-to-stderr structured logger). Local uv workspace dependency — all services declare it as `nizam-shared = { workspace = true }`.

**nizam-vault** — File-based knowledge store at `~/nizam-vault/`. Git-initialised directory. Three subdirectories: `commons/` (Noor's MECE knowledge base), `personal/` (Ayah's journal and fleeting notes), `business/` (business documents). Not committed to this repo — lives only on the VPS.

**nisab** — Minimum wealth threshold for zakat obligation. Calculated as the gold equivalent of 85g of gold at current price. Tracked in `finance.zakat_hawl.nisab_usd`.

**OpenRouter** — External LLM API aggregator. All model inference routes through OpenRouter via LiteLLM. Single upstream for all models (DeepSeek, Gemini, etc.).

**ParadeDB** — PostgreSQL extension providing BM25 full-text search via `pg_search`. Adds the `@@@` operator and `paradedb.score()` for ranked keyword search. Installed alongside pgvector.

**pgvector** — PostgreSQL extension for vector similarity search. Adds the `vector` column type and `<=>` cosine distance operator. Used for semantic search on vault embeddings.

**profile** — A named Hermes agent configuration. Lives at `~/.hermes/profiles/<name>/` (runtime) and `hermes/profiles/<name>/` (this repo, symlinked). Contains `config.yaml`, `SOUL.md`, `AGENTS.md`, `.env`, `skills/`, `memories/`.

**processed** — Vault note status. Clean, tagged, complete. Ready to reference and link. Manually promoted from `raw`. See also: `raw`, `evergreen`.

**prom file** — Text file in Prometheus exposition format. Written to `/var/lib/prometheus/node-exporter/` by nizam-os metric scripts. node-exporter picks them up via the textfile collector every 15s.

**raw** — Vault note status. Just captured. May be messy or incomplete. Default status for all newly ingested notes. Not ready to reference until promoted to `processed`.

**riba** — Interest (prohibited in Islamic finance). Riba income and expense are tracked separately in `finance.riba_log`, never included in P&L or net worth calculations. Flagged explicitly by Ayah when detected in bank statements.

**RRF** — Reciprocal Rank Fusion. Algorithm for combining two ranked result sets. Score for each item: `1/(k + rank)` where k=60. BM25 results and vector results are each ranked independently, then fused by summing their RRF scores. Items appearing in both lists score highest.

**ServiceBase** — Base class in `nizam-shared`. Instantiated with a service name, provides: JSON logger, psycopg3 connection factory (`svc.db()` context manager), AuditLogger, Redis client. Currently hardcodes `svc_knowledge` as DB user — parameterisation needed for future services.

**skill** — A custom capability defined as a `.md` file following the agentskills.io open standard. Lives in `hermes/profiles/<name>/skills/` or `hermes/skills/` (shared). Loaded by Hermes when the `skills` toolset is enabled.

**sops** — Secrets OPerationS. CLI tool for encrypting `.env` files using age. All `.enc` files in this repo are sops-encrypted. `SOPS_AGE_KEY_FILE=secrets/nizam-age-key.txt` must be set to decrypt.

**SOUL.md** — Per-profile personality file. Injected by Hermes as the system prompt prefix. Contains: agent name, communication style, tone, what the agent does not do. Never contains: file paths, tool names, workflow rules, mandates — those go in AGENTS.md.

**svc_*** — Naming convention for PostgreSQL service roles. Each MCP service connects as its own role: `svc_knowledge`, `svc_finance_personal`, `svc_finance_business`, `svc_personal`, `svc_crm`. Roles are not shared across services.

**textfile collector** — Prometheus node-exporter feature. Reads `.prom` files from a configured directory every scrape interval (15s). nizam-os uses this for custom metrics (LLM spend, service health, tool call counts).

**3-pass workflow** — See: approval gate. Pass 1 = preview. Pass 2 = draft. Pass 3 = write.

**Tirith** — Hermes built-in security framework. Enabled by default (`tirith_enabled: true`). Currently configured `fail_open: true` — a Tirith timeout does not block the tool call.

**toolset** — A named group of Hermes native tools. Examples: `terminal`, `file`, `memory`, `delegation`, `kanban`, `web`. Enabled per-profile in `platform_toolsets.discord`. Disabled by default unless listed. See `docs/HERMES.md` for full list.

**transport** — How Hermes connects to an MCP server. Two modes: `command:` (stdio subprocess — Hermes spawns the process per session) or `url:` (HTTP — Hermes connects to a persistent HTTP server). All nizam-os services use HTTP post Curator v1.

**uv** — Python package manager and workspace tool. All services are uv workspace members. `uv.lock` pins all transitive deps. `uv run` executes in the correct virtualenv. Installed to `~/.local/bin/uv`.

**virtual key** — A LiteLLM scoped API key. One virtual key per Hermes profile, created by `scripts/setup/setup-litellm-keys.sh`. Stored as `LITELLM_MASTER_KEY` in each profile's `.env`. Enables per-profile spend tracking via `user_id` in LiteLLM `SpendLogs`.

**wikilinks** — `[[concept]]` style inline links in vault note bodies. Obsidian-compatible. Link to existing notes or ghost links (notes not yet written). Over time the vault becomes a navigable graph.

**wire-hermes-profile** — `scripts/setup/wire-hermes-profile.sh`. Symlinks a Hermes profile's files from `~/.hermes/profiles/<name>/` into `hermes/profiles/<name>/` (this repo). Run after `hermes profile create <name>`.

**zakat** — Annual obligatory charity in Islamic finance. 2.5% of zakatable wealth held above nisab for a full hawl. Calculated by Ayah via `calculate_zakat` at hawl end using live gold price.
