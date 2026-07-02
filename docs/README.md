# Documentation

Three layers. Content belongs in exactly one place — cross-references are pointers, never copies.

---

### Reference `docs/*.md`

Stable contracts, one file per domain. Updated when the domain changes, not when phases complete.

**`VISION.md`** — Why this exists. North star, goals, constraints.  
**`ROADMAP.md`** — What and when. Phase statuses, build order. No design rationale, no tool detail.  
**`ARCHITECTURE.md`** — How the system fits together. Component map, data flows, design decisions. Brief rows; pointer to the relevant doc for detail.  
**`AGENTS.md`** — Per-agent contract: mandate, channels, toolsets, MCP access, command allowlists.  
**`SERVICES.md`** — Per-service contract: port, tool signatures, consumers, approval workflow, tunables.  
**`SCHEMAS.md`** — All DB schemas: full SQL, FK constraints, roles and grants, migration index.  
**`HERMES.md`** — Hermes config field reference. SOUL.md vs AGENTS.md rules. MCP transport patterns.  
**`DISCORD.md`** — Server channel map, bot setup, intents, webhooks, `DISCORD_ALLOWED_USERS`.  
**`INTEGRATIONS.md`** — External services: endpoint, auth var, rate limits, failure mode. Not rotation procedures.  
**`SECURITY.md`** — Threat model, controls per layer, known gaps, checklists. Exact allowlists live in AGENTS.md.  
**`SECRETS.md`** — Env var inventory: purpose, consumer, which phase adds it. Not rotation procedures.  
**`RUNBOOK.md`** — All procedures: fresh VPS rebuild, service management, secret rotation, common fixes.  
**`GLOSSARY.md`** — Term definitions.  
**`CONVENTION.md`** — Coding standards.

---

### Design `specs/*.md`

One file per phase. What was chosen to build and why — design decisions, schema choices, integration choices. No task lists, no terminal commands.

---

### Build &nbsp;`plans/*.md`

One file per phase. Ordered tasks, commands, test steps. Points to the matching spec for rationale. No design discussion.
