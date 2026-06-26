#!/usr/bin/env bash
# Shared logging helper for nizam-os one-shot scripts.
# Source this file — do NOT run directly.
#
# Usage in calling script:
#   SCRIPT_NAME="my-script"
#   source "$NIZAM_OS/scripts/_log.sh"
#   log_info "something happened"
#   log_warn "something looks off"
#   log_error "something failed"

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
