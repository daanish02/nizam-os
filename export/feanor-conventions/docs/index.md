---
type: catalog
title: Feanor Maintainer Documentation
description: Catalog of maintainer-facing documentation about Feanor itself — orientation, capability tiers, security posture, audit history, and design decisions; descriptive, never loaded by an execution agent.
applies_to: [maintainer]
tags: [docs, maintainer, index]
---

# Feanor Maintainer Docs

**Audience: whoever maintains Feanor.** Not the agent, and not a target project's team.

Feanor has three distinct documentation audiences, and keeping them separate is what stops the corpus becoming unnavigable:

| Location | Audience | Nature |
| :--- | :--- | :--- |
| `conventions/`, `agents/`, `meta/`, `workflows/` | the execution agent | Normative, imperative, loaded Just-In-Time |
| a target project's `docs/` | that project's team and client | Product documentation Feanor *generates* |
| **`feanor/docs/` (here)** | **the maintainer** | Descriptive — what this system is and why |

**These files are never loaded by an execution agent.** They are excluded from Context Resolver retrieval by `meta/context-resolver.md` §2. Nothing here is a rule an agent follows; everything here is context for a human deciding what the rules should be.

## Contents

- [OVERVIEW.md](./OVERVIEW.md) — Start here. What Feanor is, why it is shaped this way, how the pieces fit, and where the known gaps are.
- [CAPABILITIES.md](./CAPABILITIES.md) — The three-tier model: what every project gets, what it gets because of what it is, and what is opt-in. Also the basis for what you tell a client.
- [SECURITY-POSTURE.md](./SECURITY-POSTURE.md) — How secure Feanor itself is, and what security properties the code it produces has. Standing answer, updated by audits.
- [AUDIT-LOG.md](./AUDIT-LOG.md) — Append-only history of maintenance audits, so posture is tracked over time rather than rediscovered each run.
- [DECISIONS.md](./DECISIONS.md) — Why Feanor is built the way it is. The rationale that would otherwise live only in scattered code comments.
- [EXTENDING.md](./EXTENDING.md) — Where to register a new convention, script, template, agent, or workflow so it is actually reachable. Read before adding anything.
