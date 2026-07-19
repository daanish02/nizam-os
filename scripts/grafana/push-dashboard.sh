#!/usr/bin/env bash
# Push a dashboard JSON file to Grafana.
# Usage: push-dashboard.sh <json-file>
set -euo pipefail

NIZAM_OS="$(cd "$(dirname "$0")/../.." && pwd)"
SECRETS_FILE="$NIZAM_OS/secrets/nizam-os.env"
if [[ ! -f "$SECRETS_FILE" ]]; then
    echo "secrets file not found: $SECRETS_FILE" >&2; exit 1
fi
set -a; source "$SECRETS_FILE"; set +a

GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
GRAFANA_AUTH="${GRAFANA_AUTH:-admin:admin}"

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <dashboard.json>" >&2
    exit 1
fi

FILE="$1"
if [[ ! -f "$FILE" ]]; then
    echo "File not found: $FILE" >&2
    exit 1
fi

# overwrite:True prevents duplicate dashboards; folderId:0 pins to General folder
PAYLOAD=$(python3 -c "
import json, sys
dash = json.load(open('$FILE'))
print(json.dumps({'dashboard': dash, 'overwrite': True, 'folderId': 0}))
")

RESPONSE=$(curl -sf -u "$GRAFANA_AUTH" \
    -X POST "$GRAFANA_URL/api/dashboards/db" \
    -H 'Content-Type: application/json' \
    -d "$PAYLOAD")

VERSION=$(echo "$RESPONSE" | python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('version','?'))")
echo "pushed: $FILE → v${VERSION}"
