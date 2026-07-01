# Discord server — Darbar-e-Nizam

## Design principles

- **Categories are private by default.** Each agent sees only the channels relevant to its role. An agent that can't see a channel can't be accidentally triggered by it.
- **One channel, one purpose.** Blurry boundaries mean agents get confused context and you don't know where to look.
- **Output vs input.** Some channels are where you talk to an agent (input). Others are where agents post to you (output). A few are both. Knowing which is which prevents clutter.
- **No redundancy with existing tools.** Grafana handles real-time metrics. Hermes handles logs. Discord channels that duplicate these are removed.

---

## Server structure

### Start here (public)

| Channel | Type | Purpose |
|---|---|---|
| `#welcome` | Read-only | Server philosophy, what Nizam-OS is, how to use this server |
| `#server-map` | Read-only | Channel list, agent roster, permission overview — this doc in summary form |

No agents have access. Static reference for you.

---

### Personal (private)

Agents: **Ayah** (all but `#learning` channel) · **Noor** (`#learning` only)

| Channel | Type | Agent | Purpose |
|---|---|---|---|
| `#chat` | Input + output | Ayah | General conversation — tasks, questions, anything personal |
| `#briefing` | Output | Ayah | Scheduled daily brief: agenda, priorities, reminders. Ayah posts; you read |
| `#finances` | Input + output | Ayah | Finance queries, budget status, spending summaries |
| `#goals-tasks` | Input + output | Ayah | Goal tracking, task updates, habit streaks |
| `#journal` | Input + output | Ayah | Journal entries, reflections — prompted or free-form |
| `#learning` | Input + output | Noor | Learning tracker, reading notes, skill building. Noor curates; you add |

**Why Noor in `#learning` not Ayah:** Knowledge curation is Noor's role. Ayah handles personal execution; Noor handles what you're learning and how it connects to the knowledge base.

---

### System (private)

Agents: **Bani** (all channels)

| Channel | Type | Purpose |
|---|---|---|
| `#admin` | Input + output | Talk to Bani — system commands, skill approvals, config changes. **Skill Watcher webhook posts here.** |
| `#alerts` | Output (automated) | Grafana threshold breaches, service failures, health check anomalies. Bani may also post here. |
| `#sandbox` | Input + output | Scratch space — test commands, try things, no clean-up expected. One per server. |


---

### Chairman's office (private — user only)

No agents have access.

| Channel | Type | Purpose |
|---|---|---|
| `#strategy` | Read + write | Your planning space — active initiatives, future ideas, decisions made. No agent noise. |


---

### Arc Systems (private)

Agents: **Hala** (`#biz-chat`, `#boardroom`) · each C-suite agent in their own office only

| Channel | Type | Agent | Purpose |
|---|---|---|---|
| `#biz-chat` | Input + output | Hala | General business conversation — projects, status, coordination |
| `#boardroom` | Input + output | Hala | High-level decisions, strategy execution, cross-C-suite topics |
| `#cto-office` | Input + output | Arwa | Tech, architecture, dev projects |
| `#cfo-office` | Input + output | Omar | Finance, budgets, reporting |
| `#coo-office` | Input + output | coo | Operations, CRM, delivery |
| `#cmo-office` | Input + output | Mira | Marketing, content, brand |

**Why Hala can't see C-suite offices:** CoS coordinates at the board level, not inside each function. Each office is a private workspace for that agent + you. Hala gets outputs through `#boardroom`.

---

## Permission matrix

| Category | User | Bani | Ayah | Hala | Noor | Arwa | Omar | coo | Mira |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| Start Here | ✓ | | | | | | | | |
| Personal | ✓ | | ✓¹ | | ✓² | | | | |
| System | ✓ | ✓ | | | | | | | |
| Chairman's Office | ✓ | | | | | | | | |
| Arc Systems | ✓ | | | ✓³ | | ✓⁴ | ✓⁴ | ✓⁴ | ✓⁴ |

¹ Ayah: all Personal channels except `#learning`  
² Noor: `#learning` only  
³ Hala: `#biz-chat` + `#boardroom` only  
⁴ Each C-suite agent: their own office only

---

## Agents vs webhooks

**Agents** post through the Hermes bot (app). When Ayah sends a morning brief or Bani responds to a command, that's the bot speaking — not a webhook. Agent messages use the bot's identity; the channel name and context tell you which agent is talking.

**Webhooks** are separate, one-way automated integrations with no agent behind them. Used for system events that originate outside Hermes.

---

## Webhooks

Icons live in `assets/` in the GitHub repo.

| Webhook | Channel | Icon (from assets/) | Posts when |
|---|---|---|---|
| Skill Watcher | `#admin` | `warning` | Agent proposes a skill — embed with content, author, pending ID, approve/reject commands |

**Planned (not yet wired):**

| Webhook | Channel | Icon | Posts when |
|---|---|---|---|
| Grafana Alerts | `#alerts` | `error` / `critical` | Threshold breach, service down |

**Severity icon guide (assets/):**

| Icon | When to use |
|---|---|
| `debug` | Not wired to Discord — verbose system info for future use |
| `info` | Non-urgent automated notices |
| `warning` | Action needed, nothing broken — skill approval, stale flag, low disk |
| `error` | Something failed, system still running |
| `critical` | Intervention required — multiple services down, OOM |


---

## Recreating this server

```
1. Create server: "Darbar-e-Nizam"
2. Delete default channels

3. Categories + channels:
   Start Here      → public
     #welcome          (read-only for @everyone)
     #server-map       (read-only for @everyone)

   Personal        → private
     #chat
     #briefing
     #finances
     #goals-tasks
     #journal
     #learning

   System          → private
     #admin
     #alerts
     #sandbox

   Chairman's Office → private
     #strategy

   Arc Systems     → private
     #biz-chat
     #boardroom
     #cto-office
     #cfo-office
     #coo-office
     #cmo-office

4. Create roles: Bani · Ayah · Hala · Noor · Arwa · Omar · coo · Mira

5. Set permissions per permission matrix above

6. Add Hermes bot to server, assign each gateway its role

7. Create webhook: Skill Watcher → #admin
   Add to secrets/nizam.env: DISCORD_ADMIN_WEBHOOK=<url>

8. Pin #server-map with a summary of this doc
```

