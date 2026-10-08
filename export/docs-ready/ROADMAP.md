---
title: Roadmap — nizam-os
status: LOCKED
version: 1.0.0
date: 2026-09-26
---

# Roadmap

## Cycle 1 (building now)

The executable plan is in `export/00-START-HERE.md`. This is the summary for
orientation. **Before Phase 1**, the host layer comes from
`nizam-dotfiles/docs/RUNBOOK.md` (Machine setup): SSH, UFW, fail2ban,
Tailscale, Prometheus/Grafana/Loki.

1. **App dependencies.** Postgres + pgvector, Redis, uv, age/sops, dbmate, and
   the age key.
2. **Database.** The audit schema and per-domain roles.
3. **LiteLLM + secrets pipeline + `deploy.sh`.** This is the first live unit, so
   it ships through the release-dir deploy from day one.
4. **`nizam` package skeleton + knowledge domain.** Includes the approval
   draft-token core and the `nizam-mcp` daemon, verified standalone.
5. **Hermes + Discord + Nazim and Noor.** Includes the `nizam-approval` plugin,
   the `nizam-mcp` unit and the embedding-retry timer.
6. **Observability + backups.**
7. **Finance + calc + Ayah.**

There is no fixed calendar. Each phase ends with a real end-to-end check
against the running system before the next one starts.

## Cycle 2 (deferred — do not build without a fresh go-ahead)

In no particular committed order; re-prioritize when cycle 1 is stable in daily use:

- **Personal tracking** (CP.02, CP.05) — tasks, habits, goals, journal. Requirements already drafted in the archived prior SRS; goals and journaling specifically were flagged as possible scope creep even then (SRS Q10, resolved for cycle 1 as "defer everything in CP.02/05") — re-confirm with the owner whether all four (tasks, habits, goals, journal) are wanted or just tasks/habits.
- **Self-maintenance** (CP.04) — the system watches its own health and, within strict bounds, repairs itself, beyond what Nazim's cycle-1 restart allowlist already covers.
- **Investment review** (CP.07) — read-only brokerage synthesis with religious compliance screening. Blocked on: which brokerage, its read API, and the zakat-adjacent religious determinations (nisab basis, purification ratio) that Q-F4 already flags as needed for finance's zakat feature too — likely worth resolving both at once.
- **Business domain** — explicitly out of scope indefinitely, not merely deferred. Requires its own requirements pass from scratch if ever revisited; the old business-agent design in `export/docs/archive-reference/business-future/` is reference material only, not a plan to execute.

## Non-goals, permanently

- Multi-tenancy, multi-user, or any second identity.
- A web UI or mobile app as a primary interface — Discord is the surface, by design, not by omission.
- Horizontal scaling — this runs on one small VPS by design; if it ever needs more than that, the growth is in what agents *do*, not in adding infrastructure.
