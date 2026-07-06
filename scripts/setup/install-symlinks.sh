#!/usr/bin/env bash
# Wire all nizam-os files into system locations via symlinks.
# Run once (or re-run safely — ln -sf overwrites stale links):
#   sudo bash scripts/setup/install-symlinks.sh
set -euo pipefail

NIZAM_OS="$(cd "$(dirname "$0")/../.." && pwd)"
USER_HOME="$HOME"

# ── Systemd system units (require sudo) ───────────────────────────────────────
ln -sf "$NIZAM_OS/systemd/litellm-proxy.service"      /etc/systemd/system/litellm-proxy.service
ln -sf "$NIZAM_OS/systemd/metrics-llm.service"        /etc/systemd/system/metrics-llm.service
ln -sf "$NIZAM_OS/systemd/metrics-llm.timer"          /etc/systemd/system/metrics-llm.timer
ln -sf "$NIZAM_OS/systemd/watcher-inventory.service"  /etc/systemd/system/watcher-inventory.service
ln -sf "$NIZAM_OS/systemd/watcher-inventory.timer"    /etc/systemd/system/watcher-inventory.timer
ln -sf "$NIZAM_OS/systemd/watcher-env.service"        /etc/systemd/system/watcher-env.service
ln -sf "$NIZAM_OS/systemd/metrics-services.service"   /etc/systemd/system/metrics-services.service
ln -sf "$NIZAM_OS/systemd/metrics-services.timer"     /etc/systemd/system/metrics-services.timer
# logrotate rejects config files not owned by root — symlinks to user-owned files are refused.
# This is the only file in nizam-os that is COPIED not symlinked.
# After editing config/logrotate.nizam-os, re-run this script to push the change.
cp "$NIZAM_OS/config/logrotate.nizam-os" /etc/logrotate.d/nizam-os
chown root:root /etc/logrotate.d/nizam-os
chmod 644 /etc/logrotate.d/nizam-os

systemctl daemon-reload
echo "  reloaded system daemon"

# ── Systemd user units (no sudo needed for symlink; daemon-reload run as user) ─
USER_SYSTEMD="$USER_HOME/.config/systemd/user"
mkdir -p "$USER_SYSTEMD"
ln -sf "$NIZAM_OS/systemd/user/hermes-profile-watcher.service" "$USER_SYSTEMD/hermes-profile-watcher.service"
echo "  linked user service: hermes-profile-watcher.service"
echo "  NOTE: run as vazir → systemctl --user daemon-reload && systemctl --user enable --now hermes-profile-watcher"

# ── Hermes profile files ──────────────────────────────────────────────────────
# Each profile in nizam-os/hermes/profiles/<name>/ maps 1:1 to ~/.hermes/profiles/<name>/.
# Tracked: .env, config.yaml, *.md (root only), skills/, memories/
HERMES_PROFILES="$USER_HOME/.hermes/profiles"

# !! OFF-LIMITS: ~/.hermes/{SOUL.md,config.yaml,.env,skills/,memories/} !!
# Those are the root/default hermes agent — managed by hermes itself, never by nizam-os.
# nizam-os ONLY touches ~/.hermes/profiles/<name>/ (named profiles).
# Do NOT add symlinks into ~/.hermes/ root here.

for profile_dir in "$NIZAM_OS/hermes/profiles"/*/; do
    name=$(basename "$profile_dir")
    dst_base="$HERMES_PROFILES/$name"

    if [ ! -d "$dst_base" ]; then
        echo "  Profile $name not in ~/.hermes/profiles/ — create with: hermes profile create $name"
        continue
    fi

    for md in "$profile_dir"*.md; do
        [ -f "$md" ] || continue
        ln -sf "$md" "$dst_base/$(basename "$md")"
    done

    if [ -f "$profile_dir/config.yaml" ]; then
        ln -sf "$profile_dir/config.yaml" "$dst_base/config.yaml"
    fi

    # .env (gitignored — secrets, but symlinked so Hermes writes to nizam-os)
    if [ -f "$profile_dir/.env" ]; then
        ln -sf "$profile_dir/.env" "$dst_base/.env"
    fi

    # ln -sfn: -n treats dst as a normal file even if it's already a symlink to a dir,
    # preventing ln from following the existing link and creating the new symlink inside it.
    for dir in skills memories; do
        src="$profile_dir/$dir"
        dst="$dst_base/$dir"
        if [ -d "$src" ]; then
            ln -sfn "$src" "$dst"
        fi
    done

    echo "  linked hermes profile: $name"
done

echo ""
echo "Systemd symlinks:"
ls -la /etc/systemd/system/litellm-proxy.service \
       /etc/systemd/system/metrics-llm.service \
       /etc/systemd/system/metrics-llm.timer \
       /etc/systemd/system/metrics-services.service \
       /etc/systemd/system/metrics-services.timer \
       /etc/systemd/system/watcher-inventory.service \
       /etc/systemd/system/watcher-inventory.timer \
       /etc/systemd/system/watcher-env.service

echo ""
echo "Grafana: configure datasource and import dashboard manually."
echo "  Datasource: Prometheus @ http://localhost:9090, uid=nizam-prometheus"
echo "  Dashboard JSON: $NIZAM_OS/grafana/agents-dashboard.json"
