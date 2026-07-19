#!/usr/bin/env bash
# Watch secrets/*.env for changes — auto-encrypt to .enc and regenerate .example.
# Runs as watcher-env.service — long-running via inotifywait.
set -euo pipefail

NIZAM_OS="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_NAME="watch-env"
source "$NIZAM_OS/scripts/shared/_log.sh"

SECRETS="$NIZAM_OS/secrets"
export SOPS_AGE_KEY_FILE="$SECRETS/nizam-age-key.txt"

process_env() {
    local env_file="$1"
    local base
    base="$(basename "$env_file")"
    local enc_file="${env_file%.env}.env.enc"
    local example_file="${env_file%.env}.env.example"

    log_info "$base: encrypting"
    local pubkey
    pubkey=$(grep "public key" "$SOPS_AGE_KEY_FILE" | awk '{print $NF}')
    sops \
        --encrypt \
        --input-type dotenv \
        --output-type dotenv \
        --age "$pubkey" \
        "$env_file" > "$enc_file"

    log_info "$base: generating .example"
    grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$env_file" \
        | sed 's/=.*/=/' \
        > "$example_file"

    log_info "$base: committing"
    local enc_rel="secrets/$(basename "$enc_file")"
    local example_rel="secrets/$(basename "$example_file")"
    git -C "$NIZAM_OS" add "$enc_rel" "$example_rel"
    git -C "$NIZAM_OS" diff --cached --quiet || \
        git -C "$NIZAM_OS" commit -m "inventory: $(basename "$env_file") updated $(date +%Y-%m-%d)"
    git -C "$NIZAM_OS" push
    log_info "$base: done"
}

log_info "watching $SECRETS for *.env changes"

inotifywait -m -e close_write --format '%f' "$SECRETS" | while read -r filename; do
    # Only process plain .env files — ignore .enc, .example, .txt, etc.
    [[ "$filename" =~ \.env$ ]] || continue
    [[ "$filename" =~ \.enc\.env$ ]] && continue
    process_env "$SECRETS/$filename"
done