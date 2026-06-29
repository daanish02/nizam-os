# Gap Analysis — Vision vs Current State
> Generated 2026-06-29. Vision defined in docs/vision.md.

---

## What Hermes Provides Natively

These require zero custom code — config + SOUL.md only.

| Capability | Hermes Feature | Status in Project |
|---|---|---|
| Multi-profile agents | Profiles system | ✅ 4 of 7 profiles exist |
| Discord interface | Discord gateway | ✅ Configured |
| WhatsApp interface | WhatsApp gateway | ⚠️ Not configured yet |
| Skill self-update oversight | `guard_agent_created` + `write_approval` | ✅ Enabled in assistant config |
| Skill update approval via Discord | `approvals.mode: manual` | ✅ Configured |
| Cron / scheduled tasks | Built-in cron | ✅ Available, not yet used for automation |
| Sub-agent delegation | `delegate_task` tool | ✅ Available |
| Multi-agent coordination | Kanban board | ✅ Available, not yet wired |
| Memory per profile | MEMORY.md + USER.md | ✅ Working |
| Hooks (lifecycle logging) | hooks config | ⚠️ Not set up for audit trail |
| Voice mode | TTS/STT | ✅ Available (unused) |
| Vision / image input | vision toolset | ✅ Available |
| Code execution | code_execution toolset | ✅ Available |
| Browser / web | browser + web toolsets | ✅ Available |
| Persistent goals | goals feature | ✅ Available, unused |
| Session search | session_search toolset | ✅ Available |
| LLM routing / fallbacks | LiteLLM proxy | ✅ Running |
| Curator (skill maintenance) | curator profile | ✅ Profile exists |

---

## What Has Been Built (Custom)

### Profiles
| Profile | Agent | Status |
|---|---|---|
| `admin` | System admin | ✅ Exists with SOUL, TOOLS, PROTOCOL, HEARTBEAT |
| `assistant` | Alex (personal) | ✅ Exists with SOUL, config |
| `cos` | Raha (Chief of Staff) | ✅ Exists with SOUL, config |
| `curator` | Noor (Knowledge) | ✅ Exists with SOUL, TOOLS, config + MCP wired |
| `cto` | Arwa | ❌ Missing |
| `cfo` | Omar | ❌ Missing |
| `cmo` | Mira | ❌ Missing |
| `coo` | Hala | ❌ Missing |

### Services
| Service | What It Does | Status |
|---|---|---|
| `knowledge-service` | MCP server: vault search, read, add, ingest URL + YouTube | ✅ Built, wired to curator |
| `finance-service` | Finance ledger, multicurrency, zakat, riba, invoices | ❌ Does not exist |
| `personal-service` | Habits, goals, tasks, journaling | ❌ Does not exist |
| `system-monitor` | Health checks, safe restarts, alerts | ❌ Does not exist |
| `crm-service` | Client tracking, lightweight CRM | ❌ Does not exist |

### Database Schemas
| Schema | Purpose | Status |
|---|---|---|
| `knowledge` | vault_index, vault_embeddings, vault_audit | ✅ Migration exists (0001) |
| `personal.finance` | Personal ledger, accounts, categories | ❌ Missing |
| `personal.life` | Habits, goals, tasks, journal | ❌ Missing |
| `business.finance` | Business ledger, invoices, clients | ❌ Missing |
| `business.crm` | Clients, contacts, pipeline | ❌ Missing |
| `audit` | Immutable append-only audit log (all domains) | ❌ Missing |

### Knowledge Service — Ingestion Coverage
| Source Type | Status |
|---|---|
| URL / web page | ✅ `ingest_url` built |
| YouTube transcript | ✅ `ingest_youtube` built |
| Plain text | ✅ `add_note` built |
| PDF | ❌ Missing |
| PPT / slides | ❌ Missing |
| Audio (voice note, podcast) | ❌ Missing |
| Video (local file) | ❌ Missing |
| Image (OCR / vision) | ❌ Missing |
| Kindle highlights | ❌ Missing |

---

## What Is Yet to Be Built

Ordered by priority (personal first, business later per your instruction).

### Priority 1 — Personal Foundation

**Finance service (personal)**
- PostgreSQL schemas: `personal.finance` — accounts, transactions, categories (L1+L2), FX rates table
- Multi-currency: INR, AED, USD, SAR-ready. Store original + base (USD) + FX rate at entry
- Zakat module: gold price API → nisab calc → hawl tracking → obligation report
- Riba ledger: separate table, flagged at entry, never counted in net worth
- Audit log: append-only `audit` schema, no DELETE, every write logged
- MCP server exposing tools to Alex

**Personal life service**
- Habit tracker: habit definitions, daily logs, streaks (code, not LLM)
- Goal tracker: goals, milestones, check-ins
- Task manager: tasks with due dates, priority, status (or integrate with Hermes Kanban)
- Journal: structured prompts system, entry storage, search
- MCP server exposing tools to Alex

**Knowledge ingestion expansion**
- PDF parser (pdfminer / pymupdf)
- PPT parser (python-pptx)
- Audio transcription (Whisper local or via LiteLLM)
- Video: extract audio → transcribe
- Image: vision model → extract text / describe

**Vault walker AI**
- Trigger: cron (weekly) OR condition (N new notes since last run, configurable threshold)
- Method: Hermes delegation → child agent reads vault via knowledge-service → reasons across notes → produces insight report
- Output: Discord message to `#noor` + markdown file written to vault under `meta/`
- Entirely within Hermes capabilities (cron + delegation + knowledge-service MCP)

**System health monitor**
- Code-based (not LLM): bash/Python check loop
- Checks: Hermes gateway, LiteLLM, Postgres, knowledge-service, all systemd units
- Safe auto-restart: only idempotent restarts (systemctl restart), no data ops
- Alert: Discord webhook on failure
- Can run as systemd service or Hermes cron

### Priority 2 — Personal Completion

**Alex profile hardening**
- Wire personal-service MCP to Alex config
- Wire finance-service (personal) MCP to Alex config
- SOUL.md refinements once tools are live
- Discord channels: `#alex`, `#finance-personal`, `#journal`, `#habits`

**Vault tooling**
- Obsidian vault path defined, symlinked or mounted
- Note writer: Hermes writes frontmatter-correct .md files via knowledge-service

### Priority 3 — Business (when confident)

**Missing profiles**
- `cfo` (Omar): wire finance-service business schema
- `cto` (Arwa): wire GitHub MCP, code review skills
- `cmo` (Mira): wire LinkedIn MCP (custom), content calendar
- `coo` (Hala): wire CRM MCP, email MCP, WhatsApp gateway

**Business services**
- Finance service (business schema): separate from personal, same service, different schema
- Invoice system: PDF generation (reportlab/weasyprint), payment tracking, auto-reminders
- CRM service: clients, contacts, deal pipeline, lightweight (custom)
- WhatsApp gateway: configure Hermes WhatsApp for client comms

**Business channels**
- `#raha`, `#omar`, `#arwa`, `#mira`, `#hala`, `#audit-log`

---

## What Cannot Be Met (Limitations)

| Vision Item | Why It Can't / Won't Work As Described |
|---|---|
| Immutable audit log (truly tamper-proof) | PostgreSQL append-only is soft-immutable (superuser can delete). True immutability needs WORM storage or blockchain anchoring. Recommendation: append-only table + no DELETE grant to service user + periodic hash-chain snapshot. Good enough for internal audit, not court-grade. |
| Obsidian real-time sync to VPS | Obsidian runs locally. Vault on VPS = no local GUI without sync tool (Obsidian Sync paid, or Syncthing free). Agents write to VPS vault; you view via Syncthing-synced local Obsidian. |
| Gold price — live at all times | Needs external API key (goldprice.org, metals-api). Free tiers have rate limits. Zakat calc at hawl time is fine; real-time gold tracking requires paid tier. |
| LLM-free finance entry | Vision says LLM parses natural language → code commits. Correct approach. But: LLM parsing can misread amounts, currencies, counterparties. Mitigation: always show parsed result for confirmation before commit. Cannot fully remove LLM from NL→structured parse step without rigid input format. |
| Vault walker "reasoning across entire vault" in one shot | Context window limits. A vault of 500+ notes cannot fit in one LLM context. Mitigation: chunked traversal with delegation (child agents per domain/tag cluster), then synthesizer agent. Works but adds latency and cost. |
| Agent isolation as strong security boundary | Hermes profile tool restrictions limit what agents can do but profiles run on same VPS, same Postgres user (potentially). True blast-radius isolation needs separate DB users per schema (already in migration — `svc_knowledge`) and no cross-schema grants. Must be enforced at DB level, not just prompt level. |

---

## What's Possible With Hermes (Not Yet Used)

These are Hermes capabilities not yet wired that directly serve the vision:

| Feature | Use Case | Action Needed |
|---|---|---|
| Hermes cron | Morning brief, vault walker trigger, health checks, zakat hawl reminder | Wire cron jobs per profile |
| Delegation | Vault walker (parallel domain traversal), research tasks | Define delegation pattern in skills |
| Kanban | Cross-agent task handoff (Raha → Omar, Raha → Arwa) | Wire when business profiles exist |
| WhatsApp gateway | Client comms via Hala | Config in Hala profile |
| Goals (persistent) | Long-running personal goals (fitness, learning target) | Wire to Alex |
| Hooks | Log every tool call to structured JSON file | Add pre/post tool hooks in config |
| Voice mode | Voice journaling, quick habit log | Enable in Alex config |
| Checkpoint + rollback | Safe experimentation in Hermes config | Enable per-profile |
| Memory providers (Honcho / Mem0) | Richer cross-session memory | Evaluate after base is stable |

---

## Summary

| Area | State |
|---|---|
| Hermes infrastructure | ✅ Solid — profiles, LiteLLM, Discord, curator all working |
| Knowledge service | ✅ Core built — needs ingestion format expansion |
| Finance (personal) | ❌ Entire build needed |
| Personal life (habits/tasks/journal) | ❌ Entire build needed |
| Business profiles (CTO/CFO/CMO/COO) | ❌ Not started — correct, by design |
| Business services (finance/CRM/invoices) | ❌ Not started — correct, by design |
| System health monitor | ❌ Not built |
| Vault walker AI | ❌ Not built (feasible with cron + delegation) |
| Audit logging via hooks | ❌ Not wired |
| WhatsApp for client comms | ❌ Not configured |
