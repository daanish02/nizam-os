#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="$HOME/.nizam-os/secrets/nizam.env"
EXAMPLE_FILE="$HOME/.nizam-os/secrets/nizam.env.example"

update_example() {
    grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$ENV_FILE" \
        | sed 's/=.*/=/' \
        > "$EXAMPLE_FILE"
}

while inotifywait -e close_write "$ENV_FILE"; do
    echo "Encrypting..."
    "$HOME/.nizam-os/scripts/encrypt-env.sh"
    echo "Updating example..."
    update_example
done
