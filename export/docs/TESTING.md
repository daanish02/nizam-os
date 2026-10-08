---
title: Testing — nizam-os (Personal Domain)
status: DRAFT
version: 0.1.0
date: 2026-09-10
scope: personal
derived_from: docs/THREAT-MODEL.md §5, docs/SECURITY.md §5
---

# Testing

Where the safety net holds, and where it does not.

## Honest statement of current coverage

**There are no automated tests in this project today.** Not few — none. Linting
and type checking are configured but wired to no gate, so nothing runs them
automatically either.

That is stated plainly because a testing document that describes an aspiration
as though it were a practice is worse than no document: it tells a reader the
net exists when it does not. Everything below §1 describes what is being built
toward. Everything in this paragraph describes today.

The consequence worth understanding: **the invariants in `docs/SCHEMAS.md` and
the controls in `docs/SECURITY.md` are currently unverified.** They are
intentions. A control with no test that tries to defeat it is a claim.

---

## 1. What gets tested, and why those things

This system's stated priority is **containment, then correctness of the record,
then confidentiality, then availability** *(SECURITY §1)*. Test effort follows
that ordering rather than chasing a coverage percentage.

### Tier 1 — Security controls *(adversarial, non-negotiable)*

Every control in `docs/SECURITY.md` §5 needs a test that **supplies hostile
input and asserts refusal**. A test that confirms the happy path proves
nothing about a control; the control only exists at the boundary where it says
no.

| Control | The test must show |
| :--- | :--- |
| Path containment | A path escaping the vault root is refused |
| Fetch address filtering | Loopback, private-range, and redirect-to-private targets all refused |
| Command allowlist | An invocation composing or extending an allowlisted command is refused |
| Capability scoping | A capability outside an agent's set is unavailable, not merely refused |
| Schema isolation | A service reaching another domain's schema is refused by the database |
| Audit immutability | Update and delete on the change record are refused by grant |
| Sender identity | A message from any other identity produces no action |
| Approval gate | A state change without recorded approval does not execute |
| Query parameterisation | A value containing query syntax is stored as data, not interpreted |
| External-agent scoping | An external agent's unapproved action does not execute |

Two of these correspond to **high × high** threats and are the highest-value
tests in the project: path containment *(T-16)* and fetch filtering *(T-24)*.

### Tier 2 — Correctness invariants

The invariants in `docs/SCHEMAS.md` that, if violated, produce wrong figures
silently. Silence is what makes them worth testing more than most logic.

- Every monetary value round-trips exactly. No float ever touches money.
- Category totals reconcile exactly to period totals, for every period.
- A transfer between the owner's own accounts never appears as spending.
- No converted figure exists without its rate and as-of time.
- A habit streak derived from logs matches the schedule's definition, including
  rest days.
- A financial figure whose input could not be retrieved fails rather than
  defaulting.
- A half-completed write reports failure, never partial success.

### Tier 3 — Behaviour

Capability behaviour: ingestion produces a complete draft; retrieval returns
what it should; a task transitions correctly. Valuable, and lower priority than
the two tiers above.

### Not tested

- Model output quality. Non-deterministic and not a property of this codebase.
  Classification quality is governed by the approval gate, not by a test.
- Third-party availability.
- The dashboards.

---

## 2. Layout

Tests mirror the structure of what they test, so the test for a thing is
findable from the thing.

```text
<service>/
├── app/
│   └── <domain>/
└── tests/
    └── <domain>/          # mirrors app/ exactly
```

Fixtures shared across a service's tests live at that service's `tests/` root.

---

## 3. Tiers and when they run

| Tier | Contains | Runs |
| :--- | :--- | :--- |
| **unit** | Pure logic, invariants, control refusals with boundaries faked | Every commit. Must be fast enough that nobody is tempted to skip it |
| **integration** | Real database, real schema grants, real filesystem | Before merge. Grant isolation cannot be tested without a real database |
| **live** | Anything touching a third party | **Never by default.** Explicitly opt-in |

The live tier is opt-in because a test suite that hits a paid inference
provider or a brokerage on every run is a suite people stop running.

`[PENDING]` Which integrations have sandbox credentials — and therefore whether
their behaviour can be tested at all without touching live accounts — is
unrecorded. See `docs/INTEGRATIONS.md`.

---

## 4. How to write them

**Tests come before implementation.** Red, then green, then refactor as a
separate step.

**Expected values come from an independent source**, never from running the
code and recording what it produced. A test asserting that the code does what
the code does passes forever and proves nothing.

**Mock only at system boundaries** — a third-party API, the clock, randomness,
the network. Never mock the project's own components: a test that mocks the
thing under test is testing the mock.

**Money in tests is stated in sub-units**, like everywhere else. A test that
writes `10.50` has already violated the invariant it exists to protect.

---

## 5. Running

A single command runs lint, format check and the default tiers for every
component. It is what a commit gate runs and what a contributor runs by hand,
deliberately the same thing — a check that only exists in a pipeline is a check
nobody runs before pushing.

`[PENDING]` The command does not exist yet. It is a prerequisite for every
other testing task and should be the first thing built.

---

## 6. Definition of done

A change is not complete until:

- [ ] Its behaviour has a test that fails without the change.
- [ ] Any control it implements has an **adversarial** test.
- [ ] Any invariant it touches has a test asserting the invariant.
- [ ] The full check passes.

---

## 7. Open items

| # | Item | Blocks |
| :--- | :--- | :--- |
| 1 | The single check command does not exist. `[PENDING]` | Everything. Build first. |
| 2 | No test exists for any control or invariant. | Every claim in `docs/SECURITY.md` is unverified. |
| 3 | Sandbox credentials per integration unknown. `[PENDING]` | Whether the live tier is possible at all. |
| 4 | Performance targets unset. `[PENDING — SRS Q4]` | Nothing to assert a latency test against. |
