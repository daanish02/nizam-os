#!/usr/bin/env bash
# Wire a newly-created hermes NAMED PROFILE into nizam-os.
# Run after: hermes profile create <name>
#
# SCOPE — only ~/.hermes/profiles/<name>/ (named profiles).
# OFF-LIMITS — ~/.hermes/{SOUL.md,config.yaml,.env,skills/,memories/} are the
#   root/default hermes agent. This script NEVER touches them.
#
# Usage:
#   wire-hermes-profile.sh <profile>          single profile
#   wire-hermes-profile.sh <a> <b> ...        multiple
#   wire-hermes-profile.sh                    all profiles in ~/.hermes/profiles/
set -euo pipefail

NIZAM_OS="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_NAME="wire-hermes-profile"
source "$NIZAM_OS/scripts/shared/_log.sh"

NIZAM_PROFILES="$NIZAM_OS/hermes/profiles"
HERMES_PROFILES="$HOME/.hermes/profiles"
export SOPS_AGE_KEY_FILE="$NIZAM_OS/secrets/nizam-age-key.txt"

# If .env is missing but .env.enc exists, decrypt first (fresh VPS / after git clone)
ensure_env_decrypted() {
    local n="$1"
    local env="$n/.env"
    local enc="$n/.env.enc"

    if [ ! -f "$env" ] && [ -f "$enc" ]; then
        sops --decrypt --input-type dotenv --output-type dotenv "$enc" > "$env"
        chmod 600 "$env"
        log_info "$(basename "$n"): .env decrypted from .env.enc"
    fi
}

wire_profile() {
    local name="$1"
    local h="$HERMES_PROFILES/$name"
    local n="$NIZAM_PROFILES/$name"

    if [ ! -d "$h" ]; then
        log_warn "$name: not in ~/.hermes/profiles/ — run: hermes profile create $name"
        return 1
    fi

    mkdir -p "$n"
    ensure_env_decrypted "$n"

    # skills/ and memories/ 
    for dir in skills memories; do
        local hs="$h/$dir"
        local ns="$n/$dir"

        if [ -L "$hs" ]; then
            log_info "$name/$dir: already symlinked — skip"
        elif [ -d "$hs" ] && [ -d "$ns" ]; then
            if [ "$(ls -A "$hs" 2>/dev/null)" ]; then
                mv "$hs"/* "$ns"/ 2>/dev/null || true
            fi
            rm -rf "$hs"
            ln -sf "$ns" "$hs"
            log_info "$name/$dir: merged .hermes content → nizam-os, symlinked"
        elif [ -d "$hs" ]; then
            mv "$hs" "$ns"
            ln -sf "$ns" "$hs"
            log_info "$name/$dir: moved to nizam-os, symlinked"
        elif [ -d "$ns" ]; then
            ln -sf "$ns" "$hs"
            log_info "$name/$dir: linked from nizam-os"
        else
            mkdir -p "$ns"
            ln -sf "$ns" "$hs"
            log_info "$name/$dir: created in nizam-os, symlinked"
        fi
    done

    # .md / .env / config.yaml in profile root
    while IFS= read -r -d '' f; do
        local base; base=$(basename "$f")
        local np="$n/$base"

        if [ -L "$f" ]; then
            continue
        fi

        if [ ! -e "$np" ]; then
            mv "$f" "$np"
            ln -sf "$np" "$f"
            log_info "$name/$base: migrated → nizam-os, symlinked"
        else
            rm "$f"
            ln -sf "$np" "$f"
            log_info "$name/$base: replaced with symlink → nizam-os"
        fi
    done < <(find "$h" -maxdepth 1 \( -name "*.md" -o -name ".env" -o -name "config.yaml" \) ! -type l -print0 2>/dev/null)

    while IFS= read -r -d '' f; do
        local base; base=$(basename "$f")
        local hp="$h/$base"

        if [ ! -e "$hp" ] && [ ! -L "$hp" ]; then
            ln -sf "$f" "$hp"
            log_info "$name/$base: linked from nizam-os"
        fi
    done < <(find "$n" -maxdepth 1 \( -name "*.md" -o -name ".env" -o -name "config.yaml" \) -print0 2>/dev/null)

    log_info "$name: done"
}

if [ $# -eq 0 ]; then
    log_info "wiring all profiles in ~/.hermes/profiles/"
    for d in "$HERMES_PROFILES"/*/; do
        wire_profile "$(basename "$d")" || true
    done
else
    for name in "$@"; do
        wire_profile "$name" || true
    done
fi

log_info "all done"
