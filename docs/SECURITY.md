---
title: Security — nizam-os (Personal Domain)
status: DRAFT
version: 0.2.0
date: 2026-09-10
scope: personal
derived_from: docs/THREAT-MODEL.md, docs/SRS.md §7
---

# Security

Controls, data classification and accepted risks for the personal domain. The
threats these controls answer are in `docs/THREAT-MODEL.md`; this document is
the control register and the record of what was deliberately not controlled.

> **Placeholders.** A `[PENDING — SRS Q<n>]` marker means the control is
> designed but a value it needs is unresolved in `docs/SRS.md`. Nothing marked
> that way has been assumed.

---

## 1. Posture

This system authenticates no users, is reachable from no public network, and
serves exactly one person. It holds no third party's data and is bound by no
compliance framework. There is no external adversary with both motive and
reach.

**What it does hold is a complete picture of one person's finances and his
private journal, and it grants autonomous software the ability to act on his
behalf.** Security effort is therefore spent almost entirely on bounding what
the system may do on its own — not on defending a perimeter that nothing is
trying to cross.

The ordering that follows from this, and that governs every trade-off below:

**Containment > correctness of the record > confidentiality > availability.**

Availability is last deliberately. Nothing here carries an
Obligation-class penalty *(SRS §2)*; a day of downtime costs the owner
convenience. A wrong action taken on his behalf, or a corrupted financial
history, costs him something he cannot get back.

---

## 2. Data classification

| Category | Contents | Class | Retention |
| :--- | :--- | :--- | :--- |
| Financial records | Accounts, balances, transactions, counterparties, categories, budgets | **Confidential** | `[PENDING — SRS Q5]` |
| Journal entries | Reflective writing | **Confidential** — the most sensitive content held | `[PENDING — SRS Q5]` |
| Personal tracking | Tasks, habits, goals | Internal | `[PENDING — SRS Q5]` |
| Knowledge notes | Captured content and provenance | Internal — largely public material | Indefinite |
| Operational records | Change log, health metrics, spend | Internal — reveals behaviour patterns | `[PENDING — SRS Q5]` |
| Credentials | Provider keys, tokens, database roles, brokerage credential | **Restricted** | Until rotated |

**Not held, and worth stating:** no payment card data, no health or biometric
data, no government identifiers, no third party's personal data, no children's
data. No regulated category applies. No jurisdiction imposes a residency
requirement, because the owner is the only data subject.

---

## 3. Controls

Each control answers named threats. The full derivation is in
`docs/THREAT-MODEL.md`.

### 3.1 Autonomy containment — the primary control set

| # | Control | Answers |
| :--- | :--- | :--- |
| C-01 | Every state-changing action is presented to the owner and executes only on explicit approval. Reads execute freely. | T-07, T-23, AC.01 |
| C-02 | Each agent holds a declared capability set. Capabilities outside it are not merely refused but invisible to the agent. | T-05, AC.03 |
| C-03 | No component may install software or acquire capability while running. | T-10, AC.04 |
| C-04 | Delegation is bounded in depth and concurrency, and a sub-agent's actions remain subject to the approval gate. | T-11, T-41 |
| C-05 | Recurring scheduled work is denied by default, permitted only where a mandate requires it. | T-34, AC.09 |
| C-06 | Host command execution is restricted to one agent, bounded by an allowlist matching whole invocations, with privilege scoped to named operations. | T-32, T-33 |

### 3.2 Isolation

| # | Control | Answers |
| :--- | :--- | :--- |
| C-07 | Each service connects as its own database role, granted only on the schemas it owns. Isolation is enforced by the database, not by application logic. | T-06, T-14 |
| C-08 | Agents hold no database credentials. All state access is through a capability service. | T-06 |
| C-09 | Every value crossing into a query is bound as a parameter. No query is assembled by string composition. | T-13 |
| C-10 | Journal content is reachable only by the assistant. No other agent holds a capability for it. | T-18 |

### 3.3 Integrity of the record

| # | Control | Answers |
| :--- | :--- | :--- |
| C-11 | Every change is recorded with its acting agent, before and after state, and timestamp. | T-09 |
| C-12 | No service role holds UPDATE or DELETE on the change record. Append-only by grant. | T-12, AC.07 |
| C-13 | An action contributed by an external agent is recorded with that agent's identity. | T-39 |
| C-14 | A write that half-succeeds is reported as a failure, never as a partial success. | T-17 |

### 3.4 Untrusted input

Content the system fetches, and output the model produces, are both untrusted.
So is any result returned by an external agent.

| # | Control | Answers |
| :--- | :--- | :--- |
| C-15 | Every resolved file path must be contained within its intended root. Anything else is refused. | T-16 |
| C-16 | Outbound fetches reject non-public schemes and private address ranges, revalidated after every redirect. | T-24 |
| C-17 | Fetches carry a response size cap and a request timeout. Values `[PENDING]` — depend on NFR.01/02, themselves `[PENDING — SRS Q4]`. | T-25 |
| C-18 | External tools are invoked with an argument vector, never through a shell, with identifiers validated against an expected form first. | T-26 |
| C-19 | A result returned by an external agent is treated as untrusted content: it may not become action except through the approval gate, and may not be interpolated into a command or query. | T-40 |

### 3.5 Identity and secrets

| # | Control | Answers |
| :--- | :--- | :--- |
| C-20 | Instruction is accepted only from the owner's own identity. Every other sender is ignored. | T-01, AC.08 |
| C-21 | Secrets are encrypted at rest and never committed in plaintext. | AC.05 |
| C-22 | Known secret patterns are redacted from tool output before an agent sees them. Best-effort, explicitly not a guarantee. | T-20, AC.05 |
| C-23 | Provider and brokerage credentials are held by the service that uses them and are never in an agent's reach. | T-22, T-30 |
| C-24 | An external agent's identity is verified before any task is accepted, and it is bound by the same approval gate and capability scoping as an internal one. | T-37, T-38 |

### 3.6 Perimeter

Cheap, already in place, and not where the risk is.

| # | Control | Answers |
| :--- | :--- | :--- |
| C-25 | Every component binds to loopback. Nothing is publicly reachable. | — |
| C-26 | Management access is over a private network path, key-based, with password authentication disabled and repeated-failure banning in place. | — |
| C-27 | Operating system security updates are applied automatically, without automatic service restarts. | — |

### 3.7 Spend

| # | Control | Answers |
| :--- | :--- | :--- |
| C-28 | All inference passes through a single proxy where a ceiling is enforced. Ceiling figure `[PENDING — SRS Q3]`. | T-11, AC.06 |
| C-29 | Consumption is recorded per agent, so a runaway is attributable. | T-11 |

---

## 4. Accepted risks

Each of these is a decision, with a reason. The owner is the accepting party
for all of them, being the only party.

| # | Risk | Why accepted | Revisit when |
| :--- | :--- | :--- | :--- |
| **R-01** | **The owner approves a harmful action because the request looked plausible.** No automated inspection of a proposed action exists — the owner's judgment is the last control. *(T-08, AC.02)* | Automated inspection of model-proposed actions is not solved in general, and a wrong filter would either block legitimate work or give false confidence. Legible approval requests are the mitigation. | This is **the largest residual risk in the system.** Revisit if the owner ever approves something he regrets — the guardrail metric in `docs/PRD.md` §5 tracks exactly this. |
| **R-02** | **Confidential data is transmitted to a third-party model provider.** Any financial figure or journal entry an agent reasons over leaves the machine. *(T-19)* | Inherent to hosted inference. The alternative — local inference — costs capability the system depends on. | If local inference becomes good enough for the journal domain specifically. Worth its own decision record before the assistant is built. |
| **R-03** | The chat platform holds the full history of the owner's conversations, including financial figures and journal content. *(T-03)* | Inherent to using a hosted surface. Self-hosting the surface is deferred. | If the surface is ever self-hosted. |
| **R-04** | A compromise of the owner's platform account is indistinguishable from the owner. *(T-02)* | That account is the root of trust for the entire system. Mitigation is account hygiene, outside this system. | If the platform offers stronger binding than account possession. |
| **R-05** | Loss of the surface, or of the inference path, removes all interaction. *(T-04, T-21)* | No external party is harmed by an outage. Availability is the last priority by design. | Never, unless an Obligation-class problem appears. |
| **R-06** | A fetch reveals the owner's interests to an arbitrary third-party server. *(T-27)* | Inherent to fetching a URL he asked for. | Never. |
| **R-07** | Secret redaction is a best-effort pattern filter and will not catch an unrecognised secret format. *(T-20)* | A complete filter is not achievable. Defence is that secrets are held by services, not agents (C-23). | If a secret is ever observed in output. |

**Eliminated rather than mitigated** — worth recording, since eliminated risks
tend to be re-introduced by someone who does not know they were deliberate:

- **No capability to place, modify or cancel a brokerage order exists anywhere
  in the system.** Not disabled, not approval-gated: absent. *(T-28)*
- **No independent copy of brokerage positions is stored**, so no stored figure
  can diverge from the record. *(T-29)*

---

## 5. Verification

A control with no test that tries to defeat it is unverified. Each control
below needs a test that supplies the hostile input and asserts refusal — not a
test that confirms the happy path.

| Control | Adversarial test |
| :--- | :--- |
| C-15 path containment | A path escaping its root is refused. |
| C-16 fetch filtering | Loopback, private-range, and redirect-to-private targets are all refused. |
| C-06 command allowlist | An invocation composing or extending an allowlisted command is refused. |
| C-02 capability scoping | An agent invoking a capability outside its set fails, and cannot see it. |
| C-07 schema isolation | A service reaching another domain's schema is refused by the database. |
| C-12 audit immutability | An attempt to update or delete a change record is refused by grant. |
| C-20 sender identity | A message from any other identity produces no action. |
| C-01 approval gate | A state change without a recorded approval does not execute. |
| C-09 query parameterisation | A value containing query syntax is stored as data, not interpreted. |
| C-24 external agent scoping | An external agent's unapproved action does not execute. |

Test layout and tiers: `docs/TESTING.md`.

---

## 6. Checklists

### Adding an agent

- [ ] Capability set declared explicitly. No unrestricted access. *(C-02)*
- [ ] Approval gate on. *(C-01)*
- [ ] Runtime capability acquisition disabled. *(C-03)*
- [ ] Instruction restricted to the owner's identity; channels scoped. *(C-20)*
- [ ] Scheduling denied unless the mandate requires it. *(C-05)*
- [ ] Host access disabled unless the mandate requires it; if enabled, allowlisted. *(C-06)*
- [ ] Delegation disabled unless required; if enabled, depth and concurrency bounded. *(C-04)*
- [ ] Secret redaction on. *(C-22)*
- [ ] A dedicated database role if the agent's service needs one, granted minimally. *(C-07)*

### Adding a service

- [ ] Binds to loopback only. *(C-25)*
- [ ] Its own database role, granted only on schemas it owns. *(C-07)*
- [ ] Insert-only on the change record. No update, no delete. *(C-12)*
- [ ] No hardcoded secret. *(C-21)*
- [ ] Every query parameterised. *(C-09)*
- [ ] Every path input containment-checked. *(C-15)*
- [ ] Every outbound fetch address-filtered, size-capped and timed out. *(C-16, C-17)*
- [ ] Every write recorded with its actor. *(C-11)*
- [ ] Adversarial tests written for each control it implements. *(§5)*

### Opening the external-agent interface

Not yet built. Before it is:

- [ ] External identity verified before a task is accepted. *(C-24)*
- [ ] Approval gate applies identically to external agents. *(C-24)*
- [ ] External identity recorded on every contributed action. *(C-13)*
- [ ] Returned results treated as untrusted content. *(C-19)*
- [ ] Delegation bounded across the system boundary. *(C-04)*
- [ ] Threat model re-run — this opens a new trust boundary. *(TB-11)*

---

## 7. Open items

| # | Item | Blocks |
| :--- | :--- | :--- |
| 1 | Retention periods for every category. `[PENDING — SRS Q5]` | Bounds the exposure in R-02 and R-03. Currently undefined. |
| 2 | Inference spend ceiling. `[PENDING — SRS Q3]` | C-28 is designed but unenforced without a figure. |
| 3 | Fetch size cap and timeout values. `[PENDING — SRS Q4]` | C-17. |
| 4 | Boundary of safe unattended recovery. `[PENDING — SRS Q6]` | C-06's allowlist cannot be finalised. |
| 5 | Behaviour when inference is unavailable. `[PENDING — SRS Q2]` | Changes every service contract. |
