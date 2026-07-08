#!/usr/bin/env bash
# Decrypt nizam-os.env.enc → nizam-os.env using the age key.
# Run manually after git clone or whenever the encrypted file is updated.
set -euo pipefail

export SOPS_AGE_KEY_FILE="$HOME/nizam-os/secrets/nizam-age-key.txt"

TMP=$(mktemp)
sops \
  --decrypt \
  --input-type dotenv \
  --output-type dotenv \
  "$HOME/nizam-os/secrets/nizam-os.env.enc" \
  > "$TMP" && mv "$TMP" "$HOME/nizam-os/secrets/nizam-os.env" || { rm -f "$TMP"; exit 1; }
