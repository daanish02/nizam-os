#!/usr/bin/env bash
# Decrypt a secrets/*.env.enc → secrets/*.env using the age key.
# Run on fresh clone or whenever restoring plaintext from encrypted.
#
# Usage:
#   decrypt-env.sh                    decrypt all *.env.enc in secrets/
#   decrypt-env.sh nizam-os           decrypt secrets/nizam-os.env.enc
#   decrypt-env.sh hermes-admin       decrypt secrets/hermes-admin.env.enc
set -euo pipefail

NIZAM_OS="$(cd "$(dirname "$0")/../.." && pwd)"
SECRETS="$NIZAM_OS/secrets"
export SOPS_AGE_KEY_FILE="$SECRETS/nizam-age-key.txt"

decrypt_file() {
    local name="$1"
    local enc="$SECRETS/${name}.env.enc"
    local out="$SECRETS/${name}.env"

    if [[ ! -f "$enc" ]]; then
        echo "  SKIP: $enc not found"
        return
    fi

    local tmp
    tmp=$(mktemp)
    sops \
        --decrypt \
        --input-type dotenv \
        --output-type dotenv \
        "$enc" > "$tmp" && mv "$tmp" "$out" || { rm -f "$tmp"; exit 1; }
    chmod 600 "$out"
    echo "  decrypted: $out"
}

if [[ $# -eq 0 ]]; then
    for enc in "$SECRETS"/*.env.enc; do
        [[ -f "$enc" ]] || continue
        name="$(basename "${enc%.env.enc}")"
        decrypt_file "$name"
    done
else
    for name in "$@"; do
        decrypt_file "$name"
    done
fi