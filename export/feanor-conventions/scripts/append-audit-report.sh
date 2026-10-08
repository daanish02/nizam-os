#!/usr/bin/env bash
# Appends a new timestamped section to .feanor/audit_report.md, never
# overwriting prior sections. Called by agents/validation-agent.md.
#
# Usage: append-audit-report.sh <path-to-section-content-file> [path/to/.feanor/audit_report.md]
set -e

if [ -z "$1" ]; then
  echo "Usage: append-audit-report.sh <section-content-file> [audit_report.md path]" >&2
  exit 1
fi

CONTENT_FILE="$1"
REPORT_PATH="${2:-.feanor/audit_report.md}"

mkdir -p "$(dirname "$REPORT_PATH")"
touch "$REPORT_PATH"
if [ ! -s "$REPORT_PATH" ]; then
  echo "# Feanor Audit Report" > "$REPORT_PATH"
fi

{
  echo ""
  echo "## $(date -u +%Y-%m-%dT%H:%M:%SZ) — Audit Summary"
  echo ""
  cat "$CONTENT_FILE"
} >> "$REPORT_PATH"

echo "Appended section to $REPORT_PATH"
