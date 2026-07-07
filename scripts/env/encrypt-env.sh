#!/usr/bin/env bash
# Encrypt nizam-os.env → nizam-os.env.enc using the age public key.
# Run manually before committing secrets changes.
set -euo pipefail

export SOPS_AGE_KEY_FILE="$HOME/nizam-os/secrets/nizam-age-key.txt"

PUBKEY=$(grep "public key" "$SOPS_AGE_KEY_FILE" | awk '{print $NF}')

sops \
  --encrypt \
  --input-type dotenv \
  --output-type dotenv \
  --age "$PUBKEY" \
  "$HOME/nizam-os/secrets/nizam-os.env" \
  > "$HOME/nizam-os/secrets/nizam-os.env.enc"
