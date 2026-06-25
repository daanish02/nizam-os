#!/usr/bin/env bash
# Bidirectional watcher for hermes profile files.
#
# nizam-os → .hermes: new *.md/.env/config.yaml in nizam-os profile root
#   → auto-symlinked into ~/.hermes/profiles/{name}/
#
# .hermes → nizam-os: hermes creates new non-symlink file in ~/.hermes/profiles/{name}/
#   → migrated to nizam-os, replaced with symlink back
#   → covers: hermes profile create {name}, agent-written skills (SAVE framework)
set -euo pipefail

NIZAM_OS=/home/vazir/.nizam-os
NIZAM_PROFILES="$NIZAM_OS/hermes/profiles"
HERMES_PROFILES=/home/vazir/.hermes/profiles

echo "hermes-profile-watcher: started (bidirectional)"

# ── Direction 1: nizam-os → .hermes ──────────────────────────────────────────
# User writes file in nizam-os → auto-symlink appears in .hermes
watch_nizam_to_hermes() {
    inotifywait -m -r -e create,moved_to --format '%w%f' "$NIZAM_PROFILES" | while IFS= read -r fullpath; do
        rel="${fullpath#$NIZAM_PROFILES/}"
        profile_name="${rel%%/*}"
        filename="${rel#*/}"
        [[ "$filename" == */* ]] && continue

        case "$filename" in
            *.md|.env|config.yaml) ;;
            *) continue ;;
        esac

        dst_base="$HERMES_PROFILES/$profile_name"
        if [ ! -d "$dst_base" ]; then
            echo "hermes-profile-watcher: WARNING '$profile_name' not in ~/.hermes/profiles/ — run: hermes profile create $profile_name"
            continue
        fi

        ln -sf "$fullpath" "$dst_base/$filename"
        echo "hermes-profile-watcher: [nizam→hermes] linked $profile_name/$filename"
    done
}

# ── Direction 2: .hermes → nizam-os ──────────────────────────────────────────
# Hermes creates file/dir in .hermes (e.g. hermes profile create) → migrate to nizam-os
watch_hermes_to_nizam() {
    inotifywait -m -r -e create,moved_to --format '%w%f' "$HERMES_PROFILES" | while IFS= read -r fullpath; do
        # Skip files already managed as symlinks (avoid loop)
        [ -L "$fullpath" ] && continue

        rel="${fullpath#$HERMES_PROFILES/}"
        profile_name="${rel%%/*}"
        filename="${rel#*/}"
        [[ "$filename" == */* ]] && continue

        nizam_profile="$NIZAM_PROFILES/$profile_name"
        nizam_path="$nizam_profile/$filename"

        case "$filename" in
            *.md|.env|config.yaml)
                mkdir -p "$nizam_profile"
                if [ ! -e "$nizam_path" ]; then
                    mv "$fullpath" "$nizam_path"
                    ln -sf "$nizam_path" "$fullpath"
                    echo "hermes-profile-watcher: [hermes→nizam] migrated $profile_name/$filename"
                fi
                ;;
            skills|memories)
                if [ -d "$fullpath" ] && [ ! -L "$fullpath" ]; then
                    mkdir -p "$nizam_path"
                    sleep 1  # let hermes finish populating dir before we take over
                    if [ "$(ls -A "$fullpath" 2>/dev/null)" ]; then
                        mv "$fullpath"/* "$nizam_path"/ 2>/dev/null || true
                    fi
                    rm -rf "$fullpath"
                    ln -sf "$nizam_path" "$fullpath"
                    echo "hermes-profile-watcher: [hermes→nizam] wired dir $profile_name/$filename/"
                fi
                ;;
        esac
    done
}

trap 'kill $(jobs -p) 2>/dev/null; exit 0' EXIT INT TERM

watch_nizam_to_hermes &
watch_hermes_to_nizam &
wait
