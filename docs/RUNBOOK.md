# Nizam-OS — Runbook

**Last updated:** 2026-07-01

Day-to-day operations and procedures. All commands run as `vazir` unless noted.

---

## Fresh VPS rebuild

Use this when starting from a bare Ubuntu VPS. Work through phases in order — each plan file contains the full task list for that phase.

**Before anything else:** back up `secrets/nizam-age-key.txt` to an external location. Without it, all `.enc` files in the repo are unreadable.

### Rebuild sequence

| Phase | Plan file | Reference docs to keep open |
|---|---|---|
| 1 — Foundation | `docs/plans/20260701-foundation.md` | `docs/SECRETS.md`, `docs/SERVICES.md`, `docs/DISCORD.md` |
| 2 — Immediate fixes | `docs/plans/20260701-immediate-fixes.md` | `docs/SECURITY.md`, `docs/AGENTS.md` |
| 3 — Curator v1 | `docs/plans/20260701-curator-v1.md` | `docs/SCHEMAS.md`, `docs/HERMES.md` |
| 4 — Admin v1 | `docs/plans/20260701-admin-v1.md` | `docs/AGENTS.md`, `docs/HERMES.md` |
| 5 — Assistant v1 | `docs/plans/20260701-assistant-v1.md` | `docs/SCHEMAS.md`, `docs/INTEGRATIONS.md` |
| 6a–6e — C-suite | per-agent plan (when written) | `docs/AGENTS.md`, `docs/SERVICES.md` |

Start each phase by reading the spec (`docs/specs/`) for that phase — the plan references it for design rationale.

For system architecture, read `docs/ARCHITECTURE.md` first.

---

## Service management

### System services (require sudo)

```bash
# LiteLLM proxy
sudo systemctl status litellm-proxy
sudo systemctl restart litellm-proxy
sudo journalctl -u litellm-proxy -n 50 --no-pager

# Metrics timers
sudo systemctl status metrics-llm.timer metrics-services.timer metrics-toolcalls.timer
sudo systemctl restart metrics-llm.timer

# Inventory watcher
sudo systemctl status watcher-inventory.timer
sudo systemctl restart watcher-inventory.service   # run immediately

# Env watcher
sudo systemctl status watcher-env.service
sudo systemctl restart watcher-env.service

# knowledge-service (added in Curator v1)
sudo systemctl status knowledge-service
sudo systemctl restart knowledge-service
sudo journalctl -u knowledge-service -n 50 --no-pager

# finance-service / personal-service (added in Assistant v1)
sudo systemctl status finance-service personal-service
```

### User services (no sudo — run as vazir)

```bash
# Hermes profile watcher (bidirectional sync + auto-encrypt)
systemctl --user status hermes-profile-watcher
systemctl --user restart hermes-profile-watcher
journalctl --user -u hermes-profile-watcher -n 30 --no-pager
```

### Hermes gateways (one per active agent profile)

```bash
# Start a gateway
hermes gateway start <profile>    # e.g. hermes gateway start curator

# Stop a gateway
hermes gateway stop <profile>

# Status of all gateways
hermes gateway list

# Logs
hermes gateway logs <profile> -n 50
```

### Check all services at once

```bash
sudo systemctl status \
  litellm-proxy \
  metrics-llm.timer \
  metrics-services.timer \
  metrics-toolcalls.timer \
  watcher-inventory.timer \
  watcher-env.service \
  knowledge-service 2>/dev/null
systemctl --user status hermes-profile-watcher
```

---

## Logs

```bash
# LiteLLM spend logs (PostgreSQL)
psql -U svc_litellm -d nizam -c "SELECT * FROM litellm.spendlogs ORDER BY startTime DESC LIMIT 20;"

# knowledge-service audit trail
psql -U svc_knowledge -d nizam -c "SELECT * FROM knowledge.vault_audit ORDER BY created_at DESC LIMIT 20;"

# Prometheus metrics written by timers
ls -lh /var/lib/prometheus/node-exporter/
cat /var/lib/prometheus/node-exporter/nizam-llm.prom

# Grafana: http://localhost:3000 (or via Tailscale IP)
# Prometheus: http://localhost:9090
```

---

## Secrets

### Decrypt / edit nizam.env

```bash
# Decrypt (after clone on fresh VPS)
bash scripts/decrypt-env.sh

# Edit the plain file
nano secrets/nizam.env

# Re-encrypt (or just save the file — watcher-env.service auto-encrypts on close_write)
bash scripts/encrypt-env.sh
```

### Rotate a secret in nizam.env

1. Decrypt: `bash scripts/decrypt-env.sh`
2. Edit `secrets/nizam.env` with new value
3. Restart the service that uses it (see SECRETS.md for which service uses which var)
4. Save the file — `watcher-env.service` auto-encrypts on save. If watcher is not running: `bash scripts/encrypt-env.sh`
5. Commit `secrets/nizam.env.enc`

### Decrypt / edit a profile .env

```bash
bash scripts/decrypt-profile-env.sh <profile>   # e.g. curator
nano hermes/profiles/curator/.env
bash scripts/encrypt-profile-env.sh curator
```

Profile `.env` vars: `DISCORD_TOKEN`, `DISCORD_GUILD_ID`, `LITELLM_MASTER_KEY` (virtual key).

### Refresh yt-dlp cookies

If yt-dlp returns 429 or sign-in required:

1. Export `cookies.txt` from a logged-in browser: `yt-dlp --cookies-from-browser chrome` or use a browser extension
2. Update `YOUTUBE_COOKIES_FILE` path in `secrets/nizam.env`
3. `watcher-env.service` auto-encrypts on save

### Rotate a Discord bot token

1. discord.com/developers → Applications → select bot → Reset Token
2. `bash scripts/decrypt-profile-env.sh <name>`
3. Update `DISCORD_TOKEN` in `hermes/profiles/<name>/.env`
4. `bash scripts/encrypt-profile-env.sh <name>`
5. `hermes gateway stop <name> && hermes gateway start <name>`

### Re-generate LiteLLM virtual keys

```bash
# Creates one virtual key per profile, writes to each profile's .env
bash scripts/setup/setup-litellm-keys.sh
# Then re-encrypt all profiles
for p in admin curator assistant cos cfo coo cto cmo; do
    bash scripts/encrypt-profile-env.sh $p 2>/dev/null || true
done
```

---

## Adding a new agent profile

```bash
# 1. Create the profile in Hermes
hermes profile create <name> --description "<one-line role description>"

# 2. Wire it into nizam-os (symlinks skills/, memories/, config.yaml, .md files)
bash scripts/setup/wire-hermes-profile.sh <name>

# 3. Create hermes/profiles/<name>/ in repo if it doesn't exist yet
mkdir -p hermes/profiles/<name>

# 4. Decrypt the profile .env (if .env.enc exists)
bash scripts/decrypt-profile-env.sh <name>

# 5. Set Discord secrets in the .env
nano hermes/profiles/<name>/.env
# DISCORD_TOKEN=...
# DISCORD_GUILD_ID=...
# LITELLM_MASTER_KEY=...  (generate via setup-litellm-keys.sh or LiteLLM UI)

# 6. Write SOUL.md, AGENTS.md, config.yaml to hermes/profiles/<name>/
# (see agent's spec for content)

# 7. Start the gateway
hermes gateway start <name>
```

---

## Updating systemd units

After editing any file in `systemd/`:

```bash
# System units
sudo systemctl daemon-reload
sudo systemctl restart <unit-name>

# User units
systemctl --user daemon-reload
systemctl --user restart <unit-name>
```

After editing `config/logrotate.nizam` (logrotate is copied not symlinked):

```bash
sudo bash scripts/setup/install-symlinks.sh   # re-copies + chowns
```

---

## Observability

### Verify metrics are being written

```bash
# Check .prom files exist and are recent (< 10 min old)
stat /var/lib/prometheus/node-exporter/nizam-llm.prom
stat /var/lib/prometheus/node-exporter/nizam-services.prom
stat /var/lib/prometheus/node-exporter/nizam-toolcalls.prom

# Force-run a timer immediately
sudo systemctl start metrics-llm.service
```

### Prometheus scrape health

```bash
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool | grep -A5 "health"
```

### Grafana dashboard

Import via UI: Dashboards → Import → upload JSON file.
- `grafana/agents-dashboard.json` — LLM spend, tokens, cache hits, tool calls
- `grafana/services-dashboard.json` — service health metrics

Datasource UID must be `nizam-prometheus`. Set when configuring the Prometheus datasource in Grafana.

---

## Database

### Connect

```bash
psql -U vazir -d nizam          # as superuser
psql -U svc_knowledge -d nizam  # as service user
```

### Run a migration

```bash
psql -U vazir -d nizam -f db/migrations/0001_knowledge_schema.sql
```

### Check roles and grants

```bash
psql -U vazir -d nizam -c "\du"                         # list roles
psql -U vazir -d nizam -c "\dp knowledge.vault_index"   # check grants on table
```

### LiteLLM DB init (run once after fresh VPS)

```bash
# Requires LITELLM_DB_URL set in environment
export $(grep -v '^#' secrets/nizam.env | xargs)
litellm --config config/litellm.yaml --port 4000 &
sleep 5
# LiteLLM runs Prisma migration on startup if DB tables don't exist
# Verify:
psql -U svc_litellm -d nizam -c "\dt litellm.*"
```

---

## Common fixes

### Gateway not responding

```bash
hermes gateway stop <profile>
hermes gateway start <profile>
hermes gateway logs <profile> -n 20
```

### knowledge-service returning errors

```bash
# Check DB connection
sudo systemctl status knowledge-service
sudo journalctl -u knowledge-service -n 30 --no-pager
# Check vault dir exists
ls ~/nizam-vault/commons/
# Check schema exists
psql -U svc_knowledge -d nizam -c "\dt knowledge.*"
```

### LiteLLM not starting

```bash
sudo journalctl -u litellm-proxy -n 30 --no-pager
# Common: nizam.env not decrypted, OPENROUTER_API_KEY empty
grep OPENROUTER_API_KEY secrets/nizam.env
```

### Metrics not appearing in Grafana

```bash
# 1. Check .prom files exist
ls /var/lib/prometheus/node-exporter/
# 2. Check Prometheus can scrape them
curl -s 'http://localhost:9090/api/v1/query?query=nizam_llm_cost_usd_total' | python3 -m json.tool
# 3. Check timer is enabled
sudo systemctl is-enabled metrics-llm.timer
```

### Profile .env missing on fresh clone

```bash
# Decrypt all profiles at once
for p in admin curator assistant cos; do
    bash scripts/decrypt-profile-env.sh $p 2>/dev/null || echo "$p: no .env.enc found"
done
```
