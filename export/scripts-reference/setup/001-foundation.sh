#!/usr/bin/env bash
# Idempotent Phase 1 foundation setup for nizam-os.
# Prerequisite: ~/nizam-dotfiles/scripts/setup/001-machine-setup.sh complete.
#
# Rebuild (reusing encrypted creds):
#   git clone <repo> ~/nizam-os
#   cp <backup>/nizam-age-key.txt ~/nizam-os/secrets/nizam-age-key.txt
#   sudo bash ~/nizam-os/scripts/setup/001-foundation.sh
#
# Fresh (new creds):
#   git clone <repo> ~/nizam-os
#   sudo apt-get install -y age
#   age-keygen -o ~/nizam-os/secrets/nizam-age-key.txt
#   chmod 600 ~/nizam-os/secrets/nizam-age-key.txt
#   cp ~/nizam-os/secrets/nizam-os.env.example ~/nizam-os/secrets/nizam-os.env
#   nano ~/nizam-os/secrets/nizam-os.env   # fill all values
#   sudo bash ~/nizam-os/scripts/setup/001-foundation.sh
set -euo pipefail

# Pinned tool versions — bump here when upgrading
SOPS_VERSION="v3.13.2"
DBMATE_VERSION="v2.33.0"
PGSEARCH_VERSION="v0.24.1"
LITELLM_VERSION="1.91.0"

VAZIR_HOME="/home/vazir"
NIZAM_OS="$VAZIR_HOME/nizam-os"

BLD='\033[1m'
CYN='\033[36m'
GRN='\033[32m'
YLW='\033[33m'
RED='\033[31m'
RST='\033[0m'

_step() { printf "\n${BLD}${CYN}==> %s${RST}\n" "$*"; }
_ok()   { printf "${GRN}  %s${RST}\n" "$*"; }
_note() { printf "${YLW}  %s${RST}\n" "$*"; }
_err()  { printf "${RED}  ERROR: %s${RST}\n" "$*" >&2; }

if [ "$EUID" -ne 0 ]; then
    echo "Run with: sudo bash scripts/setup/001-foundation.sh" >&2
    exit 1
fi

printf "${BLD}${CYN}==> Phase 1 foundation setup${RST}\n"

# Pre-step: cryptography + migration tools (needed before secrets check)
_step "Cryptography and migration tools"
apt-get install -y -q age gettext-base

if ! command -v sops &>/dev/null; then
    curl -fsSL -o /usr/local/bin/sops \
        "https://github.com/getsops/sops/releases/download/${SOPS_VERSION}/sops-${SOPS_VERSION}.linux.amd64"
    chmod +x /usr/local/bin/sops
    _ok "sops ${SOPS_VERSION} installed"
else
    _ok "sops already installed"
fi

if ! command -v dbmate &>/dev/null; then
    curl -fsSL -o /usr/local/bin/dbmate \
        "https://github.com/amacneil/dbmate/releases/download/${DBMATE_VERSION}/dbmate-linux-amd64"
    chmod +x /usr/local/bin/dbmate
    _ok "dbmate ${DBMATE_VERSION} installed"
else
    _ok "dbmate already installed"
fi

_ok "age and gettext-base ready"

# Step 1: Secrets — detect fresh vs rebuild
_step "Secrets"
ENC="$NIZAM_OS/secrets/nizam-os.env.enc"
ENV="$NIZAM_OS/secrets/nizam-os.env"
AGE_KEY="$NIZAM_OS/secrets/nizam-age-key.txt"

if [ -f "$AGE_KEY" ]; then
    chmod 600 "$AGE_KEY"
fi

if [ -f "$ENV" ]; then
    _note "using existing nizam-os.env"
elif [ -f "$ENC" ] && [ -f "$AGE_KEY" ]; then
    _note "no nizam-os.env found — decrypting from nizam-os.env.enc"
    sudo -u vazir bash "$NIZAM_OS/scripts/env/decrypt-env.sh"
else
    _err "no secrets found"
    _err "rebuild: restore nizam-age-key.txt + nizam-os.env.enc, then decrypt manually"
    _err "fresh:   copy nizam-os.env.example → nizam-os.env and fill values"
    exit 1
fi

# Checked here rather than in sub-scripts — sub-scripts fail non-obviously on missing vars
required_vars=(OPENROUTER_API_KEY LITELLM_MASTER_KEY POSTGRES_SVC_LITELLM_PASS LITELLM_DB_URL REDIS_URL REDIS_PASSWORD)
missing=()
for var in "${required_vars[@]}"; do
    val=$(grep "^${var}=" "$ENV" 2>/dev/null | cut -d= -f2- || true)
    [ -z "$val" ] && missing+=("$var")
done

if [ ${#missing[@]} -gt 0 ]; then
    _err "missing values in nizam-os.env: ${missing[*]}"
    _err "fill them in and re-run"
    exit 1
fi

set -a
# shellcheck source=/dev/null
source "$ENV"
set +a
_ok "secrets loaded"

# Step 2: System packages
_step "System packages"
apt-get install -y -q \
    postgresql postgresql-client postgresql-contrib \
    redis-server inotify-tools yq
_ok "done"

# Step 3: pgvector
_step "pgvector"
apt-get install -y -q postgresql-16-pgvector
_ok "done"

# Step 4: ParadeDB (pg_search) — pinned via PGSEARCH_VERSION
_step "ParadeDB pg_search"
if ! dpkg -l postgresql-16-pg-search &>/dev/null; then
    PGSEARCH_DEB="postgresql-16-pg-search_${PGSEARCH_VERSION#v}-1PARADEDB-noble_amd64.deb"
    curl -fsSL -o /tmp/pg-search.deb \
        "https://github.com/paradedb/paradedb/releases/download/${PGSEARCH_VERSION}/${PGSEARCH_DEB}"
    apt-get install -y -q /tmp/pg-search.deb
    rm /tmp/pg-search.deb
    _ok "installed ${PGSEARCH_VERSION}"
else
    _ok "already installed"
fi

# Step 5: Redis
_step "Redis"
systemctl enable redis-server
systemctl stop redis-server 2>/dev/null || true
envsubst '${REDIS_PASSWORD}' < "$NIZAM_OS/config/redis.conf" > /etc/redis/redis.conf
chown redis:redis /etc/redis/redis.conf 2>/dev/null || chown root:root /etc/redis/redis.conf
chmod 640 /etc/redis/redis.conf
systemctl start redis-server
_ok "configured and started"

# Step 6: nizam-os Promtail config
# Loki is managed by nizam-dotfiles (port 3100). This copies the config for a
# separate promtail-nizam-os.service (symlinked in step 11) that scrapes
# ~/nizam-os/logs/ without touching dotfiles promtail.
_step "nizam-os Promtail config"
mkdir -p /etc/promtail
cp "$NIZAM_OS/config/promtail.yaml" /etc/promtail/promtail-nizam-os.yaml
chmod 644 /etc/promtail/promtail-nizam-os.yaml
_ok "config deployed to /etc/promtail/promtail-nizam-os.yaml"

# Step 7: PostgreSQL
_step "PostgreSQL"
systemctl enable postgresql
systemctl start postgresql

# pg_search requires shared_preload_libraries — set before first schema run
PG_CONF="/etc/postgresql/16/main/postgresql.conf"
if ! grep -q "pg_search" "$PG_CONF"; then
    echo "shared_preload_libraries = 'pg_search'" >> "$PG_CONF"
    systemctl restart postgresql
    _note "pg_search added to shared_preload_libraries — restarted"
fi

# Superuser role for vazir (peer auth — no password, for direct psql access)
sudo -u postgres psql -c "DO \$\$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'vazir') THEN
    CREATE USER vazir SUPERUSER;
  END IF;
END \$\$;" > /dev/null
_ok "vazir superuser role ready"

POSTGRES_SVC_LITELLM_PASS="$POSTGRES_SVC_LITELLM_PASS" \
    bash "$NIZAM_OS/scripts/setup/setup-db.sh"
_ok "database ready"

# Step 8: uv + LiteLLM
# Runs after PostgreSQL so prisma db push can connect to svc_litellm/litellm schema
_step "uv + LiteLLM"
if ! sudo -u vazir bash -c 'command -v uv >/dev/null 2>&1'; then
    sudo -u vazir bash -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'
    _ok "uv installed"
else
    _ok "uv already installed"
fi
sudo -u vazir bash -c "PATH=\"\$HOME/.local/bin:\$PATH\" uv tool install --with prisma 'litellm[proxy]==${LITELLM_VERSION}'"
LITELLM_BIN="$VAZIR_HOME/.local/share/uv/tools/litellm/bin"
SCHEMA="$VAZIR_HOME/.local/share/uv/tools/litellm/lib/python3.12/site-packages/litellm/proxy/schema.prisma"
sudo -u vazir bash -c "PATH=\"${LITELLM_BIN}:\$PATH\" DATABASE_URL=\"${LITELLM_DB_URL}\" prisma generate --schema='${SCHEMA}'"
sudo -u vazir bash -c "PATH=\"${LITELLM_BIN}:\$PATH\" DATABASE_URL=\"${LITELLM_DB_URL}\" prisma db push --schema='${SCHEMA}' --accept-data-loss"
_ok "litellm ${LITELLM_VERSION} installed"

# Step 9: Database migrations (dbmate)
_step "Database migrations"
sudo -u vazir bash -c "cd '$NIZAM_OS' && \
    DATABASE_URL='postgresql:///nizam?host=/var/run/postgresql' \
    dbmate --no-dump-schema -d db/migrations up"
_ok "migrations applied"

# Step 10: Prometheus textfile dir
_step "Prometheus textfile directory"
mkdir -p /var/lib/prometheus/node-exporter
chown vazir:vazir /var/lib/prometheus/node-exporter
_ok "done"

# Step 11: Symlinks
_step "Installing symlinks"
bash "$NIZAM_OS/scripts/setup/install-symlinks.sh"

# Enable promtail-nizam-os now that its unit is symlinked
systemctl daemon-reload
systemctl enable --now promtail-nizam-os.service
_ok "promtail-nizam-os started (pushes to dotfiles Loki at :3100)"

# Step 12: Encrypt secrets
_step "Encrypt secrets"
if [ ! -f "$ENC" ]; then
    sudo -u vazir bash "$NIZAM_OS/scripts/env/encrypt-env.sh"
    _ok "nizam-os.env.enc created — commit this file"
else
    _ok "already encrypted"
fi

# Step 13: Phase 1 systemd units
_step "Enabling Phase 1 units"
systemctl enable --now \
    watcher-env.service \
    watcher-inventory.timer \
    metrics-llm.timer \
    metrics-services.timer \
    metrics-toolcalls.timer
systemctl enable litellm-proxy.service
systemctl start litellm-proxy.service
_ok "done"

# Step 14: Wait for LiteLLM
_step "Waiting for LiteLLM (up to 60s)"
for i in $(seq 1 30); do
    if curl -sf http://localhost:4000/health/liveliness >/dev/null 2>&1; then
        _ok "LiteLLM is up"
        break
    fi
    sleep 2
    if [ "$i" -eq 30 ]; then
        _err "LiteLLM did not come up in 60s"
        _err "check: journalctl -u litellm-proxy -n 50"
        exit 1
    fi
done

# Step 15: Confirm Loki reachable (managed by dotfiles)
_step "Confirming Loki reachable (up to 30s)"
for i in $(seq 1 15); do
    if curl -sf http://localhost:3100/ready >/dev/null 2>&1; then
        _ok "Loki is up at :3100"
        break
    fi
    sleep 2
    if [ "$i" -eq 15 ]; then
        _err "Loki not reachable at :3100"
        _err "check: systemctl status loki && journalctl -u loki -n 30"
        exit 1
    fi
done

printf "\n${BLD}${CYN}====================================================================================${RST}\n"
printf "${BLD}${GRN}Phase 1 foundation complete.${RST}\n"
printf "\n${BLD}Manual steps remaining:${RST}\n"
printf "  1. Open Grafana: http://<tailscale-ip>:3000\n"
printf "  2. Connections → Data Sources → Add → Prometheus\n"
printf "       URL: http://localhost:9090  |  UID: nizam-prometheus\n"
printf "  3. Connections → Data Sources → Add → Loki\n"
printf "       URL: http://localhost:3100  |  UID: nizam-loki\n"
printf "  4. Dashboards → Import → grafana/001-personal-dashboard.json\n"
printf "${BLD}${CYN}====================================================================================${RST}\n"
