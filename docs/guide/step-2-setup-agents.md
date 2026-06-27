# Step 2 — Setup Agents

Gives you: Discord bot → Hermes profile gateways → named agents → LiteLLM proxy.

---

## Prerequisites

Step 1 complete (LiteLLM proxy running, metrics flowing). Plus:
- Discord server created ("Darbar-e-Nizam")
- Discord bot created in Developer Portal, bot token available
- Bot invited to server with `bot` + `applications.commands` scopes

---

## 1. Install Hermes

```bash
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash

# Verify
hermes --version
```

---

## 2. Initial Setup

Run the setup wizard once:
```bash
hermes setup
```

Set:
- Provider: OpenRouter (enter your OpenRouter API key — this is overridden in step 4)
- Model: `deepseek/deepseek-v4-flash` (default, overridden per-profile later)

---

## 3. Discord Bot — Privileged Intents

**Required before the gateway can connect.**

Developer Portal → Applications → [your bot] → **Bot** tab → **Privileged Gateway Intents**:
- Enable **Message Content Intent**
- Enable **Server Members Intent**
- Save Changes

Without these, the gateway starts but immediately errors:
```
discord.errors.PrivilegedIntentsRequired
```

---

## 4. Route Through LiteLLM

Hermes must send calls through the local LiteLLM proxy (port 4000) for observability.

> **Note:** `~/.hermes/config.yaml`, `~/.hermes/.env`, `~/.hermes/skills/`, and `~/.hermes/memories/`
> are the root/default hermes agent — managed by hermes itself. Edit them directly; **never symlink them
> into nizam-os.** Only files under `~/.hermes/profiles/<name>/` are managed by nizam-os.

**`~/.hermes/config.yaml`** — change base_url:
```yaml
model:
  default: deepseek/deepseek-v4-flash
  provider: openrouter
  base_url: http://localhost:4000   # was https://openrouter.ai/api/v1
  api_mode: chat_completions
```

**`~/.hermes/.env`** — replace OpenRouter key with LiteLLM master key:
```bash
# Hermes sends this as Bearer auth to LiteLLM proxy.
# Real OpenRouter key lives in ~/.nizam-os/secrets/nizam.env, used by litellm-proxy.service.
OPENROUTER_API_KEY=<LITELLM_MASTER_KEY from nizam.env>
```

---

## 5. Discord Gateway Setup

```bash
hermes gateway setup
```

Follow prompts for Discord. Paste your `DISCORD_BOT_TOKEN` when asked.

After setup, `~/.hermes/.env` will have:
```
DISCORD_BOT_TOKEN=...
DISCORD_ALLOWED_USERS=<your Discord user ID>
```

---

## 6. Disable the Default Hermes Agent

Hermes ships with a root agent at `~/.hermes/` (SOUL.md, config.yaml, .env, skills/, memories/).
**Do not use it.** All agents in nizam-os run as named profiles under `~/.hermes/profiles/<name>/`.

Disable the default agent's gateway so it never starts:
```bash
hermes gateway disable      # prevents the root agent from spawning a Discord gateway
```

Verify it is off:
```bash
systemctl --user is-active hermes-gateway 2>/dev/null || echo "not running — good"
```

> The root `~/.hermes/` files (SOUL.md, config.yaml, .env, skills/, memories/) are left alone.
> nizam-os never symlinks, modifies, or tracks them. They are hermes's internal concern.

---

## 7. Create Admin Profile

```bash
hermes profile create admin
```

This creates `~/.hermes/profiles/admin/` with a default SOUL.md.

Wire it into nizam-os (nizam-os is source of truth for all profile files):
```bash
bash ~/.nizam-os/scripts/setup/wire-hermes-profile.sh admin
```

This migrates SOUL.md, config.yaml, .env, skills/, and memories/ from `~/.hermes/profiles/admin/`
into `~/.nizam-os/hermes/profiles/admin/` and replaces each with a symlink back.
Edit any file in nizam-os → git commit → `hermes gateway restart`. No copy step.

Set admin as the active profile:
```bash
hermes profile use admin
```

Verify:
```bash
hermes profile list   # admin should have ◆
```

---

## 8. Start Admin Gateway

Each profile runs its own gateway — `admin gateway`, `assistant gateway`, etc.
The default root `hermes gateway` is disabled (step 6); never use it.

```bash
admin setup                  # configure admin profile (Discord token, channels, model)
admin gateway install        # install hermes-gateway-admin as user systemd service
admin gateway start          # start it
admin gateway status         # verify running
```

Verify in journal:
```bash
journalctl --user -u hermes-gateway-admin -n 20 --no-pager | grep -E "discord|ready|connect"
```

Gateway connects, Discord shows bot online.

---

## 9. Test Bani

In Discord, go to any channel the bot can see. Mention the bot:
```
@Bani what services are running right now?
```

Expect: Bani runs `systemctl list-units` (or similar), replies with service status.

Verify the call went through LiteLLM:
```bash
psql "postgresql://svc_litellm:<password>@127.0.0.1:5432/nizam" \
  -c 'SELECT model, user_id, spend FROM litellm."LiteLLM_SpendLogs" ORDER BY "startTime" DESC LIMIT 3;'
```

`user_id` column should show `admin` (Hermes passes profile name as the user field).

---

## 10. Channel Routing

After the bot is online, lock Bani to the `#admin` channel:

1. Get the channel ID: right-click `#admin` → Copy Channel ID (Developer Mode must be on)
2. Set free response for that channel:

```bash
hermes config set discord.free_response_channels <channel-id>
hermes config set discord.allowed_channels <channel-id>
```

`free_response_channels` = Bani responds without requiring an @mention.  
`allowed_channels` = Bani only listens in this channel. Leave empty for all channels.

Restart gateway after config change:
```bash
admin gateway restart
```

---

## 11. Add to Inventory

`~/.nizam-os/inventory/tracked-services.txt` — add each profile gateway:
```
hermes-gateway-admin.service
hermes-gateway-assistant.service
hermes-gateway-cos.service
```

---

## Full Stack Verify

```bash
# All gateways running
hermes gateway list

# Last 3 LLM calls (confirms routing through proxy)
psql "postgresql://svc_litellm:<password>@127.0.0.1:5432/nizam" \
  -c 'SELECT model, user_id, prompt_tokens, completion_tokens FROM litellm."LiteLLM_SpendLogs" ORDER BY "startTime" DESC LIMIT 3;'
```

---

## Adding More Profiles

Pattern for every new profile. Two concrete examples:

### Example 1 — assistant (Ayah, personal assistant)

```bash
# 1. create profile
hermes profile create assistant

# 2. configure it (Discord token, model, channels)
assistant setup

# 3. wire into nizam-os (migrates SOUL.md, config.yaml, .env, skills/, memories/ → nizam-os, symlinks back)
bash ~/.nizam-os/scripts/setup/wire-hermes-profile.sh assistant
# logs to ~/.nizam-os/logs/scripts.log — check it if anything looks silently skipped

# 4. install and start its gateway
assistant gateway install
assistant gateway start
assistant gateway status

# 5. verify in journal
journalctl --user -u hermes-gateway-assistant -n 20 --no-pager
```

### Example 2 — cos (Hala, Chief of Staff)

```bash
hermes profile create cos
cos setup
bash ~/.nizam-os/scripts/setup/wire-hermes-profile.sh cos
cos gateway install
cos gateway start
cos gateway status
```

### Notes

- Each profile gets its own systemd service: `hermes-gateway-<name>`
- `hermes gateway list` shows all installed gateways and their status
- `~/.hermes/profiles/<name>/` files that nizam-os manages (SOUL.md, config.yaml, .env, skills/, memories/) become symlinks into `~/.nizam-os/hermes/profiles/<name>/` after wiring — git-tracked, edit in nizam-os
- Runtime files hermes writes (sessions, logs, cache, state.db, etc.) stay as real files in `~/.hermes/profiles/<name>/` — nizam-os never touches them
- **Never run `wire-hermes-profile.sh` without a profile name arg during active sessions** — it processes all profiles and will briefly interrupt running gateways that hold files open
