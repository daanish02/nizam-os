# Phase 1 Foundation — Guide

**What this builds:** PostgreSQL, Redis, LiteLLM, Loki, Promtail, audit schema, nizam-shared, systemd units, and Grafana dashboard skeleton. No agents. No Discord.

**Spec:** [001 Foundation — Design](../specs/001-foundation-design.md)  
**Plan:** [001 Foundation — Plan](../plans/001-foundation-plan.md)  
**Next phase:** [002 Hermes Baseline — Guide](002-hermes-baseline-guide.md)

---

## Prerequisites

- [ ] `nizam-dotfiles` `001-machine-setup.sh` complete and verified on this machine
- [ ] Tailscale running (`tailscale status` shows connected)

---

## Step 1 — Clone the repo

```bash
git clone <repo-url> ~/nizam-os
cd ~/nizam-os
```

---

## Step 2 — Choose your path

### Path A — Fresh (first time, no prior credentials)

Generate an age key and fill secrets manually:

```bash
# Age key encryption
sudo apt-get install -y age

age-keygen -o ~/nizam-os/secrets/nizam-age-key.txt
chmod 600 ~/nizam-os/secrets/nizam-age-key.txt

openssl rand -hex 32   # → LITELLM_MASTER_KEY
openssl rand -hex 32   # → POSTGRES_SVC_LITELLM_PASS
openssl rand -hex 32   # → REDIS_PASSWORD

cp ~/nizam-os/secrets/nizam-os.env.example ~/nizam-os/secrets/nizam-os.env
nano ~/nizam-os/secrets/nizam-os.env
```

> **Passwords must use `openssl rand -hex 32`, never base64.**
> `LITELLM_DB_URL` and `REDIS_URL` embed the password directly in the URL string. Base64 output contains `/` which breaks URL parsers (Prisma P1013 "invalid port", Redis `ValueError: invalid port`). Hex is alphanumeric only — safe in any URL field.

`nizam-os.env` needs these values:

| Variable | Where to get it |
|----------|----------------|
| `OPENROUTER_API_KEY` | openrouter.ai → Keys |
| `LITELLM_MASTER_KEY` | generated above |
| `POSTGRES_SVC_LITELLM_PASS` | generated above |
| `LITELLM_DB_URL` | `postgresql://svc_litellm:POSTGRES_SVC_LITELLM_PASS@127.0.0.1:5432/nizam?schema=litellm` |
| `REDIS_PASSWORD` | generated above |
| `REDIS_URL` | `redis://:REDIS_PASSWORD@127.0.0.1:6379/0` |

After `001-foundation.sh` runs, it will encrypt `nizam-os.env` → `nizam-os.env.enc` and prompt you to commit it. Back up `nizam-age-key.txt` to a password manager — it is the only thing not in git.

---

### Path B — Rebuild (migrating to new machine, credentials already exist)

You need two things from your previous machine (or backup):

1. **`nizam-age-key.txt`** — the age private key (backed up to password manager)
2. **`nizam-os.env.enc`** — already in git, no action needed

```bash
# Restore the age key
nano ~/nizam-os/secrets/nizam-age-key.txt   # paste key content from password manager
```

`001-foundation.sh` decrypts automatically only when `nizam-os.env` does **not** exist. If `nizam-os.env` is present (e.g. you edited it manually), it is used as-is and the `.enc` file is left untouched. The watcher then re-encrypts on next save.

On a fresh machine with no `nizam-os.env`, foundation.sh decrypts from `.enc` automatically. No other manual step needed.

---

## Step 3 — Run `001-foundation.sh`

```bash
# Run foundation setup script
sudo bash ~/nizam-os/scripts/setup/001-foundation.sh
```

Takes 5–10 minutes. Idempotent — if it fails partway, fix the error and re-run.

**What it does (in order):**
1. Detects path (rebuild vs fresh), decrypts or validates secrets
2. Installs: PostgreSQL 16, pgvector, ParadeDB, Redis, age, sops, gettext-base (Loki managed by dotfiles)
3. Configures Redis from `config/redis.conf` (substitutes password from env)
4. Copies nizam-os Promtail config to `/etc/promtail/promtail-nizam-os.yaml`
5. Starts PostgreSQL, creates `nizam` database, `vazir` superuser role, `svc_litellm` role, enables extensions
6. Installs uv + LiteLLM via `uv tool install --with prisma`, runs `prisma generate` + `prisma db push` (needs DB from step 5)
7. Runs dbmate migrations (`db/migrations/`)
8. Creates `/var/lib/prometheus/node-exporter/` owned by vazir
9. Wires symlinks (`install-symlinks.sh`), starts `promtail-nizam-os.service`
10. Encrypts `nizam-os.env` → `nizam-os.env.enc` if not already done
11. Enables: `watcher-env`, `watcher-inventory.timer`, all metrics timers
12. Starts `litellm-proxy`, waits for `/health/liveliness`
13. Waits for Loki `/ready`

---

## Step 4 — Verify

```bash
# LiteLLM
curl -s http://localhost:4000/health/liveliness
# → {"status":"healthy"}

# Redis
source ~/nizam-os/secrets/nizam-os.env && redis-cli -a "$REDIS_PASSWORD" ping
# → PONG

# PostgreSQL — both schemas present (runs as vazir via peer auth)
psql nizam -c "\dn"
# → audit, litellm

# Loki
curl -s http://localhost:3100/ready
# → ready

# Metric files (wait 5 min after timers start)
ls /var/lib/prometheus/node-exporter/nizam-*.prom
# → nizam-llm.prom  nizam-services.prom  nizam-toolcalls.prom

# All Phase 1 units active
systemctl is-active \
  litellm-proxy loki promtail promtail-nizam-os \
  watcher-env watcher-inventory.timer \
  metrics-llm.timer metrics-services.timer metrics-toolcalls.timer
# → all: active
```

---

## Step 5 — Grafana setup (manual)

Open `http://<tailscale-ip>:3000` (default login: admin/admin — change immediately).

**Add datasources:**

1. Connections → Data Sources → Add → **Prometheus**
   - URL: `http://localhost:9090`
   - UID: `nizam-prometheus`
   - → Save & Test

2. Connections → Data Sources → Add → **Loki**
   - URL: `http://localhost:3100`
   - UID: `nizam-loki`
   - → Save & Test

**Import dashboard:**

3. Dashboards → New → Import → upload `grafana/001-personal-dashboard.json`

Most panels show "no data" until later phases populate them — that is expected.

---

## Step 6 — Commit secrets (Path A only)

If this was a fresh setup, commit the newly created `nizam-os.env.enc`:

```bash
cd ~/nizam-os
git add secrets/nizam-os.env.enc
git commit -m "secrets: initial encrypted env for phase 1"
git push
```

---

## Troubleshooting

Script is idempotent — fix the error, re-run:

```bash
sudo bash ~/nizam-os/scripts/setup/001-foundation.sh
```

Missing env values:

```bash
nano ~/nizam-os/secrets/nizam-os.env   # fill all 6 values
```

LiteLLM not starting:

```bash
journalctl -u litellm-proxy -n 50
# Common causes:
#   LITELLM_DB_URL wrong — check password has no special chars (must be hex)
#   PostgreSQL not ready — check: systemctl status postgresql
```

Prisma `P1013 invalid port number` or LiteLLM/Redis `ValueError: invalid port`:

```bash
# Password in LITELLM_DB_URL or REDIS_URL contains '/' from base64 encoding.
# Regenerate all affected passwords with hex (no special chars):
openssl rand -hex 32   # → new POSTGRES_SVC_LITELLM_PASS
openssl rand -hex 32   # → new REDIS_PASSWORD
# Update nizam-os.env — setup-db.sh will ALTER USER on next run.
# Update LITELLM_DB_URL and REDIS_URL to use new passwords with 127.0.0.1 (not localhost).
```

Redis auth failure:

```bash
grep requirepass /etc/redis/redis.conf
grep REDIS_PASSWORD ~/nizam-os/secrets/nizam-os.env
# → both values must match
```

Loki not ready:

```bash
journalctl -u loki -n 30
# Common: /var/lib/loki/ permissions or config syntax error
```

Metric files not appearing after 5 min:

```bash
systemctl start metrics-llm.service
journalctl -u metrics-llm -n 20
```

sops decrypt fails ("no age identity found"):

```bash
age-keygen -y ~/nizam-os/secrets/nizam-age-key.txt
# → prints public key — must match line 1 of nizam-os.env.enc
```

pg_search not loading:

```bash
grep shared_preload_libraries /etc/postgresql/16/main/postgresql.conf
# → shared_preload_libraries = 'pg_search'
journalctl -u postgresql -n 10 | grep -i "error\|pg_search"
```
