#!/usr/bin/env bash
# Idempotent Phase 2 setup — Hermes baseline (admin).
# Pre-requisite: Phase 1 complete, nizam-os.env with Phase 2 vars populated.
# Run: sudo bash ~/nizam-os/scripts/setup/002-hermes.sh
set -euo pipefail

NIZAM_OS="$(cd "$(dirname "$0")/../.." && pwd)"
NIZAM_ENV="$NIZAM_OS/secrets/nizam-os.env"

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

[[ $EUID -ne 0 ]] && { _err "Run with: sudo bash scripts/setup/002-hermes.sh"; exit 1; }
[[ ! -f "$NIZAM_ENV" ]] && { _err "nizam-os.env not found — complete Phase 1 first"; exit 1; }

set -a; source "$NIZAM_ENV"; set +a

# Step 1: Verify Phase 1 prerequisites
_step "Verifying Phase 1 prerequisites"
curl -sf http://localhost:4000/health/liveliness > /dev/null || {
    _err "LiteLLM not running at :4000 — complete Phase 1 first"; exit 1
}
sudo -u vazir psql -U vazir -d nizam -c "SELECT 1" > /dev/null 2>&1 || {
    _err "PostgreSQL nizam DB not reachable — complete Phase 1 first"; exit 1
}
_ok "Phase 1 prerequisites satisfied"

# Step 2: Validate Discord env vars
_step "Validating Phase 2 env vars"
: "${DISCORD_GUILD_ID:?DISCORD_GUILD_ID missing}"
: "${DISCORD_OWNER_ID:?DISCORD_OWNER_ID missing}"
: "${DISCORD_TOKEN_ADMIN:?DISCORD_TOKEN_ADMIN missing}"
: "${DISCORD_CHANNEL_ALERTS:?DISCORD_CHANNEL_ALERTS missing}"
: "${DISCORD_CHANNEL_LOGS:?DISCORD_CHANNEL_LOGS missing}"
: "${DISCORD_CHANNEL_ADMIN:?DISCORD_CHANNEL_ADMIN missing}"
: "${DISCORD_CHANNEL_SANDBOX:?DISCORD_CHANNEL_SANDBOX missing}"
_ok "all Phase env vars present"

# Step 3: Check Hermes installation
_step "Checking Hermes installation"
HERMES_BIN="$(sudo -u vazir bash -c 'command -v hermes || echo ""')"
[[ -z "$HERMES_BIN" ]] && HERMES_BIN="/home/vazir/.local/bin/hermes"
if [[ ! -x "$HERMES_BIN" ]]; then
    _err "hermes binary not found — install Hermes first, then re-run"
    _note "See: docs/guides/002-hermes-baseline-guide.md → Step 3"
    exit 1
fi
_ok "hermes installed: $(sudo -u vazir "$HERMES_BIN" --version 2>&1 | head -1)"

# Step 4: Check admin profile + wire symlinks
_step "Checking admin profile and wiring symlinks"
ADMIN_PROFILE_DIR="$(sudo -u vazir bash -c 'echo $HOME')/.hermes/profiles/admin"
if [[ ! -d "$ADMIN_PROFILE_DIR" ]]; then
    _err "admin profile not found — complete admin profile setup first, then re-run"
    _note "See: docs/guides/002-hermes-baseline-guide.md → Step 5"
    exit 1
fi
bash "$NIZAM_OS/scripts/setup/install-symlinks.sh"
loginctl enable-linger vazir 2>/dev/null || true
_ok "symlinks wired, linger enabled for vazir"

# Step 5: Configure admin profile config
_step "Patching admin profile config"
CONFIG="$NIZAM_OS/config/hermes-admin-config.yaml"
ADMIN_ENV="$NIZAM_OS/secrets/hermes-admin.env"

if [[ ! -f "$CONFIG" ]]; then
    _err "hermes-admin-config.yaml not found — re-run install-symlinks.sh after completing admin profile setup"
    exit 1
fi

# Seed hermes-admin.env with placeholder keys (idempotent)
touch "$ADMIN_ENV"
chown vazir:vazir "$ADMIN_ENV"
chmod 600 "$ADMIN_ENV"
_add_env_key() {
    local key="$1"
    grep -q "^${key}=" "$ADMIN_ENV" 2>/dev/null || echo "${key}=" >> "$ADMIN_ENV"
}
_add_env_key "DISCORD_ALLOWED_USERS"
_add_env_key "LITELLM_VIRTUAL_KEY_ADMIN"
# Values known from nizam-os.env — write directly (idempotent update)
_set_env_key() {
    local key="$1" val="$2"
    if grep -q "^${key}=" "$ADMIN_ENV" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${val}|" "$ADMIN_ENV"
    else
        echo "${key}=${val}" >> "$ADMIN_ENV"
    fi
}
_set_env_key "DISCORD_BOT_TOKEN"       "$DISCORD_TOKEN_ADMIN"
_set_env_key "DISCORD_CHANNEL_ALERTS"  "$DISCORD_CHANNEL_ALERTS"
_set_env_key "DISCORD_CHANNEL_LOGS"    "$DISCORD_CHANNEL_LOGS"
_set_env_key "DISCORD_CHANNEL_ADMIN"   "$DISCORD_CHANNEL_ADMIN"
_set_env_key "DISCORD_CHANNEL_SANDBOX" "$DISCORD_CHANNEL_SANDBOX"
_ok "hermes-admin.env: keys present"

# model: api_key from env var
sudo -u vazir yq -yi '.model.api_key = "${LITELLM_VIRTUAL_KEY_ADMIN}"' "$CONFIG"

# stt: disable
sudo -u vazir yq -yi '.stt.enabled = false' "$CONFIG"

# memory: disable write
sudo -u vazir yq -yi '.memory.memory_enabled = false' "$CONFIG"
sudo -u vazir yq -yi '.memory.user_profile_enabled = false' "$CONFIG"

# security block
sudo -u vazir yq -yi '.security.tirith_enabled = true' "$CONFIG"
sudo -u vazir yq -yi '.security.tirith_path = "tirith"' "$CONFIG"
sudo -u vazir yq -yi '.security.tirith_timeout = 5' "$CONFIG"
sudo -u vazir yq -yi '.security.tirith_fail_open = true' "$CONFIG"
sudo -u vazir yq -yi '.security.redact_secrets = true' "$CONFIG"
sudo -u vazir yq -yi '.security.allow_lazy_installs = false' "$CONFIG"

# discord block
sudo -u vazir yq -yi '.discord.require_mention = false' "$CONFIG"
sudo -u vazir yq -yi '.discord.allowed_channels = ["${DISCORD_CHANNEL_ALERTS}", "${DISCORD_CHANNEL_LOGS}", "${DISCORD_CHANNEL_ADMIN}", "${DISCORD_CHANNEL_SANDBOX}"]' "$CONFIG"
sudo -u vazir yq -yi '.discord.auto_thread = true' "$CONFIG"
sudo -u vazir yq -yi '.discord.history_backfill = true' "$CONFIG"
sudo -u vazir yq -yi '.discord.history_backfill_limit = 50' "$CONFIG"
sudo -u vazir yq -yi '.discord.reactions = true' "$CONFIG"

# approvals block
sudo -u vazir yq -yi '.approvals.mode = "manual"' "$CONFIG"
sudo -u vazir yq -yi '.approvals.cron_mode = "manual"' "$CONFIG"

# command_allowlist
sudo -u vazir yq -yi '
  .command_allowlist = [
    "systemctl restart litellm-proxy",
    "systemctl start litellm-proxy",
    "systemctl restart watcher-env",
    "systemctl start watcher-env",
    "systemctl restart watcher-inventory.timer",
    "systemctl start watcher-inventory.timer",
    "systemctl restart metrics-llm.timer",
    "systemctl start metrics-llm.timer",
    "systemctl restart metrics-services.timer",
    "systemctl start metrics-services.timer",
    "systemctl restart metrics-toolcalls.timer",
    "systemctl start metrics-toolcalls.timer",
    "systemctl restart loki",
    "systemctl start loki",
    "systemctl restart promtail",
    "systemctl start promtail",
    "systemctl restart prometheus",
    "systemctl start prometheus",
    "systemctl restart prometheus-node-exporter",
    "systemctl start prometheus-node-exporter",
    "systemctl restart grafana-server",
    "systemctl start grafana-server",
    "systemctl restart postgresql",
    "systemctl start postgresql",
    "systemctl restart redis-server",
    "systemctl start redis-server"
  ]
' "$CONFIG"

_ok "hermes-admin-config.yaml patched"

# Step 6: Sudoers for admin
_step "Writing sudoers rule for admin"
cat > /etc/sudoers.d/admin-nizam <<'SUDOERS'
# admin (Hermes admin agent) — passwordless systemctl restart/start for defined services
# Generated by scripts/setup/002-hermes.sh. Edit source, not this file.
Cmnd_Alias NIZAM_SERVICES = \
    /usr/bin/systemctl restart litellm-proxy, /usr/bin/systemctl start litellm-proxy, \
    /usr/bin/systemctl restart watcher-env, /usr/bin/systemctl start watcher-env, \
    /usr/bin/systemctl restart watcher-inventory.timer, /usr/bin/systemctl start watcher-inventory.timer, \
    /usr/bin/systemctl restart metrics-llm.timer, /usr/bin/systemctl start metrics-llm.timer, \
    /usr/bin/systemctl restart metrics-services.timer, /usr/bin/systemctl start metrics-services.timer, \
    /usr/bin/systemctl restart metrics-toolcalls.timer, /usr/bin/systemctl start metrics-toolcalls.timer, \
    /usr/bin/systemctl restart loki, /usr/bin/systemctl start loki, \
    /usr/bin/systemctl restart promtail, /usr/bin/systemctl start promtail, \
    /usr/bin/systemctl restart prometheus, /usr/bin/systemctl start prometheus, \
    /usr/bin/systemctl restart prometheus-node-exporter, /usr/bin/systemctl start prometheus-node-exporter, \
    /usr/bin/systemctl restart grafana-server, /usr/bin/systemctl start grafana-server, \
    /usr/bin/systemctl restart postgresql, /usr/bin/systemctl start postgresql, \
    /usr/bin/systemctl restart redis-server, /usr/bin/systemctl start redis-server
vazir ALL=(ALL) NOPASSWD: NIZAM_SERVICES
SUDOERS
chmod 440 /etc/sudoers.d/admin-nizam
visudo -c -f /etc/sudoers.d/admin-nizam > /dev/null
_ok "sudoers: /etc/sudoers.d/admin-nizam"

# Step 7: Install and start admin gateway
_step "Enabling Hermes gateway for admin"
RUNTIME_DIR="/run/user/$(id -u vazir)"
if sudo -u vazir XDG_RUNTIME_DIR="$RUNTIME_DIR" systemctl --user is-active hermes-gateway-admin.service &>/dev/null; then
    _ok "hermes-gateway-admin: already running"
else
    sudo -u vazir XDG_RUNTIME_DIR="$RUNTIME_DIR" \
        "$HERMES_BIN" -p admin gateway install --start-now --start-on-login
    _ok "hermes-gateway-admin: installed and started"
fi

# Done
printf "\n${BLD}${CYN}=================================================================${RST}\n"
printf "${BLD}${GRN}002-hermes.sh complete.${RST}\n"
printf "\n${BLD}Manual verification:${RST}\n"
printf "  1. Open Discord — admin shows green presence in server members\n"
printf "  2. Send a message in #admin — admin responds\n"
printf "  3. Check logs: journalctl --user -u hermes-gateway-admin -f\n"
printf "  4. See exit criteria: docs/guides/002-hermes-baseline-guide.md\n"
printf "${BLD}${CYN}=================================================================${RST}\n"
