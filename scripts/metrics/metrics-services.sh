#!/usr/bin/env bash
# Reads inventory/services.txt → writes nizam-services.prom for Prometheus node-exporter.
# Runs every 5 min as root via metrics-services.timer (same pattern as metrics-llm).
set -euo pipefail

NIZAM_OS="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_NAME="metrics-services"
source "$NIZAM_OS/scripts/shared/_log.sh"

SERVICES_FILE="$NIZAM_OS/inventory/services.txt"
OUT="/var/lib/prometheus/node-exporter/nizam-services.prom"
TMP="${OUT}.tmp"

if [ ! -f "$SERVICES_FILE" ]; then
    log_error "services.txt not found — skipping"
    exit 1
fi

total=0
up=0
metric_lines=()

while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    svc=$(echo "$line" | cut -d'|' -f1 | tr -d ' ')
    type=$(echo "$line" | cut -d'|' -f2 | tr -d ' ')
    status=$(echo "$line" | cut -d'|' -f3 | tr -d ' ')
    [[ -z "$svc" ]] && continue

    val=0
    [[ "$status" == "active" ]] && val=1

    metric_lines+=("nizam_service_up{service=\"${svc}\",type=\"${type}\"} ${val}")
    total=$((total + 1))
    up=$((up + val))
done < "$SERVICES_FILE"

{
    echo "# HELP nizam_service_up Service is active (1) or not (0)"
    echo "# TYPE nizam_service_up gauge"
    for m in "${metric_lines[@]}"; do
        echo "$m"
    done

    echo "# HELP nizam_services_total Total number of tracked services"
    echo "# TYPE nizam_services_total gauge"
    echo "nizam_services_total ${total}"

    echo "# HELP nizam_services_up_total Number of tracked services currently active"
    echo "# TYPE nizam_services_up_total gauge"
    echo "nizam_services_up_total ${up}"
} > "$TMP"

mv "$TMP" "$OUT"
chmod 644 "$OUT"
log_info "wrote ${up}/${total} services up"
