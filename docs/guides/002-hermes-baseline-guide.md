# Phase 2 Hermes Baseline — Guide

**What this builds:** Discord server, Grafana personal agent-usage panels, Hermes installation, default Hermes profile, `admin` (Nazim) Hermes profile, agents wired to LiteLLM, agent governance framework setup.

**Spec:** [002 Hermes Baseline — Design](../specs/002-hermes-baseline-design.md)  
**Plan:** [002 Hermes Baseline — Plan](../plans/002-hermes-baseline-plan.md)  
**Previous phase:** [001 Foundation — Guide](001-foundation-guide.md)  
**Next phase:** [003 Knowledge Curator — Guide](003-knowledge-guide.md) 

---

## Prerequisites

- [ ] Phase 1 complete: `sudo bash ~/nizam-os/scripts/setup/001-foundation.sh` ran without errors
- [ ] LiteLLM reachable: `curl -s http://localhost:4000/health/liveliness` → `"I'm alive!"`
- [ ] PostgreSQL running with `nizam` database

---

## Step 1 — Create Discord server

1. Open Discord → Create a Server → name: **Darbar**
2. Enable Developer Mode: User Settings → Advanced → Developer Mode
3. Right-click the server icon → Copy Server ID → save as `DISCORD_GUILD_ID`
4. Right-click your own username → Copy User ID → save as `DISCORD_OWNER_ID`

> All related assets for iconography can be found in [ASSETS](~/nizam-os/assets).

**Create categories and channels**:

| Category | Channels |
|---|---|
| 🙋‍♂️┃Introduction | `📜ㆍcharter` |
| 👤┃Personal | `💬ㆍchat`, `📋ㆍbriefing`, `🌱ㆍlife`, `💵ㆍfinances`, `🧠ㆍlearning` |
| 🗄️┃System | `🚨ㆍalerts`, `📄ㆍlogs`, `🛠️ㆍadmin`, `📦ㆍsandbox` |
| 👑┃Executive | `♞・strategy` |
| 🤖┃Arc Systems | `💼ㆍbiz-chat`, `👥ㆍboardroom`, `⚙️ㆍcoo-office`, `💰ㆍcfo-office`, `💻ㆍcto-office`, `📢ㆍcmo-office` |

**Permission model:**
- Right-click each category → Edit Category → Permissions → enable private category
- Right-click each channel → Edit Channel → Permissions → enable access to private channel to members from below table

|Member|Category|Channel|
|----|--------|-------|
|All|Introduction|`#charter`|
|None|Executive|`#strategy`|
|`admin`|System|`#alerts`|
|`admin`|System|`#logs`|
|`admin`|System|`#admin`|
|`admin`|System|`#sandbox`|
|`assistant`|Personal|`#chat`|
|`assistant`|Personal|`#life`|
|`assistant`|Personal|`#briefing`|
|`assistant`|Personal|`#finances`|
|`curator`|Personal|`#learning`|
|`cos`|Arc Systems|`#biz-chat`|
|`cos`|Arc Systems|`#boardroom`|
|`coo`|Arc Systems|`#coo-office`|
|`cfo`|Arc Systems|`#cfo-office`|
|`cto`|Arc Systems|`#cto-office`|
|`cmo`|Arc Systems|`#cmo-office`|

**Copy System channel IDs** — right-click each channel → Copy Channel ID:
- `#alerts` → `DISCORD_CHANNEL_ALERTS`
- `#logs` → `DISCORD_CHANNEL_LOGS`
- `#admin` → `DISCORD_CHANNEL_ADMIN`
- `#sandbox` → `DISCORD_CHANNEL_SANDBOX`

> These IDs are written as literal integers into `hermes-admin-config.yaml` by `002-hermes.sh` (not as `${VAR}` references — the discord adapter reads `allowed_channels` at startup before the profile secret scope is active, so env var expansion doesn't work there).

**Create Grafana alert webhooks:**
- `#alerts` → Server Settings → Integrations → Webhooks → New Webhook → copy URL → `DISCORD_WEBHOOK_WARNING`
- `#alerts` Server Settings → Integrations → Webhooks → New Webhook → copy URL → `DISCORD_WEBHOOK_CRITICAL`

**Create Discord bot application for `admin`:**
1. Go to [discord.com/developers/applications](https://discord.com/developers/applications) → New Application → name: **Nazim**
2. Bot → Reset Token → copy token → save as `DISCORD_TOKEN_ADMIN`
3. Bot → Privileged Gateway Intents → enable **Server Members Intent** + **Message Content Intent** + **Presence Intent**
4. OAuth2 → URL Generator → scope `bot` → permissions 
    - `Send Messages` + `Create Public Threads` + `Send Messages in Threads` + `Pin Messages` + `Embed Links` + `Attach Files` + `Read Message History` + `Mention Everyone` + `Add Reactions` + `Use Slash Commands` 
    - → open generated URL → add bot to Darbar

> Generated URL: ...permissions=2252111199062080...

Add all values to `secrets/nizam-os.env`.

---

## Step 2 — Grafana agent usage panels

Import the pre-built dashboard JSON — panels will show "no data" until `admin` makes its first call.

```bash
# Push grafana dashboard to server
sudo bash ~/nizam-os/scripts/grafana/push-dashboard.sh ~/nizam-os/grafana/001-personal-dashboard.json

# Wire Grafana alert webhooks
bash ~/nizam-os/scripts/setup/setup-alerts.sh
```

Verify: Grafana → Alerting → Contact points → Test `nizam-warn` and `nizam-crit`.

---

## Step 3 — Install and setup default Hermes Agent manually

```bash
# Install Hermes Agent
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
```

**Hermes Setup:**
1. Select `Blank Slate` to start with a minimal configuration.
2. Select `Custom endpoint` as the inference provider.
3. Enter your local model server URL as the `API Base URL`.
4. Skip adding /v1 if your endpoint does not use it.
5. Select Chat Completions (`chat_completions`) as the API compatibility mode.
6. Enter your model name `...`.
7. Leave Context Length blank to auto-detect it.
8. Press Enter to keep the default display name.
9. Keep the `Local` terminal backend.
11. Enable `Discord` under Messaging Platforms.
12. Disable all `CLI` tools.
13. Disable all `Discord` tools.
14. Add Discord `bot token`.
15. Add Discord `owner ID`.
16. Install `gateway` and start with system linger.
17. Confirm the service is running `hermes gateway status` before using Hermes.

---

## Step 4 — Create LiteLLM virtual key for default profile

The default Hermes gateway needs a virtual key to make LiteLLM calls. Each agent profile gets its own virtual key for isolated spend tracking and independent revocation.

```bash
source ~/nizam-os/secrets/nizam-os.env

curl -X POST "$LITELLM_URL/key/generate" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{}' | json


# Copy key value from the response
# Set as virtual key for profile
LITELLM_VIRTUAL_KEY=sk-...  # ~/.hermes/.env
```

```yaml
# Point default profile to env var
model:
  default: ...
  provider: custom
  base_url: http://localhost:4000
  api_mode: chat_completions
  api_key: ${LITELLM_VIRTUAL_KEY}  # add to ~/.hermes/config.yaml

```

Verify the default gateway `hermes gateway restart && hermes gateway status` is running and responding in Discord. Confirm the Grafana agent usage panels are tracking the call.

```bash
# Stop default profile gateway
hermes gateway stop
```

---

## Step 5 — Setup `admin`

```bash
# Add admin profile
hermes profile create admin --desc "Nazim monitors Nizam infrastructure health via Prometheus, detects service failures proactively, restarts approved services, maintains system knowledge base, and posts concise incident reports in Discord." --no-skills
```

**`admin` Setup:**
1. Run `admin setup` to start setup.
1. Select `Blank Slate` to start with a minimal configuration.
2. Select `Custom endpoint` as the inference provider.
3. Enter your local model server URL as the `API Base URL`.
4. Skip adding /v1 if your endpoint does not use it.
5. Select Chat Completions (`chat_completions`) as the API compatibility mode.
6. Enter your model name `...`.
7. Leave Context Length blank to auto-detect it.
8. Press Enter to keep the default display name.
9. Keep the `Local` terminal backend.
11. Enable `Discord` under Messaging Platforms.
12. Disable all `CLI` tools.
13. Enable following tools: 
    - `Terminal & Processes`
    - `File Operations`
    - `Skills`
    - `Task Planning`
    - `Memory`
    - `Context Engine`
    - `Session Search`
    - `Clarifying Questions`
14. Add Discord `bot token`.
15. Add Discord `owner ID`.
16. Install `gateway` and start with system linger.
17. Confirm the service is running `admin gateway status` before using Hermes.

```bash
# Restart admin profile gateway
admin gateway restart
```

---

## Step 6 — Run `002-hermes.sh`


```bash
# Run hermes setup script
sudo bash ~/nizam-os/scripts/setup/002-hermes.sh
```

Idempotent — if it fails partway, fix the error and re-run.

**What it does (in order):**
1. Verifies Phase 1: LiteLLM at `:4000` healthy, PostgreSQL `nizam` DB reachable
2. Validates all Phase 2 Discord env vars are set in `secrets/nizam-os.env`
3. Checks `hermes` binary is installed
4. Checks `admin` profile directory exists; seeds `config/hermes-admin-config.yaml` and `secrets/hermes-admin.env` from auto-generated files (first run only); wires all symlinks via `install-symlinks.sh`; enables `loginctl linger` for vazir
5. Patches `hermes-admin-config.yaml` via `yq`: model `api_key`, STT disabled, memory write disabled, security block (tirith, redact, no lazy installs), discord block (channels, auto_thread, history, reactions), approvals set to manual; adds placeholder keys to `secrets/hermes-admin.env`
6. Writes `/etc/sudoers.d/admin-nizam` with `NIZAM_SERVICES` alias for passwordless `systemctl restart/start`
7. Installs and starts `hermes-gateway-admin` (idempotent — skips if already active)

---

## Step 7 — Create LiteLLM virtual key for `admin` profile

```bash
source ~/nizam-os/secrets/nizam-os.env

curl -X POST "$LITELLM_URL/key/generate" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{}' | json


# Copy key value from the response
LITELLM_VIRTUAL_KEY_ADMIN=sk-...  # ~/nizam-os/secrets/hermes-admin.env
```

```yaml
# Point default profile to env var
model:
  default: ...
  provider: custom
  base_url: http://localhost:4000
  api_mode: chat_completions
  api_key: ${LITELLM_VIRTUAL_KEY_ADMIN}  # add to ~/nizam-os/config/hermes-admin-config.yaml
```

---

## Step 8 — Fill virtual key and restart gateway

`002-hermes.sh` left `LITELLM_VIRTUAL_KEY_ADMIN=` as a placeholder. Fill it with the key from Step 7:

```bash
# Edit the admin env file (symlinked — editing this edits the runtime file)
nano ~/nizam-os/secrets/hermes-admin.env
# Set: LITELLM_VIRTUAL_KEY_ADMIN=sk-...
```

Restart gateway to pick up the key:

```bash
admin gateway restart && admin gateway status
```

Check logs for errors:

```bash
admin gateway logs --tail 20
```

---

## Step 10 — Install SAVE framework

> [TBD — you will define the SAVE framework skill files and installation steps here.]

Install notes:
- `skill-write` is disabled in the UI — skill files are written manually to `hermes/profiles/admin/skills/`
- `memory-write` is disabled — no memory tool access needed for installation
- Each skill file is committed to the repo and picked up via the symlink at `~/.hermes/profiles/admin/skills/`

Placeholder structure (fill with actual skill file names and content):

```bash
# Verify skills dir symlink
ls ~/.hermes/profiles/admin/skills/   # → should point to hermes/profiles/admin/skills/

# Add skill files manually
cp <save-skill-files> ~/nizam-os/hermes/profiles/admin/skills/
```

After installing:

```bash
admin gateway restart && admin gateway status
```

---

## Step 11 — Verify exit criteria

```bash
# Gateway running
admin gateway status   # → active (running)

hermes profile list   # → admin listed

# Virtual key exists
source ~/nizam-os/secrets/nizam-os.env
curl -s -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  http://localhost:4000/key/list \
  | python3 -c "
import json, sys
keys = json.load(sys.stdin)
n = [k for k in keys.get('keys', [])]
print('total virtual keys:', len(n))
" 
# → admin virtual keys: 1

# Config symlink
readlink ~/.hermes/profiles/admin/config.yaml   # → .../nizam-os/config/admin-config.yaml

# command_allowlist present
grep "systemctl restart litellm-proxy" ~/nizam-os/config/admin-config.yaml

# Sudoers (if applicable)
sudo visudo -c -f /etc/sudoers.d/admin-nizam    # → parsed OK
```

**Manual:** Open Discord → `admin` shows green presence in server member list → send message in `#admin` → Nazim responds.

**Grafana:** Agent Usage panels show first data point for `admin`.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `DISCORD_TOKEN_ADMIN missing` | Add to `secrets/nizam-os.env`, re-run `admin setup` |
| Gateway crashes immediately | `admin gateway logs --tail 50` — likely bad token or wrong channel IDs |
| Bot online but not responding | Check `discord.allowed_channels` in `config/admin-config.yaml` — IDs must match actual channel IDs |
| Virtual key creation fails | `curl -s http://localhost:4000/health/liveliness` — LiteLLM must be running |
| LiteLLM returns 400 / "unknown param" | `config/litellm.yaml` must have `drop_params: true`; `systemctl restart litellm-proxy` after change |
| Model routing broken / double-prefix | Do not use `openrouter/deepseek/...` in hermes config — use `deepseek/...` only |
| `api_mode` errors | Use `chat_completions` (underscore), not `chat/completions` — patch with `yq` (Step 10) |
| Config changes not applied | `admin gateway restart` after any config edit |
| Grafana agent panels show no data | Trigger a test message to Nazim; check `nizam_llm_requests_today` in Prometheus |
