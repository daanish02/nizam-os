---
title: "Spec 004 — Personal Tracking"
status: DRAFT
version: 0.1.0
date: 2026-09-10
scope: personal
---

# Spec: Personal Tracking

> **File:** `docs/specs-new/004-personal.md`
> **Scope:** CP.02 and CP.05 — tasks, habits, goals, journal, and the scheduled
> daily summaries. Owns the `personal` schema.
> **Builds on:**
>
> - `docs/SRS.md` §5 CP.02, CP.05 — FR.02.1.1..FR.02.3.1, FR.05.1.1..FR.05.4.1
> - `docs/SCHEMAS.md` — `personal` entities
> - `docs/specs-new/001-knowledge.md` — journal entries are vault notes
> - `docs/specs-new/002-finance.md` — the briefing reports position

---

## Open Questions

- [ ] **Q-P1 — are goals and journal in scope?** `[PENDING — SRS Q10]`. The
      owner named **tasks and habits**. Goals and journal were carried from
      earlier material and never confirmed. **Both are specified here so the
      contract exists if wanted, and both are marked deferrable.** If out of
      scope, `goals` and `journal` leave the schema and this spec loses two
      sections. — Owner decides. **Blocking for those two sections only.**
- [ ] **Q-P2 — briefing delivery times.** FR.02.2.1 and FR.02.2.2 require a
      morning briefing and an evening recap "at a configured time". No times
      are configured. — Owner decides.
- [ ] **Q-P3 — habit schedule expressiveness.** "Every weekday", "three times a
      week", "every other day" are different kinds of rule, and the third is
      what makes a general recurrence syntax necessary. Whether the owner needs
      that generality or only fixed weekdays decides how streaks are computed.
      — Owner decides.
- [ ] **Q-P4 — reminder behaviour.** CP.02 is about not missing deadlines, and
      the daily briefing is the stated mechanism. Whether a task due today
      should also prompt outside the briefing is unspecified. — Owner decides.

---

## Shared Types

```
TaskStatus   enum(open, complete, abandoned)
             — legal: open->complete, open->abandoned,
               complete->open (reopen), abandoned->open (revive)
             — complete and abandoned are DISTINCT terminal states.
               Collapsing them loses the difference between what was done and
               what was dropped, which is most of what reviewing the record is for

Priority     enum(low, normal, high)

Energy       enum(low, medium, high)
             — how much capacity the task demands, distinct from priority.
               A high-priority low-energy task is the one to do when tired

GoalStatus   enum(active, achieved, abandoned, paused)   [Q-P1]

Schedule                            when a habit is expected   [Q-P3]
  kind:       string                daily | weekdays | weekly_count | custom
  days:       string[]?             for weekdays: MO..SU
  count:      integer?              for weekly_count: times per week
  rest_days:  string[]              days a miss does NOT break the streak
                                    — the distinction that makes streaks
                                      tolerable rather than punitive

StreakState                         always DERIVED, never stored  (P-3)
  current:    integer               consecutive scheduled completions
  longest:    integer
  last_on:    date?
  at_risk:    boolean               scheduled today and not yet logged
```

---

## MCP Tools

Reads free; writes approval-gated *(FR.06.2.1)*. Sole caller: the assistant.

### `create_task`

**Description:** Record a commitment the owner has stated.

**When NOT to call:** Do not call to log something already done — that is not a
task. Do not call for a recurring behaviour — use `define_habit`.

**Inputs:**

```
description:  string   required  — 1..500 chars
due_on:       date     optional
priority:     string   optional  default=normal
energy:       string   optional
goal_id:      integer  optional   [Q-P1]
approved:     boolean  optional  default=false
```

**Logic:**

1. Validate `description` non-empty after trim → `INVALID_DESCRIPTION`.
2. Validate enums → `INVALID_PRIORITY`, `INVALID_ENERGY`.
3. If `goal_id` supplied, resolve it → `GOAL_NOT_FOUND`. **A task with no goal
   is equally valid** *(FR.02.1.2)* — most tasks are not goal work, and
   requiring one would make capture heavier than the thing it replaces.
4. A past `due_on` is **accepted, not rejected** — the owner may be recording
   something already overdue, which is precisely when he most needs it recorded.
   Flag it in the draft.
5. **If not approved:** return the interpretation. Persist nothing. Stop.
6. Insert with `status=open`. Audit. Return.

**Output — created:** `status`, `id`, `description`, `due_on?`, `overdue: boolean`

**Error cases:** `INVALID_DESCRIPTION`, `INVALID_PRIORITY`, `INVALID_ENERGY`,
`GOAL_NOT_FOUND`, `STORE_UNAVAILABLE`.

**Idempotent:** no.

---

### `update_task`

**Description:** Change a task's state or fields.

**Inputs:**

```
id:           integer  required
status:       string   optional
description:  string   optional
due_on:       date     optional
priority:     string   optional
energy:       string   optional
approved:     boolean  optional  default=false
```

**Logic:**

1. Resolve → `TASK_NOT_FOUND`.
2. If `status` changes, validate the transition → `ILLEGAL_STATUS_TRANSITION`.
   **`complete` and `abandoned` are not interchangeable** — the model must not
   mark a dropped task complete because the owner said "forget it".
3. On transition to a terminal state, set `closed_at`. On reopen, clear it.
4. **If not approved:** return before and after. Persist nothing. Stop.
5. Update, audit with before and after state, return.

**Error cases:** `TASK_NOT_FOUND`, `ILLEGAL_STATUS_TRANSITION`, validation errors.

**Idempotent:** yes — converges on the same field values.

---

### `list_tasks`

**Description:** List tasks by status, due window or goal.

**Inputs:**

```
status:    string   optional  default=open
due_from:  date     optional
due_to:    date     optional
priority:  string   optional
goal_id:   integer  optional   [Q-P1]
limit:     integer  optional  default=50  — 1..200
```

**Logic:** validate; query with **every filter bound as a parameter** *(C-09)*;
order by due date ascending nulls last, then priority descending — the owner
asking "what's due" wants the soonest thing first, and an undated task is not
more urgent than a dated one.

**Output:** `count`, `tasks[]`, `overdue_count`

**Idempotent:** yes.

---

### `define_habit`

**Description:** Define a recurring behaviour to track.  `[Q-P3]`

**Inputs:**

```
name:       string   required  — 1..100, unique among active habits
schedule:   object   required  — Schedule
approved:   boolean  optional  default=false
```

**Logic:**

1. Validate `name` unique among active habits → `HABIT_EXISTS`.
2. Validate the schedule shape for its `kind` → `INVALID_SCHEDULE`.
3. Validate `rest_days` do not cover every scheduled day → `SCHEDULE_EMPTY`, which
   would define a habit that can never be missed and never be kept.
4. Approval-gated. Insert. Audit.

**Error cases:** `HABIT_EXISTS`, `INVALID_SCHEDULE`, `SCHEDULE_EMPTY`.

**Idempotent:** no.

---

### `log_habit`

**Description:** Record that a habit was performed on a date.

**When NOT to call:** Do not call twice for the same habit and date — it will be
refused, and refusing is correct.

**Inputs:**

```
habit:      string   required  — name or id
on_date:    date     optional  default=today
note:       string   optional
approved:   boolean  optional  default=false
```

**Logic:**

1. Resolve the habit → `HABIT_NOT_FOUND`. Reject inactive → `HABIT_INACTIVE`.
2. Reject a future date → `FUTURE_DATE`.
3. **If a log already exists for that habit and date, return `ALREADY_LOGGED`
   rather than inserting** *(FR.05.1.1)* — a repeated statement must not
   double-count, and a unique constraint on `(habit_id, on_date)` makes that
   structural rather than checked.
4. Approval-gated. Insert. Audit.
5. Return the **recomputed** streak *(P-3)*.

**Output:** `status`, `habit`, `on_date`, `streak: StreakState`

**Error cases:** `HABIT_NOT_FOUND`, `HABIT_INACTIVE`, `FUTURE_DATE`,
`ALREADY_LOGGED` (not an error the model should retry past).

**Idempotent:** effectively — a second identical call is refused, leaving one log.

---

### `report_habits`

**Description:** Report every active habit with its current streak.

**Inputs:** `as_of: date optional default=today`

**Logic:**

1. For each active habit, **derive** the streak from its logs and schedule
   *(P-3)*: walk backwards from `as_of`, counting consecutive scheduled days
   that have a log, treating `rest_days` as neither breaking nor extending.
2. Set `at_risk` when today is scheduled and unlogged.

**Output:** `as_of`, `habits[]` with name, schedule summary, `StreakState`.

**Idempotent:** yes.

---

### `write_journal`   `[Q-P1]`

**Description:** Record a reflective entry.

**Inputs:**

```
content:    string   required  — non-empty
entry_date: date     optional  default=today
approved:   boolean  optional  default=false
```

**Logic:**

1. Validate non-empty → `EMPTY_CONTENT`.
2. **If not approved:** return a preview. Persist nothing. Stop.
3. **Write the vault file first, then the index row** — the file is
   authoritative, exactly as in `001-knowledge` *(K-3)*.
4. **If either write fails, report failure — never partial success**
   *(FR.05.3.2, C-14)*. An entry the owner believes is saved and is not is the
   worst outcome in this domain: the content is gone and he does not know.
5. Audit. Return.

**Output:** `status`, `id`, `file_path`, `entry_date`

**Error cases:** `EMPTY_CONTENT`, `VAULT_WRITE_FAILED`, `INDEX_WRITE_FAILED`
(**file exists, index does not** — recoverable by reindex), `STORE_UNAVAILABLE`.

**Idempotent:** no. Multiple entries per day are valid.

---

### `manage_goal`   `[Q-P1]`

**Description:** Create a goal or change its state.

**Inputs:** `action` (create|update), `id?`, `title?`, `target_date?`,
`status?`, `approved`

**Logic:** validate; approval-gate; on transition to `achieved` or `abandoned`,
**report how many related tasks remain open** — closing a goal with open tasks
is legal but the owner should see it.

**Output:** `status`, `id`, `open_task_count`

**Idempotent:** `update` converges.

---

## Schema

### `Task` → `personal.tasks`

```
id:           bigserial     PK
description:  text          not-null
status:       text          not-null, default 'open'  — TaskStatus
priority:     text          not-null, default 'normal'
energy:       text          nullable
due_on:       date          nullable
goal_id:      bigint        nullable, FK->goals.id, set-null on delete   [Q-P1]
                            — nullable because most tasks are not goal work
closed_at:    timestamptz   nullable
                            — not-null if and only if status is terminal (P-2)
created_at:   timestamptz   not-null, default now()
updated_at:   timestamptz   not-null
```

### `Habit` → `personal.habits`

```
id:           bigserial     PK
name:         text          not-null
schedule:     jsonb         not-null  — Schedule   [Q-P3]
active:       boolean       not-null, default true
                            — deactivated, never deleted: logs must keep
                              resolving their habit
created_at:   timestamptz   not-null, default now()
```

Partial unique index on `(name) WHERE active` — one active habit per name, while
allowing a retired habit of the same name to remain in history.

### `HabitLog` → `personal.habit_logs`

```
id:         bigserial     PK
habit_id:   bigint        not-null, FK->habits.id, restrict
on_date:    date          not-null
note:       text          nullable
created_at: timestamptz   not-null, default now()
```

**Unique on `(habit_id, on_date)`** — this is what makes FR.05.1.1's
no-double-counting rule structural rather than a check that can be forgotten.

### `Goal` → `personal.goals`   `[Q-P1]`

```
id:           bigserial     PK
title:        text          not-null
status:       text          not-null, default 'active'
target_date:  date          nullable
closed_at:    timestamptz   nullable
created_at:   timestamptz   not-null, default now()
```

### `JournalEntry` → `personal.journal`   `[Q-P1]`

```
id:          bigserial     PK
file_path:   text          not-null, unique
                           — the vault file. AUTHORITATIVE  (NFR.07)
entry_date:  date          not-null
content:     text          not-null
                           — a copy held for search only. NOT authoritative
content_hash: text         not-null
created_at:  timestamptz   not-null, default now()
```

**Relationships:**

- `Goal` to `Task`: one-to-many, nullify on delete. A goal's removal orphans its
  tasks rather than destroying them — the work happened regardless.
- `Habit` to `HabitLog`: one-to-many, restrict. A habit with logs cannot be
  deleted, only deactivated.

**Indexes:**

| Name | Fields | Type | Access pattern |
| :--- | :--- | :--- | :--- |
| `task_status_due_idx` | `(status, due_on)` | btree | "What is open and due" — the briefing's main query |
| `task_goal_idx` | `goal_id` | btree | Tasks for a goal |
| `habit_log_uniq` | `(habit_id, on_date)` | unique btree | Enforces no double-counting |
| `habit_log_date_idx` | `(habit_id, on_date DESC)` | btree | Backward streak walk |
| `habit_active_uniq` | `(name) WHERE active` | partial unique | One active habit per name |
| `journal_date_idx` | `entry_date DESC` | btree | Recent entries |

**Invariants:**

- **P-1 — Distinct terminal states.** `complete` and `abandoned` are never
  conflated, in storage or in reporting.
- **P-2 — Closure consistency.** `closed_at` is non-null if and only if status
  is terminal.
- **P-3 — Streaks are derived, never stored.** No counter column exists. A
  stored counter drifts from the logs and there is then no way to tell which is
  right *(FR.05.1.2)*.
- **P-4 — One log per habit per day.** DB-enforced *(FR.05.1.1)*.
- **P-5 — Vault authority for journal.** The file is the record; the row is for
  search. A row without a file is inconsistent and reported as failure
  *(FR.05.3.2)*.
- **P-6 — Journal is assistant-only.** No other agent holds any capability
  reaching journal content *(C-10)*.
- **P-7 — Deactivate, never delete.** Habits and goals deactivate so history
  keeps resolving.

---

## Flows

### Morning briefing

**Trigger:** the configured morning time `[Q-P2]`.

**Preconditions:** none. **A missing input degrades the briefing; it never
cancels it** — a briefing that says "I could not reach your accounts" is useful;
silence is not.

**Steps:**

1. **Position** — Actor: `finance` — current balances and total.
   - On failure: include the failure in the briefing, continue.
2. **Due** — Actor: `personal` — tasks due today and overdue.
   - On failure: include the failure, continue.
3. **Habits** — Actor: `personal` — habits scheduled today, and those at risk.
4. **Compose and deliver** — Actor: the assistant.
   - On delivery failure: **record it** *(FR.02.2.3)*. A missed briefing that
     leaves no trace is indistinguishable from a day the owner ignored.

**End state — success:** delivered, with any partial failures named inside it.

**End state — failure:** a recorded delivery failure, retrievable later.

**Idempotency:** one delivery per day. A retry after a recorded failure must not
produce a second briefing.

---

### Evening recap

**Trigger:** the configured evening time `[Q-P2]`.

**Steps:** the day's spending *(`002-finance`)*; tasks closed today; habits
logged and still open; **then open a thread inviting a journal entry**
*(FR.02.2.2)*. A reply to that thread routes to `write_journal`, which is still
approval-gated — the owner confirms what will be stored.

---

### Streak derivation

**Trigger:** any read of habit state.

**Steps:** walk backwards from the reference date; for each day, classify as
scheduled, rest, or unscheduled; a scheduled day with a log extends the streak;
a scheduled day without one ends it; rest and unscheduled days pass through
untouched.

**Why derived rather than stored:** a stored counter must be updated on every
log, on every backdated log, on every schedule change, and on every deletion.
Each is a place to get it wrong silently. Derivation is always correct by
construction *(P-3)*.

---

## Domain Invariants

- Every write is approval-gated and audited.
- Every filter value is a bound parameter *(C-09)*.
- Streaks are computed, never stored *(P-3)*.
- Journal content never leaves the assistant's reach *(C-10)*.
- A journal write that half-succeeds reports failure *(P-5)*.
- Terminal task states are never conflated *(P-1)*.

---

## Acceptance Criteria

| # | Criterion | Traces to |
| :--- | :--- | :--- |
| D-01 | A stated task is created with description and optional due date | FR.02.1.1 |
| D-02 | A task with no goal is valid | FR.02.1.2 |
| D-03 | A task due in the past is accepted and flagged overdue | capture-first |
| D-04 | `complete` and `abandoned` are distinguishable after the fact | P-1, FR.02.3.1 |
| D-05 | `closed_at` is set exactly when status is terminal | P-2 |
| D-06 | **A second habit log for the same date is refused by the database** | P-4, FR.05.1.1 |
| D-07 | A miss on a rest day leaves the streak intact | FR.05.1.2 |
| D-08 | A miss on a scheduled day breaks the streak | FR.05.1.2 |
| D-09 | No stored streak counter exists in the schema | P-3 |
| D-10 | A backdated log recomputes the streak correctly with no repair step | P-3 |
| D-11 | The morning briefing arrives unprompted at the configured time | FR.02.2.1 |
| D-12 | A briefing with one failed input still delivers, naming the failure | resilience |
| D-13 | **A suppressed delivery leaves a retrievable failure record** | FR.02.2.3 |
| D-14 | A journal entry exists as both vault file and index row | FR.05.3.1 |
| D-15 | **An index write failing after a vault write reports failure, not success** | FR.05.3.2, P-5 |
| D-16 | No agent other than the assistant can reach journal content | C-10 |
| D-17 | Every write produces one audit row naming the actor | FR.06.3.1 |
| D-18 | Every personal capability is reachable from the one surface | FR.05.4.1 |

---

## Open Items

| # | Item | Blocks |
| :--- | :--- | :--- |
| 1 | Goals and journal in scope? `[Q-P1 / SRS Q10]` | Two tool sections and two entities |
| 2 | Briefing times. `[Q-P2]` | Both scheduled flows |
| 3 | Habit schedule expressiveness. `[Q-P3]` | `Schedule`, streak derivation |
| 4 | Reminders outside the briefing. `[Q-P4]` | Whether CP.02 is fully met |
