---
title: Vision — nizam-os
status: LOCKED
version: 1.0.0
date: 2026-09-26
scope: personal
---

# Vision

nizam-os is a private AI operating system for one person. It replaces the manual operational work of Danish's personal life — tracking money, remembering commitments, retaining what he reads, keeping the system itself healthy — with a small team of autonomous agents, each owning a domain, all reachable through a single chat surface (Discord). No web UI, no mobile app, no server login in normal operation.

**Problem, in the owner's own words:** *"either it is manual, or I'm not doing anything. Where a thing is not manual, it simply does not happen."* The system exists so that operational upkeep no longer competes for the owner's attention with the decisions that actually need it.

**Scope: personal only, this cycle.** Business (a coordination layer with CFO/COO/CTO/CMO-style agents, CRM, client work) was explored in an earlier iteration of this project and deliberately dropped: *"let me limit myself only to the personal aspect for now."* It may return as a separate, later effort with its own requirements pass — never folded back into the personal system's scope without a fresh decision.

**Cycle 1 domains** (build now, in order):
1. **Knowledge** — capture and retrieve what the owner reads and studies.
2. **Personal finance** — spending visibility, position reporting, zakat.

**Cycle 2 domains** (deferred, do not build without explicit instruction):
3. Personal tracking — tasks, habits, goals, journal.
4. Self-maintenance — the system watches and, within strict bounds, repairs itself.
5. Investment review — read-only brokerage synthesis with religious compliance screening.

## Why this order

The owner named finance and knowledge as the two domains with the most standing cost today (financial blindness, and reading that doesn't compound). Tasks/habits and self-maintenance are valuable but lower-cost-of-delay; investment review depends on brokerage integration that hasn't been scoped. Building two domains well, end to end, with real daily use, is worth more than five domains half-built.

## Non-negotiable properties (every domain must honor these)

- **Single owner, single surface.** No second user, no roles, no tenancy. Every capability reachable from one Discord server.
- **Autonomy is bounded and reviewable.** Read-only actions execute directly. Every state-changing action requires the owner's explicit approval, is attributed to the acting agent, and is recorded append-only. See `docs/specs/004-agent-runtime.md`.
- **Money is exact.** Integer sub-units, never floating point. See `docs/specs/003-calc.md`.
- **The vault file is truth.** Knowledge notes are Markdown files in a git repo; any database index is a derived, rebuildable cache of them, never the other way round.
- **Everything degrades gracefully, nothing crashes silently.** If the LLM proxy is down, deterministic recording still works and the reasoning-dependent part is queued, not lost or crashed.
- **No component is reachable from the public internet** other than the management path (SSH via Tailscale). No compliance regime applies — this system holds one person's own data about himself, on his own machine — so proportion of effort goes toward containing the system's own autonomy, not perimeter defense against an external attacker with something to gain.

## What "done" looks like for cycle 1

The owner reports a transaction or asks about his spending, and captures or retrieves a piece of knowledge, entirely through Discord conversation, with zero manual bookkeeping or filing — and trusts the numbers and the notes enough to stop doing either by hand.
