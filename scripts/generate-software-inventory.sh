#!/usr/bin/env bash
# Enumerate installed apt packages and local binaries to stdout.
# Called by watch-inventory.sh — output is piped to inventory/software.txt.
set -euo pipefail

echo "=== APT PACKAGES ==="

apt-mark showmanual | while read -r pkg; do
    dpkg-query -W -f='${Package} | ${Version}\n' "$pkg" 2>/dev/null
done | sort

echo
echo "=== LOCAL BINARIES ==="

find /usr/local/bin -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | sort

if [ -d "$HOME/.local/bin" ]; then
    find "$HOME/.local/bin" -maxdepth 1 -type f -printf '%f\n' | sort
fi
