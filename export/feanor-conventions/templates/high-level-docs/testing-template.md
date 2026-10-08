---
type: template
title: TESTING.md Template
description: Blueprint for docs/TESTING.md — documents test tiers, directory layout, run commands, and coverage intent; generated during /scaffold and updated as the suite grows.
applies_to: [hld, testing]
tags: [template, testing]
---

# Testing

> **Project:** {{PROJECT_NAME}}

## Status

Canon. Update when test layout, tiers, markers, or run commands change. Build progress lives in `PLAN.md`, not here.

---

## What This Suite Covers

One short paragraph — not a list of every test, but the honest answer to "what can I trust this suite to catch?" Name the critical paths and domain logic under test, and be explicit about what is NOT covered yet. A reader should finish this paragraph with a clear sense of where the safety net holds and where it doesn't.

> Example: "The suite covers the full order lifecycle (creation → payment → fulfilment → cancellation) including all error branches. Auth middleware and rate-limit enforcement are tested at the API layer. Data-pipeline transforms are unit-tested in isolation. Frontend integration and e2e flows are not automated — TypeScript and manual QA are the gate there."

---

## Test Layout

{{For each service/component, show the test directory tree and what each folder targets.}}

### {{COMPONENT_NAME}} (`{{COMPONENT_DIR}}/tests/`, {{TEST_RUNNER}})

Layout mirrors `{{COMPONENT_DIR}}/{{SOURCE_ROOT}}/`, one subdirectory per domain:

```
tests/
├── {{DOMAIN_A}}/     # {{WHAT_THESE_TESTS_COVER}}
├── {{DOMAIN_B}}/     # {{WHAT_THESE_TESTS_COVER}}
└── {{SHARED}}/       # shared fixtures, factories, test utilities
```

Repeat this block for each service that has a test suite.

---

## Test Tiers

Three tiers, separated by marker. The split is mechanical — the principle is: fast feedback first, real dependencies by explicit opt-in only.

| Tier                  | Marker                   | What runs                                                               | Speed          | When to run                                      |
| :-------------------- | :----------------------- | :---------------------------------------------------------------------- | :------------- | :----------------------------------------------- |
| **Unit / mocked**     | _(no marker — default)_  | Pure logic + boundary mocks. No real DB, network, or external services. | Fast (< 5s)    | Every save, every commit                         |
| **Integration**       | `{{INTEGRATION_MARKER}}` | Real DB, real queues, no external network calls.                        | Medium (5–60s) | Pre-push, CI on PR                               |
| **End-to-end / live** | `{{E2E_MARKER}}`         | Full stack, real external services. Writes real data, costs real money. | Slow (60s+)    | Deliberate, not in CI against shared credentials |

> Adjust tier names and markers to match the test runner in use. The table structure stays the same.

### Mocking boundary

Unit tests mock at system boundaries only: external HTTP, the database, time, and randomness. Never mock own domain classes, services, or utilities — if internal code is hard to test without mocking it, the abstraction boundary is wrong.

---

## Running Tests

### {{COMPONENT_NAME}}

```bash
# Default: unit/mocked tier only
{{DEFAULT_RUN_COMMAND}}

# Integration tier (real DB, no external network)
{{INTEGRATION_RUN_COMMAND}}

# Full e2e (real external services — run deliberately)
{{E2E_RUN_COMMAND}}
```

Repeat per service. Keep commands exact and copy-pasteable — someone landing here cold should be able to run the suite without reading any other file.

---

## CI

CI runs the **default (unit/mocked) tier only** on every push. Integration and e2e tiers require explicit opt-in — never run them against shared or production-adjacent credentials in an automated context without dedicated test infrastructure.

```yaml
# .github/workflows/test.yml excerpt
- run: { { CI_TEST_COMMAND } } # default tier, no live markers
```

---

## Writing New Tests

- Red first — write the failing test before any implementation.
- One behavior per test. Name it `test_<what>_<condition>_<expected>`.
- Test the public boundary (the seam), not implementation internals.
- If a test requires mocking an internal class to pass, the design has a boundary problem — fix the design.
