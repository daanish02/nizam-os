#!/usr/bin/env bash
set -euo pipefail

BASE="$HOME/.nizam-os/inventory"

mkdir -p "$BASE"

SOFTWARE="$BASE/software.txt"
SERVICES="$BASE/services.txt"

SOFTWARE_HASH="$BASE/software.sha256"
SERVICES_HASH="$BASE/services.sha256"

DIFF_FILE="$BASE/last.diff"

TMP_SOFTWARE=$(mktemp)
TMP_SERVICES=$(mktemp)

"$HOME/.nizam-os/scripts/generate-software-inventory.sh" > "$TMP_SOFTWARE"
"$HOME/.nizam-os/scripts/generate-services-inventory.sh" > "$TMP_SERVICES"

SOFTWARE_NEW_HASH=$(sha256sum "$TMP_SOFTWARE" | awk '{print $1}')
SERVICES_NEW_HASH=$(sha256sum "$TMP_SERVICES" | awk '{print $1}')

# First run
if [ ! -f "$SOFTWARE" ]; then
    mv "$TMP_SOFTWARE" "$SOFTWARE"
    mv "$TMP_SERVICES" "$SERVICES"

    echo "$SOFTWARE_NEW_HASH" > "$SOFTWARE_HASH"
    echo "$SERVICES_NEW_HASH" > "$SERVICES_HASH"

    exit 0
fi

SOFTWARE_OLD_HASH=$(cat "$SOFTWARE_HASH")
SERVICES_OLD_HASH=$(cat "$SERVICES_HASH")

if [ "$SOFTWARE_NEW_HASH" = "$SOFTWARE_OLD_HASH" ] &&
   [ "$SERVICES_NEW_HASH" = "$SERVICES_OLD_HASH" ]; then

    rm "$TMP_SOFTWARE"
    rm "$TMP_SERVICES"
    exit 0
fi

{
    echo "=== SOFTWARE CHANGES ==="
    diff -u "$SOFTWARE" "$TMP_SOFTWARE" || true

    echo
    echo "=== SERVICE CHANGES ==="
    diff -u "$SERVICES" "$TMP_SERVICES" || true
} > "$DIFF_FILE"

mv "$TMP_SOFTWARE" "$SOFTWARE"
mv "$TMP_SERVICES" "$SERVICES"

echo "$SOFTWARE_NEW_HASH" > "$SOFTWARE_HASH"
echo "$SERVICES_NEW_HASH" > "$SERVICES_HASH"

echo "Inventory changed"

ENV_FILE="$HOME/.nizam-dotfiles/secrets/nizam.env"
if [ -f "$ENV_FILE" ]; then
    # shellcheck source=/dev/null
    source "$ENV_FILE"
fi

if [ -n "${NIZAM_INVENTORY_WATCHER:-}" ]; then
    curl -s \
        -F "payload_json={\"content\":\"Hey, something changed in your system inventory. Diff attached for context.\"}" \
        -F "file=@${DIFF_FILE};filename=inventory.diff" \
        "$NIZAM_INVENTORY_WATCHER" > /dev/null
fi
