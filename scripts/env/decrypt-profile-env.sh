#!/usr/bin/env bash
# Decrypt a profile's .env.enc → .env using SOPS + age.
# Run on a fresh VPS or after deleting a plaintext .env.
#
# Usage:
#   decrypt-profile-env.sh <profile>       single profile
#   decrypt-profile-env.sh                 all profiles in hermes/profiles/
set -euo pipefail

NIZAM_OS="$HOME/nizam-os"
SCRIPT_NAME="decrypt-profile-env"
source "$NIZAM_OS/scripts/shared/_log.sh"

PROFILES="$NIZAM_OS/hermes/profiles"
export SOPS_AGE_KEY_FILE="$NIZAM_OS/secrets/nizam-age-key.txt"

decrypt_profile() {
    local name="$1"
    local enc="$PROFILES/$name/.env.enc"
    local env="$PROFILES/$name/.env"

    if [ ! -f "$enc" ]; then
        log_warn "$name: .env.enc not found — skip"
        return
    fi

    sops \
        --decrypt \
        --input-type dotenv \
        --output-type dotenv \
        "$enc" > "$env"

    chmod 600 "$env"
    log_info "$name: decrypted → .env"
}

if [ $# -eq 0 ]; then
    log_info "decrypting all profiles"
    for d in "$PROFILES"/*/; do
        decrypt_profile "$(basename "$d")"
    done
else
    for name in "$@"; do
        decrypt_profile "$name"
    done
fi
