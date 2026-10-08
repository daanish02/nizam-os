#!/usr/bin/env bash
# Idempotent Phase 4 setup — Noor (knowledge curator).
# Pre-requisite: Phase 3 complete, nizam-os.env with Phase 4 vars populated.
# Run: sudo bash ~/nizam-os/scripts/setup/003-curator.sh
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

[[ $EUID -ne 0 ]] && { _err "Run with: sudo bash scripts/setup/003-curator.sh"; exit 1; }
[[ ! -f "$NIZAM_ENV" ]] && { _err "nizam-os.env not found — complete Phase 1 first"; exit 1; }

set -a; source "$NIZAM_ENV"; set +a

# ---------------------------------------------------------------------------
# Step 1: Verify Phase 3 prerequisites
# ---------------------------------------------------------------------------
_step "Verifying Phase 3 prerequisites"

curl -sf http://localhost:4000/health/liveliness > /dev/null || {
    _err "LiteLLM not running at :4000 — complete Phase 1 first"; exit 1
}

sudo -u vazir psql -U vazir -d nizam -c "SELECT 1 FROM knowledge.vault_index LIMIT 1" > /dev/null 2>&1 || {
    _err "knowledge schema not found — run dbmate migration 002_knowledge_schema.sql first"; exit 1
}

if ! sudo -u vazir XDG_RUNTIME_DIR="/run/user/$(id -u vazir)" \
        systemctl --user is-active hermes-gateway-admin.service &>/dev/null; then
    _err "hermes-gateway-admin not running — complete Phase 3 first"; exit 1
fi

_ok "Phase 3 prerequisites satisfied"

# ---------------------------------------------------------------------------
# Step 2: Validate env vars
# ---------------------------------------------------------------------------
_step "Validating Phase 4 env vars"
: "${DISCORD_TOKEN_CURATOR:?DISCORD_TOKEN_CURATOR missing from nizam-os.env}"
: "${DISCORD_CHANNEL_LEARNING:?DISCORD_CHANNEL_LEARNING missing from nizam-os.env}"
: "${POSTGRES_SVC_KNOWLEDGE_PASS:?POSTGRES_SVC_KNOWLEDGE_PASS missing from nizam-os.env}"
: "${DISCORD_OWNER_ID:?DISCORD_OWNER_ID missing from nizam-os.env}"
_ok "all Phase 4 env vars present"

# ---------------------------------------------------------------------------
# Step 3: Set svc_knowledge DB password
# ---------------------------------------------------------------------------
_step "Configuring svc_knowledge DB role"
sudo -u vazir psql -U vazir -d nizam -c \
    "ALTER ROLE svc_knowledge PASSWORD '$POSTGRES_SVC_KNOWLEDGE_PASS';" > /dev/null
_ok "svc_knowledge password set"

# ---------------------------------------------------------------------------
# Step 4: Create vault commons directory
# ---------------------------------------------------------------------------
_step "Creating vault commons directory"
COMMONS_DIR="/home/vazir/nizam-vault/commons"
if [[ ! -d "$COMMONS_DIR" ]]; then
    sudo -u vazir mkdir -p "$COMMONS_DIR"
    _ok "created: $COMMONS_DIR"
else
    _ok "already exists: $COMMONS_DIR"
fi

# ---------------------------------------------------------------------------
# Step 5: Check Hermes installation
# ---------------------------------------------------------------------------
_step "Checking Hermes installation"
HERMES_BIN="$(sudo -u vazir bash -c 'command -v hermes || echo ""')"
[[ -z "$HERMES_BIN" ]] && HERMES_BIN="/home/vazir/.local/bin/hermes"
if [[ ! -x "$HERMES_BIN" ]]; then
    _err "hermes binary not found"; exit 1
fi
_ok "hermes: $(sudo -u vazir "$HERMES_BIN" --version 2>&1 | head -1)"

# ---------------------------------------------------------------------------
# Step 6: Install uv dependencies for knowledge-service
# ---------------------------------------------------------------------------
_step "Installing knowledge-service dependencies"
sudo -u vazir bash -c "cd '$NIZAM_OS' && /home/vazir/.local/bin/uv sync --package knowledge-service"
_ok "knowledge-service deps installed"

# ---------------------------------------------------------------------------
# Step 7: Wire curator profile symlinks
# ---------------------------------------------------------------------------
_step "Wiring curator profile symlinks"

CURATOR_HERMES="$(sudo -u vazir bash -c 'echo $HOME')/.hermes/profiles/curator"
CURATOR_NIZAM="$NIZAM_OS/hermes/profiles/curator"

if [[ ! -d "$CURATOR_HERMES" ]]; then
    _err "curator profile not found in ~/.hermes/profiles/ — run: hermes profile create curator first"; exit 1
fi

mkdir -p "$CURATOR_NIZAM/memories" "$CURATOR_NIZAM/skills" "$CURATOR_NIZAM/pending"
chown -R vazir:vazir "$CURATOR_NIZAM"

# Seed: copy hermes-generated files into nizam-os if not already there
_seed() {
    local src="$1" dst="$2"
    [[ -L "$src" ]] && return
    [[ -e "$dst" ]] && return
    [[ -e "$src" ]] || return
    cp -a "$src" "$dst"
    chown -R vazir:vazir "$dst"
    echo "  seeded: $dst"
}

_seed "$CURATOR_HERMES/config.yaml" "$NIZAM_OS/config/hermes-curator-config.yaml"

# Merge memories/skills/pending from hermes into nizam-os then symlink
for dir in memories skills pending; do
    hs="$CURATOR_HERMES/$dir"
    ns="$CURATOR_NIZAM/$dir"
    if [[ ! -L "$hs" ]] && [[ -d "$hs" ]]; then
        if [[ "$(ls -A "$hs" 2>/dev/null)" ]]; then
            rsync -a --no-links "$hs/" "$ns/"
            chown -R vazir:vazir "$ns/"
        fi
        rm -rf "$hs"
        echo "  merged $dir → nizam-os"
    fi
    sudo -u vazir ln -sf "$ns" "$hs"
    _ok "$dir: symlinked"
done

# Symlink root profile files
sudo -u vazir ln -sf "$CURATOR_NIZAM/SOUL.md"                      "$CURATOR_HERMES/SOUL.md"
sudo -u vazir ln -sf "$CURATOR_NIZAM/AGENTS.md"                    "$CURATOR_HERMES/AGENTS.md"
sudo -u vazir ln -sf "$NIZAM_OS/secrets/hermes-curator.env"        "$CURATOR_HERMES/.env"
sudo -u vazir ln -sf "$NIZAM_OS/config/hermes-curator-config.yaml" "$CURATOR_HERMES/config.yaml"
_ok "root profile files symlinked"

# ---------------------------------------------------------------------------
# Step 8: Populate hermes-curator.env
# ---------------------------------------------------------------------------
_step "Populating hermes-curator.env"
CURATOR_ENV="$NIZAM_OS/secrets/hermes-curator.env"

POSTGRES_DSN_CURATOR="postgresql://svc_knowledge:${POSTGRES_SVC_KNOWLEDGE_PASS}@127.0.0.1:5432/nizam"
REDIS_URL="${REDIS_URL:-redis://127.0.0.1:6379/0}"
LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY:-}"

_set_env_key() {
    local key="$1" val="$2"
    if ! grep -q "^${key}=" "$CURATOR_ENV" 2>/dev/null || grep -q "^${key}=$" "$CURATOR_ENV"; then
        sed -i "/^${key}=/d" "$CURATOR_ENV"
        echo "${key}=${val}" >> "$CURATOR_ENV"
    fi
}

_set_env_key "DISCORD_BOT_TOKEN"        "$DISCORD_TOKEN_CURATOR"
_set_env_key "DISCORD_ALLOWED_USERS"    "$DISCORD_OWNER_ID"
_set_env_key "DISCORD_CHANNEL_LEARNING" "$DISCORD_CHANNEL_LEARNING"
_set_env_key "LITELLM_MASTER_KEY"       "$LITELLM_MASTER_KEY"
_set_env_key "POSTGRES_DSN"             "$POSTGRES_DSN_CURATOR"
_set_env_key "REDIS_URL"                "$REDIS_URL"
_set_env_key "VAULT_ROOT"               "/home/vazir/nizam-vault"

_ok "hermes-curator.env populated"

# ---------------------------------------------------------------------------
# Step 9: Patch curator config via yq
# ---------------------------------------------------------------------------
_step "Patching hermes-curator-config.yaml"
CONFIG="$NIZAM_OS/config/hermes-curator-config.yaml"

sudo -u vazir yq -yi '.model.api_key = "${LITELLM_VIRTUAL_KEY_CURATOR}"'  "$CONFIG"
sudo -u vazir yq -yi '.stt.enabled = false'                                "$CONFIG"
sudo -u vazir yq -yi '.memory.memory_enabled = true'                       "$CONFIG"
sudo -u vazir yq -yi '.memory.user_profile_enabled = true'                 "$CONFIG"
sudo -u vazir yq -yi '.memory.write_approval = true'                       "$CONFIG"
sudo -u vazir yq -yi '.memory.memory_char_limit = 2200'                    "$CONFIG"
sudo -u vazir yq -yi '.memory.user_char_limit = 1375'                      "$CONFIG"
sudo -u vazir yq -yi '.compression.enabled = true'                         "$CONFIG"
sudo -u vazir yq -yi '.compression.threshold = 0.6'                        "$CONFIG"
sudo -u vazir yq -yi '.compression.target_ratio = 0.3'                     "$CONFIG"
sudo -u vazir yq -yi '.compression.protect_last_n = 10'                    "$CONFIG"
sudo -u vazir yq -yi '.compression.hygiene_hard_message_limit = 5000'      "$CONFIG"
sudo -u vazir yq -yi '.compression.protect_first_n = 3'                    "$CONFIG"
sudo -u vazir yq -yi '.compression.abort_on_summary_failure = true'        "$CONFIG"
sudo -u vazir yq -yi '.compression.in_place = false'                       "$CONFIG"
sudo -u vazir yq -yi '.context.engine = "compressor"'                      "$CONFIG"
sudo -u vazir yq -yi '.security.tirith_enabled = true'                     "$CONFIG"
sudo -u vazir yq -yi '.security.tirith_path = "tirith"'                    "$CONFIG"
sudo -u vazir yq -yi '.security.tirith_timeout = 5'                        "$CONFIG"
sudo -u vazir yq -yi '.security.tirith_fail_open = true'                   "$CONFIG"
sudo -u vazir yq -yi '.security.redact_secrets = true'                     "$CONFIG"
sudo -u vazir yq -yi '.security.allow_lazy_installs = false'               "$CONFIG"
sudo -u vazir yq -yi ".discord.allowed_channels = [$DISCORD_CHANNEL_LEARNING]" "$CONFIG"
sudo -u vazir yq -yi '.discord.require_mention = false'                    "$CONFIG"
sudo -u vazir yq -yi '.discord.auto_thread = true'                         "$CONFIG"
sudo -u vazir yq -yi '.discord.history_backfill = true'                    "$CONFIG"
sudo -u vazir yq -yi '.discord.history_backfill_limit = 50'                "$CONFIG"
sudo -u vazir yq -yi '.discord.reactions = true'                           "$CONFIG"
sudo -u vazir yq -yi '.approvals.mode = "manual"'                          "$CONFIG"
sudo -u vazir yq -yi '.approvals.cron_mode = "deny"'                       "$CONFIG"
sudo -u vazir yq -yi '.goals.max_turns = 20'                               "$CONFIG"
sudo -u vazir yq -yi '.session_reset.mode = "none"'                        "$CONFIG"
sudo -u vazir yq -yi '.prompt_caching.cache_ttl = "5m"'                    "$CONFIG"

# Disabled toolsets — curator has file + memory, no terminal
sudo -u vazir yq -yi '
  .agent.disabled_toolsets = [
    "browser",
    "clarify",
    "code_execution",
    "computer_use",
    "context_engine",
    "cronjob",
    "delegation",
    "discord",
    "discord_admin",
    "feishu_doc",
    "feishu_drive",
    "homeassistant",
    "image_gen",
    "kanban",
    "project",
    "search",
    "session_search",
    "skills",
    "spotify",
    "terminal",
    "todo",
    "tts",
    "video",
    "video_gen",
    "vision",
    "web",
    "x_search",
    "yuanbao"
  ]
' "$CONFIG"

sudo -u vazir yq -yi '.platform_toolsets.cli = ["file", "memory"]' "$CONFIG"

_ok "hermes-curator-config.yaml patched"

# ---------------------------------------------------------------------------
# Step 10: Wire knowledge-service as MCP stdio server
# ---------------------------------------------------------------------------
_step "Wiring knowledge-service MCP (stdio)"

UV_BIN="/home/vazir/.local/bin/uv"
KS_CMD="$UV_BIN"
KS_ARGS="run --directory $NIZAM_OS python services/knowledge-service/server.py"

RUNTIME_DIR="/run/user/$(id -u vazir)"
POSTGRES_DSN_CURATOR="postgresql://svc_knowledge:${POSTGRES_SVC_KNOWLEDGE_PASS}@127.0.0.1:5432/nizam"
REDIS_URL="${REDIS_URL:-redis://127.0.0.1:6379/0}"

# Add or re-wire — always patch env block in config so secrets stay current
if ! sudo -u vazir XDG_RUNTIME_DIR="$RUNTIME_DIR" \
        "$HERMES_BIN" -p curator mcp list 2>/dev/null | grep -q "knowledge-service"; then
    sudo -u vazir XDG_RUNTIME_DIR="$RUNTIME_DIR" \
        "$HERMES_BIN" -p curator mcp add knowledge-service \
            --command "$KS_CMD" \
            --args $KS_ARGS
    _ok "knowledge-service MCP added"
else
    _ok "knowledge-service MCP already present — updating env"
fi

# Inject env vars and enable — yq patches the config directly
SUPADATA_API_KEY="${SUPADATA_API_KEY:-}"

sudo -u vazir yq -yi "
  .mcp_servers[\"knowledge-service\"].env = {
    \"POSTGRES_DSN\": \"$POSTGRES_DSN_CURATOR\",
    \"REDIS_URL\": \"$REDIS_URL\",
    \"LITELLM_MASTER_KEY\": \"$LITELLM_MASTER_KEY\",
    \"VAULT_ROOT\": \"/home/vazir/nizam-vault\",
    \"SUPADATA_API_KEY\": \"$SUPADATA_API_KEY\"
  } |
  .mcp_servers[\"knowledge-service\"].enabled = true
" "$CONFIG"
_ok "knowledge-service MCP env wired and enabled"

# ---------------------------------------------------------------------------
# Step 11: Install and start curator gateway
# ---------------------------------------------------------------------------
_step "Enabling Hermes gateway for curator"
RUNTIME_DIR="/run/user/$(id -u vazir)"

if sudo -u vazir XDG_RUNTIME_DIR="$RUNTIME_DIR" \
        systemctl --user is-active hermes-gateway-curator.service &>/dev/null; then
    _ok "hermes-gateway-curator: already running"
else
    sudo -u vazir XDG_RUNTIME_DIR="$RUNTIME_DIR" \
        "$HERMES_BIN" -p curator gateway install --start-now --start-on-login
    _ok "hermes-gateway-curator: installed and started"
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
printf "\n${BLD}${CYN}=================================================================${RST}\n"
printf "${BLD}${GRN}003-curator.sh complete.${RST}\n"
printf "\n${BLD}Manual verification:${RST}\n"
printf "  1. Open Discord — Noor shows green presence in server members\n"
printf "  2. Send a message in #learning — Noor responds\n"
printf "  3. Test ingestion: paste a URL into #learning\n"
printf "  4. Confirm draft appears, approve, verify note in ~/nizam-vault/commons/\n"
printf "  5. Check logs: journalctl --user -u hermes-gateway-curator -f\n"
printf "${BLD}${CYN}=================================================================${RST}\n"
