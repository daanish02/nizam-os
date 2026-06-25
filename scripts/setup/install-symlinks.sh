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

# ── Hermes profile files ──────────────────────────────────────────────────────
# Hermes is a user service. Each profile in nizam-os/hermes/profiles/<name>/
# maps 1:1 to ~/.hermes/profiles/<name>/.
# Tracked per profile: .env, config.yaml, *.md (root only), skills/, memories/
# .env is gitignored (secrets) but symlinked so Hermes writes to nizam-os path.
USER_HOME=/home/vazir
HERMES_PROFILES="$USER_HOME/.hermes/profiles"

# Wire ~/.hermes/SOUL.md to admin — gateway uses root SOUL.md, not profile SOUL.md
ln -sf "$NIZAM_OS/hermes/profiles/admin/SOUL.md" "$USER_HOME/.hermes/SOUL.md"
echo "  linked ~/.hermes/SOUL.md → admin/SOUL.md (gateway default)"

for profile_dir in "$NIZAM_OS/hermes/profiles"/*/; do
    name=$(basename "$profile_dir")
    dst_base="$HERMES_PROFILES/$name"

    if [ ! -d "$dst_base" ]; then
        echo "  Profile $name not in ~/.hermes/profiles/ — create with: hermes profile create $name"
        continue
    fi

    # .md files in profile root
    for md in "$profile_dir"*.md; do
        [ -f "$md" ] || continue
        ln -sf "$md" "$dst_base/$(basename "$md")"
    done

    # config.yaml
    if [ -f "$profile_dir/config.yaml" ]; then
        ln -sf "$profile_dir/config.yaml" "$dst_base/config.yaml"
    fi

    # .env (gitignored — secrets, but symlinked so Hermes writes to nizam-os)
    if [ -f "$profile_dir/.env" ]; then
        ln -sf "$profile_dir/.env" "$dst_base/.env"
    fi

    # skills/ and memories/ as directory symlinks
    # Any new file Hermes writes inside lands directly in nizam-os (git tracks it)
    for dir in skills memories; do
        src="$profile_dir/$dir"
        dst="$dst_base/$dir"
        if [ -d "$src" ] && [ ! -L "$dst" ]; then
            rm -rf "$dst"
            ln -sf "$src" "$dst"
        elif [ -d "$src" ]; then
            ln -sf "$src" "$dst"
        fi
    done

    echo "  linked hermes profile: $name"
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
