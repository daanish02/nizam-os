# Step 2 — Hermes Gateway + Bani (admin)

Gives you: Discord bot → Hermes gateway → Bani (admin agent) → LiteLLM proxy.

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
```

Verify:
```bash
hermes --version   # Hermes Agent v0.17.x
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

**`~/.hermes/config.yaml`** — change base_url:
```yaml
model:
  default: deepseek/deepseek-v4-flash
  provider: openrouter
  base_url: http://localhost:4000   # was https://openrouter.ai/api/v1
  api_mode: chat/completions
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

## 6. Create Admin Profile

```bash
hermes profile create admin
```

This creates `~/.hermes/profiles/admin/` with a default SOUL.md.

Wire SOUL.md to nizam-os (symlink — nizam-os is source of truth):
```bash
sudo bash ~/.nizam-os/scripts/setup/install-symlinks.sh
```

This replaces `~/.hermes/profiles/admin/SOUL.md` with a symlink to `~/.nizam-os/hermes/profiles/admin/SOUL.md`.  
Edit SOUL.md in nizam-os → git commit → `hermes gateway restart`. No copy step.

Set admin as the default profile (the one the gateway runs as):
```bash
hermes profile use admin
```

Verify:
```bash
hermes profile list   # admin should have ◆
```

---

## 7. Start Gateway

```bash
hermes gateway install      # install as user systemd service
systemctl --user enable --now hermes-gateway
```

Verify:
```bash
systemctl --user status hermes-gateway --no-pager   # active (running)
journalctl --user -u hermes-gateway -n 20 --no-pager | grep -E "discord|ready|connect"
```

Gateway connects, Discord shows bot online.

---

## 8. Test Bani

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

## 9. Channel Routing

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
hermes gateway restart
```

---

## 10. Add to Inventory

`~/.nizam-os/inventory/tracked-services.txt` already includes:
```
# Nizam-OS — Hermes Gateway
hermes-gateway.service
```

---

## Full Stack Verify

```bash
# All services running
systemctl --user is-active hermes-gateway
sudo systemctl is-active litellm-proxy

# Gateway connected
journalctl --user -u hermes-gateway -n 5 --no-pager

# Last 3 LLM calls (confirms routing through proxy)
psql "postgresql://svc_litellm:<password>@127.0.0.1:5432/nizam" \
  -c 'SELECT model, user_id, prompt_tokens, completion_tokens FROM litellm."LiteLLM_SpendLogs" ORDER BY "startTime" DESC LIMIT 3;'
```

---

## Adding More Profiles

```bash
hermes profile create alex
mkdir -p ~/.nizam-os/hermes/profiles/alex
# write ~/.nizam-os/hermes/profiles/alex/SOUL.md
sudo bash ~/.nizam-os/scripts/setup/install-symlinks.sh   # wires SOUL.md symlink
hermes gateway restart
```

The gateway runs ONE profile (admin). Other profiles (alex, raha, etc.) will get their own gateway instances in later steps when channel routing is configured per-profile.
