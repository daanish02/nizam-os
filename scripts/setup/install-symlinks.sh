#!/usr/bin/env bash
# Wire all nizam-os files into system locations via symlinks.
# Run once (or re-run safely — ln -sf overwrites stale links):
#   sudo bash scripts/setup/install-symlinks.sh
set -euo pipefail

NIZAM_OS="$(cd "$(dirname "$0")/../.." && pwd)"
USER_HOME="$(getent passwd vazir | cut -d: -f6)"

# Systemd system units (require sudo) 
ln -sf "$NIZAM_OS/systemd/litellm-proxy.service"      /etc/systemd/system/litellm-proxy.service
ln -sf "$NIZAM_OS/systemd/metrics-llm.service"        /etc/systemd/system/metrics-llm.service
ln -sf "$NIZAM_OS/systemd/metrics-llm.timer"          /etc/systemd/system/metrics-llm.timer
ln -sf "$NIZAM_OS/systemd/watcher-inventory.service"  /etc/systemd/system/watcher-inventory.service
ln -sf "$NIZAM_OS/systemd/watcher-inventory.timer"    /etc/systemd/system/watcher-inventory.timer
ln -sf "$NIZAM_OS/systemd/watcher-env.service"        /etc/systemd/system/watcher-env.service
ln -sf "$NIZAM_OS/systemd/metrics-services.service"   /etc/systemd/system/metrics-services.service
ln -sf "$NIZAM_OS/systemd/metrics-services.timer"     /etc/systemd/system/metrics-services.timer
ln -sf "$NIZAM_OS/systemd/metrics-toolcalls.service"  /etc/systemd/system/metrics-toolcalls.service
ln -sf "$NIZAM_OS/systemd/metrics-toolcalls.timer"    /etc/systemd/system/metrics-toolcalls.timer
ln -sf "$NIZAM_OS/systemd/promtail-nizam-os.service"  /etc/systemd/system/promtail-nizam-os.service
# logrotate rejects config files not owned by root — symlinks to user-owned files are refused.
# This is the only file in nizam-os that is COPIED not symlinked.
# After editing config/logrotate.nizam-os, re-run this script to push the change.
cp "$NIZAM_OS/config/logrotate.nizam-os" /etc/logrotate.d/nizam-os
chown root:root /etc/logrotate.d/nizam-os
chmod 644 /etc/logrotate.d/nizam-os

systemctl daemon-reload
echo "  reloaded system daemon"

# Systemd user units (vazir) — skill/profile watchers
USER_SYSTEMD="$USER_HOME/.config/systemd/user"
sudo -u vazir mkdir -p "$USER_SYSTEMD"
sudo -u vazir ln -sf "$NIZAM_OS/systemd/user/hermes-skill-watcher.service"   "$USER_SYSTEMD/hermes-skill-watcher.service"
sudo -u vazir ln -sf "$NIZAM_OS/systemd/user/hermes-profile-watcher.service" "$USER_SYSTEMD/hermes-profile-watcher.service"
sudo -u vazir XDG_RUNTIME_DIR="/run/user/$(id -u vazir)" systemctl --user daemon-reload
echo "  reloaded user daemon"

# Hermes runtime symlinks for admin (all created as vazir, not root)
HERMES_ADMIN_RUNTIME="$USER_HOME/.hermes/profiles/admin"

# Seed repo from auto-generated hermes profile files before symlinking.
# Only copies when source is a real file/dir (not already a symlink) and repo destination absent.
_seed() {
    local src="$1" dst="$2"
    [[ -L "$src" ]] && return   # already a symlink — repo is authoritative, skip
    [[ -e "$dst" ]] && return   # repo file exists — seed already ran
    [[ -e "$src" ]] || return   # hermes hasn't generated this yet — skip
    cp -a "$src" "$dst"
    chown -R vazir:vazir "$dst"
    echo "  seeded: $dst"
}

_seed "$HERMES_ADMIN_RUNTIME/config.yaml"   "$NIZAM_OS/config/hermes-admin-config.yaml"
_seed "$HERMES_ADMIN_RUNTIME/.env"          "$NIZAM_OS/secrets/hermes-admin.env"
_seed "$HERMES_ADMIN_RUNTIME/SOUL.md"       "$NIZAM_OS/hermes/profiles/admin/SOUL.md"
_seed "$HERMES_ADMIN_RUNTIME/AGENTS.md"     "$NIZAM_OS/hermes/profiles/admin/AGENTS.md"

# Copy hermes-generated memories/skills into repo, then replace real dirs with symlinks.
# rsync -a (no --ignore-existing) ensures all hermes content (USER.md, MEMORY.md, etc.) lands in repo.
if [[ ! -L "$HERMES_ADMIN_RUNTIME/memories" ]] && [[ -d "$HERMES_ADMIN_RUNTIME/memories" ]]; then
    sudo -u vazir mkdir -p "$NIZAM_OS/hermes/profiles/admin/memories"
    rsync -a --no-links "$HERMES_ADMIN_RUNTIME/memories/" "$NIZAM_OS/hermes/profiles/admin/memories/"  # --no-links: don't copy symlinks — prevents circular refs if a previous broken run left symlinks in the runtime dir
    chown -R vazir:vazir "$NIZAM_OS/hermes/profiles/admin/memories/"
    rm -rf "$HERMES_ADMIN_RUNTIME/memories"
    echo "  seeded: hermes/profiles/admin/memories"
fi
if [[ ! -L "$HERMES_ADMIN_RUNTIME/skills" ]] && [[ -d "$HERMES_ADMIN_RUNTIME/skills" ]]; then
    sudo -u vazir mkdir -p "$NIZAM_OS/hermes/profiles/admin/skills"
    rsync -a --no-links "$HERMES_ADMIN_RUNTIME/skills/" "$NIZAM_OS/hermes/profiles/admin/skills/"  # --no-links: don't copy symlinks — prevents circular refs if a previous broken run left symlinks in the runtime dir
    chown -R vazir:vazir "$NIZAM_OS/hermes/profiles/admin/skills/"
    rm -rf "$HERMES_ADMIN_RUNTIME/skills"
    echo "  seeded: hermes/profiles/admin/skills"
fi
if [[ ! -L "$HERMES_ADMIN_RUNTIME/pending" ]] && [[ -d "$HERMES_ADMIN_RUNTIME/pending" ]]; then
    sudo -u vazir mkdir -p "$NIZAM_OS/hermes/profiles/admin/pending"
    rsync -a --no-links "$HERMES_ADMIN_RUNTIME/pending/" "$NIZAM_OS/hermes/profiles/admin/pending/"  # --no-links: prevents circular refs
    chown -R vazir:vazir "$NIZAM_OS/hermes/profiles/admin/pending/"
    rm -rf "$HERMES_ADMIN_RUNTIME/pending"
    echo "  seeded: hermes/profiles/admin/pending"
fi
chown -R vazir:vazir "$NIZAM_OS/hermes/profiles/admin"

sudo -u vazir ln -sf "$NIZAM_OS/hermes/profiles/admin/SOUL.md"     "$HERMES_ADMIN_RUNTIME/SOUL.md"
sudo -u vazir ln -sf "$NIZAM_OS/hermes/profiles/admin/AGENTS.md"   "$HERMES_ADMIN_RUNTIME/AGENTS.md"
sudo -u vazir ln -sf "$NIZAM_OS/secrets/hermes-admin.env"                 "$HERMES_ADMIN_RUNTIME/.env"
sudo -u vazir ln -sf "$NIZAM_OS/config/hermes-admin-config.yaml"          "$HERMES_ADMIN_RUNTIME/config.yaml"
sudo -u vazir ln -sf "$NIZAM_OS/hermes/profiles/admin/memories"    "$HERMES_ADMIN_RUNTIME/memories"
sudo -u vazir ln -sf "$NIZAM_OS/hermes/profiles/admin/skills"      "$HERMES_ADMIN_RUNTIME/skills"
sudo -u vazir ln -sf "$NIZAM_OS/hermes/profiles/admin/pending"     "$HERMES_ADMIN_RUNTIME/pending"

echo "  hermes-gateway-admin.service managed by Hermes (admin gateway install)"

echo ""
echo "Systemd symlinks:"
ls -la /etc/systemd/system/litellm-proxy.service \
       /etc/systemd/system/metrics-llm.service \
       /etc/systemd/system/metrics-llm.timer \
       /etc/systemd/system/metrics-services.service \
       /etc/systemd/system/metrics-services.timer \
       /etc/systemd/system/metrics-toolcalls.service \
       /etc/systemd/system/metrics-toolcalls.timer \
       /etc/systemd/system/promtail-nizam-os.service \
       /etc/systemd/system/watcher-env.service \
       /etc/systemd/system/watcher-inventory.service \
       /etc/systemd/system/watcher-inventory.timer 

echo ""
echo "Hermes runtime symlinks (admin):"
ls -la "$USER_HOME/.hermes/profiles/admin/SOUL.md" \
       "$USER_HOME/.hermes/profiles/admin/AGENTS.md" \
       "$USER_HOME/.hermes/profiles/admin/.env" \
       "$USER_HOME/.hermes/profiles/admin/config.yaml" \
       "$USER_HOME/.hermes/profiles/admin/memories" \
       "$USER_HOME/.hermes/profiles/admin/skills" \
       "$USER_HOME/.hermes/profiles/admin/pending"

echo ""
echo "Grafana: configure datasources and import dashboard manually."
echo "  Prometheus @ http://localhost:9090, uid=nizam-prometheus"
echo "  Loki       @ http://localhost:3100, uid=nizam-loki"
echo "  Dashboard JSON: $NIZAM_OS/grafana/001-personal-dashboard.json"
