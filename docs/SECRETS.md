# Nizam-OS — Secrets Reference

**Last updated:** 2026-07-01

All env vars: purpose, consumer, where stored, how to rotate. For rotation procedures see `docs/RUNBOOK.md`.

---

## Storage model

| File | Contents | Committed |
|---|---|---|
| `secrets/nizam.env` | Shared system vars | No (gitignored) |
| `secrets/nizam.env.enc` | sops-encrypted nizam.env | Yes |
| `secrets/nizam.env.example` | Keys only, no values | Yes |
| `hermes/profiles/<name>/.env` | Per-profile Discord + LiteLLM key | No (gitignored) |
| `hermes/profiles/<name>/.env.enc` | sops-encrypted profile .env | Yes |
| `secrets/nizam-age-key.txt` | age private key | No (gitignored) — **back up before VPS wipe** |

Encryption: sops + age keypair. Scripts: `scripts/encrypt-env.sh`, `scripts/decrypt-env.sh`, `scripts/encrypt-profile-env.sh <name>`, `scripts/decrypt-profile-env.sh <name>`.

`watcher-env.service` auto-encrypts `nizam.env` on file save (inotifywait `close_write`). Profile `.env` files are auto-encrypted by `hermes-profile-watcher.service` on change.

---

## `secrets/nizam.env` — shared system vars

| Variable | Purpose | Consumer(s) | Rotation |
|---|---|---|---|
| `OPENROUTER_API_KEY` | Auth for OpenRouter API | LiteLLM proxy (`litellm-proxy.service`) | Generate new key at openrouter.ai → Settings → API Keys. Update nizam.env. Restart litellm-proxy. |
| `LITELLM_MASTER_KEY` | LiteLLM admin operations (create virtual keys, view spend) | `setup-litellm-keys.sh`, any direct LiteLLM API call | Set once. Rotate by updating nizam.env + restarting litellm-proxy + re-running setup-litellm-keys.sh. |
| `LITELLM_DB_PASSWORD` | PostgreSQL password for `svc_litellm` role | LiteLLM proxy (via `LITELLM_DB_URL`) | `ALTER ROLE svc_litellm WITH PASSWORD 'new'` in psql. Update LITELLM_DB_PASSWORD and LITELLM_DB_URL. Restart litellm-proxy. |
| `LITELLM_DB_URL` | Full DSN: `postgresql://svc_litellm:<pass>@localhost/nizam` | LiteLLM proxy | Rebuild from updated LITELLM_DB_PASSWORD. |
| `DATABASE_URL` | Legacy alias for LITELLM_DB_URL | Unused or same as LITELLM_DB_URL | Same as LITELLM_DB_URL. |
| `POSTGRES_SVC_KNOWLEDGE_PASS` | PostgreSQL password for `svc_knowledge` role | `knowledge-service` (via ServiceBase) | `ALTER ROLE svc_knowledge WITH PASSWORD 'new'` in psql. Update nizam.env. Restart knowledge-service. |
| `VAULT_ROOT` | Path to nizam-vault directory | `knowledge-service` (vault_io.py) | Default: `~/nizam-vault`. Override only if vault moves. |
| `REDIS_URL` | Redis DSN: `redis://localhost:6379/0` | LiteLLM proxy (cache), `nizam-shared` ServiceBase | Typically static. Change only if Redis port changes. |
| `DISCORD_ADMIN_WEBHOOK` | Webhook URL for admin/alert notifications | `scripts/watch-inventory.sh`, admin alerting | Regenerate in Discord: channel settings → Integrations → Webhooks. |
| `YOUTUBE_API_KEY` | YouTube Data API v3 key | `knowledge-service` transcript.py (Tier 3 fallback) | Generate at console.cloud.google.com → Credentials. 10,000 units/day free tier. |
| `YOUTUBE_COOKIES_FILE` | Path to `cookies.txt` for yt-dlp auth | `knowledge-service` transcript.py (Tier 2) | Re-export cookies from browser if yt-dlp starts getting 429s. |
| `NIZAM_INVENTORY_WATCHER` | Discord webhook for inventory-change notifications | `scripts/watch-inventory.sh` | **Missing from nizam.env.example — add on rebuild.** Same rotation as DISCORD_ADMIN_WEBHOOK. |

### Vars added in Curator v1

| Variable | Purpose | Consumer |
|---|---|---|
| `VISION_MODEL` | Vision model for `ingest_image` (default: `google/gemini-2.0-flash`) | `knowledge-service` vision.py |

### Vars added in Assistant v1

| Variable | Purpose | Consumer |
|---|---|---|
| `POSTGRES_SVC_FINANCE_PERSONAL_PASS` | Password for `svc_finance_personal` | `finance-service` |
| `POSTGRES_SVC_PERSONAL_PASS` | Password for `svc_personal` | `personal-service` |
| `FX_API_KEY` | exchangerate-api.com — FX rates at transaction time | `finance-service` |
| `GOLD_API_KEY` | metals-api.com or goldpricez.com — gold price for zakat calc | `finance-service` |

### Vars added in CTO v1

| Variable | Purpose | Consumer |
|---|---|---|
| `GITHUB_PAT` | GitHub fine-grained PAT for Reem's GitHub MCP server | `hermes/profiles/cto/.env` (per-profile, not nizam.env) |

---

## `hermes/profiles/<name>/.env` — per-profile vars

Same structure for all profiles. Values differ per profile.

| Variable | Purpose | Notes |
|---|---|---|
| `DISCORD_TOKEN` | Bot token for this profile's Discord bot | One bot per profile. Generate at discord.com/developers. |
| `DISCORD_GUILD_ID` | Discord server (guild) snowflake ID | Same value across all profiles — same server. |
| `LITELLM_MASTER_KEY` | This profile's LiteLLM virtual key | Created by `setup-litellm-keys.sh`. `user_id` = profile name → per-agent spend tracking. |

### Rotate a Discord bot token

1. discord.com/developers → Applications → select bot → Reset Token
2. `bash scripts/decrypt-profile-env.sh <name>`
3. Update `DISCORD_TOKEN` in `hermes/profiles/<name>/.env`
4. `bash scripts/encrypt-profile-env.sh <name>`
5. Restart the gateway: `hermes gateway stop <name> && hermes gateway start <name>`

---

## age keypair

`secrets/nizam-age-key.txt` — private key for all sops encryption.

**Back up before VPS wipe.** Without it, all `.enc` files are unreadable.

```bash
# Verify key is present and matches .enc files
cat secrets/nizam-age-key.txt | head -1   # should show: # created: ...

# Test decrypt
SOPS_AGE_KEY_FILE=secrets/nizam-age-key.txt sops --decrypt secrets/nizam.env.enc | head -3
```

Public key is embedded in `.sops.yaml` at the repo root (or inline in each `.enc` file). To check which public key was used:

```bash
head -5 secrets/nizam.env.enc   # sops metadata block shows the recipient
```

---

## `.sops.yaml`

Controls which files sops encrypts and with which key. If missing, sops falls back to `SOPS_AGE_RECIPIENTS` env var. Check the repo root for this file.

---

## What is NOT a secret

| Item | Where it lives | Why not a secret |
|---|---|---|
| LiteLLM config | `config/litellm.yaml` | No secrets inline — all values via `os.environ/VAR` |
| Hermes config.yaml | `hermes/profiles/<name>/config.yaml` | No secrets — just routing and toolset config |
| DB schema SQL | `db/migrations/` | No credentials |
| Discord channel IDs | `hermes/profiles/<name>/config.yaml` | Not sensitive — Discord channel IDs are public within the server |
