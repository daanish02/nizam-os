#!/usr/bin/env bash
# Bidirectional sync for hermes named profile files (NAMED PROFILES only — never root ~/.hermes/).
# nizam-os → .hermes: new files symlinked in; .hermes → nizam-os: new real files migrated to repo + symlinked back.
# Covers hermes profile create and SAVE framework agent-written skills.
set -euo pipefail

NIZAM_OS="$(cd "$(dirname "$0")/.." && pwd)"
NIZAM_PROFILES="$NIZAM_OS/hermes/profiles"
HERMES_PROFILES="$HOME/.hermes/profiles"

echo "hermes-profile-watcher: started (bidirectional)"

# ── Direction 1: nizam-os → .hermes ──────────────────────────────────────────
watch_nizam_to_hermes() {
    inotifywait -m -r -e create,moved_to --format '%w%f' "$NIZAM_PROFILES" | while IFS= read -r fullpath; do
        rel="${fullpath#$NIZAM_PROFILES/}"
        profile_name="${rel%%/*}"
        filename="${rel#*/}"
        [[ "$filename" == */* ]] && continue  # depth-limit: skip events from subdirectories

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
watch_hermes_to_nizam() {
    inotifywait -m -r -e create,moved_to --format '%w%f' "$HERMES_PROFILES" | while IFS= read -r fullpath; do
        # Skip files already managed as symlinks (avoid loop)
        [ -L "$fullpath" ] && continue

        rel="${fullpath#$HERMES_PROFILES/}"
        profile_name="${rel%%/*}"
        filename="${rel#*/}"
        [[ "$filename" == */* ]] && continue  # depth-limit: skip events from subdirectories

        nizam_profile="$NIZAM_PROFILES/$profile_name"
        nizam_path="$nizam_profile/$filename"

        case "$filename" in
            *.md|.env|config.yaml)
                mkdir -p "$nizam_profile"
                if [ ! -e "$nizam_path" ]; then
                    mv "$fullpath" "$nizam_path"
                    ln -sf "$nizam_path" "$fullpath"
                    echo "hermes-profile-watcher: [hermes→nizam] migrated $profile_name/$filename"
                    # New profile config — apply SAVE governance automatically
                    if [[ "$filename" == "config.yaml" ]]; then
                        echo "hermes-profile-watcher: [governance] applying SAVE to new profile $profile_name"
                        python3 "$NIZAM_OS/scripts/save/setup-profile-governance.py" "$profile_name" &
                    fi
                fi
                ;;
            skills|memories|pending)
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

# ── Direction 3: nizam-os .env close_write → auto-encrypt ────────────────────
watch_env_encrypt() {
    inotifywait -m -r -e close_write --format '%w%f' "$NIZAM_PROFILES" | while IFS= read -r fullpath; do
        rel="${fullpath#$NIZAM_PROFILES/}"
        profile_name="${rel%%/*}"
        filename="${rel#*/}"

        [[ "$filename" == ".env" ]] || continue

        echo "hermes-profile-watcher: [env→enc] encrypting $profile_name/.env"
        # encrypt updated profile env to secrets/
        local env_src="$NIZAM_OS/secrets/hermes-${profile_name}.env"
        local pubkey
        pubkey=$(grep "public key" "$NIZAM_OS/secrets/nizam-age-key.txt" | awk '{print $NF}')
        sops --encrypt --input-type dotenv --output-type dotenv --age "$pubkey" \
            "$env_src" > "${env_src%.env}.env.enc"
        grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$env_src" | sed 's/=.*/=/' > "${env_src%.env}.env.example"
    done
}


# ── Direction 4: memories close_write → .audit.json + Discord notification ─────
watch_memory_audit() {
    local secrets_file="$NIZAM_OS/secrets/nizam-os.env"
    local webhook=""
    if [[ -f "$secrets_file" ]]; then
        webhook=$(grep '^DISCORD_WEBHOOK_ALERTS=' "$secrets_file" 2>/dev/null | cut -d= -f2- | tr -d '\r' || true)
    fi

    inotifywait -m -r -e close_write --format '%w%f' "$NIZAM_PROFILES" | while IFS= read -r fullpath; do
        rel="${fullpath#$NIZAM_PROFILES/}"
        profile_name="${rel%%/*}"
        rest="${rel#*/}"

        # Only memories/*.md files; skip .audit.json and non-md files
        [[ "$rest" == memories/*.md ]] || continue
        filename="${rest#memories/}"

        audit_file="$NIZAM_PROFILES/$profile_name/memories/.audit.json"
        nizam_rel="${fullpath#$NIZAM_OS/}"
        diff_summary=$(git -C "$NIZAM_OS" diff HEAD -- "$nizam_rel" 2>/dev/null | head -c 500 || true)
        timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

        # If any session was active in the last 60 seconds, tag as agent-approved
        actor="manual"
        sessions_dir="$HOME/.hermes/profiles/$profile_name/sessions"
        if [[ -d "$sessions_dir" ]] && find "$sessions_dir" -name "*.json" -mmin -1 2>/dev/null | grep -q .; then
            actor="agent-approved"
        fi

        AUDIT_FILE="$audit_file" PROFILE="$profile_name" FILE="$filename" \
        ACTOR="$actor" DIFF="$diff_summary" TS="$timestamp" \
        python3 -c "
import json, os
from pathlib import Path
audit_file = Path(os.environ['AUDIT_FILE'])
entries = json.loads(audit_file.read_text()) if audit_file.exists() else []
entries.append({'timestamp': os.environ['TS'], 'profile': os.environ['PROFILE'],
    'file': os.environ['FILE'], 'actor': os.environ['ACTOR'],
    'diff_summary': os.environ['DIFF'][:500]})
audit_file.write_text(json.dumps(entries, indent=2) + '\n')
" || true

        echo "hermes-profile-watcher: [memory-audit] $profile_name/memories/$filename (actor=$actor)"

        if [[ -n "$webhook" ]]; then
            WEBHOOK="$webhook" PROFILE="$profile_name" FILE="$filename" \
            ACTOR="$actor" DIFF="${diff_summary:0:300}" TS="$timestamp" \
            python3 -c "
import json, os, urllib.request
diff = os.environ['DIFF']
diff_field = ('\`\`\`diff\n' + diff + '\n\`\`\`') if diff else '(no staged diff)'
payload = {'embeds': [{'title': 'Memory updated: \`' + os.environ['FILE'] + '\`',
    'color': 5793266,
    'fields': [
        {'name': 'Profile', 'value': os.environ['PROFILE'], 'inline': True},
        {'name': 'Actor', 'value': os.environ['ACTOR'], 'inline': True},
        {'name': 'Time', 'value': os.environ['TS'], 'inline': True},
        {'name': 'Diff', 'value': diff_field, 'inline': False},
    ]}]}
req = urllib.request.Request(os.environ['WEBHOOK'],
    data=json.dumps(payload).encode(),
    headers={'Content-Type': 'application/json'}, method='POST')
try:
    urllib.request.urlopen(req, timeout=10)
except Exception as e:
    print('Discord POST failed:', e)
" || true
        fi
    done
}

trap 'kill $(jobs -p) 2>/dev/null; exit 0' EXIT INT TERM  # reap all background watcher processes on exit

watch_nizam_to_hermes &
watch_hermes_to_nizam &
watch_env_encrypt &
watch_memory_audit &
wait
