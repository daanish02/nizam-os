#!/usr/bin/env bash
# Wire all nizam-os files into system locations via symlinks.
# Run once (or re-run safely — ln -sf overwrites stale links):
#   sudo bash scripts/setup/install-symlinks.sh
set -euo pipefail

NIZAM_OS="$(cd "$(dirname "$0")/../.." && pwd)"
USER_HOME="$HOME"

# Systemd system units (require sudo) 
ln -sf "$NIZAM_OS/systemd/litellm-proxy.service"      /etc/systemd/system/litellm-proxy.service
ln -sf "$NIZAM_OS/systemd/metrics-llm.service"        /etc/systemd/system/metrics-llm.service
ln -sf "$NIZAM_OS/systemd/metrics-llm.timer"          /etc/systemd/system/metrics-llm.timer
ln -sf "$NIZAM_OS/systemd/watcher-inventory.service"  /etc/systemd/system/watcher-inventory.service
ln -sf "$NIZAM_OS/systemd/watcher-inventory.timer"    /etc/systemd/system/watcher-inventory.timer
ln -sf "$NIZAM_OS/systemd/watcher-env.service"        /etc/systemd/system/watcher-env.service
ln -sf "$NIZAM_OS/systemd/metrics-services.service"    /etc/systemd/system/metrics-services.service
ln -sf "$NIZAM_OS/systemd/metrics-services.timer"     /etc/systemd/system/metrics-services.timer
ln -sf "$NIZAM_OS/systemd/metrics-toolcalls.service"    /etc/systemd/system/metrics-toolcalls.service
ln -sf "$NIZAM_OS/systemd/metrics-toolcalls.timer"     /etc/systemd/system/metrics-toolcalls.timer
ln -sf "$NIZAM_OS/systemd/promtail-nizam-os.service"   /etc/systemd/system/promtail-nizam-os.service
# logrotate rejects config files not owned by root — symlinks to user-owned files are refused.
# This is the only file in nizam-os that is COPIED not symlinked.
# After editing config/logrotate.nizam-os, re-run this script to push the change.
cp "$NIZAM_OS/config/logrotate.nizam-os" /etc/logrotate.d/nizam-os
chown root:root /etc/logrotate.d/nizam-os
chmod 644 /etc/logrotate.d/nizam-os

systemctl daemon-reload
echo "  reloaded system daemon"

# Hermes user units and profile symlinks are Phase 2 — not wired here.

echo ""
echo "Systemd symlinks:"
ls -la /etc/systemd/system/litellm-proxy.service \
       /etc/systemd/system/metrics-llm.service \
       /etc/systemd/system/metrics-llm.timer \
       /etc/systemd/system/metrics-services.service \
       /etc/systemd/system/metrics-services.timer \
       /etc/systemd/system/watcher-inventory.service \
       /etc/systemd/system/watcher-inventory.timer \
       /etc/systemd/system/watcher-env.service \
       /etc/systemd/system/metrics-toolcalls.service \
       /etc/systemd/system/metrics-toolcalls.timer

echo ""
echo "Grafana: configure datasources and import dashboard manually."
echo "  Prometheus @ http://localhost:9090, uid=nizam-prometheus"
echo "  Loki       @ http://localhost:3100, uid=nizam-loki"
echo "  Dashboard JSON: $NIZAM_OS/grafana/001-personal-dashboard.json"
