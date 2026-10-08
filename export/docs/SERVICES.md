---
title: Services — nizam-os (Personal Domain)
status: DRAFT
version: 0.2.0
date: 2026-09-10
scope: personal
derived_from: docs/ARCHITECTURE.md, docs/SRS.md
---

# Services

The capability surface: what each service owns, who may call it, and the
contract it holds to. Concrete tool signatures, parameters and tunables are
specification tier and live in `docs/specs/`.

**Two rules shape everything here.**

Agents hold no state access. Every read and write goes through a service, and
a service connects to the database as its own role. Isolation is enforced below
the application layer *(C-07, C-08)*.

A service does not know which agent is calling it. Capability is filtered on
the agent's side by its declared set. This is what makes the roster cheap to
change: adding capability means building or extending a service, never editing
an agent.

> **Placeholders.** `[PENDING — SRS Q<n>]` marks a contract detail that depends
> on an unresolved question in `docs/SRS.md`. Nothing marked that way has been
> assumed.

---

## Surface

All services bind to loopback only *(C-25)*. Ports are an implementation
detail recorded in `docs/specs/`; nothing outside the machine can reach any of
them.

| Service | Owns | Callers | State |
| :--- | :--- | :--- | :--- |
| `knowledge` | Vault ingestion, classification, indexing, retrieval | Noor, Hakim, Rashid, Ayah (read only) | `knowledge` schema + the vault |
| `personal` | Tasks, habits, goals, journal | Ayah | `personal` schema + journal files |
| `finance` | Transactions, accounts, budgets, reconciliation, zakat | Ayah | `finance_personal` schema |
| `math` | Exact arithmetic on money | Ayah, Rashid | None |
| `investment` | Brokerage reads | Rashid | None |

---

## `knowledge`

**Owns** the owner's vault: taking a source in, deciding what it is, storing it
durably, and finding it again.

**Capabilities** — ingest from a web link, a video, or a document; propose a
classification; write an approved note; retrieve by meaning and by wording;
read a note.

**Contract**

- **No vault write without the owner's approval.** Ingestion is two-pass:
  produce a complete draft, present it, write only on approval. A rejected
  draft leaves nothing behind *(FR.03.4.1)*.
- **The service proposes the classification; the owner never supplies it.**
  Title, subject areas and tags are the service's job. Asking the owner to
  categorise would reintroduce the filing work the capability exists to remove
  *(FR.03.2.1)*.
- Subject areas come from a controlled vocabulary; tags are unconstrained
  *(FR.03.2.2)*.
- **The vault file is authoritative.** The index is derived and rebuildable
  from files alone *(NFR.07, NFR.08)*.
- Retrieval combines meaning-based and word-based matching into one ranked
  result, and **degrades to word-based alone when embedding is unavailable,
  saying so** rather than failing *(FR.03.3.2, FR.03.3.3)*.
- Extraction attempts an alternative method before reporting failure
  *(FR.03.1.3)*.

**Boundaries** — Noor and Hakim read and write. Rashid writes screening notes
and reads. Ayah reads only; the assistant does not curate.

**Untrusted input.** This service is the system's main ingress for content
nobody controls. Every fetch is address-filtered, size-capped and timed out;
every resolved path is containment-checked; external tools are invoked without
a shell *(C-15, C-16, C-17, C-18)*. Fetch limits `[PENDING — SRS Q4]`.

---

## `personal`

**Owns** tasks, habits, goals and the journal. Ayah is the sole caller — no
other agent reaches this domain, and journal content is reachable by no other
agent at all *(C-10)*.

**Capabilities** — create and transition a task; record a habit completion and
report its streak; hold goals; write a journal entry.

**Contract**

- A task's terminal states are **complete** and **abandoned**, and they are
  distinct *(FR.02.3.1)*.
- A habit's streak is derived from its logs and schedule at read time, never
  stored. A stored counter drifts and there is then no way to tell which is
  right *(FR.05.1.2)*.
- A repeated completion for the same date does not double-count *(FR.05.1.1)*.
- **A journal entry is written to the vault and indexed. If either fails, the
  operation is reported as a failure — never as a partial success**
  *(FR.05.3.2, C-14)*.
- The vault file is authoritative; the indexed copy exists for search only.

`[PENDING — SRS Q10]` Goals and journal may be out of scope for the first
cycle. The owner named tasks and habits; these two were carried from earlier
material and are unconfirmed.

---

## `finance`

**Owns** the owner's money. Ayah is the sole caller.

**Capabilities** — record a transaction and a transfer; report spending by
period and category; report balances and position; hold budgets and report
against them; compute zakat.

**Contract**

- **Every amount is an integer in the currency's smallest sub-unit. No
  floating-point arithmetic on money, anywhere, ever** *(NFR.05, FR.01.1.3)*.
- **An unrecognised category is refused, never invented** *(FR.01.1.2)*. The
  vocabulary is the owner's.
- **A transfer between the owner's own accounts is not spending** and never
  appears as such in a report. Cross-currency transfers record sent and
  received amounts separately, with any fee separate again *(FR.01.1.4)*.
- **No converted figure is presented without its rate and as-of time**
  *(FR.01.3.2)*.
- Category totals reconcile exactly to period totals *(NFR.06)*.
- Recurring and irregular costs are spread across the months they cover, so an
  annual charge is twelve monthly impacts rather than one spike *(FR.01.2.3)*.
- **Zakat is computed at request time and stored nowhere.** The result states
  the threshold used, its source and its as-of time. A computation whose inputs
  could not be retrieved **fails rather than substituting a default**
  *(FR.01.5.1, FR.01.5.2)*.

`[PENDING — SRS Q1]` If zakat is Obligation-class rather than Expectation, the
correctness bar on this service rises across the board.

---

## `math`

**Owns** exact arithmetic. Stateless: no database, no writes, no memory.

**Capabilities** — sub-unit-safe arithmetic, currency conversion, compound
interest, amortisation, zakat arithmetic.

**Contract**

- Deterministic and stateless. The same inputs always produce the same output.
- Holds no data and reaches no schema.

**Why it exists as a callable capability rather than as reasoning.** An agent
doing arithmetic inside its own reasoning will eventually get it wrong in a way
nothing detects, because there is no artefact to check. Making arithmetic a
call means every financial figure has a derivation that can be verified and
repeated *(NFR.05)*.

---

## `investment`

**Owns** reads from the brokerage. Rashid is the sole caller. Stateless.

**Capabilities** — current positions, watchlist, price data, filing data.

**Contract**

- **No capability to place, modify or cancel an order exists.** Not disabled,
  not approval-gated: absent from the service entirely *(FR.07.1.2, T-28)*.
- **The brokerage is the sole record of holdings. No copy is stored**, so no
  stored figure can diverge from the truth *(FR.07.1.3, T-29)*.
- Every figure carries its source and as-of date *(FR.07.3.2)*.
- **A required input that cannot be retrieved yields an explicit inconclusive
  result, never an assumed one** *(FR.07.3.3)*.
- Brokerage credentials are held here and are never in an agent's reach
  *(C-23)*.

Screening output is qualitative and is written to the vault through
`knowledge`, not stored as rows here *(FR.07.4.1)*.

---

## Agent capability sets

Each agent's declared set. Anything absent is invisible to that agent, not
merely refused *(C-02)*.

| Agent | Services | Host access | Delegation | Scheduling |
| :--- | :--- | :--- | :--- | :--- |
| **Nazim** | none | **Enabled** — allowlisted invocations, scoped privilege | No | Permitted, mandate requires it |
| **Noor** | `knowledge` (full) | No | No | Denied |
| **Ayah** | `personal` (full), `finance` (full), `math` (full), `knowledge` (read) | No | No | Permitted, mandate requires it |
| **Hakim** | `knowledge` (read + write) | No | **Yes** — bounded | Denied |
| **Rashid** | `investment` (full), `math` (full), `knowledge` (read + write) | No | **Yes** — bounded | Denied |

Delegation and scheduling bounds: `[PENDING]`.

**Applied to every agent without exception:** approval required on every state
change; no runtime capability acquisition; instruction accepted only from the
owner's identity; secret redaction on; channels scoped to the agent's own.
Full checklist: `docs/SECURITY.md` §6.

**Nazim holds host access and no service access.** It is the only agent that
can execute on the machine and the only one that reaches no data — the
separation is deliberate. The highest-privilege agent should have nothing to
exfiltrate, and the data-holding agents should have no way to execute.

---

## The external-agent boundary

**Not built.** Described here because the containment model has to exist before
the interface opens, not after.

The system will expose an interface by which an agent built outside it can be
delegated a task and return a result, **without any existing agent being
modified to accommodate it** *(FR.06.4.1, NFR.20)*.

**Contract, non-negotiable**

- An external agent is bound by **the same approval gate** as an internal one.
  Interoperation widens who may participate; it never widens what may happen
  unapproved *(FR.06.4.2, NFR.21)*.
- Its capability set is declared and scoped exactly as an internal agent's is.
- Its identity is verified before any task is accepted *(C-24)*.
- Its identity is recorded on every action it takes or contributes to
  *(FR.06.4.3, C-13)*.
- **A result it returns is untrusted content** — equivalent to fetched web
  content. It may not become action except through the approval gate, and may
  not be interpolated into a command or a query *(C-19, T-40)*.
- Delegation depth and concurrency are bounded across the system boundary as
  within it *(FR.06.4.4)*.

Opening this interface creates a new trust boundary and requires the threat
model to be re-run. Pre-conditions: `docs/SECURITY.md` §6.

---

## Adding a service

The full checklist is `docs/SECURITY.md` §6. In summary: loopback only; its own
database role granted minimally; insert-only on the change record; no hardcoded
secret; every query parameterised; every path containment-checked; every fetch
filtered and bounded; every write attributed; and an adversarial test for each
control it implements.

---

## Open items

| # | Item | Affects |
| :--- | :--- | :--- |
| 1 | Behaviour when inference is unavailable. `[PENDING — SRS Q2]` | **Every service contract.** Whether a capability degrades or fails is unresolved and must be settled before specs are written. |
| 2 | Fetch size cap and timeout. `[PENDING — SRS Q4]` | `knowledge` |
| 3 | Delegation depth and concurrency bounds. `[PENDING]` | Hakim, Rashid, external agents |
| 4 | Whether goals and journal are in the first cycle. `[PENDING — SRS Q10]` | `personal` |
| 5 | Whether zakat is Obligation-class. `[PENDING — SRS Q1]` | `finance`, `math` |
