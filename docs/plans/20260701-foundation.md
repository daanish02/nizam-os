# Foundation — rebuild plan

> **For agentic workers:** execute tasks in order. Each task ends with a verification step. Do not proceed to the next task if verification fails.

**Goal:** Reproduce the current foundation state on a fresh Hostinger KVM2 VPS (Ubuntu 22.04) from the nizam-os git repo.

**Spec:** `docs/specs/20260701-foundation-design.md`

**Secrets prerequisite:** the age private key (`secrets/nizam-age-key.txt`) must be available before starting. Back it up before wiping the VPS. Without it, `nizam.env.enc` cannot be decrypted.

---

## Task 1: OS baseline + security

- [ ] **Step 1: Set hostname**

```bash
sudo hostnamectl set-hostname nizam-vps
```

- [ ] **Step 2: Create user `vazir` if not already created**

```bash
sudo adduser vazir
sudo usermod -aG sudo vazir
```

- [ ] **Step 3: Harden SSH**

Edit `/etc/ssh/sshd_config`:
```
PasswordAuthentication no
PermitRootLogin no
```

Add your SSH public key to `/home/vazir/.ssh/authorized_keys`, then:
```bash
sudo systemctl restart ssh
```

Verify SSH key auth works in a second terminal before closing the current session.

- [ ] **Step 4: UFW**

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
sudo ufw status
```

Expected: status active, rules as above.

- [ ] **Step 5: fail2ban**

```bash
sudo apt install -y fail2ban
sudo systemctl enable --now fail2ban
sudo fail2ban-client status sshd
```

Expected: `sshd` jail active, currently 0 banned.

- [ ] **Step 6: unattended-upgrades**

```bash
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure --priority=low unattended-upgrades
```

Select "Yes" to enable.

- [ ] **Step 7: Tailscale**

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --auth-key <YOUR_TAILSCALE_AUTH_KEY>
tailscale ip -4
```

Expected: Tailscale IP printed.

---

## Task 2: Install packages + uv

- [ ] **Step 1: System packages**

```bash
sudo apt update && sudo apt install -y \
    build-essential git curl wget \
    python3.12 python3.12-dev python3-pip \
    nodejs npm \
    inotify-tools \
    age sops \
    logrotate
```

Verify Python version:
```bash
python3.12 --version
```
Expected: `Python 3.12.x`

Verify Node.js (needed for GitHub MCP in future Reem build):
```bash
node --version
```
Expected: `v20.x` or higher.

- [ ] **Step 2: Install uv**

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
source ~/.bashrc
uv --version
```
Expected: uv version printed.

- [ ] **Step 3: Install yt-dlp**

```bash
pip install -U yt-dlp
yt-dlp --version
```
Expected: version printed.

---

## Task 3: PostgreSQL + extensions

- [ ] **Step 1: Install PostgreSQL**

```bash
sudo apt install -y postgresql postgresql-contrib
sudo systemctl enable --now postgresql
sudo systemctl is-active postgresql
```
Expected: `active`

- [ ] **Step 2: Install pgvector**

```bash
sudo apt install -y postgresql-15-pgvector
```

If not available via apt:
```bash
sudo apt install -y postgresql-server-dev-15 git
git clone --branch v0.7.4 https://github.com/pgvector/pgvector.git /tmp/pgvector
cd /tmp/pgvector && make && sudo make install
```

Verify:
```bash
sudo -u postgres psql -c "CREATE EXTENSION IF NOT EXISTS vector;" nizam 2>/dev/null || echo "(DB not created yet — verify after Task 3 Step 4)"
```

- [ ] **Step 3: Install ParadeDB (pg_search / BM25)**

Follow ParadeDB apt repo install (check paradedb.com for current Ubuntu 22.04 instructions — they change between releases):

```bash
curl -fsSL https://packagecloud.io/paradedb/paradedb/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/paradedb-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/paradedb-archive-keyring.gpg] https://packagecloud.io/paradedb/paradedb/ubuntu jammy main" | sudo tee /etc/apt/sources.list.d/paradedb.list
sudo apt update && sudo apt install -y postgresql-15-pg-search
```

- [ ] **Step 4: Create nizam database + svc_litellm**

Ensure `LITELLM_DB_PASSWORD` is set (will be in nizam.env after Task 5):
```bash
export LITELLM_DB_PASSWORD=$(grep LITELLM_DB_PASSWORD ~/nizam-os/secrets/nizam.env | cut -d= -f2)
bash ~/nizam-os/scripts/setup/setup-db.sh
```

Expected output: "Database setup complete." with LITELLM_DB_URL to add to nizam.env.

- [ ] **Step 5: Enable extensions in nizam database**

```bash
sudo -u postgres psql nizam <<SQL
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_search;
\dx
SQL
```

Expected: both extensions listed in `\dx` output.

---

## Task 4: Redis

- [ ] **Step 1: Install + enable**

```bash
sudo apt install -y redis-server
sudo systemctl enable --now redis-server
redis-cli ping
```
Expected: `PONG`

- [ ] **Step 2: Bind to localhost only**

Verify `/etc/redis/redis.conf` has:
```
bind 127.0.0.1 ::1
```

If not, add it and restart:
```bash
sudo systemctl restart redis-server
```

---

## Task 5: Clone repo + decrypt secrets

- [ ] **Step 1: Clone**

```bash
git clone https://github.com/<your-username>/nizam-os.git ~/nizam-os
cd ~/nizam-os
```

- [ ] **Step 2: Place age private key**

Copy `secrets/nizam-age-key.txt` from your backup to `~/nizam-os/secrets/nizam-age-key.txt`:
```bash
chmod 600 ~/nizam-os/secrets/nizam-age-key.txt
```

- [ ] **Step 3: Decrypt nizam.env**

```bash
export SOPS_AGE_KEY_FILE=~/nizam-os/secrets/nizam-age-key.txt
sops --decrypt --input-type dotenv --output-type dotenv \
    ~/nizam-os/secrets/nizam.env.enc > ~/nizam-os/secrets/nizam.env
chmod 600 ~/nizam-os/secrets/nizam.env
```

Verify key variables are present:
```bash
grep -E "^(OPENROUTER_API_KEY|LITELLM_MASTER_KEY|POSTGRES_SVC_KNOWLEDGE_PASS|REDIS_URL)=" ~/nizam-os/secrets/nizam.env
```
Expected: all 4 lines appear with values.

- [ ] **Step 4: Decrypt profile .envs**

```bash
export SOPS_AGE_KEY_FILE=~/nizam-os/secrets/nizam-age-key.txt
bash ~/nizam-os/scripts/setup/wire-hermes-profile.sh admin curator
```

This decrypts each profile's `.env.enc` → `.env` if the plain `.env` is missing. Will also wire symlinks (which is a no-op before Hermes profiles exist — safe to run, will warn about missing profiles).

---

## Task 6: Hermes install + profile wiring

- [ ] **Step 1: Install Hermes**

Follow Hermes installation instructions (check Hermes docs — package or install script):
```bash
# If pip-installable:
pip install hermes-agent
# Verify:
hermes --version
```

- [ ] **Step 2: Create named profiles**

```bash
hermes profile create admin --description "System admin, infrastructure, incident response, Hermes expertise."
hermes profile create curator --description "Knowledge vault curator, web/YouTube ingestion, taxonomy keeper."
hermes profile create assistant --description "Personal assistant, habits, goals, tasks, journal, personal finance."
hermes profile create cos --description "Chief of Staff, business delegation, weekly review, Kanban orchestrator."
```

- [ ] **Step 3: Wire all profiles**

```bash
bash ~/nizam-os/scripts/setup/wire-hermes-profile.sh admin curator assistant cos
```

Expected output: each profile shows `done`. Verify symlinks:
```bash
ls -la ~/.hermes/profiles/admin/SOUL.md
ls -la ~/.hermes/profiles/curator/config.yaml
```
Expected: both are symlinks pointing into `~/nizam-os/hermes/profiles/`.

---

## Task 7: Systemd symlinks + system services

- [ ] **Step 1: Run install-symlinks.sh**

```bash
sudo bash ~/nizam-os/scripts/setup/install-symlinks.sh
```

Expected: prints symlink paths. Runs `systemctl daemon-reload`.

- [ ] **Step 2: Enable user service (run as vazir, not root)**

```bash
systemctl --user daemon-reload
systemctl --user enable --now hermes-profile-watcher.service
systemctl --user is-active hermes-profile-watcher.service
```
Expected: `active`

- [ ] **Step 3: Enable + start system services**

```bash
sudo systemctl enable --now litellm-proxy.service
sudo systemctl enable --now watcher-env.service
sudo systemctl enable --now watcher-inventory.timer
```

Verify:
```bash
systemctl is-active litellm-proxy.service watcher-env.service watcher-inventory.timer
```
Expected: all `active`

---

## Task 8: LiteLLM DB initialization + virtual keys

The LiteLLM proxy must be running and `LITELLM_DB_URL` must be set in `nizam.env` before this task.

- [ ] **Step 1: Add LITELLM_DB_URL to nizam.env**

The value was printed at the end of `setup-db.sh` output (Task 3 Step 4). Edit `nizam.env` to add it if not already present:
```
LITELLM_DB_URL=postgresql://svc_litellm:<PASSWORD>@localhost:5432/nizam?schema=litellm
```

- [ ] **Step 2: Restart LiteLLM proxy**

On first start with a valid `DATABASE_URL`, LiteLLM auto-runs Prisma migration to create its tables:
```bash
sudo systemctl restart litellm-proxy.service
sleep 10
sudo journalctl -u litellm-proxy.service -n 30
```

Expected in logs: "Database migration complete" or similar Prisma output. No errors about "relation does not exist".

- [ ] **Step 3: Verify spend tracking**

```bash
curl -s -H "Authorization: Bearer $(grep LITELLM_MASTER_KEY ~/nizam-os/secrets/nizam.env | cut -d= -f2)" \
    http://localhost:4000/spend/logs?limit=1 | python3 -m json.tool
```
Expected: empty list `[]` (no spend yet) — not an error about missing table.

- [ ] **Step 4: Create per-profile LiteLLM virtual keys**

```bash
source ~/nizam-os/secrets/nizam.env
bash ~/nizam-os/scripts/setup/setup-litellm-keys.sh
```

Expected: each profile gets a virtual key written to its `.env`. Script prints `key: created and written`.

Verify admin profile has a virtual key:
```bash
grep LITELLM_MASTER_KEY ~/nizam-os/hermes/profiles/admin/.env
```
Expected: a `sk-...` key that differs from the master key in `nizam.env`.

- [ ] **Step 5: Restart hermes gateways**

```bash
systemctl --user restart hermes-gateway-admin hermes-gateway-curator
systemctl --user is-active hermes-gateway-admin hermes-gateway-curator
```
Expected: both `active`

---

## Task 9: knowledge schema + svc_knowledge

- [ ] **Step 1: Create svc_knowledge role**

```bash
source ~/nizam-os/secrets/nizam.env
sudo -u postgres psql nizam <<SQL
CREATE USER svc_knowledge WITH PASSWORD '${POSTGRES_SVC_KNOWLEDGE_PASS}';
SQL
```

- [ ] **Step 2: Run migration**

```bash
sudo -u postgres psql nizam < ~/nizam-os/db/migrations/0001_knowledge_schema.sql
```

Expected: no errors. Tables created: vault_index, vault_embeddings, vault_audit.

- [ ] **Step 3: Verify schema**

```bash
sudo -u postgres psql nizam <<SQL
\dn
SELECT tablename FROM pg_tables WHERE schemaname = 'knowledge';
SQL
```
Expected: `knowledge` schema listed, three tables shown.

- [ ] **Step 4: Create vault directory**

```bash
mkdir -p ~/nizam-vault/commons
cd ~/nizam-vault && git init && git add -A && git commit -m "init: empty vault"
```

- [ ] **Step 5: Verify knowledge-service loads**

Open a Discord session with Noor (or test via CLI):
```bash
cd ~/nizam-os/services/knowledge-service
source ~/nizam-os/secrets/nizam.env
uv run python server.py
```
Expected: no import errors, MCP starts. Tool calls now connect to DB successfully.

---

## Task 10: Prometheus + Grafana + metric timers

- [ ] **Step 1: Install Prometheus + node-exporter**

```bash
sudo apt install -y prometheus prometheus-node-exporter
sudo systemctl enable --now prometheus prometheus-node-exporter
```

- [ ] **Step 2: Configure node-exporter textfile collection**

Add textfile collector to node-exporter unit or args:
```
--collector.textfile.directory=/var/lib/prometheus/node-exporter
```

Create the textfile dir if it doesn't exist:
```bash
sudo mkdir -p /var/lib/prometheus/node-exporter
sudo chown vazir:vazir /var/lib/prometheus/node-exporter
```

Restart node-exporter:
```bash
sudo systemctl restart prometheus-node-exporter
```

- [ ] **Step 3: Install Grafana**

```bash
sudo apt install -y apt-transport-https software-properties-common
wget -q -O - https://packages.grafana.com/gpg.key | sudo apt-key add -
echo "deb https://packages.grafana.com/oss/deb stable main" | sudo tee /etc/apt/sources.list.d/grafana.list
sudo apt update && sudo apt install -y grafana
sudo systemctl enable --now grafana-server
```

Verify:
```bash
curl -s http://localhost:3000/api/health
```
Expected: `{"database":"ok",...}`

- [ ] **Step 4: Configure Prometheus datasource in Grafana**

In Grafana UI (http://localhost:3000, default admin/admin — change password):
- Connections → Data Sources → Add → Prometheus
- URL: `http://localhost:9090`
- UID: `nizam-prometheus` (must match what the dashboard JSON expects)
- Save & Test → green checkmark

- [ ] **Step 5: Import dashboards**

Dashboards → Import → Upload JSON file:
- Import `grafana/agents-dashboard.json` → "Nizam — Agents"
- Import `grafana/services-dashboard.json` → "Nizam — Services"

Set datasource to `nizam-prometheus` when prompted.

- [ ] **Step 6: Enable metric timers**

```bash
sudo systemctl enable --now metrics-llm.timer metrics-services.timer metrics-toolcalls.timer
```

Wait 2 minutes, then:
```bash
ls -la /var/lib/prometheus/node-exporter/*.prom
```
Expected: `nizam-llm.prom`, `nizam-services.prom`, `nizam-toolcalls.prom` with recent timestamps.

- [ ] **Step 7: Verify panels show data**

In Grafana, open "Nizam — Agents" dashboard. "Proxy Up" stat panel should show 1. "Services" dashboard should show service rows with green/red status.

---

## Task 11: Inventory watcher

- [ ] **Step 1: Initialize inventory**

First run populates the baselines:
```bash
bash ~/nizam-os/scripts/watch-inventory.sh
```

Expected: creates `inventory/services.txt`, `inventory/software.txt`, `inventory/services.sha256`, `inventory/software.sha256`. No Discord notification on first run (no diff).

- [ ] **Step 2: Verify inventory content**

```bash
cat ~/nizam-os/inventory/services.txt | head -10
```
Expected: lines in format `service.name | system | active`

- [ ] **Step 3: Add NIZAM_INVENTORY_WATCHER to nizam.env**

If you want Discord notifications on inventory changes, add the webhook URL:
```
NIZAM_INVENTORY_WATCHER=https://discord.com/api/webhooks/...
```
Then re-encrypt: `bash ~/nizam-os/scripts/encrypt-env.sh`

---

## Task 12: Hermes gateway verification

By this point all infrastructure is up. Verify agents respond.

- [ ] **Step 1: Confirm gateways are active**

```bash
systemctl --user is-active hermes-gateway-admin hermes-gateway-curator
```
Expected: both `active`

- [ ] **Step 2: Send a Discord message to Nazim**

In the Discord server, in one of Nazim's allowed channels, @ Nazim and ask a simple question. Expected: response within 30 seconds.

- [ ] **Step 3: Send a Discord message to Noor**

In Noor's allowed channel (set `discord.allowed_channels` in curator config.yaml first if not already set). Expected: response. Vault tool calls will succeed now that the DB schema is set up.

- [ ] **Step 4: Run Nazim's health check**

Ask Nazim to run a health check. He should report service statuses using the procedure in HEARTBEAT.md.

---

## Task 13: Post-rebuild state vs immediate-fixes backlog

After completing Tasks 1–12, the VPS is at foundation state. The following gaps remain intentionally deferred to the immediate-fixes plan:

- Admin SOUL.md / PROTOCOL.md / HEARTBEAT.md still reference "Bani" → fix in `docs/plans/20260701-immediate-fixes.md`
- AGENTS.md missing from all profiles → Phase 0 immediate fixes
- TOOLS.md present in admin + curator → delete (Phase 0)
- `allow_lazy_installs: true` in all profiles → fix (Phase 0)
- Compression model not pinned → fix (Phase 0)
- `DISCORD_ALLOWED_USERS` not set → fix (Phase 0)
- Nazim sudoers entry missing → fix (Phase 0)
- LiteLLM spend tracking: virtual keys created but `DISCORD_ALLOWED_USERS` not yet enforced

Do NOT attempt to fix these during the foundation rebuild — they are a separate scope. Complete the rebuild first, verify done criteria, then work the immediate-fixes plan.

---

## Verification checklist

Run after all tasks complete:

```bash
# System services
systemctl is-active \
  litellm-proxy.service postgresql.service redis-server.service \
  prometheus.service grafana-server.service prometheus-node-exporter.service \
  metrics-llm.timer metrics-services.timer metrics-toolcalls.timer \
  watcher-env.service watcher-inventory.timer \
  fail2ban.service ufw.service

# User services
systemctl --user is-active hermes-profile-watcher.service
systemctl --user is-active hermes-gateway-admin.service hermes-gateway-curator.service

# Endpoints
curl -s http://localhost:4000/health/liveliness   # → "OK" or {"status":"healthy"}
redis-cli ping                                     # → PONG
curl -s http://localhost:3000/api/health           # → {"database":"ok",...}

# Secrets
grep -c "=" ~/nizam-os/secrets/nizam.env          # → 11+ lines

# DB
sudo -u postgres psql nizam -c "\dn"              # → litellm + knowledge schemas
sudo -u postgres psql nizam -c "SELECT tablename FROM pg_tables WHERE schemaname='knowledge';"
# → vault_index, vault_embeddings, vault_audit

# Vault
ls ~/nizam-vault/commons                           # → directory exists

# Metrics
ls -la /var/lib/prometheus/node-exporter/*.prom    # → 3 files, recent timestamps
```

All checks pass → foundation is live.
