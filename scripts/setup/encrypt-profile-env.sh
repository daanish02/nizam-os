#!/usr/bin/env bash
# Encrypt a profile's .env → .env.enc using SOPS + age.
# Also generates .env.example (keys only, values stripped).
# Run after editing .env for a profile.
#
# Usage:
#   encrypt-profile-env.sh <profile>       single profile
#   encrypt-profile-env.sh                 all profiles in hermes/profiles/
set -euo pipefail

NIZAM_OS="$HOME/.nizam-os"
SCRIPT_NAME="encrypt-profile-env"
source "$NIZAM_OS/scripts/_log.sh"

PROFILES="$NIZAM_OS/hermes/profiles"
export SOPS_AGE_KEY_FILE="$NIZAM_OS/secrets/nizam-age-key.txt"
PUBKEY=$(grep "public key" "$SOPS_AGE_KEY_FILE" | awk '{print $NF}')

encrypt_profile() {
    local name="$1"
    local env="$PROFILES/$name/.env"
    local enc="$PROFILES/$name/.env.enc"
    local example="$PROFILES/$name/.env.example"

    if [ ! -f "$env" ]; then
        log_warn "$name: .env not found — skip"
        return
    fi

    sops \
        --encrypt \
        --input-type dotenv \
        --output-type dotenv \
        --age "$PUBKEY" \
        "$env" > "$enc"
    log_info "$name: encrypted → .env.enc"

    grep -E '^\s*#|^\s*$|^[A-Za-z_][A-Za-z0-9_]*=' "$env" \
        | sed 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1=/' \
        > "$example"
    log_info "$name: example generated → .env.example"
}

if [ $# -eq 0 ]; then
    log_info "encrypting all profiles"
    for d in "$PROFILES"/*/; do
        encrypt_profile "$(basename "$d")"
    done
else
    for name in "$@"; do
        encrypt_profile "$name"
    done
fi
