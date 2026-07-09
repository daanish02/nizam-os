#!/usr/bin/env bash
# Shared logging helper for nizam-os one-shot scripts.
# Source this file — set SCRIPT_NAME first, then call log_info / log_warn / log_error.
# Override log path: NIZAM_LOG=/path/to/other.log source _log.sh

NIZAM_LOG="${NIZAM_LOG:-$HOME/nizam-os/logs/scripts.log}"
mkdir -p "$(dirname "$NIZAM_LOG")"

_nizam_log() {
    local level="$1"; shift
    local msg="$*"
    local ts; ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local escaped_msg="${msg//\\/\\\\}"
    escaped_msg="${escaped_msg//\"/\\\"}"
    local line="{\"ts\":\"${ts}\",\"level\":\"${level}\",\"script\":\"${SCRIPT_NAME:-script}\",\"msg\":\"${escaped_msg}\"}"

    if [ -t 1 ]; then
        case "$level" in
            INFO)    printf '\033[0;32m[INFO]\033[0m  %s %s\n' "$ts" "$msg" ;;
            WARNING) printf '\033[0;33m[WARN]\033[0m  %s %s\n' "$ts" "$msg" ;;
            ERROR)   printf '\033[0;31m[ERROR]\033[0m %s %s\n' "$ts" "$msg" ;;
            *)       printf '[%s] %s %s\n' "$level" "$ts" "$msg" ;;
        esac
    else
        echo "$line"
    fi

    echo "$line" >> "$NIZAM_LOG"
}

log_info()  { _nizam_log "INFO"  "$@"; }
log_warn()  { _nizam_log "WARNING"  "$@"; }
log_error() { _nizam_log "ERROR" "$@"; }
