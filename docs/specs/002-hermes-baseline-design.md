# Hermes Baseline — Design Spec

**Phase:** 2  
**Charter refs:** [ARCHITECTURE](../ARCHITECTURE.md), [SECURITY](../SECURITY.md), [SERVICES](../SERVICES.md)

---

## Prerequisite

Phase 1 complete: LiteLLM at `localhost:4000`, PostgreSQL running with `nizam` DB, Grafana at `localhost:3000`, `nizam-os.env` fully populated.

`config/litellm.yaml` must have `drop_params: true` under `litellm_settings`. Without this, LiteLLM forwards Hermes-specific params to OpenRouter which rejects them with a 400.

```yaml
litellm_settings:
  drop_params: true
```

---

## Delivery model

Phase 2 is primarily manual setup with one small transition script. Hermes auto-generates the agent config through its interactive `admin setup` wizard — the generated config is then symlinked into the repo and patched with `yq` for required values. This is the pattern for all future agent profiles.

**Phase 2 is Nazim (admin) only.** Other agent profiles are activated in their own phases.

**Run order:**

1. Create Discord server + webhooks + Nazim bot application (manual)
2. Populate Phase 2 vars in `secrets/nizam-os.env`
3. Add Grafana agent-usage panels (before Hermes — tracking starts immediately)
4. Wire Grafana alerts to Discord (`bash scripts/setup/setup-alerts.sh`)
5. Create LiteLLM virtual key for default profile — test default gateway — then: `sudo bash ~/nizam-os/scripts/setup/002-hermes.sh` (stops default gateway)
6. Create LiteLLM virtual key for admin (`sk-nizam-admin`)
7. `hermes profile create admin --desc "..."` + `admin setup` (interactive wizard)
8. `admin gateway install && admin gateway start`
9. Symlink config into repo, patch with `yq`, write sudoers
10. Install SAVE framework skills
11. `admin gateway restart && admin gateway status`

---

## Discord server structure

Server name: **Darbar**. One owner account.

**Categories and channels:**

| Category | Channel | Agent access |
|---|---|---|
| Welcome | #vision | — |
| Welcome | #server-map | — |
| Personal | #chat | assistant |
| Personal | #briefing | assistant |
| Personal | #life | assistant |
| Personal | #finances | assistant |
| Personal | #learning | curator |
| System | #alerts | admin |
| System | #logs | admin |
| System | #admin | admin |
| System | #sandbox | admin |
| Chairman's Office | #strategy | Owner only — no agents ever |
| Arc Systems | #biz-chat | cos |
| Arc Systems | #boardroom | cos |
| Arc Systems | #coo-office | coo |
| Arc Systems | #cfo-office | cfo |
| Arc Systems | #cto-office | cto |
| Arc Systems | #cmo-office | cmo |

**Chairman's Office** is visible and accessible to the owner only. No bot role has permissions in this category.

**Discord permission model:**
- Default: deny `View Channel` for `@everyone` on all categories
- One Discord role per agent — grants view + send access to that agent's channels only
- admin role → System category
- curator role → #learning only
- assistant role → Personal category except #learning
- cos role → #biz-chat, #boardroom
- cfo role → #cfo-office
- coo role → #coo-office
- cto role → #cto-office
- cmo role → #cmo-office

**Phase 2 creates only the admin bot application.** Other bots are created in their respective phases.

**admin bot application setup (Discord Developer Portal):**

1. New Application → name: `admin`
2. Bot → Reset Token → copy token
3. Bot → Privileged Gateway Intents → enable **Server Members Intent** and **Message Content Intent**
4. OAuth2 → URL Generator → scope `bot`, permissions `Send Messages` + `Read Message History` → copy invite URL → add to server

---

## nizam-os.env additions for Phase 2

| Variable | Purpose |
|---|---|
| `DISCORD_GUILD_ID` | Server (guild) ID — right-click server icon → Copy Server ID |
| `DISCORD_OWNER_ID` | Your Discord user ID — right-click username → Copy User ID |
| `DISCORD_CHANNEL_ALERTS` | #alerts channel ID |
| `DISCORD_CHANNEL_LOGS` | #logs channel ID |
| `DISCORD_CHANNEL_ADMIN` | Bot token for admin |
| `DISCORD_CHANNEL_SANDBOX` | #sandbox channel ID |

All other channel IDs and bot tokens are added in their respective phases.

---

## Hermes installation

Hermes installed as a system binary, accessible to user `vazir`. Install per official Hermes docs.

```bash
hermes --version   # must succeed before running 002-hermes.sh
```

---

## Config generation model

Hermes generates `~/.hermes/profiles/admin/config.yaml` automatically when you run `admin setup`. Do not write this file from scratch — Hermes owns the initial generation.

After generation:
1. Copy to `config/admin-config.yaml` (repo SSOT)
2. Symlink: `~/.hermes/profiles/admin/config.yaml` → `config/admin-config.yaml`
3. Patch specific keys with `yq` (do not overwrite the whole file)

Any key not explicitly patched retains its Hermes-generated value.

---

## Profile directory structure

Two directory trees — SSOT in the repo, runtime that Hermes reads:

**SSOT (repo — committed):**

```
nizam-os/
├── config/
│   └── admin-config.yaml      ← admin's Hermes config
├── secrets/
│   ├── admin.env              ← plaintext per-agent env (gitignored)
│   └── admin.env.enc          ← age-encrypted (committed)
└── hermes/
    └── profiles/
        └── admin/
            ├── memories/      ← persistent agent memory (committed)
            ├── skills/        ← domain skills (committed)
            ├── SOUL.md        ← agent persona and mandate
            └── AGENTS.md      ← agent roster reference
```

**Runtime (Hermes reads — machine-local, not committed):**

```
~/.hermes/profiles/admin/
├── config.yaml   → symlink → ~/nizam-os/config/admin-config.yaml
├── .env          → symlink → ~/nizam-os/secrets/admin.env
├── memories/     → symlink → ~/nizam-os/hermes/profiles/admin/memories/
├── skills/       → symlink → ~/nizam-os/hermes/profiles/admin/skills/
├── SOUL.md       → symlink → ~/nizam-os/hermes/profiles/admin/SOUL.md
└── AGENTS.md     → symlink → ~/nizam-os/hermes/profiles/admin/AGENTS.md
```

**Naming convention:** SSOT files use `<agent>-config.yaml` and `<agent>.env` so they coexist in their respective folders. Hermes reads `config.yaml` and `.env` — the symlink provides the rename.

**Fresh machine recovery:** `secrets/admin.env.enc` is committed. Decrypt to restore the plaintext: `sops --decrypt secrets/admin.env.enc > secrets/admin.env`.

---

## Profile config constraints

admin's `config/admin-config.yaml`:

| Field | Value |
|---|---|
| `allow_lazy_installs` | `false` |
| `approvals.mode` | `manual` |
| `redact_secrets` | `true` |
| `DISCORD_ALLOWED_USERS` | owner's Discord user ID |
| `discord.allowed_channels` | `[ALERTS, LOGS, ADMIN, SANDBOX]` channel IDs |
| `cron_mode` | `manual` |
| `terminal` | enabled with `command_allowlist` scoped to service restarts |
| `model.default` | `deepseek/deepseek-v4-flash` |
| `model.provider` | `custom` |
| `model.base_url` | `http://localhost:4000` |
| `model.api_key` | `"${LITELLM_VIRTUAL_KEY}"` (resolved from profile `.env`) |
| `model.api_mode` | `chat_completions` |
| compression model | `deepseek/deepseek-v4-flash` |

Model names omit the `openrouter/` prefix — LiteLLM's wildcard routing (`model_name: "*"` → `openrouter/*`) adds it when forwarding to OpenRouter. Using the full `openrouter/deepseek/...` form in Hermes config causes double-prefix and routing failures.

`api_mode` must be `chat_completions` (underscore). The slash form `chat/completions` is not recognized by Hermes's custom provider.

Models route through LiteLLM at `localhost:4000`.

---

## Per-profile secrets

`secrets/admin.env` (plaintext, gitignored, live file Hermes reads via symlink):

```
DISCORD_TOKEN=<admin bot token>
LITELLM_VIRTUAL_KEY=sk-nizam-admin-...
DISCORD_ALLOWED_USERS=<owner discord user id>
```

Hermes resolves `"${LITELLM_VIRTUAL_KEY}"` in `admin-config.yaml` from this env file at startup. The model block in `admin-config.yaml` references it as a string literal — Hermes expands it, not the shell.

`secrets/admin.env.enc` — same age key as `nizam-os.env` (`secrets/nizam-age-key.txt`), committed.

---

## LiteLLM virtual key

One virtual key per agent profile via the LiteLLM Admin API. Key alias pattern: `sk-nizam-<profile>`. Written to `secrets/<profile>.env` as `LITELLM_VIRTUAL_KEY` by the setup script.

Phase 2 creates: `sk-nizam-admin` → `secrets/admin.env`.

Per-profile keys enable per-agent spend tracking and independent revocation. Never reuse the master key or share a virtual key across profiles.

---

## Sudoers — admin

File: `/etc/sudoers.d/admin-nizam`

Grants `vazir` passwordless `systemctl restart` and `systemctl start` for the defined service list — nothing else.

Services admin can restart:

```
litellm-proxy, watcher-env, watcher-inventory.timer,
metrics-llm.timer, metrics-services.timer, metrics-toolcalls.timer,
loki, promtail, prometheus, prometheus-node-exporter,
grafana-server, postgresql, redis-server
```

admin's `command_allowlist` in `admin-config.yaml` mirrors this list exactly.

---

## Systemd unit

One user service for Phase 2:

| Unit | Type | Purpose |
|---|---|---|
| `hermes-admin.service` | user, persistent | Hermes gateway for admin |

Unit file: `systemd/hermes-admin.service`, symlinked to `~/.config/systemd/user/hermes-admin.service` by `install-symlinks.sh`.

User services run under `vazir` via `loginctl enable-linger vazir`.

Logs to `logs/hermes-admin.log` — tailed by Promtail into Loki.

---

## Exit criteria

```bash
# Hermes installed
hermes --version   # → version string

# Gateway active
systemctl --user is-active hermes-admin   # → active

# Virtual key exists
source ~/nizam-os/secrets/nizam-os.env
curl -s -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  http://localhost:4000/key/list \
  | python3 -c "
import json,sys
keys = json.load(sys.stdin)
print(len([k for k in keys.get('keys',[]) if k.get('key_alias','')=='sk-nizam-admin']))
"
# → 1

# Symlinks in place
readlink ~/.hermes/profiles/admin/config.yaml   # → .../nizam-os/config/admin-config.yaml
readlink ~/.hermes/profiles/admin/.env          # → .../nizam-os/secrets/admin.env

# Sudoers valid
sudo visudo -c -f /etc/sudoers.d/admin-nizam   # → parsed OK

# Manual: open Discord — admin shows green presence in server member list
# Manual: send message in #admin — admin responds
```
