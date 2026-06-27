#!/usr/bin/env bash
# Shared logging helper for nizam-os one-shot scripts.
# Source this file — set SCRIPT_NAME first, then call log_info / log_warn / log_error.
# Override log path: NIZAM_LOG=/path/to/other.log source _log.sh

NIZAM_LOG="${NIZAM_LOG:-$HOME/.nizam-os/logs/scripts.log}"
mkdir -p "$(dirname "$NIZAM_LOG")"

_nizam_log() {
    local level="$1"; shift
    local msg="$*"
    local ts; ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local line
    printf -v line "%s [%-5s] [%s] %s" "$ts" "$level" "${SCRIPT_NAME:-script}" "$msg"
    echo "$line"
    echo "$line" >> "$NIZAM_LOG"
}

log_info()  { _nizam_log "INFO"  "$@"; }
log_warn()  { _nizam_log "WARN"  "$@"; }
log_error() { _nizam_log "ERROR" "$@"; }
