#!/usr/bin/env bash
# Enumerate tracked service statuses to stdout (one line per service).
# Called by watch-inventory.sh — output is piped to inventory/services.txt.
set -euo pipefail

export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

TRACKED="$HOME/.nizam-os/inventory/tracked-services.txt"

[ -f "$TRACKED" ] || {
    echo "Missing tracked-services.txt" >&2
    exit 1
}

service_status() {
    local svc="$1"
    local status

    if systemctl --user list-unit-files "$svc" --no-legend 2>/dev/null | grep -q "^$svc"; then
        status=$(systemctl --user is-active "$svc" 2>/dev/null || true)
        printf '%s | user | %s\n' \
            "$svc" \
            "${status:-inactive}"

    elif systemctl list-unit-files "$svc" --no-legend 2>/dev/null | grep -q "^$svc"; then
        status=$(systemctl is-active "$svc" 2>/dev/null || true)
        printf '%s | system | %s\n' \
            "$svc" \
            "${status:-inactive}"

    else
        printf '%s | - | not-found\n' "$svc"
    fi
}

grep -vE '^\s*#|^\s*$' "$TRACKED" |
while read -r svc; do
    service_status "$svc"
done | sort
