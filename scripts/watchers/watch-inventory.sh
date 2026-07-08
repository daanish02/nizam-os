#!/usr/bin/env bash
# Detect package inventory changes, notify via Discord embed, and commit to git.
# Runs hourly via watcher-inventory.timer.
# On first run, writes baseline and exits silently.
# On subsequent runs, diffs against baseline; posts embed if changed, then commits.
set -euo pipefail

NIZAM_OS="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_NAME="watch-inventory"
source "$NIZAM_OS/scripts/shared/_log.sh"

BASE="$NIZAM_OS/inventory"
mkdir -p "$BASE"

PACKAGES="$BASE/packages.txt"
PACKAGES_HASH="$BASE/packages.sha256"
DIFF_FILE="$BASE/last.diff"

TMP_PACKAGES=$(mktemp)
trap 'rm -f "$TMP_PACKAGES"' EXIT

"$NIZAM_OS/scripts/generate-packages-inventory.sh" > "$TMP_PACKAGES"

PACKAGES_NEW_HASH=$(sha256sum "$TMP_PACKAGES" | awk '{print $1}')

if [ ! -f "$PACKAGES" ]; then
    cp "$TMP_PACKAGES" "$PACKAGES"
    echo "$PACKAGES_NEW_HASH" > "$PACKAGES_HASH"
    log_info "baseline written"
    exit 0
fi

PACKAGES_OLD_HASH=$(cat "$PACKAGES_HASH")

if [ "$PACKAGES_NEW_HASH" = "$PACKAGES_OLD_HASH" ]; then
    exit 0
fi

diff -u "$PACKAGES" "$TMP_PACKAGES" > "$DIFF_FILE" || true

cp "$TMP_PACKAGES" "$PACKAGES"
echo "$PACKAGES_NEW_HASH" > "$PACKAGES_HASH"

log_info "package inventory changed"

ENV_FILE="$NIZAM_OS/secrets/nizam-os.env"
if [ -f "$ENV_FILE" ]; then
    # shellcheck source=/dev/null
    set -a; source "$ENV_FILE"; set +a
fi

# Discord embed — diff as code block with color (```diff renders +/- as green/red)
if [ -n "${DISCORD_WEBHOOK_LOGS:-}" ]; then
    DIFF_CONTENT=$(cat "$DIFF_FILE")
    # Truncate to stay within Discord embed description limit (4096 chars)
    MAX=3800
    if [ "${#DIFF_CONTENT}" -gt "$MAX" ]; then
        DIFF_CONTENT="${DIFF_CONTENT:0:$MAX}"$'\n... (truncated)'
    fi
    # Escape backslashes and double-quotes for JSON
    DIFF_ESCAPED=$(printf '%s' "$DIFF_CONTENT" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk '{printf "%s\\n", $0}')
    curl -sf -X POST "$DISCORD_WEBHOOK_LOGS" \
        -H "Content-Type: application/json" \
        -d "{\"embeds\":[{\"title\":\"Package inventory changed\",\"description\":\"\\`\\`\\`diff\\n${DIFF_ESCAPED}\\`\\`\\`\",\"color\":3447003}]}" \
        > /dev/null || log_warn "Discord notify failed"
fi

# Auto-commit changed packages.txt so git history tracks package drift
cd "$NIZAM_OS"
git add inventory/packages.txt inventory/packages.sha256 2>/dev/null || true
git commit -m "inventory: packages updated $(date +%Y-%m-%d)" 2>/dev/null || true
git push 2>/dev/null || log_warn "git push failed — will retry next run"
