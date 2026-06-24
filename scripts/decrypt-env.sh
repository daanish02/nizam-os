#!/usr/bin/env bash
set -euo pipefail

export SOPS_AGE_KEY_FILE="$HOME/.nizam-os/secrets/nizam-age-key.txt"

sops \
  --decrypt \
  --input-type dotenv \
  --output-type dotenv \
  "$HOME/.nizam-os/secrets/nizam.env.enc" \
  > "$HOME/.nizam-os/secrets/nizam.env"
