#!/usr/bin/env bash
# Pull a dashboard from Grafana and write to a JSON file.
# Usage: pull-dashboard.sh <uid> <output-file>
# Find UID in Grafana URL: /d/<uid>/dashboard-name
set -euo pipefail

NIZAM_OS="$(cd "$(dirname "$0")/../.." && pwd)"
SECRETS_FILE="$NIZAM_OS/secrets/nizam-os.env"
if [[ ! -f "$SECRETS_FILE" ]]; then
    echo "secrets file not found: $SECRETS_FILE" >&2; exit 1
fi
set -a; source "$SECRETS_FILE"; set +a

GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
GRAFANA_AUTH="${GRAFANA_AUTH:-admin:admin}"

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <uid> <output.json>" >&2
    exit 1
fi

DASH_UID="$1"
FILE="$2"

# Grafana wraps exports in {meta, dashboard} — unwrap to the inner object so push-dashboard.sh can re-wrap correctly
curl -sf -u "$GRAFANA_AUTH" "$GRAFANA_URL/api/dashboards/uid/$DASH_UID" \
    | python3 -c "
import json, sys
r = json.load(sys.stdin)
dash = r['dashboard']
with open('$FILE', 'w') as f:
    json.dump(dash, f, indent=2)
    f.write('\n')
print(f'pulled: uid=$DASH_UID v{dash.get(\"version\",\"?\")} → $FILE')
"
