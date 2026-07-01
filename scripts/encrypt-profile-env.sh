#!/usr/bin/env bash
# Encrypt a profile's .env → .env.enc using SOPS + age.
# Run after editing .env for a profile.
#
# Usage:
#   encrypt-profile-env.sh <profile>       single profile
#   encrypt-profile-env.sh                 all profiles in hermes/profiles/
set -euo pipefail

NIZAM_OS="$HOME/nizam-os"
PROFILES="$NIZAM_OS/hermes/profiles"
export SOPS_AGE_KEY_FILE="$NIZAM_OS/secrets/nizam-age-key.txt"
PUBKEY=$(grep "public key" "$SOPS_AGE_KEY_FILE" | awk '{print $NF}')

encrypt_profile() {
    local name="$1"
    local env="$PROFILES/$name/.env"
    local enc="$PROFILES/$name/.env.enc"
    local example="$PROFILES/$name/.env.example"

    if [ ! -f "$env" ]; then
        echo "  [$name] .env not found — skip"
        return
    fi

    sops \
        --encrypt \
        --input-type dotenv \
        --output-type dotenv \
        --age "$PUBKEY" \
        "$env" > "$enc"
    echo "  [$name] encrypted → $enc"

    # Generate .env.example: preserve comments and keys, strip values
    grep -E '^\s*#|^\s*$|^[A-Za-z_][A-Za-z0-9_]*=' "$env" \
        | sed 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1=/' \
        > "$example"
    echo "  [$name] example   → $example"
}

if [ $# -eq 0 ]; then
    for d in "$PROFILES"/*/; do
        encrypt_profile "$(basename "$d")"
    done
else
    for name in "$@"; do
        encrypt_profile "$name"
    done
fi
