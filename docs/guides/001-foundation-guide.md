# Phase 1 Foundation — Guide

**What this builds:** PostgreSQL, Redis, LiteLLM, Loki, Promtail, audit schema, nizam-shared refactor, systemd units, and Grafana dashboard skeletons. No agents. No Discord.

**Spec:** [docs/specs/001-foundation.md](../specs/001-foundation.md)  
**Plan:** [docs/plans/001-foundation.md](../plans/001-foundation.md)  
**Next phase:** [docs/guides/002-hermes-baseline.md](002-hermes-baseline.md)

---

## Prerequisites

- [ ] `~/nizam-dotfiles/docs/startup-guide.md` complete — all 9 steps done and verified
- [ ] Fresh VPS reachable via Tailscale (`ssh vazir@<tailscale-ip>` works)
- [ ] `git` and `age` available on VPS

---

## Step 1 — Before wiping the old repo

Do this on the **old machine** before deleting anything.

**1a. Back up the age private key**

```bash
cat ~/nizam-os/secrets/nizam-age-key.txt
```

Copy this to a password manager or secure external location. Without it, `nizam.env.enc` cannot be decrypted. This is the only thing that cannot be recovered from git.

**1b. Confirm `nizam.env.enc` is committed**

```bash
cd ~/nizam-os
git status secrets/nizam.env.enc
# Expected: nothing (already committed) or "modified" — commit it
```

If modified: `git add secrets/nizam.env.enc && git commit -m "secrets: update encrypted env"`.

**1c. Confirm dashboard JSONs are in `docs/grafana/`**

```bash
ls docs/grafana/
# Expected: personal-dashboard.json  business-dashboard.json
```

If they don't exist yet, import them from Grafana UI first (Dashboards → ⋮ → Export JSON → Save to file) and commit.

**1d. Wipe**

Keep only `docs/` — everything else gets deleted and rebuilt from the plan.

---

## Step 2 — Clone on new VPS

```bash
git clone <repo-url> ~/nizam-os
cd ~/nizam-os
```

---

## Step 3 — Secrets setup

**Rebuild (reusing existing credentials — most common):**

```bash
# Restore the age key you backed up in Step 1a
nano ~/nizam-os/secrets/nizam-age-key.txt   # paste key content

# foundation.sh will detect nizam.env.enc and decrypt automatically
```

**Fresh (new credentials):**

```bash
# Generate age key
age-keygen -o ~/nizam-os/secrets/nizam-age-key.txt

# Generate strong passwords — run each command separately, copy outputs
openssl rand -base64 32   # → LITELLM_DB_PASSWORD
openssl rand -base64 32   # → REDIS_PASSWORD
openssl rand -base64 32   # → LITELLM_MASTER_KEY

# Fill nizam.env
cp ~/nizam-os/secrets/nizam.env.example ~/nizam-os/secrets/nizam.env
nano ~/nizam-os/secrets/nizam.env
```

`nizam.env` needs 7 values:

| Variable | Where to get it |
|----------|----------------|
| `OPENROUTER_API_KEY` | openrouter.ai → Keys |
| `LITELLM_MASTER_KEY` | generated above |
| `LITELLM_DB_PASSWORD` | generated above |
| `LITELLM_DB_URL` | `postgresql://svc_litellm:LITELLM_DB_PASSWORD@localhost:5432/nizam?schema=litellm` |
| `REDIS_URL` | `redis://:REDIS_PASSWORD@localhost:6379/0` |
| `REDIS_PASSWORD` | generated above |
| `DISCORD_WEBHOOK_LOGS` | leave empty for now — fill in Phase 2 |

---

## Step 4 — Run foundation.sh

```bash
sudo bash ~/nizam-os/scripts/setup/foundation.sh
```

Takes 5–10 minutes. The script is idempotent — if it fails partway, fix the error and re-run from the same point.

**What it does (in order):**
1. Detects rebuild vs fresh, decrypts or validates secrets
2. Installs: PostgreSQL 16, pgvector, ParadeDB, Redis, Loki, Promtail, age, sops, gettext-base
3. Configures Redis from `config/redis.conf` (envsubst fills the password)
4. Installs Loki + Promtail, copies configs, starts both
5. Installs uv + LiteLLM via `uv tool install`
6. Creates `nizam` database, `svc_litellm` role, enables extensions
7. Runs `db/migrations/001_audit_schema.sql`
8. Creates `/var/lib/prometheus/node-exporter/` (owned by vazir)
9. Wires symlinks (`install-symlinks.sh`)
10. Encrypts `nizam.env` → `nizam.env.enc` if not already done
11. Enables: `watcher-env`, `watcher-inventory.timer`, all metrics timers
12. Starts `litellm-proxy`, waits for `/health/liveliness`
13. Waits for Loki `/ready`
14. Prints Grafana setup instructions

---

## Step 5 — Verify exit criteria

Run after foundation.sh completes:

```bash
# LiteLLM
curl -s http://localhost:4000/health/liveliness
# → {"status":"healthy"}

# Redis
source ~/nizam-os/secrets/nizam.env && redis-cli -a "$REDIS_PASSWORD" ping
# → PONG

# PostgreSQL — both schemas present
sudo -u postgres psql nizam -c "\dn"
# → audit, litellm

# Loki
curl -s http://localhost:3100/ready
# → ready

# Secrets
grep -c "=" ~/nizam-os/secrets/nizam.env
# → 7

# Metric files (wait 5 min after timers start)
ls /var/lib/prometheus/node-exporter/nizam-*.prom
# → nizam-llm.prom  nizam-services.prom  nizam-toolcalls.prom

# All Phase 1 units active
systemctl is-active \
  litellm-proxy loki promtail \
  watcher-env watcher-inventory.timer \
  metrics-llm.timer metrics-services.timer metrics-toolcalls.timer
# → all: active
```

---

## Step 6 — Grafana setup (manual)

Grafana has no CLI for datasource + dashboard import. Do this once via browser.

Open Grafana at `http://<tailscale-ip>:3000` (default login: admin/admin — change immediately).

**Datasources:**

1. Connections → Data Sources → Add → **Prometheus**
   - URL: `http://localhost:9090`
   - UID: `nizam-prometheus`
   - → Save & Test (should show green)

2. Connections → Data Sources → Add → **Loki**
   - URL: `http://localhost:3100`
   - UID: `nizam-loki`
   - → Save & Test

**Dashboards:**

3. Dashboards → New → Import → upload `docs/grafana/personal-dashboard.json`
4. Dashboards → New → Import → upload `docs/grafana/business-dashboard.json`

> Most panels will show "no data" — that's correct. Infrastructure and LLM panels populate immediately. Finance, habits, and knowledge panels populate in Phases 4–5.

---

## Step 7 — Commit `nizam.env.enc`

If this was a fresh setup (new credentials), foundation.sh created a new `nizam.env.enc`. Commit it:

```bash
cd ~/nizam-os
git add secrets/nizam.env.enc secrets/nizam.env.example
git commit -m "secrets: initial encrypted env for phase 1"
git push
```

---

## Troubleshooting

**LiteLLM doesn't start:**
```bash
journalctl -u litellm-proxy -n 50
# Common: LITELLM_DB_URL wrong, or PostgreSQL not yet accepting connections
```

**Redis auth failure:**
```bash
# Check password matches between nizam.env and /etc/redis/redis.conf
grep requirepass /etc/redis/redis.conf
grep REDIS_PASSWORD ~/nizam-os/secrets/nizam.env
```

**Loki not ready:**
```bash
journalctl -u loki -n 30
# Common: /var/lib/loki/ permissions or config syntax error
```

**Metric files not appearing:**
```bash
# Trigger manually to see errors
systemctl start metrics-llm.service
journalctl -u metrics-llm -n 20
```

**Re-run foundation.sh after partial failure:**
```bash
sudo bash ~/nizam-os/scripts/setup/foundation.sh
# Safe — every block checks state before acting
```

---

## What's next

Phase 1 is infrastructure only. No agents, no Discord. Proceed to:

**[Phase 2 — Hermes baseline](002-hermes-baseline.md):** Hermes install, Discord server setup, all agent profiles configured, LiteLLM virtual keys per agent.