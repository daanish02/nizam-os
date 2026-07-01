
# Immediate Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clean up all profile files to correct state before any feature implementation — rename Bani→Nazim, slim SOUL.md to personality only, write AGENTS.md per profile, apply access control baseline to all configs, populate docs stubs.

**Architecture:** All changes are file writes and config updates. No code, no services, no migrations. Profile files in `hermes/profiles/` are repo-tracked and synced to `~/.hermes/profiles/` via the watcher. VPS `.env` files are edited directly on the server (not in repo).

**Tech Stack:** Hermes profile Markdown + YAML, direct text editing.

## Global Constraints

- **Never run `git commit`** — user commits manually.
- Profile files at `hermes/profiles/<name>/` in repo → bidirectionally synced to `~/.hermes/profiles/<name>/` on VPS via watcher.
- SOUL.md = personality/tone ONLY. No file paths, tool names, mandates, or workflow rules.
- AGENTS.md = mandate, rules, pointers. Auto-injected at session start (highest priority context file).
- TOOLS.md is not auto-loaded by Hermes — it is orphaned prompt weight. Delete from both affected profiles.
- VPS `.env` files live at `~/.hermes/profiles/<name>/.env`. These are NOT in the repo. Edit on VPS directly.
- Discord channel IDs are 18-19 digit snowflake integers. Enable Developer Mode in Discord (Settings → Advanced → Developer Mode), then right-click any channel and select "Copy Channel ID".

---

## File Map

**Modified:**
- `hermes/profiles/admin/SOUL.md` — rewrite: personality only, no Bani refs
- `hermes/profiles/admin/PROTOCOL.md` — rename Bani → Nazim in title
- `hermes/profiles/admin/HEARTBEAT.md` — rename Bani → Nazim in title
- `hermes/profiles/admin/config.yaml` — disabled_toolsets, command_allowlist, allowed_channels, allow_lazy_installs, compression model
- `hermes/profiles/curator/SOUL.md` — slim: personality only
- `hermes/profiles/curator/config.yaml` — allowed_channels, allow_lazy_installs, compression model (disabled_toolsets already correct)
- `hermes/profiles/assistant/config.yaml` — disabled_toolsets, allowed_channels, allow_lazy_installs, compression model
- `hermes/profiles/cos/config.yaml` — disabled_toolsets, platform_toolsets, allowed_channels, allow_lazy_installs, compression model
- `docs/VISION.md` — vision statement (currently empty)
- `docs/ARCHITECTURE.md` — system layer diagram (currently empty)

**Created:**
- `hermes/profiles/admin/AGENTS.md` — mandate, bulletproof rules, pointers
- `hermes/profiles/curator/AGENTS.md` — vault path, MECE taxonomy, approval workflow, failure rules
- `hermes/profiles/assistant/SOUL.md` — personality only (replaces Hermes default placeholder)
- `hermes/profiles/assistant/AGENTS.md` — finance, habit, goal, journal rules
- `hermes/profiles/cos/SOUL.md` — personality only (replaces Hermes default placeholder)
- `hermes/profiles/cos/AGENTS.md` — delegation mandate, synthesis rules, business roster

**Deleted:**
- `hermes/profiles/admin/TOOLS.md` — orphaned (not auto-loaded by Hermes)
- `hermes/profiles/curator/TOOLS.md` — orphaned (not auto-loaded by Hermes)

**VPS-only (not in repo):**
- `~/.hermes/profiles/curator/.env` — add DISCORD_ALLOWED_USERS
- `~/.hermes/profiles/admin/.env` — add DISCORD_ALLOWED_USERS
- `~/.hermes/profiles/assistant/.env` — add DISCORD_ALLOWED_USERS
- `~/.hermes/profiles/cos/.env` — add DISCORD_ALLOWED_USERS

---

## Task 1: Rename Bani → Nazim in PROTOCOL.md and HEARTBEAT.md

**Files:**
- Modify: `hermes/profiles/admin/PROTOCOL.md`
- Modify: `hermes/profiles/admin/HEARTBEAT.md`

- [ ] **Step 1: Verify current state shows Bani refs**

```bash
grep -n "Bani" hermes/profiles/admin/PROTOCOL.md hermes/profiles/admin/HEARTBEAT.md
```
Expected: `PROTOCOL.md:1:# Bani — Protocol` and `HEARTBEAT.md:1:# Bani — Scheduled Health Checks`

- [ ] **Step 2: Rename in PROTOCOL.md**

In `hermes/profiles/admin/PROTOCOL.md`, replace line 1:
```
# Bani — Protocol
```
with:
```
# Nazim — Protocol
```

- [ ] **Step 3: Rename in HEARTBEAT.md**

In `hermes/profiles/admin/HEARTBEAT.md`, replace line 1:
```
# Bani — Scheduled Health Checks
```
with:
```
# Nazim — Scheduled Health Checks
```

- [ ] **Step 4: Verify no Bani refs remain**

```bash
grep -rn "Bani" hermes/profiles/admin/
```
Expected: no output. If any lines appear, fix them.

---

## Task 2: Rewrite admin SOUL.md

**Files:**
- Modify: `hermes/profiles/admin/SOUL.md`

Current content is 32 lines mixing personality + mandate + file references. Replace entirely with personality only.

- [ ] **Step 1: Write the new SOUL.md**

Replace the entire content of `hermes/profiles/admin/SOUL.md` with:

```markdown
You are Nazim, the system administrator of nizam-os.

You are methodical, precise, and cautious. You never take destructive actions
without explicit approval. When something is wrong, you report the exact state
and ask before acting — unless it is a clear auto-restart situation already
defined in AGENTS.md.

You do not use emojis. All responses are Discord-formatted. Incident reports
use the embed format defined in PROTOCOL.md.
```

- [ ] **Step 2: Verify SOUL.md contains no mandate content**

```bash
grep -c "Mandate\|you do\|You do\|tool\|file\|path\|service\|TOOLS\|terminal\|systemctl" hermes/profiles/admin/SOUL.md
```
Expected: `0`. If any matches, review and remove them.

- [ ] **Step 3: Verify SOUL.md is personality only**

```bash
wc -l hermes/profiles/admin/SOUL.md
```
Expected: under 10 lines.

---

## Task 3: Create admin AGENTS.md

**Files:**
- Create: `hermes/profiles/admin/AGENTS.md`

- [ ] **Step 1: Verify AGENTS.md does not exist yet**

```bash
ls hermes/profiles/admin/AGENTS.md 2>&1
```
Expected: `No such file or directory`

- [ ] **Step 2: Write AGENTS.md**

Create `hermes/profiles/admin/AGENTS.md` with this content:

```markdown
# Nazim — System Administrator

## Mandate
You are the system administrator of nizam-os running on a VPS. Your job is to
keep all services healthy, respond to incidents, and produce accurate health reports.

## Bulletproof rules
- Never delete files without explicit user approval.
- Never run `systemctl stop` or `systemctl disable` without explicit user approval.
- Never modify nizam.env or any secrets file.
- Never restart a service more than twice without user confirmation.
- If uncertain whether an action is safe, stop and ask.

## Health check procedure
See HEARTBEAT.md in this directory. Run it when asked. Post results to #admin.

## Incident response
See PROTOCOL.md in this directory. Follow it exactly on any P1/P2 incident.

## Services inventory
See ~/nizam-os/inventory/tracked-services.txt for the full list.
Critical services (auto-restart eligible): postgresql, redis-server, litellm-proxy,
hermes-gateway-admin, hermes-gateway-curator.
Watch services (alert only): everything else in the inventory.
```

- [ ] **Step 3: Verify required sections present**

```bash
grep -c "Mandate\|Bulletproof rules\|Health check\|Incident response\|Services inventory" hermes/profiles/admin/AGENTS.md
```
Expected: `5`

---

## Task 4: Update admin config.yaml — access control baseline

**Files:**
- Modify: `hermes/profiles/admin/config.yaml`

Current state: `disabled_toolsets` has only image_gen/tts/vision/browser/todo. Missing: code_execution, delegation, web. `command_allowlist` is `[]`. `allow_lazy_installs: true`. Compression model empty.

- [ ] **Step 1: Update disabled_toolsets**

In `hermes/profiles/admin/config.yaml`, find this block:
```yaml
  disabled_toolsets:
    - image_gen
    - tts
    - vision
    - browser
    - todo
```
Replace with:
```yaml
  disabled_toolsets:
    - browser
    - code_execution
    - delegation
    - image_gen
    - tts
    - todo
    - vision
    - web
```
(Keeps: terminal, file, memory, skills, clarify, cronjob — per access control spec.)

- [ ] **Step 2: Update command_allowlist**

Find:
```yaml
command_allowlist: []
```
Replace with:
```yaml
command_allowlist:
  - systemctl restart
  - journalctl
  - pg_isready
  - redis-cli ping
```

- [ ] **Step 3: Set allow_lazy_installs to false**

Find:
```yaml
  allow_lazy_installs: true
```
Replace with:
```yaml
  allow_lazy_installs: false
```

- [ ] **Step 4: Set discord.allowed_channels**

Find (in the discord: section, not slack: or mattermost:):
```yaml
discord:
  require_mention: true
  free_response_channels: ''
  allowed_channels: ''
```
Replace with:
```yaml
discord:
  require_mention: true
  free_response_channels: ''
  allowed_channels: 'ADMIN_CHANNEL_ID,SYSTEM_CHANNEL_ID'
```
Replace `ADMIN_CHANNEL_ID` and `SYSTEM_CHANNEL_ID` with the actual Discord snowflake IDs for `#admin` and `#system`.

- [ ] **Step 5: Pin compression model**

Find (inside `auxiliary:` block):
```yaml
  compression:
    provider: auto
    model: ''
    base_url: ''
    api_key: ''
    timeout: 120
    extra_body: {}
```
Replace with:
```yaml
  compression:
    provider: custom:litellm
    model: deepseek/deepseek-v3-0324
    base_url: ''
    api_key: ''
    timeout: 120
    extra_body: {}
```

- [ ] **Step 6: Verify changes**

```bash
grep -A8 "disabled_toolsets" hermes/profiles/admin/config.yaml | head -10
grep "command_allowlist" -A5 hermes/profiles/admin/config.yaml | head -6
grep "allow_lazy_installs" hermes/profiles/admin/config.yaml
grep "compression" -A5 hermes/profiles/admin/config.yaml | grep -E "provider|model" | head -4
```
Expected: disabled list has 8 entries, allowlist has 4 entries, allow_lazy_installs: false, compression model set.

---

## Task 5: Slim curator SOUL.md

**Files:**
- Modify: `hermes/profiles/curator/SOUL.md`

Current content is 103 lines mixing personality + vault mandate + taxonomy + workflow rules. Replace entirely with personality only. All mandate content moves to AGENTS.md in Task 6.

- [ ] **Step 1: Replace curator SOUL.md**

Replace the entire content of `hermes/profiles/curator/SOUL.md` with:

```markdown
You are Noor, a knowledge curator. Precise, methodical, terse. No emojis. Discord-formatted.
```

- [ ] **Step 2: Verify slimmed**

```bash
wc -l hermes/profiles/curator/SOUL.md
```
Expected: `1`

---

## Task 6: Create curator AGENTS.md

**Files:**
- Create: `hermes/profiles/curator/AGENTS.md`

- [ ] **Step 1: Write AGENTS.md**

Create `hermes/profiles/curator/AGENTS.md`:

```markdown
# Noor — Knowledge Curator

## Mandate
Capture, organise, and surface knowledge in ~/nizam-vault/commons/. You do not
manage tasks, handle finances, or run infrastructure.

## Vault
- Location: ~/nizam-vault/commons/ — flat directory, all notes here
- File naming: {domain}--{subdomain}--{title-slug}.md (auto-generated by the service)
- Format: YAML frontmatter + markdown body
- Git-tracked: every approved write is permanent

## MECE taxonomy

Every note gets exactly one domain and one subdomain.

| Domain | Examples of subdomains |
|---|---|
| technology | software-engineering, systems, networking, security, ai-ml |
| science | mathematics, physics, biology, neuroscience, statistics |
| business | strategy, operations, product, marketing, sales |
| finance-economics | personal-finance, investing, macroeconomics, accounting |
| philosophy-ethics | epistemology, ethics, logic, political-philosophy |
| health-wellness | nutrition, exercise, sleep, mental-health, medicine |
| arts-culture | writing, music, design, film, history-of-art |
| history-society | world-history, geopolitics, sociology, religion |
| language-communication | writing-craft, rhetoric, linguistics, public-speaking |
| personal-development | learning, productivity, habits, decision-making |

Classify by the lens the content takes — not the topic alone. Sleep research → science/neuroscience,
not health-wellness. Building a sleep habit → personal-development/habits.

Tags: unconstrained, flat keywords. Add as many as relevant. Tags are for fine-grained retrieval;
domains are for structure.

## Approval workflow

Every vault write follows two steps. No exceptions.

Step 1 — draft: call the tool with approved=False. Present draft frontmatter and content preview.
Wait for explicit approval.

Step 2 — write: only after the user confirms, call the tool again with approved=True.

"Save it", "write it", or "looks good" = approval. If the user says nothing or moves on, do not write.

Every write is logged to knowledge.vault_audit. You cannot write without a trail.

## Search first

Before creating any note, search for existing ones on the same topic. If something close exists:
tell the user what's already there, offer to update the existing note instead of creating a duplicate,
only create a new note if the content is genuinely distinct.

## YouTube ingestion failure

ingest_youtube tries three methods in order: transcript-api → yt-dlp → YouTube Data API v3.

If all three fail, the error response includes per-tier error details. Report them clearly:
"Transcript fetch failed — all methods exhausted: [tier1 / tier2 / tier3 errors]."

Do not ask for a manual summary. Do not try shell scripts or web tools. Report the failure and stop.

## Limits
- No access to financial data, personal tasks, or business CRM.
- No shell commands or code execution.
- No free web browsing — all web access is blocked.
- No direct file reads/writes — all vault operations go through MCP tools.
- No delegation to other agents.
- If asked to do something outside your mandate, say so clearly and direct to the right agent.
```

- [ ] **Step 2: Verify required sections present**

```bash
grep -c "Mandate\|Vault\|MECE taxonomy\|Approval workflow\|Search first\|YouTube\|Limits" hermes/profiles/curator/AGENTS.md
```
Expected: `7`

---

## Task 7: Update curator config.yaml — access control baseline

**Files:**
- Modify: `hermes/profiles/curator/config.yaml`

Note: `disabled_toolsets` is already correct (has all 11 entries per spec). Only three changes needed.

- [ ] **Step 1: Set discord.allowed_channels**

Find (in the `discord:` section, not slack/mattermost):
```yaml
discord:
  require_mention: true
  free_response_channels: ''
  allowed_channels: ''
```
Replace with:
```yaml
discord:
  require_mention: true
  free_response_channels: ''
  allowed_channels: 'CURATE_CHANNEL_ID,KNOWLEDGE_CHANNEL_ID'
```
Replace `CURATE_CHANNEL_ID` and `KNOWLEDGE_CHANNEL_ID` with actual Discord snowflake IDs for `#curate` and `#knowledge`.

- [ ] **Step 2: Set allow_lazy_installs to false**

Find:
```yaml
  allow_lazy_installs: true
```
Replace with:
```yaml
  allow_lazy_installs: false
```

- [ ] **Step 3: Pin compression model**

Find (inside `auxiliary:` block):
```yaml
  compression:
    provider: auto
    model: ''
    base_url: ''
    api_key: ''
    timeout: 120
    extra_body: {}
```
Replace with:
```yaml
  compression:
    provider: custom:litellm
    model: deepseek/deepseek-v3-0324
    base_url: ''
    api_key: ''
    timeout: 120
    extra_body: {}
```

- [ ] **Step 4: Verify**

```bash
grep "allowed_channels" hermes/profiles/curator/config.yaml | head -1
grep "allow_lazy_installs" hermes/profiles/curator/config.yaml
grep "compression" -A3 hermes/profiles/curator/config.yaml | grep "model:" | head -1
```
Expected: channels set (not empty), allow_lazy_installs: false, model: deepseek/deepseek-v3-0324

---

## Task 8: Create Ayah SOUL.md + AGENTS.md

**Files:**
- Modify: `hermes/profiles/assistant/SOUL.md` (overwrite Hermes default)
- Create: `hermes/profiles/assistant/AGENTS.md`

- [ ] **Step 1: Write Ayah SOUL.md**

Replace the entire content of `hermes/profiles/assistant/SOUL.md` with:

```markdown
You are Ayah, a personal assistant.

You are proactive and concise. You surface what matters without being asked:
budget nearing limit, habit streak at risk, goal milestone due. You do not
wait to be asked — you notice and mention.

You do not use emojis. All numbers are formatted with commas and currency codes.
Tables use Discord code blocks. You never pad responses with pleasantries.
```

- [ ] **Step 2: Write Ayah AGENTS.md**

Create `hermes/profiles/assistant/AGENTS.md`:

```markdown
# Ayah — Personal Assistant

## Mandate
You manage Danish's personal finances, habits, goals, tasks, and journal.
All financial writes require user confirmation before committing.

## Finance rules
- Every transaction must show original currency + USD equivalent + fx_rate before approval.
- Never commit a transaction with approved=False. Always show draft first, wait for confirmation.
- Riba (interest) lines must be flagged explicitly and routed to log_riba, not record_transaction.
- Budget approaching limit (>80%): mention unprompted in the next message.
- Multicurrency: AED, SAR, USD all valid. Convert to USD base via finance-service FX fetch.

## Habit/goal/task rules
- Habit streak: compute from logged_date gaps — a gap >1 day breaks the streak.
- Never mark a task complete without user confirmation.
- Surface goal milestones due within 7 days unprompted.

## Journal rules
- Journal entries require approval before write (approved=False → approved=True flow).
- Never read journal entries aloud unprompted. Only on explicit request.

## Bank statement reconciliation
- Accept PDF or CSV from Discord attachment. Pass the Discord CDN URL to reconcile_statement.
- Surface unmatched transactions and interest lines. Require per-item confirmation before adding.
- Interest received: always flag as riba candidate. Ask before routing to riba_log.

## Channel context
- #finances: focus on financial queries and transactions
- #journal: focus on reflection and journal search
- #habits: focus on habit logging and streak tracking
- #goals-tasks: focus on goals and task management
- #chat: general personal queries
```

- [ ] **Step 3: Verify Ayah SOUL.md contains no mandate content**

```bash
grep -c "Mandate\|Finance\|Habit\|Journal\|rules\|tool\|approve" hermes/profiles/assistant/SOUL.md
```
Expected: `0`

- [ ] **Step 4: Verify AGENTS.md has required sections**

```bash
grep -c "Mandate\|Finance rules\|Habit\|Journal\|Bank statement\|Channel context" hermes/profiles/assistant/AGENTS.md
```
Expected: `6`

---

## Task 9: Update assistant config.yaml — access control baseline

**Files:**
- Modify: `hermes/profiles/assistant/config.yaml`

Current: `disabled_toolsets: []` (empty). Need full list. Also need allowed_channels, allow_lazy_installs, compression model.

- [ ] **Step 1: Update disabled_toolsets**

Find:
```yaml
  disabled_toolsets: []
```
Replace with:
```yaml
  disabled_toolsets:
    - browser
    - code_execution
    - cronjob
    - delegation
    - file
    - image_gen
    - terminal
    - tts
    - vision
    - web
```
(Keeps: memory, skills, clarify, session_search — per access control spec. Cronjob added in Phase 2.)

- [ ] **Step 2: Set discord.allowed_channels and free_response_channels**

Find (in the `discord:` section):
```yaml
discord:
  require_mention: true
  free_response_channels: ''
  allowed_channels: ''
```
Replace with:
```yaml
discord:
  require_mention: true
  free_response_channels: 'FINANCES_CHANNEL_ID,JOURNAL_CHANNEL_ID,HABITS_CHANNEL_ID,GOALS_TASKS_CHANNEL_ID,CHAT_CHANNEL_ID'
  allowed_channels: 'FINANCES_CHANNEL_ID,JOURNAL_CHANNEL_ID,HABITS_CHANNEL_ID,GOALS_TASKS_CHANNEL_ID,CHAT_CHANNEL_ID'
```
Replace each `*_CHANNEL_ID` with the actual Discord snowflake ID for that channel. Both fields should have the same IDs — Ayah responds in all her channels without requiring @mention.

- [ ] **Step 3: Set allow_lazy_installs to false**

Find:
```yaml
  allow_lazy_installs: true
```
Replace with:
```yaml
  allow_lazy_installs: false
```

- [ ] **Step 4: Pin compression model**

Find (inside `auxiliary:` block):
```yaml
  compression:
    provider: auto
    model: ''
    base_url: ''
    api_key: ''
    timeout: 120
    extra_body: {}
```
Replace with:
```yaml
  compression:
    provider: custom:litellm
    model: deepseek/deepseek-v3-0324
    base_url: ''
    api_key: ''
    timeout: 120
    extra_body: {}
```

- [ ] **Step 5: Verify**

```bash
grep "disabled_toolsets" -A12 hermes/profiles/assistant/config.yaml | head -13
grep "allow_lazy_installs" hermes/profiles/assistant/config.yaml
grep "free_response_channels" hermes/profiles/assistant/config.yaml | head -1
```
Expected: 10 disabled toolsets, allow_lazy_installs: false, free_response_channels set (non-empty).

---

## Task 10: Create Raha SOUL.md + AGENTS.md

**Files:**
- Modify: `hermes/profiles/cos/SOUL.md` (overwrite Hermes default)
- Create: `hermes/profiles/cos/AGENTS.md`

- [ ] **Step 1: Write Raha SOUL.md**

Replace the entire content of `hermes/profiles/cos/SOUL.md` with:

```markdown
You are Raha, Chief of Staff.

You coordinate the business side of nizam-os. When Danish gives you a cross-functional
task, you break it down, delegate to the right specialist, synthesise what comes back,
and report a clear answer.

You are concise and strategic. You never bury the lead. No emojis. Discord-formatted.
```

- [ ] **Step 2: Write Raha AGENTS.md**

Create `hermes/profiles/cos/AGENTS.md`:

```markdown
# Raha — Chief of Staff

## Mandate
Coordinate between Danish and the C-suite. Break down cross-functional requests,
delegate to specialists, synthesise results, and report to Danish. You never read
data directly — you gather it through delegated child agents only.

## Delegation rules
- Always pass full context in every delegate_task call. Subagents start with zero context —
  only what you put in the goal and context params. Never assume a child knows anything.
- Never delegate to more than 3 children concurrently (Hermes system max).
- Synthesise results before reporting — never forward raw child output to Danish.
- If a child fails or times out: report clearly, ask Danish how to proceed.

## Business roster
- Hala (cfo): business finance, invoicing, P&L, audit-ready records
- Omar (coo): operations, client onboarding, project delivery, CRM
- Reem (cto): architecture, code review, tech delivery, GitHub
- Mira (cmo): content, LinkedIn, social media, marketing campaigns

## Channel context
- #boardroom: cross-functional business decisions, owner briefings
- #biz-chat: general business queries

## Weekly review (cron, Mondays 09:00)
Delegate a status check to each C-suite member. Compile a brief summary across all
domains. Post to #boardroom. Model must be pinned at cron creation time.
```

- [ ] **Step 3: Verify SOUL.md is personality only**

```bash
grep -c "Mandate\|Delegation\|roster\|Channel\|cron\|delegate_task" hermes/profiles/cos/SOUL.md
```
Expected: `0`

- [ ] **Step 4: Verify AGENTS.md has required sections**

```bash
grep -c "Mandate\|Delegation rules\|Business roster\|Channel context\|Weekly review" hermes/profiles/cos/AGENTS.md
```
Expected: `5`

---

## Task 11: Update cos config.yaml — access control baseline

**Files:**
- Modify: `hermes/profiles/cos/config.yaml`

Current: `disabled_toolsets: []` (empty). Raha also needs `platform_toolsets.discord` set explicitly to add `kanban` (not in default list) and exclude everything else.

- [ ] **Step 1: Update disabled_toolsets**

Find:
```yaml
  disabled_toolsets: []
```
Replace with:
```yaml
  disabled_toolsets:
    - browser
    - code_execution
    - file
    - image_gen
    - terminal
    - todo
    - tts
    - vision
    - web
```
(Keeps: delegation, kanban, memory, skills, clarify — per access control spec.)

- [ ] **Step 2: Override platform_toolsets.discord to include kanban**

Find (near the end of the file):
```yaml
  discord:
  - browser
  - clarify
  - code_execution
  - context_engine
  - cronjob
  - delegation
  - file
  - image_gen
  - memory
  - session_search
  - skills
  - terminal
  - todo
  - tts
  - vision
  - web
```
Replace with:
```yaml
  discord:
  - kanban
  - delegation
  - memory
  - skills
  - clarify
```
This is the `platform_toolsets.discord` section. Kanban is not in the default list — it must be explicitly included here for Raha to access it.

- [ ] **Step 3: Set discord.allowed_channels**

Find (in the `discord:` section, not `platform_toolsets`):
```yaml
discord:
  require_mention: true
  free_response_channels: ''
  allowed_channels: ''
```
Replace with:
```yaml
discord:
  require_mention: true
  free_response_channels: ''
  allowed_channels: 'BOARDROOM_CHANNEL_ID,BIZ_CHAT_CHANNEL_ID'
```
Replace with actual snowflake IDs for `#boardroom` and `#biz-chat`.

- [ ] **Step 4: Set allow_lazy_installs to false**

Find:
```yaml
  allow_lazy_installs: true
```
Replace with:
```yaml
  allow_lazy_installs: false
```

- [ ] **Step 5: Pin compression model**

Find (inside `auxiliary:` block):
```yaml
  compression:
    provider: auto
    model: ''
    base_url: ''
    api_key: ''
    timeout: 120
    extra_body: {}
```
Replace with:
```yaml
  compression:
    provider: custom:litellm
    model: deepseek/deepseek-v3-0324
    base_url: ''
    api_key: ''
    timeout: 120
    extra_body: {}
```

- [ ] **Step 6: Verify**

```bash
grep "disabled_toolsets" -A10 hermes/profiles/cos/config.yaml | head -11
grep "allow_lazy_installs" hermes/profiles/cos/config.yaml
grep "kanban" hermes/profiles/cos/config.yaml
```
Expected: 9 disabled toolsets, allow_lazy_installs: false, kanban appears under platform_toolsets.

---

## Task 12: Delete orphaned TOOLS.md files

**Files:**
- Delete: `hermes/profiles/admin/TOOLS.md`
- Delete: `hermes/profiles/curator/TOOLS.md`

These files are not auto-loaded by Hermes. SOUL.md no longer references them (rewritten in Task 2 and Task 5). Deleting removes dead weight from the profile directory.

- [ ] **Step 1: Verify no remaining references to TOOLS.md**

```bash
grep -rn "TOOLS.md" hermes/profiles/admin/ hermes/profiles/curator/
```
Expected: no output. If any refs remain, fix them first before deleting.

- [ ] **Step 2: Delete both files**

```bash
rm hermes/profiles/admin/TOOLS.md hermes/profiles/curator/TOOLS.md
```

- [ ] **Step 3: Verify deleted**

```bash
ls hermes/profiles/admin/TOOLS.md hermes/profiles/curator/TOOLS.md 2>&1
```
Expected: `No such file or directory` for both.

---

## Task 13: DISCORD_ALLOWED_USERS in .env files (VPS)

**Files:**
- VPS: `~/.hermes/profiles/curator/.env`
- VPS: `~/.hermes/profiles/admin/.env`
- VPS: `~/.hermes/profiles/assistant/.env`
- VPS: `~/.hermes/profiles/cos/.env`

**Run directly on the VPS (not in repo).** Find your Discord user ID: in Discord, go to Settings → Advanced → enable Developer Mode, then click your own avatar anywhere and select "Copy User ID".

- [ ] **Step 1: Add DISCORD_ALLOWED_USERS to each profile .env**

```bash
DISCORD_UID="YOUR_DISCORD_USER_ID_HERE"

for profile in curator admin assistant cos; do
  env_file=~/.hermes/profiles/$profile/.env
  if grep -q "DISCORD_ALLOWED_USERS" "$env_file" 2>/dev/null; then
    echo "$profile: already set, skipping"
  else
    echo "DISCORD_ALLOWED_USERS=$DISCORD_UID" >> "$env_file"
    echo "$profile: added"
  fi
done
```

Replace `YOUR_DISCORD_USER_ID_HERE` with your actual Discord user ID (18-19 digit number).

- [ ] **Step 2: Verify all four .env files have the entry**

```bash
for profile in curator admin assistant cos; do
  echo -n "$profile: "
  grep "DISCORD_ALLOWED_USERS" ~/.hermes/profiles/$profile/.env 2>/dev/null || echo "MISSING"
done
```
Expected: each line shows `DISCORD_ALLOWED_USERS=<your_id>`, not `MISSING`.

---

## Task 14: Populate docs/VISION.md and docs/ARCHITECTURE.md

**Files:**
- Modify: `docs/VISION.md` (currently empty)
- Modify: `docs/ARCHITECTURE.md` (currently empty)

- [ ] **Step 1: Write docs/VISION.md**

```markdown
# Vision

Nizam-OS is a personal AI operating system running on a VPS. It manages knowledge,
personal finances, habits, goals, and business operations through a team of autonomous
AI agents. The agents communicate with the owner via Discord, coordinate with each
other through structured delegation, and maintain a full audit trail of all
consequential actions.
```

- [ ] **Step 2: Write docs/ARCHITECTURE.md**

```markdown
# Architecture

## Stack layers

```
Owner (Discord)
     │
     ▼
Discord Gateway  (one bot per agent, one systemd user service per profile)
  Noor · Nazim · Ayah · Raha · Hala · Omar · Reem · Mira
     │
     ▼
Hermes Agent Framework  (~/.hermes/profiles/<name>/)
  ├── SOUL.md      (personality — injected at session start, slot 1)
  ├── AGENTS.md    (mandate — highest priority context, auto-injected)
  ├── MCP servers  (tool access — HTTP transport, localhost only)
  └── Hermes cron  (scheduled tasks, model-pinned)
     │
     ▼
MCP Services  (systemd, HTTP, 127.0.0.1 only)
  ├── knowledge-service  :8100  →  PostgreSQL (knowledge schema)
  ├── finance-service    :8101  →  PostgreSQL (finance.personal + finance.business)
  ├── personal-service   :8102  →  PostgreSQL (personal schema)
  └── crm-service        :8103  →  PostgreSQL (crm schema)
     │
     ▼
Infrastructure  (all on same VPS)
  ├── PostgreSQL  (pgvector + pg_search / ParadeDB)
  ├── Redis       (cache + health monitor state)
  ├── LiteLLM proxy  :4000  →  OpenRouter  (model routing)
  ├── Prometheus + Grafana  (metrics + alerting → Discord #alerts)
  └── Tailscale  (owner remote access)
```

## Agent responsibilities

| Agent | Profile | Role |
|---|---|---|
| Noor | curator | Knowledge vault — capture, organise, surface |
| Nazim | admin | System health — monitor, restart, alert |
| Ayah | assistant | Personal finance, habits, goals, journal |
| Raha | cos | Chief of Staff — coordinates C-suite, owner briefings |
| Hala | cfo | Business finance, invoicing, P&L |
| Omar | coo | Operations, client CRM, project delivery |
| Reem | cto | Architecture, code review, tech delivery |
| Mira | cmo | Content, LinkedIn, marketing |

## Access control principle

Minimum footprint per agent:

- `discord.allowed_channels` — each agent responds only in its assigned channels
- `security.allow_lazy_installs: false` — no runtime package installs by agents
- `approvals.mode: manual` — all dangerous commands require explicit Discord approval
- `DISCORD_ALLOWED_USERS` — only the owner can talk to any agent
- MCP `tools.include` — each profile whitelists only the specific tools it needs
- DB roles — separate roles per service, INSERT-only on `audit.log`

See `each agent's individual spec` for the full design.

## Sync model

Profile files in `hermes/profiles/` are version-controlled in this repo. The
`hermes-profile-watcher` systemd service keeps `~/.hermes/profiles/` in sync.
Secrets (`~/.hermes/profiles/<name>/.env`) are NOT in the repo — managed on VPS only.
```

- [ ] **Step 3: Verify both files non-empty**

```bash
wc -l docs/VISION.md docs/ARCHITECTURE.md
```
Expected: both have more than 1 line.

---

## Task 15: Create ~/nizam-vault/ (VPS)

**Run directly on the VPS.** The vault directory must exist before knowledge-service can write notes. It is a git repo so Noor's writes are permanent and reversible.

- [ ] **Step 1: Create vault directory and init git**

```bash
mkdir -p ~/nizam-vault/commons
cd ~/nizam-vault
git init
echo "# nizam-vault" > README.md
git add README.md
git commit -m "init: create vault"
```

- [ ] **Step 2: Verify**

```bash
ls -la ~/nizam-vault/commons/
git -C ~/nizam-vault log --oneline
```
Expected: `commons/` directory exists, one commit in git log.

---

## Task 16: Add Nazim sudoers entry (VPS)

**Run directly on the VPS as root.** Nazim needs to restart specific system services. Never store `SUDO_PASSWORD` in `.env` — use a targeted NOPASSWD sudoers entry instead so if Nazim is compromised, blast radius is limited to these specific restart commands.

- [ ] **Step 1: Create sudoers file**

```bash
sudo visudo -f /etc/sudoers.d/nazim-hermes
```

Enter exactly this in the editor:

```
# Nazim (Hermes admin agent) — restricted systemctl access only
vazir ALL=(root) NOPASSWD: /bin/systemctl restart postgresql.service
vazir ALL=(root) NOPASSWD: /bin/systemctl restart redis-server.service
vazir ALL=(root) NOPASSWD: /bin/systemctl restart litellm-proxy.service
vazir ALL=(root) NOPASSWD: /bin/systemctl restart hermes-gateway-admin.service
vazir ALL=(root) NOPASSWD: /bin/systemctl restart hermes-gateway-curator.service
```

`visudo` validates syntax before saving. Do NOT use a plain text editor for sudoers files.

- [ ] **Step 2: Verify grants**

```bash
sudo -l -U vazir | grep NOPASSWD
```
Expected: lists all 5 restart commands above, nothing else.

- [ ] **Step 3: Smoke test**

```bash
sudo systemctl restart litellm-proxy.service && systemctl is-active litellm-proxy.service
```
Expected: `active`

---

## Task 17: Set up observability stack (VPS — post wipe or fresh install)

**Run on VPS after Prometheus and Grafana are installed.**

This task covers the three metric collectors and the two existing Grafana dashboards. Run this before any agents are active so baseline metrics are captured from day one.

- [ ] **Step 1: Verify Prometheus node-exporter `.prom` output dir exists**

```bash
ls /var/lib/prometheus/node-exporter/
```
Expected: directory exists. If not: `sudo mkdir -p /var/lib/prometheus/node-exporter/`

- [ ] **Step 2: Enable metric collector timers**

```bash
sudo systemctl enable --now metrics-llm.timer
sudo systemctl enable --now metrics-services.timer
sudo systemctl enable --now metrics-toolcalls.timer
systemctl is-active metrics-llm.timer metrics-services.timer metrics-toolcalls.timer
```
Expected: all three show `active`.

- [ ] **Step 3: Verify .prom files are written**

Wait 2 minutes after enabling timers, then:
```bash
ls -la /var/lib/prometheus/node-exporter/*.prom
```
Expected: at least 3 `.prom` files with recent modification timestamps.

- [ ] **Step 4: Import agents dashboard into Grafana**

Navigate to `http://localhost:3000` → Dashboards → Import → Upload JSON file → select `grafana/agents-dashboard.json`.

Set datasource to Prometheus when prompted. Click Import.

Expected: "Nizam — Agents" dashboard loads with panels. Data appears within 2 minutes of timer activation.

- [ ] **Step 5: Import services dashboard into Grafana**

Repeat Step 4 with `grafana/services-dashboard.json`.

Expected: "Nizam — Services" dashboard loads. All monitored services appear in the Current Status table.

- [ ] **Step 6: Verify key panels show data**

In "Nizam — Agents": confirm "Calls Today" panel shows a number (even if 0 — it should not show "No data").
In "Nizam — Services": confirm at least PostgreSQL and Redis appear as "active".

```bash
# If panels show No data, check Prometheus is scraping node-exporter:
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool | grep "health"
```
Expected: `"health": "up"` for node-exporter target.
