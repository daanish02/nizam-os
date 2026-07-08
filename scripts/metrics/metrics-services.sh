#!/usr/bin/env bash
# Polls tracked-services.txt → writes nizam-services.prom for Prometheus node-exporter.
# Runs every 5 min as root via metrics-services.timer.
set -euo pipefail

NIZAM_OS="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_NAME="metrics-services"
source "$NIZAM_OS/scripts/shared/_log.sh"

TRACKED="$NIZAM_OS/inventory/tracked-services.txt"
OUT="/var/lib/prometheus/node-exporter/nizam-services.prom"
TMP="${OUT}.tmp"

if [ ! -f "$TRACKED" ]; then
    log_error "tracked-services.txt not found — skipping"
    exit 1
fi

total=0
up=0
metric_lines=()

while IFS= read -r svc; do
    [[ -z "$svc" || "$svc" == \#* ]] && continue

    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        val=1
        up=$((up + 1))
    else
        val=0
    fi

    metric_lines+=("nizam_service_up{service=\"${svc}\"} ${val}")
    total=$((total + 1))
done < "$TRACKED"

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

if [ "$up" -lt "$total" ]; then
    log_error "services degraded: ${up}/${total} up"
else
    log_info "all ${total} services up"
fi
