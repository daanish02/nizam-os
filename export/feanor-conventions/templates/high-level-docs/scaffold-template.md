---
type: template
title: Scaffold Structure Template
description: Blueprint for docs/SCAFFOLD.md — the declared directory structure /scaffold builds from, listing only meaningful directories and what each owns.
applies_to: [scaffold, hld]
tags: [template, scaffold, layout]
---

# Project Structure

> **Status:** Declared at `/hld`, built by `/scaffold`.

This is the **input** to scaffolding, not a snapshot of it. It records decisions — which services exist, which domains each owns — so `/scaffold` can build the tree and `/audit` can check the tree still matches.

**List only what was decided.** No `uv.lock`, `.venv/`, `node_modules/`, `__pycache__`, `.next/`, or build output: those are consequences of the toolchain, not choices, and a document that lists them drifts the moment anything is installed. If a line would be identical for every project using this stack, leave it out — the language conventions already specify it.

---

## Services

One entry per independently deployable unit. Each gets its own Dockerfile and `.dockerignore`.

| Directory | Language | Owns | Deployable |
| :--- | :--- | :--- | :--- |
| `{{backend/ or services/<role>/}}` | {{Python / Go}} | {{one sentence: what this service is responsible for}} | yes |
| `{{frontend/}}` | {{TypeScript / Next.js}} | {{...}} | yes |

Use `backend/` when there is exactly one backend service. With more than one, every backend service moves to `services/<role>/`, named for its role rather than its language — see `conventions/{python,go}/project-layout.md`.

## Domain Packages

The domains each service owns, derived from the SRS and the topology above. These become `app/<domain>/` (Python), `internal/<domain>/` (Go), or `src/features/<domain>/` (Next.js), with tests mirroring them.

| Service | Domain | Owns |
| :--- | :--- | :--- |
| `{{backend}}` | `{{orders}}` | {{what belongs in this package and what does not}} |
| `{{backend}}` | `{{billing}}` | {{...}} |
| `{{frontend}}` | `{{orders}}` | {{the pages and components for this domain}} |

A domain is a business capability, not a technical layer. `orders` is a domain; `models`, `services`, and `handlers` are not — those are the layers *inside* each domain package.

## Shared Code

Only genuinely cross-domain code, used by 2+ domains. Not a catch-all — anything used by one domain lives in that domain's package.

| Path | Holds |
| :--- | :--- |
| `{{backend/app/utils/}}` | {{e.g. db session factory, date helpers}} |
| `{{frontend/src/lib/}}` | {{e.g. fetch wrapper, formatters}} |

## Deviations

Anything that departs from the language's `project-layout.md`, and why. An empty section is the expected case — a deviation is a decision that needs a reason, and one without a reason here is a mistake, not a choice.

- {{none / the deviation and its justification}}
