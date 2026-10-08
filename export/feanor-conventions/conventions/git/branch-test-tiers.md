---
type: convention
title: Branch Test Tiers
description: Required test scope and security gates that must pass before merging into each branch tier (feature, qa, main).
applies_to: [git]
tags: [git, testing, ci, security]
---

# Branch Test Tiers

Test scope grows with the branch tier. All required checks at a tier **MUST** pass before merge — none are advisory.

| Tier                  | Required to merge                                                                                                                              |
| :-------------------- | :--------------------------------------------------------------------------------------------------------------------------------------------- |
| `feature/*` / `fix/*` | Unit tests (fast, no live DB/LLM calls)                                                                                                        |
| `qa`                  | Unit tests + integration tests (real DB, mocked/sandboxed external services) + smoke test (app boots, critical endpoints respond)              |
| `main`                | Unit + integration + e2e tests + smoke test, **plus** security gate: `bandit` (Python) / `gosec` (Go) static analysis + secret scan (e.g. `detect-secrets`/`gitleaks`), all clean |

## Rules

- A merge to `qa` blocks on any unit, integration, or smoke test failure — no merging with known-red tests.
- A merge to `main` additionally blocks on `bandit`/`gosec` findings and secret-scan hits. Both must report clean, not just "no high-severity."
- Smoke tests run post-merge (post-deploy to the relevant environment), not pre-merge — they verify the deployed result, not the diff.
- `hotfix/*` merging directly to `main` still goes through the full `main`-tier gate — urgency doesn't waive the security/test bar.
- New test suites (e2e, security) live alongside the existing tiering convention from [../cross-stack/testing.md](../cross-stack/testing.md) — this file defines _which_ tiers gate _which_ branches, not how individual tests are written.
