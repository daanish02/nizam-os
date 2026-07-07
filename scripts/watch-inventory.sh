#!/usr/bin/env bash
# Detect software inventory changes and notify via Discord webhook.
# Runs hourly via watcher-inventory.timer.
# On first run, writes baseline and exits silently.
# On subsequent runs, diffs against baseline; POSTs diff to webhook if changed.
set -euo pipefail

NIZAM_OS="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_NAME="watch-inventory"
source "$NIZAM_OS/scripts/_log.sh"

BASE="$NIZAM_OS/inventory"
mkdir -p "$BASE"

SOFTWARE="$BASE/software.txt"
SOFTWARE_HASH="$BASE/software.sha256"
DIFF_FILE="$BASE/last.diff"

TMP_SOFTWARE=$(mktemp)
trap 'rm -f "$TMP_SOFTWARE"' EXIT

"$NIZAM_OS/scripts/generate-software-inventory.sh" > "$TMP_SOFTWARE"

SOFTWARE_NEW_HASH=$(sha256sum "$TMP_SOFTWARE" | awk '{print $1}')

if [ ! -f "$SOFTWARE" ]; then
    cp "$TMP_SOFTWARE" "$SOFTWARE"
    echo "$SOFTWARE_NEW_HASH" > "$SOFTWARE_HASH"
    log_info "baseline written"
    exit 0
fi

SOFTWARE_OLD_HASH=$(cat "$SOFTWARE_HASH")

if [ "$SOFTWARE_NEW_HASH" = "$SOFTWARE_OLD_HASH" ]; then
    exit 0
fi

diff -u "$SOFTWARE" "$TMP_SOFTWARE" > "$DIFF_FILE" || true

cp "$TMP_SOFTWARE" "$SOFTWARE"
echo "$SOFTWARE_NEW_HASH" > "$SOFTWARE_HASH"

log_info "software inventory changed"

ENV_FILE="$NIZAM_OS/secrets/nizam-os.env"
if [ -f "$ENV_FILE" ]; then
    # shellcheck source=/dev/null
    set -a; source "$ENV_FILE"; set +a
fi

if [ -n "${DISCORD_WEBHOOK_LOGS:-}" ]; then
    curl -s \
        -F "payload_json={\"content\":\"Software inventory changed on nizam-vps. Diff attached.\"}" \
        -F "file=@${DIFF_FILE};filename=inventory.diff" \
        "$DISCORD_WEBHOOK_LOGS" > /dev/null
fi
