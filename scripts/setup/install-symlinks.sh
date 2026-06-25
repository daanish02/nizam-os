#!/usr/bin/env bash
# Wire all nizam-os files into system locations via symlinks.
# Run once (or re-run safely — ln -sf overwrites stale links):
#   sudo bash scripts/install-symlinks.sh
set -euo pipefail

NIZAM_OS=/home/vazir/.nizam-os

# ── Systemd units ─────────────────────────────────────────────────────────────
ln -sf "$NIZAM_OS/systemd/litellm-proxy.service"      /etc/systemd/system/litellm-proxy.service
ln -sf "$NIZAM_OS/systemd/metrics-llm.service"        /etc/systemd/system/metrics-llm.service
ln -sf "$NIZAM_OS/systemd/metrics-llm.timer"          /etc/systemd/system/metrics-llm.timer
ln -sf "$NIZAM_OS/systemd/watcher-inventory.service"  /etc/systemd/system/watcher-inventory.service
ln -sf "$NIZAM_OS/systemd/watcher-inventory.timer"    /etc/systemd/system/watcher-inventory.timer
ln -sf "$NIZAM_OS/systemd/watcher-env.service"        /etc/systemd/system/watcher-env.service

systemctl daemon-reload

# ── Hermes SOUL.md files ──────────────────────────────────────────────────────
# Hermes gateway is a user service installed by 'hermes gateway install'.
# The gateway uses ~/.hermes/SOUL.md (root profile) regardless of active_profile.
# admin/SOUL.md is the default agent — symlinked at root so gateway picks it up.
USER_HOME=/home/vazir
ln -sf "$NIZAM_OS/hermes/profiles/admin/SOUL.md" "$USER_HOME/.hermes/SOUL.md"
echo "  linked ~/.hermes/SOUL.md → admin/SOUL.md"

# Named profile SOUL.md files (for hermes -p <name> CLI usage)
for profile_dir in "$NIZAM_OS/hermes/profiles"/*/; do
    name=$(basename "$profile_dir")
    src="$profile_dir/SOUL.md"
    dst="$USER_HOME/.hermes/profiles/$name/SOUL.md"
    if [ ! -f "$src" ]; then continue; fi
    if [ ! -d "$USER_HOME/.hermes/profiles/$name" ]; then
        echo "  Profile $name missing — create with: hermes profile create $name"
        continue
    fi
    ln -sf "$src" "$dst"
    echo "  linked hermes/$name/SOUL.md"
done

echo ""
echo "Systemd symlinks:"
ls -la /etc/systemd/system/litellm-proxy.service \
       /etc/systemd/system/metrics-llm.service \
       /etc/systemd/system/metrics-llm.timer \
       /etc/systemd/system/watcher-inventory.service \
       /etc/systemd/system/watcher-inventory.timer \
       /etc/systemd/system/watcher-env.service

echo ""
echo "Grafana: configure datasource and import dashboard manually."
echo "  Datasource: Prometheus @ http://localhost:9090, uid=nizam-prometheus"
echo "  Dashboard JSON: $NIZAM_OS/grafana/agents-dashboard.json"
