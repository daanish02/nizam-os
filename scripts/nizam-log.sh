#!/usr/bin/env bash
# Unified log viewer for nizam-os.
# Shows: system services → user services → one-shot scripts (sequential).
#
# Usage:
#   nizam-log              last 30 lines per section
#   nizam-log -n 100       last 100 lines per section
#   nizam-log -f           follow system journal (most useful for live debug)
#   nizam-log -s scripts   show only scripts.log
#   nizam-log -s agents    show only hermes gateway logs
#   nizam-log -s metrics   show only metrics-llm logs

LINES=30
FOLLOW=0
SECTION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--lines)   LINES="$2"; shift ;;
        -f|--follow)  FOLLOW=1 ;;
        -s|--section) SECTION="$2"; shift ;;
    esac
    shift
done

SCRIPTS_LOG="$HOME/.nizam-os/logs/scripts.log"
JFMT="--output=short-iso"

sep() { printf '\n\033[1;34m══ %s ══\033[0m\n' "$1"; }

show_system() {
    sep "system services (last $LINES)"
    sudo journalctl \
        -u litellm-proxy -u metrics-llm \
        -u watcher-env -u watcher-inventory \
        -n "$LINES" --no-pager "$JFMT"
}

show_agents() {
    sep "agent gateways (last $LINES)"
    journalctl --user \
        -u hermes-gateway-admin -u hermes-gateway-assistant \
        -u hermes-gateway-cos -u hermes-gateway-curator \
        -u hermes-profile-watcher \
        -n "$LINES" --no-pager "$JFMT"
}

show_scripts() {
    sep "one-shot scripts (last $LINES)"
    if [[ -f "$SCRIPTS_LOG" ]]; then
        tail -n "$LINES" "$SCRIPTS_LOG"
    else
        echo "(no scripts log yet)"
    fi
}

if [[ $FOLLOW -eq 1 ]]; then
    sep "following system services — Ctrl-C to stop"
    sudo journalctl \
        -u litellm-proxy -u metrics-llm \
        -u watcher-env -u watcher-inventory \
        -f "$JFMT"
    exit 0
fi

case "$SECTION" in
    system)  show_system ;;
    agents)  show_agents ;;
    scripts) show_scripts ;;
    metrics) sep "metrics-llm (last $LINES)"; sudo journalctl -u metrics-llm -n "$LINES" --no-pager "$JFMT" ;;
    "")
        show_system
        show_agents
        show_scripts
        ;;
    *)
        echo "unknown section: $SECTION"
        echo "valid: system | agents | scripts | metrics"
        exit 1
        ;;
esac
