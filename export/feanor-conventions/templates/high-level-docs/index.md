---
type: template
title: High-Level Docs Selection Guide
description: YAGNI-based selection heuristic for deciding which docs/ artifacts to generate during /hld — lists every candidate template and the conditions that justify generating it.
applies_to: [hld, architecture]
tags: [template, high-level-docs, architecture]
---

# High-Level Docs Selection Guide

`docs/` holds a project's high-level docs — durable, high-value references, not implementation detail. Generating one of these is **not automatic**: pick the subset the project actually needs. Apply YAGNI — a doc that would sit empty or duplicate another doc doesn't get created.

**Never link or reference a `feanor/`/`conventions/`/`.feanor/` path from any file generated into `docs/`.** Everything under `docs/` is a deliverable that persists on `main`; `feanor/` and `.feanor/` are stripped before a branch reaches it (`git/branch-strategy.md`'s "Feanor Scoping"). A reference from a persistent doc into build-time-only tooling becomes a dead link exactly when the doc is read by someone without Feanor installed — describe every approach standalone, in plain terms, not by pointing at internal machinery.

## Always required

- **[ARCHITECTURE.md](./architecture-template.md)** — every project gets one. It's the minimum viable high-level doc: system topology, components, tech stack.
- **[SCAFFOLD.md](./scaffold-template.md)** — every project gets one. The declared directory structure `/scaffold` builds from: services, the domain packages each owns, shared code, and any deviation from the language layout. Decisions only — never lockfiles, caches, or build output.
- **[TESTING.md](./testing-template.md)** — every project gets one. Test layout, tiers, run commands, and an honest statement of what the suite covers. Generated during `/scaffold` and kept up to date as the suite grows. Since TDD is mandatory, a project without this doc has no shared language for where the safety net holds.
- **PRD.md** — produced earlier by the `/prd` phase (`templates/prd-template.md`), not by `/hld`. Listed here only because it's part of the same "high-level docs" family.

## Conditionally mandatory — not a judgment call

`SECURITY.md` **and** `THREAT-MODEL.md` are both **required** when *any* of the following is true. This is a deterministic check, not the architect's assessment of whether the project "feels" security-sensitive:

- the system authenticates users; or
- it stores Confidential or Restricted data per `conventions/cross-stack/data-protection.md`; or
- it is multi-tenant; or
- it accepts input from, or sends data to, a third party; or
- it is reachable from the public internet.

| Doc | Template |
| :--- | :--- |
| [SECURITY.md](./security-template.md) | Controls, data classification, PII inventory, accepted risks |
| [THREAT-MODEL.md](./threat-model-template.md) | Trust boundaries and STRIDE findings — method in `meta/threat-model.md` |

When none of the conditions holds, state that explicitly in `ARCHITECTURE.md` ("no authentication, no personal data, no network surface — security docs N/A") rather than omitting them silently. A missing security doc and a deliberately-absent one look identical in a repo, and only one of them is fine.

## Select if applicable

| Doc                                                     | Generate when...                                                                                                                              |
| :------------------------------------------------------ | :-------------------------------------------------------------------------------------------------------------------------------------------- |
| [SCHEMAS.md](./schemas-template.md)                     | The project persists structured data (DB tables/collections, message schemas) worth documenting independent of migration files.               |
| [APIS.md](./apis-template.md)                           | The project exposes an API consumed by another service or a separate frontend. Skip for a single-process script/CLI with no API surface.      |
| [UI.md](./ui-template.md)                               | The project has a user-facing interface with non-trivial flows/states worth documenting beyond the code itself.                               |
| [DEPLOYMENT.md](./deployment-template.md)               | The project deploys somewhere non-trivial (more than "run one script") — multiple environments, infra dependencies, a real release process.   |
| [RUNBOOK.md](./runbook-template.md)                     | The project runs in production and someone will need to respond to an incident — on-call steps, common failure modes, recovery procedures.    |
| [EXTERNAL-SERVICES.md](./external-services-template.md) | The project depends on third-party services/APIs (payment processor, LLM provider, email service, etc.) worth tracking in one place.          |
| [PLAN.md](./plan-template.md)                           | The project has a forward-looking roadmap worth keeping separate from the PRD's frozen requirements — near-term milestones, known follow-ups. |

## Rule

If a candidate doc's content would just repeat what's already in ARCHITECTURE.md or the PRD, don't create it. If mid-project a new need emerges that clearly deserves its own high-level doc and isn't covered above, propose it — this list isn't exhaustive.

## Diagrams

Regardless of which docs are selected, see [diagrams-guide.md](./diagrams-guide.md) for the three Excalidraw diagrams generated alongside them.
