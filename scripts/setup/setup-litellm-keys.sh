#!/usr/bin/env bash
# Creates one LiteLLM virtual key per Hermes profile (user_id = profile name).
# Updates each profile's config.yaml (openrouter → custom:litellm) and .env.
# Idempotent: skips profiles that already have a virtual key in .env.
set -euo pipefail

NIZAM_ENV="/home/vazir/.nizam-os/secrets/nizam.env"
PROFILES_DIR="/home/vazir/.nizam-os/hermes/profiles"
LITELLM_URL="http://localhost:4000"

# shellcheck source=/dev/null
source "$NIZAM_ENV"
MASTER_KEY="${LITELLM_MASTER_KEY:?LITELLM_MASTER_KEY not set in $NIZAM_ENV}"

curl -sf "$LITELLM_URL/health/liveliness" >/dev/null || {
    echo "ERROR: LiteLLM not reachable at $LITELLM_URL" >&2
    exit 1
}

update_config() {
    local config="$1"
    local profile="$2"

    if grep -q "custom:litellm" "$config"; then
        echo "  config.yaml: already updated"
        return 0
    fi

    python3 - "$config" <<'PYEOF'
import sys
import re

path = sys.argv[1]
with open(path) as f:
    content = f.read()

content = re.sub(r'^(  provider:\s*)openrouter', r'\1custom:litellm', content, flags=re.MULTILINE)
content = re.sub(r'^(  base_url:\s*)https://openrouter\.ai/api/v1', r'\1http://localhost:4000', content, flags=re.MULTILINE)
content = re.sub(r'^(  api_mode:\s*)chat_completions\b', r'\1chat/completions', content, flags=re.MULTILINE)

custom_block = (
    "custom_providers:\n"
    "  - name: litellm\n"
    "    base_url: http://localhost:4000\n"
    "    key_env: LITELLM_MASTER_KEY\n"
    "    api_mode: chat/completions"
)
content = re.sub(
    r'^(fallback_providers: \[\])',
    r'\1\n' + custom_block,
    content,
    flags=re.MULTILINE,
)

with open(path, 'w') as f:
    f.write(content)
PYEOF
    echo "  config.yaml: updated (openrouter → custom:litellm)"
}

create_or_get_key() {
    local profile="$1"
    local env_file="$2"

    # If .env already has a key that differs from master key, it's already a virtual key
    existing=$(grep "^LITELLM_MASTER_KEY=" "$env_file" 2>/dev/null | cut -d= -f2- || echo "")
    if [[ -n "$existing" ]] && [[ "$existing" != "$MASTER_KEY" ]]; then
        echo "  key: already set (virtual key in .env, skipping)"
        return 0
    fi

    response=$(curl -sf -X POST "$LITELLM_URL/key/generate" \
        -H "Authorization: Bearer $MASTER_KEY" \
        -H "Content-Type: application/json" \
        -d "{\"user_id\": \"$profile\", \"key_alias\": \"nizam-$profile\", \"duration\": null}" \
        2>&1) || {
        echo "  key: ERROR calling /key/generate: $response" >&2
        return 1
    }

    key=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin)['key'])" 2>/dev/null || echo "")
    if [[ -z "$key" ]]; then
        echo "  key: ERROR parsing response: $response" >&2
        return 1
    fi

    if grep -q "^LITELLM_MASTER_KEY=" "$env_file"; then
        sed -i "s|^LITELLM_MASTER_KEY=.*|LITELLM_MASTER_KEY=$key|" "$env_file"
    else
        echo "LITELLM_MASTER_KEY=$key" >> "$env_file"
    fi
    echo "  key: created and written to .env (user_id=$profile)"
}

for profile_dir in "$PROFILES_DIR"/*/; do
    profile=$(basename "$profile_dir")
    config_file="$profile_dir/config.yaml"
    env_file="$profile_dir/.env"

    echo ""
    echo "=== $profile ==="

    [[ ! -f "$config_file" ]] && { echo "  no config.yaml — skip"; continue; }
    [[ ! -f "$env_file" ]]    && { echo "  no .env — skip"; continue; }

    update_config "$config_file" "$profile"
    create_or_get_key "$profile" "$env_file"
done

echo ""
echo "Done. Restart gateways to pick up changes:"
echo "  systemctl --user restart hermes-gateway-admin hermes-gateway-assistant hermes-gateway-cos hermes-gateway-curator"
