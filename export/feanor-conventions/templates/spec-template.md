---
type: template
title: Spec Template
description: Per-domain implementation contract blueprint (one file per domain) — covers API endpoints, data entities, flows, MCP tools, and acceptance criteria; the architect engine fills this during /specs.
applies_to: [specs]
tags: [template, specs, contracts]
---

# Spec: {{DOMAIN_NAME}}

> **File:** `docs/specs/NNN-{{domain}}.md`
> **Scope:** {{What domain this covers, e.g. "Auth — registration, login, token refresh, user entity"}}
> **Builds on:**
>
> - `docs/PRD.md` § {{relevant section}} — requirements and user flows driving this domain
> - `docs/ARCHITECTURE.md` § {{relevant section}} — component responsible, auth boundary, error envelope
> - `docs/APIS.md` / `docs/SCHEMAS.md` — surface overview (do not repeat; only add implementation detail)
> - `docs/specs/NNN-{{other-domain}}.md` — if this domain depends on another spec's types

Do not restate what these docs already say. Add only: step-by-step logic, validation rules with business reasons, error taxonomy, field semantics, invariants, state transitions.

---

## Open Questions

Any unresolved decision that would affect implementation. Block dependent tickets in `plan.toml` until resolved.

- [ ] {{Question}} — {{who resolves / what triggers resolution}}

Remove section when empty.

---

## Shared Types

Name every shape used across more than one endpoint or entity in this domain. Reference by name below — do not repeat inline.

```
{{TypeName}}
  {{field}}:  {{type}}  — {{what it means; format/range/allowed values if constrained}}
  {{field}}:  {{type}}  — {{constraint and business reason}}
```

Omit section if nothing is shared.

---

## API

_(Include when this domain has HTTP endpoints or MCP tools. One subsection per endpoint/tool. Omit section entirely if domain has no API surface.)_

### `{{HTTP_METHOD}} /{{path/:param}}`

**Auth:** {{Bearer JWT | API key | none}} — {{any additional permission check}}

**Logic (execution order):**

1. {{Validate — name each field, the rule, what fails it and with which error code}}
2. {{Business rule check — e.g. "verify workspace not suspended; if so → 403 WORKSPACE_SUSPENDED"}}
3. {{DB / external call — what is read or written, to which store, under what condition}}
4. {{Side effects — e.g. "enqueue welcome email", "invalidate cache key `user:{id}`"}}
5. {{Return success response}}

Every step that can fail must name the failure. No "handle errors appropriately."

**Request:**

```
Body (application/json):
  {{field}}:  {{type}}  required  — {{business constraint, e.g. "1–100 chars, unique per workspace"}}
  {{field}}:  {{type}}  optional  — {{default and what it controls}}

Path params:  {{param}}: UUID — {{what entity it identifies}}
Query params: {{param}}: {{type}}  optional  default={{value}}  — {{what it filters}}
```

**Response — `{{STATUS_CODE}}`:**

```
  {{field}}:  {{type}}  — {{what it contains}}
```

**Error taxonomy:**

| Condition            | Status    | Code                  | Message              |
| :------------------- | :-------- | :-------------------- | :------------------- |
| {{specific trigger}} | `{{4xx}}` | `{{SCREAMING_SNAKE}}` | "{{Human-readable}}" |

Every error this endpoint can return must be in this table.

---

## Schema

_(Include when this domain owns data entities. One subsection per entity. Omit section entirely if domain owns no entities.)_

### `{{EntityName}}` → `{{table_or_collection_name}}`

```
id:           UUID          PK, generated server-side, immutable
created_at:   timestamp     not-null, default now(), immutable
updated_at:   timestamp     not-null, updated on every write

{{field}}:    {{type}}      not-null | nullable | unique | FK→{{other_table.field}}
              — {{what this field means in business terms}}
              — {{constraint reason: why not-null / why unique / what the FK enforces}}

{{status}}:   enum({{val1}}, {{val2}}, {{val3}})   not-null, default {{val1}}
              — legal transitions: {{val1}}→{{val2}}, {{val2}}→{{val3}} only
              — {{val1}}: {{meaning}}  |  {{val2}}: {{meaning}}  |  {{val3}}: {{meaning}}

{{field}}:    {{type}}      immutable after creation
              — {{why it must not change}}
```

**Relationships:**

- `{{EntityA}}` to `{{EntityB}}`: one-to-many — delete cascades | nullifies | restricted
- _(State cardinality and cascade rule for every relationship)_

**Indexes:**

| Name           | Fields      | Type         | Access pattern                                               |
| :------------- | :---------- | :----------- | :----------------------------------------------------------- |
| `{{idx_name}}` | `{{field}}` | unique btree | {{specific query this index serves — not "for performance"}} |

**Invariants** (application-layer unless noted as DB constraint):

- {{e.g. "user may not have more than one active subscription"}}
- {{e.g. "`cancelled_at` non-null if and only if `status = 'cancelled'`"}}

---

## MCP Tools

_(Include when this domain exposes tools over the MCP protocol — callable by an AI client, not a human or HTTP consumer. One subsection per tool. Omit section entirely if domain has no MCP surface.)_

MCP tools are functions, not endpoints. The contract has three audiences: the AI model reading the tool description to decide whether to call it, the AI runtime validating inputs, and the server implementation executing it.

### `{{tool_name}}`

**Description (shown to the model):** {{One sentence — what this tool does and when the model should choose it over alternatives. Be precise: a vague description causes the model to call the wrong tool or call it unnecessarily.}}

**When NOT to call this tool:** {{Conditions where the model might plausibly reach for this tool but shouldn't — e.g. "do not call if the data is already in context", "do not call for read-only lookups — use `{{other_tool}}` instead"}}

**Inputs:**

```
{{param}}:  {{type}}  required  — {{what it means; valid values or format}}
{{param}}:  {{type}}  optional  default={{value}}  — {{what it controls}}
```

**Logic (execution order):**

1. {{Validate inputs — name each param, the rule, what fails it}}
2. {{Core operation — what is read/written/computed}}
3. {{Side effects if any — what changes in external state as a result}}
4. {{Return}}

**Output:**

```
{{field}}:  {{type}}  — {{what it contains; what the model should do with it}}
```

**Error cases:**

| Condition            | Error returned to model         | Notes                                     |
| :------------------- | :------------------------------ | :---------------------------------------- |
| {{specific trigger}} | `{{error_code}}`: "{{message}}" | {{any recovery the model should attempt}} |

**Idempotent:** {{yes / no — can the model safely retry on failure?}}

---

## MCP Prompts

_(Include when this domain exposes MCP prompts — named, parameterized prompt templates the model can request by name. One subsection per prompt. Omit section entirely if domain has no MCP prompts.)_

MCP prompts are templates, not function calls. They return pre-filled message(s) the model uses as a starting point — the domain's canonical way to frame a task for the model.

### `{{prompt_name}}`

**Purpose:** {{What task this prompt frames and when the model should request it over alternatives}}

**Arguments:**

```
{{arg}}:  {{type}}  required  — {{what it controls in the rendered prompt}}
{{arg}}:  {{type}}  optional  default={{value}}  — {{what it controls}}
```

**Returns:** {{Describe the message(s) returned — role (user/assistant/system), what they contain, how the model should use them}}

**Example rendered output (with sample arg values):**

```
role: user
content: "{{what the filled prompt looks like}}"
```

---

## Flows

_(Include when this domain has a multi-step or async process that spans components or has non-trivial branching. Simple CRUD endpoints do not need a flow — the API section covers them. One subsection per flow.)_

### {{Flow Name}}

**Trigger:** {{What starts this flow — which endpoint, event, queue message, schedule}}

**Preconditions:** {{What must be true; what error if precondition fails}}

**Steps (execution order):**

1. **{{Step name}}** — Actor: `{{Component}}` — {{what it does, what it reads/writes}}
   - On failure: {{specific failure}} → {{retry N× / dead-letter / return error / alert}}

2. **{{Step name}}** — Actor: `{{Component}}` — {{action}}
   - Decision: if {{condition}} → step 3A; else → step 3B

3A. **{{Branch}}** — {{action}} → proceed to step 4
3B. **{{Branch}}** — {{action}} → flow ends with {{outcome}}

_(Every async handoff — queue publish, webhook, background job — is its own step naming what is sent and to where.)_

**Failure handling:**

| Step  | Failure              | Immediate action                                    | Recovery                                                          |
| :---- | :------------------- | :-------------------------------------------------- | :---------------------------------------------------------------- |
| {{N}} | {{specific failure}} | {{e.g. "mark order `payment_pending`, return 202"}} | {{e.g. "retry job every 30s up to 3×; then dead-letter + alert"}} |

**End state — success:** {{what is true in the system when flow completes}}

**End state — failure:** {{what is true if flow fails unrecoverably}}

**Idempotency:** {{Can this flow be safely retried? What prevents double-execution?}}

---

## Domain Invariants

Rules that cut across multiple endpoints, entities, or flows in this domain — stated once, not repeated inline:

- {{e.g. "all mutating endpoints reject requests if workspace status is `suspended`"}}
- {{e.g. "server generates all resource IDs; client-supplied IDs rejected with 400 CLIENT_ID_REJECTED"}}
- {{e.g. "soft-delete only — no hard deletes; `deleted_at` timestamp marks deletion"}}
