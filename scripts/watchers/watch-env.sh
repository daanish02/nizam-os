#!/usr/bin/env bash
# Watch nizam-os.env for changes and auto-encrypt + update .env.example.
# Runs as watcher-env.service — long-running via inotifywait.
set -euo pipefail

NIZAM_OS="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_NAME="watch-env"
source "$NIZAM_OS/scripts/shared/_log.sh"

ENV_FILE="$NIZAM_OS/secrets/nizam-os.env"
EXAMPLE_FILE="$NIZAM_OS/secrets/nizam-os.env.example"

update_example() {
    grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$ENV_FILE" \
        | sed 's/=.*/=/' \
        > "$EXAMPLE_FILE"
}

while inotifywait -e close_write "$ENV_FILE"; do
    log_info "encrypting nizam-os.env"
    "$NIZAM_OS/scripts/env/encrypt-env.sh"
    log_info "updating .env.example"
    update_example
    log_info "committing and pushing"
    git -C "$NIZAM_OS" add secrets/nizam-os.env.enc secrets/nizam-os.env.example
    git -C "$NIZAM_OS" commit -m "chore(secrets): update nizam-os.env.enc"
    git -C "$NIZAM_OS" push
    log_info "done"
done
